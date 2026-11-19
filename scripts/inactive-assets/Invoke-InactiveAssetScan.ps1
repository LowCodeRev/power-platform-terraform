<#
.SYNOPSIS
Inactive asset policy scan (report only). Lists every app and cloud flow in the tenant and reports which ones
the policy would warn about, quarantine or delete. It changes nothing in the tenant.

.DESCRIPTION
Policy values come from policies/inactive-assets.json; any period can be overridden per run for testing, and
-AsOf evaluates the policy as if "now" were another date.

Signals used for "last activity":
  apps   lastModifiedTime from the Power Apps admin API plus the most recent launch from the Purview audit log
         (Graph security/auditLog/queries, needs AuditLogsQuery.Read.All). If the audit log cannot be read the
         scan still completes: app results then rest on modification only and are marked UsageSignal = unavailable.
  flows  lastModifiedTime plus the most recent run from run history (the platform keeps about 28 days).

With -DataverseUrl the scan is also logged to Dataverse: each asset's current state is upserted, the run is
recorded with its counts, and every change of stage becomes an event. The last run seen for a flow and the last
launch seen for an app are kept there, so activity that has aged out of the platform's own history still counts,
and later scans only need to read the audit log since the previous scan.

Authentication uses the current Azure CLI session (`az login` locally, azure/login OIDC in GitHub Actions).

.EXAMPLE
./Invoke-InactiveAssetScan.ps1
.EXAMPLE
./Invoke-InactiveAssetScan.ps1 -InactiveDays 1 -QuarantineWarningDays 1 -QuarantinedDays 1 -DeleteWarningDays 1
.EXAMPLE
./Invoke-InactiveAssetScan.ps1 -AsOf 2027-06-01
#>
[CmdletBinding()]
param(
    [string] $PolicyPath = (Join-Path $PSScriptRoot '..\..\policies\inactive-assets.json'),
    [string] $OutputPath = (Join-Path (Get-Location) 'inactive-assets-report'),
    [Nullable[double]] $InactiveDays,
    [Nullable[double]] $QuarantineWarningDays,
    [Nullable[double]] $QuarantinedDays,
    [Nullable[double]] $DeleteWarningDays,
    [Nullable[datetime]] $AsOf,
    # Log the scan to Dataverse (schema from Deploy-InactiveAssetSchema.ps1). Omit to only write report files.
    [string] $DataverseUrl = $env:INACTIVE_ASSETS_DATAVERSE_URL,
    # Do not query the audit log for app launches on this run.
    [switch] $SkipLaunchSignal,
    [string] $PublisherPrefix = 'rev'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'InactiveAssets.psm1') -Force

# ---------- policy ----------
$policy = Get-Content -Raw -Path $PolicyPath | ConvertFrom-Json
if ($policy.mode -ne 'report') {
    throw "Policy mode '$($policy.mode)' is not implemented. Only 'report' exists; this script never changes the tenant."
}
$periods = [pscustomobject]@{
    inactiveDays          = [double]$policy.periods.inactiveDays
    quarantineWarningDays = [double]$policy.periods.quarantineWarningDays
    quarantinedDays       = [double]$policy.periods.quarantinedDays
    deleteWarningDays     = [double]$policy.periods.deleteWarningDays
}
if ($null -ne $InactiveDays) { $periods.inactiveDays = $InactiveDays }
if ($null -ne $QuarantineWarningDays) { $periods.quarantineWarningDays = $QuarantineWarningDays }
if ($null -ne $QuarantinedDays) { $periods.quarantinedDays = $QuarantinedDays }
if ($null -ne $DeleteWarningDays) { $periods.deleteWarningDays = $DeleteWarningDays }

$scanTime = [datetime]::UtcNow
$now = $scanTime
if ($null -ne $AsOf) { $now = ConvertTo-UtcDate $AsOf }
$assetTypes = @($policy.assetTypes)
$include = @($policy.environments.include)
$excludeManaged = $true
if ($policy.PSObject.Properties['excludeManaged']) { $excludeManaged = [bool]$policy.excludeManaged }
$skippedManaged = 0
$launchCfg = [pscustomobject]@{ enabled = $true; lookbackDays = 180.0; timeoutMinutes = 30.0 }
if ($policy.PSObject.Properties['appLaunchSignal']) {
    foreach ($n in 'enabled', 'lookbackDays', 'timeoutMinutes') {
        if ($policy.appLaunchSignal.PSObject.Properties[$n]) { $launchCfg.$n = $policy.appLaunchSignal.$n }
    }
}
$exclude = @($policy.environments.exclude)

# ---------- HTTP ----------
$script:Tokens = @{}
function Get-Token([string] $Resource) {
    if (-not $script:Tokens.ContainsKey($Resource)) {
        $t = az account get-access-token --resource $Resource --query accessToken -o tsv
        if ($LASTEXITCODE -ne 0 -or -not $t) { throw "Could not get a token for $Resource. Run 'az login --allow-no-subscriptions --tenant <tenant>' first." }
        $script:Tokens[$Resource] = $t
    }
    return $script:Tokens[$Resource]
}

function Invoke-Api([string] $Uri, [string] $Resource, [string] $Method = 'Get', $Body = $null) {
    for ($attempt = 1; ; $attempt++) {
        try {
            $req = @{ Method = $Method; Uri = $Uri; Headers = @{ Authorization = "Bearer $(Get-Token $Resource)" } }
            if ($null -ne $Body) {
                $req.ContentType = 'application/json'
                $req.Body = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 8))
            }
            return Invoke-RestMethod @req
        }
        catch {
            $status = 0
            if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
            if ($attempt -lt 5 -and ($status -eq 429 -or $status -ge 500)) { Start-Sleep -Seconds (5 * $attempt); continue }
            throw
        }
    }
}

function Get-AllPages([string] $Uri, [string] $Resource) {
    $items = New-Object System.Collections.Generic.List[object]
    while ($Uri) {
        $page = Invoke-Api $Uri $Resource
        foreach ($v in @($page.value)) { if ($null -ne $v) { $items.Add($v) } }
        $Uri = $null
        foreach ($n in 'nextLink', '@odata.nextLink') {
            if ($page.PSObject.Properties[$n] -and $page.$n) { $Uri = $page.$n }
        }
    }
    return $items
}

function Get-Prop($Object, [string] $Name) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}

$PowerApps = 'https://service.powerapps.com/'
$Flow = 'https://service.flow.microsoft.com/'
$Graph = 'https://graph.microsoft.com/'

$script:Users = @{}
function Resolve-User([string] $ObjectId) {
    # Flows only carry the creator's object id. Fail soft: the report is still useful without a UPN.
    if (-not $ObjectId) { return $null }
    if (-not $script:Users.ContainsKey($ObjectId)) {
        try {
            $script:Users[$ObjectId] = Invoke-Api "https://graph.microsoft.com/v1.0/users/${ObjectId}?`$select=userPrincipalName,displayName,mail" $Graph
        }
        catch { $script:Users[$ObjectId] = $null }
    }
    return $script:Users[$ObjectId]
}

function Get-AppLaunchRecords([datetime] $Start, [datetime] $End, [double] $TimeoutMinutes) {
    # Audit log searches are asynchronous: create the query, wait for it, then page through its records.
    # All Power Apps app events are requested and narrowed to launches afterwards.
    $base = 'https://graph.microsoft.com/v1.0/security/auditLog/queries'
    $query = Invoke-Api $base $Graph 'Post' @{
        displayName         = "Inactive asset scan $($End.ToString('yyyy-MM-dd HH:mm'))Z"
        filterStartDateTime = $Start.ToString('yyyy-MM-ddTHH:mm:ssZ')
        filterEndDateTime   = $End.ToString('yyyy-MM-ddTHH:mm:ssZ')
        recordTypeFilters   = @('powerAppsApp')
    }
    $deadline = [datetime]::UtcNow.AddMinutes($TimeoutMinutes)
    $status = [string]$query.status
    while ($status -notin 'succeeded', 'failed', 'cancelled') {
        if ([datetime]::UtcNow -gt $deadline) { throw "audit log query $($query.id) was still '$status' after $TimeoutMinutes minute(s)" }
        Start-Sleep -Seconds 20
        $status = [string](Invoke-Api "$base/$($query.id)" $Graph).status
    }
    if ($status -ne 'succeeded') { throw "audit log query $($query.id) ended as '$status'" }
    return @(Get-AllPages "$base/$($query.id)/records?`$top=1000" $Graph)
}

# ---------- previous state (Dataverse) ----------
$px = $PublisherPrefix
$known = @{}
$launchesThrough = $null
if ($DataverseUrl) {
    Import-Module (Join-Path $PSScriptRoot 'Dataverse.psm1') -Force
    Connect-Dataverse $DataverseUrl
    foreach ($row in @(Get-DvAll "${px}_governedassets?`$select=${px}_assetid,${px}_stage,${px}_lastrunon,${px}_lastlaunchon,statecode")) {
        $known[[string]$row."${px}_assetid"] = $row
    }
    # The end of the audit window the last successful scan read. Launches before it are already stored per app.
    $prior = @(Get-DvAll "${px}_assetscans?`$select=${px}_launchesthrough&`$filter=${px}_launchesthrough ne null&`$orderby=${px}_launchesthrough desc&`$top=1")
    if ($prior.Count -gt 0) { $launchesThrough = ConvertTo-UtcDate $prior[0]."${px}_launchesthrough" }
    Write-Host "Dataverse: $($known.Count) asset(s) already tracked"
}

# ---------- evaluation ----------
$records = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Record($Asset) {
    $latest = Get-LatestActivity -Signals $Asset.Signals
    if ($null -eq $latest) {
        $warnings.Add("$($Asset.AssetType) '$($Asset.DisplayName)' ($($Asset.AssetId)) has no activity timestamp; skipped.")
        return
    }
    $s = Get-InactiveAssetStage -LastActivity $latest.When -AsOf $now -Periods $periods
    $exemption = Get-ActiveExemption -Exemptions @($policy.exemptions) -AssetId $Asset.AssetId -AsOf $now
    $stage = $s.Stage
    if ($exemption -and $stage -ne 'Active') { $stage = 'Exempt' }

    $records.Add([pscustomobject][ordered]@{
            AssetType           = $Asset.AssetType
            AssetSubtype        = $Asset.AssetSubtype
            AssetId             = $Asset.AssetId
            DisplayName         = $Asset.DisplayName
            EnvironmentId       = $Asset.EnvironmentId
            EnvironmentName     = $Asset.EnvironmentName
            OwnerId             = $Asset.OwnerId
            OwnerUpn            = $Asset.OwnerUpn
            OwnerName           = $Asset.OwnerName
            PlatformState       = $Asset.PlatformState
            CreatedTime         = $Asset.CreatedTime
            LastModifiedTime    = $Asset.Signals['modified']
            LastRunTime         = $Asset.Signals['run']
            LastLaunchTime      = $Asset.Signals['launch']
            LastActivityTime    = $latest.When
            LastActivitySource  = $latest.Source
            UsageSignal         = $Asset.UsageSignal
            DaysInactive        = $s.DaysInactive
            Stage               = $stage
            ProjectedStage      = $s.Stage
            NextStage           = $s.NextStage
            NextStageOn         = $s.NextStageOn
            QuarantineWarningOn = $s.QuarantineWarningOn
            QuarantineOn        = $s.QuarantineOn
            DeleteWarningOn     = $s.DeleteWarningOn
            DeleteOn            = $s.DeleteOn
            ExemptReason        = $(if ($exemption) { [string](Get-Prop $exemption 'reason') } else { $null })
            ScanTime            = $scanTime
            EvaluatedAsOf       = $now
        })
}

# ---------- discovery ----------
$envs = @(Get-AllPages 'https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2021-04-01' $PowerApps)
$envs = @($envs | Where-Object { ($include.Count -eq 0 -or $include -contains $_.name) -and ($exclude -notcontains $_.name) })
Write-Host "Scanning $($envs.Count) environment(s), evaluating as of $($now.ToString('u'))"

# A flow modified inside the inactivity window is active regardless of runs, so its run history is not fetched.
$activeCutoff = $now.AddDays(-$periods.inactiveDays)
$pendingApps = New-Object System.Collections.Generic.List[hashtable]
# Environment and asset type pairs whose listing returned something. An empty listing can mean "none exist" or
# "this identity cannot see them", so only a non-empty one is trusted when deciding an asset is gone.
$listed = @{}

foreach ($environment in $envs) {
    $envId = $environment.name
    $envName = $environment.properties.displayName

    if ($assetTypes -contains 'app') {
        $apps = @(Get-AllPages "https://api.powerapps.com/providers/Microsoft.PowerApps/scopes/admin/environments/$envId/apps?api-version=2016-11-01" $PowerApps)
        Write-Host "  $envName : $($apps.Count) app(s)"
        if ($apps.Count -gt 0) { $listed["$envId|app"] = $true }
        foreach ($a in $apps) {
            $p = $a.properties
            $owner = Get-Prop $p 'owner'
            # Apps are evaluated after the loop, once launches for the whole tenant have been read.
            $pendingApps.Add(@{
                    AssetType = 'app'; AssetSubtype = (Get-Prop $a 'appType'); AssetId = $a.name; DisplayName = $p.displayName
                    EnvironmentId = $envId; EnvironmentName = $envName
                    OwnerId = (Get-Prop $owner 'id'); OwnerUpn = (Get-Prop $owner 'userPrincipalName'); OwnerName = (Get-Prop $owner 'displayName')
                    PlatformState = $null; CreatedTime = (ConvertTo-UtcDate (Get-Prop $p 'createdTime'))
                    Signals = @{ modified = (ConvertTo-UtcDate (Get-Prop $p 'lastModifiedTime')); run = $null; launch = $null }
                    UsageSignal = 'unavailable'
                })
        }
    }

    if ($assetTypes -contains 'flow') {
        $flows = @(Get-AllPages "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/scopes/admin/environments/$envId/v2/flows?api-version=2016-11-01" $Flow)
        Write-Host "  $envName : $($flows.Count) flow(s)"
        if ($flows.Count -gt 0) { $listed["$envId|flow"] = $true }
        foreach ($f in $flows) {
            $p = $f.properties
            # Flows shipped inside managed solutions (Microsoft's or a vendor's) are not the maker's to lose.
            if ($excludeManaged -and (Get-Prop $p 'isManaged') -eq $true) { $skippedManaged++; continue }
            $modified = ConvertTo-UtcDate (Get-Prop $p 'lastModifiedTime')
            $lastRun = $null
            $usage = 'not-needed'
            if ($null -eq $modified -or $modified -lt $activeCutoff) {
                try {
                    $runs = Invoke-Api "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/scopes/admin/environments/$envId/flows/$($f.name)/runs?api-version=2016-11-01&`$top=1" $Flow
                    $usage = 'run-history'
                    foreach ($r in @($runs.value)) {
                        if ($null -eq $r) { continue }
                        $start = ConvertTo-UtcDate (Get-Prop $r.properties 'startTime')
                        if ($null -ne $start -and ($null -eq $lastRun -or $start -gt $lastRun)) { $lastRun = $start }
                    }
                }
                catch {
                    $usage = 'unavailable'
                    $warnings.Add("Run history unavailable for flow '$($p.displayName)' ($($f.name)): $($_.Exception.Message)")
                }
            }
            # Run history only reaches back about 28 days; keep the latest run ever seen for this flow.
            if ($known.ContainsKey($f.name)) {
                $storedRun = ConvertTo-UtcDate (Get-Prop $known[$f.name] "${px}_lastrunon")
                if ($null -ne $storedRun -and ($null -eq $lastRun -or $storedRun -gt $lastRun)) { $lastRun = $storedRun }
            }
            $creatorId = Get-Prop (Get-Prop $p 'creator') 'objectId'
            $user = Resolve-User $creatorId
            Add-Record @{
                AssetType = 'flow'; AssetSubtype = $null; AssetId = $f.name; DisplayName = $p.displayName
                EnvironmentId = $envId; EnvironmentName = $envName
                OwnerId = $creatorId; OwnerUpn = (Get-Prop $user 'userPrincipalName'); OwnerName = (Get-Prop $user 'displayName')
                PlatformState = (Get-Prop $p 'state'); CreatedTime = (ConvertTo-UtcDate (Get-Prop $p 'createdTime'))
                Signals = @{ modified = $modified; run = $lastRun }
                UsageSignal = $usage
            }
        }
    }
}

# ---------- app launches (audit log) ----------
$launchNote = 'App results rest on **last modification only**: app launches were not read on this run, so an app that is used daily but not edited shows as inactive.'
$launchWindowEnd = $null
if ($pendingApps.Count -gt 0) {
    $launches = @{}
    if ($SkipLaunchSignal -or -not $launchCfg.enabled) {
        Write-Host 'App launches: skipped'
    }
    else {
        # The audit log is read in real time even when -AsOf moves the evaluation date.
        $windowStart = $scanTime.AddDays(-[double]$launchCfg.lookbackDays)
        if ($null -ne $launchesThrough -and $launchesThrough.AddDays(-2) -gt $windowStart) { $windowStart = $launchesThrough.AddDays(-2) } # overlap covers late-arriving events
        try {
            Write-Host "App launches: querying the audit log from $($windowStart.ToString('u')) (this can take several minutes)"
            $auditRecords = @(Get-AppLaunchRecords $windowStart $scanTime ([double]$launchCfg.timeoutMinutes))
            foreach ($g in @($auditRecords | Group-Object operation)) { Write-Host "  audit: $($g.Count) x $($g.Name)" }
            $launchRecords = @($auditRecords | Where-Object { [string]$_.operation -like '*Launch*' })
            $launches = Get-LatestLaunchByApp -Records $launchRecords -AppIds @($pendingApps | ForEach-Object { $_.AssetId })
            $launchWindowEnd = $scanTime
            foreach ($app in $pendingApps) { $app.UsageSignal = 'audit-log' }
            $launchNote = "App launches were read from the audit log from $($windowStart.ToString('yyyy-MM-dd')): $($launchRecords.Count) launch event(s) across $($launches.Count) app(s)."
            Write-Host "App launches: $($launchRecords.Count) launch event(s), $($launches.Count) app(s) matched"
        }
        catch {
            $why = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $why = "$why $($_.ErrorDetails.Message)" }
            $warnings.Add("App launches could not be read from the audit log, so apps were judged on modification only: $why")
            Write-Host "App launches: unavailable ($why)"
        }
    }
    foreach ($app in $pendingApps) {
        $launch = $null
        if ($launches.ContainsKey($app.AssetId.ToLower())) { $launch = $launches[$app.AssetId.ToLower()] }
        # The audit log is only kept for a limited time; keep the latest launch ever seen for this app.
        if ($known.ContainsKey($app.AssetId)) {
            $stored = ConvertTo-UtcDate (Get-Prop $known[$app.AssetId] "${px}_lastlaunchon")
            if ($null -ne $stored -and ($null -eq $launch -or $stored -gt $launch)) { $launch = $stored }
        }
        $app.Signals['launch'] = $launch
        Add-Record $app
    }
}

# ---------- output ----------
$stageOrder = @('Delete', 'DeleteWarning', 'Quarantine', 'QuarantineWarning', 'Exempt', 'Active')
$sorted = @($records | Sort-Object @{ Expression = { [array]::IndexOf($stageOrder, $_.Stage) } }, @{ Expression = 'DaysInactive'; Descending = $true })

function Format-Date($d) { if ($null -eq $d) { return '' } return ([datetime]$d).ToString('yyyy-MM-dd') }

New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
$report = [ordered]@{
    scanTime      = $scanTime
    evaluatedAsOf = $now
    mode          = 'report'
    periods       = $periods
    counts        = [ordered]@{}
    warnings      = @($warnings)
    assets        = $sorted
}
foreach ($st in $stageOrder) { $report.counts[$st] = @($sorted | Where-Object Stage -eq $st).Count }
$report | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $OutputPath 'inactive-assets.json') -Encoding utf8
$sorted | Export-Csv -Path (Join-Path $OutputPath 'inactive-assets.csv') -NoTypeInformation -Encoding utf8

$md = New-Object System.Collections.Generic.List[string]
$md.Add('## Inactive asset scan (report only, nothing was changed)')
$md.Add('')
$md.Add("Evaluated as of **$($now.ToString('u'))**. Periods (days): inactive $($periods.inactiveDays), quarantine warning $($periods.quarantineWarningDays), quarantined $($periods.quarantinedDays), delete warning $($periods.deleteWarningDays).")
$md.Add('')
$md.Add('| Would be | Count |')
$md.Add('|---|---|')
$labels = [ordered]@{ Delete = 'Deleted'; DeleteWarning = 'Warned of deletion'; Quarantine = 'Quarantined'; QuarantineWarning = 'Warned of quarantine'; Exempt = 'Exempt'; Active = 'Left alone (active)' }
foreach ($st in $stageOrder) { $md.Add("| $($labels[$st]) | $($report.counts[$st]) |") }
$flagged = @($sorted | Where-Object { $_.Stage -ne 'Active' })
if ($flagged.Count -gt 0) {
    $md.Add('')
    $md.Add('| Stage | Type | Name | Environment | Owner | Last activity | Source | Days inactive | Next step | Usage signal |')
    $md.Add('|---|---|---|---|---|---|---|---|---|---|')
    foreach ($r in $flagged) {
        $next = ''
        if ($r.Stage -eq 'Exempt') { $next = "exempt: $($r.ExemptReason)" }
        elseif ($r.NextStage) { $next = "$($r.NextStage) on $(Format-Date $r.NextStageOn)" }
        $who = $r.OwnerUpn; if (-not $who) { $who = $r.OwnerId }
        $md.Add("| $($r.Stage) | $($r.AssetType) | $(([string]$r.DisplayName).Replace('|', '/')) | $($r.EnvironmentName) | $who | $(Format-Date $r.LastActivityTime) | $($r.LastActivitySource) | $($r.DaysInactive) | $next | $($r.UsageSignal) |")
    }
}
if (@($sorted | Where-Object { $_.AssetType -eq 'app' }).Count -gt 0) {
    $md.Add('')
    $md.Add("> $launchNote")
}
if ($skippedManaged -gt 0) {
    $md.Add('')
    $md.Add("$skippedManaged flow(s) from managed solutions were skipped (excludeManaged).")
}
if ($warnings.Count -gt 0) {
    $md.Add('')
    $md.Add('**Warnings**')
    foreach ($w in $warnings) { $md.Add("- $w") }
}
$md | Set-Content -Path (Join-Path $OutputPath 'summary.md') -Encoding utf8
if ($env:GITHUB_STEP_SUMMARY) { $md | Add-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding utf8 }

# ---------- Dataverse log ----------
if ($DataverseUrl) {
    function Iso($d) { if ($null -eq $d) { return $null } return ([datetime]$d).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }

    # Choice values by label with spaces removed, e.g. 'QuarantineWarning' -> 910270001.
    $stageValue = @{}; $stageName = @{}
    foreach ($o in (Invoke-Dv GET "GlobalOptionSetDefinitions(Name='${px}_assetlifecyclestage')").Options) {
        $label = ([string]$o.Label.UserLocalizedLabel.Label).Replace(' ', '')
        $stageValue[$label] = [int]$o.Value; $stageName[[int]$o.Value] = $label
    }
    $typeValue = @{}
    foreach ($o in (Invoke-Dv GET "GlobalOptionSetDefinitions(Name='${px}_assettype')").Options) { $typeValue[([string]$o.Label.UserLocalizedLabel.Label).ToLower()] = [int]$o.Value }

    $isTest = ($null -ne $AsOf) -or ($null -ne $InactiveDays) -or ($null -ne $QuarantineWarningDays) -or ($null -ne $QuarantinedDays) -or ($null -ne $DeleteWarningDays)
    $runUrl = $null
    if ($env:GITHUB_RUN_ID) { $runUrl = "$($env:GITHUB_SERVER_URL)/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)" }
    $scanId = Invoke-Dv POST "${px}_assetscans" @{
        "${px}_name"                   = "Scan $($scanTime.ToString('yyyy-MM-dd HH:mm'))Z"
        "${px}_scanon"                 = (Iso $scanTime)
        "${px}_evaluatedasof"          = (Iso $now)
        "${px}_mode"                   = 'report'
        "${px}_istest"                 = $isTest
        "${px}_inactivedays"           = $periods.inactiveDays
        "${px}_quarantinewarningdays"  = $periods.quarantineWarningDays
        "${px}_quarantineddays"        = $periods.quarantinedDays
        "${px}_deletewarningdays"      = $periods.deleteWarningDays
        "${px}_totalcount"             = $sorted.Count
        "${px}_activecount"            = $report.counts['Active']
        "${px}_quarantinewarningcount" = $report.counts['QuarantineWarning']
        "${px}_quarantinecount"        = $report.counts['Quarantine']
        "${px}_deletewarningcount"     = $report.counts['DeleteWarning']
        "${px}_deletecount"            = $report.counts['Delete']
        "${px}_exemptcount"            = $report.counts['Exempt']
        "${px}_runurl"                 = $runUrl
        "${px}_launchesthrough"        = (Iso $launchWindowEnd)
    } -ReturnId

    $events = 0
    foreach ($r in $sorted) {
        $isNew = -not $known.ContainsKey($r.AssetId)
        $row = @{
            "${px}_name"                = ([string]$r.DisplayName)
            "${px}_assettype"           = $typeValue[$r.AssetType]
            "${px}_subtype"             = $r.AssetSubtype
            "${px}_environmentid"       = $r.EnvironmentId
            "${px}_environmentname"     = $r.EnvironmentName
            "${px}_ownerobjectid"       = $r.OwnerId
            "${px}_ownerupn"            = $r.OwnerUpn
            "${px}_ownername"           = $r.OwnerName
            "${px}_platformstate"       = $r.PlatformState
            "${px}_assetcreatedon"      = (Iso $r.CreatedTime)
            "${px}_lastmodifiedon"      = (Iso $r.LastModifiedTime)
            "${px}_lastrunon"           = (Iso $r.LastRunTime)
            "${px}_lastlaunchon"        = (Iso $r.LastLaunchTime)
            "${px}_lastactivityon"      = (Iso $r.LastActivityTime)
            "${px}_lastactivitysource"  = $r.LastActivitySource
            "${px}_usagesignal"         = $r.UsageSignal
            "${px}_daysinactive"        = [math]::Min([double]$r.DaysInactive, 1000000)
            "${px}_stage"               = $stageValue[$r.Stage]
            "${px}_nextstage"           = $r.NextStage
            "${px}_nextstageon"         = (Iso $r.NextStageOn)
            "${px}_quarantinewarningon" = (Iso $r.QuarantineWarningOn)
            "${px}_quarantineon"        = (Iso $r.QuarantineOn)
            "${px}_deletewarningon"     = (Iso $r.DeleteWarningOn)
            "${px}_deleteon"            = (Iso $r.DeleteOn)
            "${px}_exemptreason"        = $r.ExemptReason
            "${px}_lastscanon"          = (Iso $scanTime)
            statecode                   = 0
            statuscode                  = 1
        }
        if ($isNew) { $row["${px}_firstseenon"] = (Iso $scanTime) }
        Invoke-Dv PATCH "${px}_governedassets(${px}_assetid='$($r.AssetId)')" $row | Out-Null

        # An event for every change of stage. A newly seen asset that is simply active is not news.
        $from = $null
        if (-not $isNew) { $from = Get-Prop $known[$r.AssetId] "${px}_stage" }
        $to = $stageValue[$r.Stage]
        if (($isNew -and $r.Stage -ne 'Active') -or (-not $isNew -and $from -ne $to)) {
            $fromLabel = 'New'; if ($null -ne $from) { $fromLabel = $stageName[[int]$from] }
            Invoke-Dv POST "${px}_assetevents" @{
                "${px}_name"             = "$($r.DisplayName): $fromLabel to $($r.Stage)"
                "${px}_eventon"          = (Iso $now)
                "${px}_fromstage"        = $from
                "${px}_tostage"          = $to
                "${px}_daysinactive"     = [math]::Min([double]$r.DaysInactive, 1000000)
                "${px}_asset@odata.bind" = "/${px}_governedassets(${px}_assetid='$($r.AssetId)')"
                "${px}_scan@odata.bind"  = "/${px}_assetscans($scanId)"
            } | Out-Null
            $events++
        }
    }

    # Assets in the scanned scope that no longer exist in the tenant are deactivated, not deleted: history stays.
    $seen = @{}; foreach ($r in $sorted) { $seen[$r.AssetId] = $true }
    $typeName = @{}; foreach ($k in $typeValue.Keys) { $typeName[[int]$typeValue[$k]] = $k }
    $gone = 0
    foreach ($row in @(Get-DvAll "${px}_governedassets?`$select=${px}_assetid,${px}_environmentid,${px}_assettype&`$filter=statecode eq 0")) {
        if ($seen.ContainsKey([string]$row."${px}_assetid")) { continue }
        if (-not $listed.ContainsKey("$($row."${px}_environmentid")|$($typeName[[int]$row."${px}_assettype"])")) { continue }
        Invoke-Dv PATCH "${px}_governedassets($($row."${px}_governedassetid"))" @{ statecode = 1; statuscode = 2 } | Out-Null
        $gone++
    }
    Write-Host "Dataverse: scan $scanId logged, $($sorted.Count) asset(s) upserted, $events event(s), $gone no longer present"
}

Write-Host ''
foreach ($st in $stageOrder) { Write-Host ("{0,-18} {1}" -f $st, $report.counts[$st]) }
Write-Host "Report written to $OutputPath"

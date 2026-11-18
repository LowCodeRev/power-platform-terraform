<#
.SYNOPSIS
Inactive asset policy scan (report only). Lists every app and cloud flow in the tenant and reports which ones
the policy would warn about, quarantine or delete. It changes nothing in the tenant.

.DESCRIPTION
Policy values come from policies/inactive-assets.json; any period can be overridden per run for testing, and
-AsOf evaluates the policy as if "now" were another date.

Signals used for "last activity":
  apps   lastModifiedTime from the Power Apps admin API. App launches are NOT available from that API; until a
         launch signal is wired in (Purview audit log), app results rest on modification only and are marked
         UsageSignal = unavailable.
  flows  lastModifiedTime plus the most recent run from run history (the platform keeps about 28 days).

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
    [Nullable[datetime]] $AsOf
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

function Invoke-Api([string] $Uri, [string] $Resource) {
    for ($attempt = 1; ; $attempt++) {
        try {
            return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $(Get-Token $Resource)" }
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
        if ($page.PSObject.Properties['nextLink'] -and $page.nextLink) { $Uri = $page.nextLink }
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

foreach ($environment in $envs) {
    $envId = $environment.name
    $envName = $environment.properties.displayName

    if ($assetTypes -contains 'app') {
        $apps = @(Get-AllPages "https://api.powerapps.com/providers/Microsoft.PowerApps/scopes/admin/environments/$envId/apps?api-version=2016-11-01" $PowerApps)
        Write-Host "  $envName : $($apps.Count) app(s)"
        foreach ($a in $apps) {
            $p = $a.properties
            $owner = Get-Prop $p 'owner'
            Add-Record @{
                AssetType = 'app'; AssetSubtype = (Get-Prop $a 'appType'); AssetId = $a.name; DisplayName = $p.displayName
                EnvironmentId = $envId; EnvironmentName = $envName
                OwnerId = (Get-Prop $owner 'id'); OwnerUpn = (Get-Prop $owner 'userPrincipalName'); OwnerName = (Get-Prop $owner 'displayName')
                PlatformState = $null; CreatedTime = (ConvertTo-UtcDate (Get-Prop $p 'createdTime'))
                Signals = @{ modified = (ConvertTo-UtcDate (Get-Prop $p 'lastModifiedTime')); run = $null }
                UsageSignal = 'unavailable'
            }
        }
    }

    if ($assetTypes -contains 'flow') {
        $flows = @(Get-AllPages "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/scopes/admin/environments/$envId/v2/flows?api-version=2016-11-01" $Flow)
        Write-Host "  $envName : $($flows.Count) flow(s)"
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
    $md.Add('> App results rest on **last modification only**: no app launch signal is wired in yet, so an app that is used daily but not edited shows as inactive.')
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

Write-Host ''
foreach ($st in $stageOrder) { Write-Host ("{0,-18} {1}" -f $st, $report.counts[$st]) }
Write-Host "Report written to $OutputPath"

# Pure policy logic for the inactive asset lifecycle. No network calls live here, so it is unit-testable
# (see tests/InactiveAssets.Tests.ps1). Written to run on both Windows PowerShell 5.1 and PowerShell 7.

Set-StrictMode -Version Latest

function ConvertTo-UtcDate {
    # ConvertFrom-Json yields DateTime on PowerShell 7 and strings on 5.1; accept both.
    param($Value)
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    if ($Value -is [datetime]) {
        # A bare date such as -AsOf 2027-06-01 has no zone; read it as UTC rather than the machine's local time.
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) { return [datetime]::SpecifyKind($Value, [DateTimeKind]::Utc) }
        return $Value.ToUniversalTime()
    }
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime }
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    return [datetime]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles)
}

function Get-InactiveAssetStage {
    <#
    .SYNOPSIS
    Places an asset on the lifecycle timeline from its last activity alone.

    .DESCRIPTION
    Timeline, measured from the last activity (modification, run or use):

        0 ........ inactiveDays ........ +quarantineWarningDays ........ +quarantinedDays ........ +deleteWarningDays
        | Active  | QuarantineWarning   | Quarantine                    | DeleteWarning          | Delete

    Report mode is a projection: it answers "where would this asset be if the policy had been running all
    along". Enforce mode must instead anchor each clock on the date the owner was actually notified, so that
    nothing is quarantined or deleted without its full warning period.
    #>
    param(
        [Parameter(Mandatory)] [datetime] $LastActivity,
        [Parameter(Mandatory)] [datetime] $AsOf,
        [Parameter(Mandatory)] $Periods
    )

    $inactive = [double]$Periods.inactiveDays
    $warnQ = [double]$Periods.quarantineWarningDays
    $quarantined = [double]$Periods.quarantinedDays
    $warnD = [double]$Periods.deleteWarningDays
    foreach ($p in @($inactive, $warnQ, $quarantined, $warnD)) {
        if ($p -lt 0) { throw "Policy periods must not be negative." }
    }

    $last = $LastActivity.ToUniversalTime()
    $quarantineWarningOn = $last.AddDays($inactive)
    $quarantineOn = $quarantineWarningOn.AddDays($warnQ)
    $deleteWarningOn = $quarantineOn.AddDays($quarantined)
    $deleteOn = $deleteWarningOn.AddDays($warnD)

    $now = $AsOf.ToUniversalTime()
    if ($now -ge $deleteOn) { $stage = 'Delete'; $next = $null; $nextOn = $null }
    elseif ($now -ge $deleteWarningOn) { $stage = 'DeleteWarning'; $next = 'Delete'; $nextOn = $deleteOn }
    elseif ($now -ge $quarantineOn) { $stage = 'Quarantine'; $next = 'DeleteWarning'; $nextOn = $deleteWarningOn }
    elseif ($now -ge $quarantineWarningOn) { $stage = 'QuarantineWarning'; $next = 'Quarantine'; $nextOn = $quarantineOn }
    else { $stage = 'Active'; $next = 'QuarantineWarning'; $nextOn = $quarantineWarningOn }

    [pscustomobject]@{
        Stage               = $stage
        DaysInactive        = [math]::Round(($now - $last).TotalDays, 2)
        NextStage           = $next
        NextStageOn         = $nextOn
        QuarantineWarningOn = $quarantineWarningOn
        QuarantineOn        = $quarantineOn
        DeleteWarningOn     = $deleteWarningOn
        DeleteOn            = $deleteOn
    }
}

function Get-LatestActivity {
    # Picks the most recent of several named timestamps. Returns $null when none is set.
    param([Parameter(Mandatory)] [hashtable] $Signals)
    $best = $null
    foreach ($name in $Signals.Keys) {
        $when = ConvertTo-UtcDate $Signals[$name]
        if ($null -eq $when) { continue }
        if ($null -eq $best -or $when -gt $best.When) { $best = [pscustomobject]@{ Source = $name; When = $when } }
    }
    return $best
}

function Get-LatestLaunchByApp {
    # Latest launch per app from audit log records. The shape of auditData differs between event versions, so an
    # event is attributed to an app when one of the known app ids appears anywhere in it. Keys are lower-case ids.
    param([object[]] $Records, [string[]] $AppIds)
    $wanted = @{}
    foreach ($id in @($AppIds)) { if ($id) { $wanted[$id.ToLower()] = $true } }
    $latest = @{}
    foreach ($r in @($Records)) {
        if ($null -eq $r) { continue }
        $when = $null
        if ($r.PSObject.Properties['createdDateTime']) { $when = ConvertTo-UtcDate $r.createdDateTime }
        if ($null -eq $when) { continue }
        $text = ($r | ConvertTo-Json -Depth 20 -Compress).ToLower()
        foreach ($m in [regex]::Matches($text, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')) {
            $id = $m.Value
            if (-not $wanted.ContainsKey($id)) { continue }
            if (-not $latest.ContainsKey($id) -or $when -gt $latest[$id]) { $latest[$id] = $when }
        }
    }
    return $latest
}

function Get-ActiveExemption {
    # An exemption matches on assetId and applies until its optional "expires" date.
    param($Exemptions, [Parameter(Mandatory)] [string] $AssetId, [Parameter(Mandatory)] [datetime] $AsOf)
    foreach ($e in @($Exemptions)) {
        if ($null -eq $e) { continue }
        if ([string]$e.assetId -ne $AssetId) { continue }
        $expires = $null
        if ($e.PSObject.Properties['expires']) { $expires = ConvertTo-UtcDate $e.expires }
        if ($null -eq $expires -or $expires -gt $AsOf.ToUniversalTime()) { return $e }
    }
    return $null
}

Export-ModuleMember -Function ConvertTo-UtcDate, Get-InactiveAssetStage, Get-LatestActivity, Get-LatestLaunchByApp, Get-ActiveExemption

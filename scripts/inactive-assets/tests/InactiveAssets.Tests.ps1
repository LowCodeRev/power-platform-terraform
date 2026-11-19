# Pester 5. Run: Invoke-Pester scripts/inactive-assets/tests
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\InactiveAssets.psm1') -Force
    $script:Periods = [pscustomobject]@{ inactiveDays = 90; quarantineWarningDays = 14; quarantinedDays = 90; deleteWarningDays = 14 }
    $script:Last = [datetime]::new(2026, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
}

Describe 'Get-InactiveAssetStage' {
    It 'is <Stage> after <Days> days' -ForEach @(
        @{ Days = 0; Stage = 'Active' }
        @{ Days = 89.9; Stage = 'Active' }
        @{ Days = 90; Stage = 'QuarantineWarning' }
        @{ Days = 103.9; Stage = 'QuarantineWarning' }
        @{ Days = 104; Stage = 'Quarantine' }
        @{ Days = 193.9; Stage = 'Quarantine' }
        @{ Days = 194; Stage = 'DeleteWarning' }
        @{ Days = 207.9; Stage = 'DeleteWarning' }
        @{ Days = 208; Stage = 'Delete' }
        @{ Days = 1000; Stage = 'Delete' }
    ) {
        (Get-InactiveAssetStage -LastActivity $Last -AsOf $Last.AddDays($Days) -Periods $Periods).Stage | Should -Be $Stage
    }

    It 'reports the dates of each step' {
        $s = Get-InactiveAssetStage -LastActivity $Last -AsOf $Last.AddDays(95) -Periods $Periods
        $s.QuarantineWarningOn | Should -Be $Last.AddDays(90)
        $s.QuarantineOn | Should -Be $Last.AddDays(104)
        $s.DeleteWarningOn | Should -Be $Last.AddDays(194)
        $s.DeleteOn | Should -Be $Last.AddDays(208)
        $s.NextStage | Should -Be 'Quarantine'
        $s.NextStageOn | Should -Be $Last.AddDays(104)
        $s.DaysInactive | Should -Be 95
    }

    It 'honours fractional periods for testing' {
        $short = [pscustomobject]@{ inactiveDays = 0.5; quarantineWarningDays = 0.25; quarantinedDays = 0.5; deleteWarningDays = 0.25 }
        (Get-InactiveAssetStage -LastActivity $Last -AsOf $Last.AddHours(13) -Periods $short).Stage | Should -Be 'QuarantineWarning'
        (Get-InactiveAssetStage -LastActivity $Last -AsOf $Last.AddHours(37) -Periods $short).Stage | Should -Be 'Delete'
    }

    It 'rejects negative periods' {
        $bad = [pscustomobject]@{ inactiveDays = -1; quarantineWarningDays = 14; quarantinedDays = 90; deleteWarningDays = 14 }
        { Get-InactiveAssetStage -LastActivity $Last -AsOf $Last -Periods $bad } | Should -Throw
    }
}

Describe 'Get-LatestActivity' {
    It 'picks the most recent signal and names it' {
        $r = Get-LatestActivity -Signals @{ modified = '2026-01-01T00:00:00Z'; run = '2026-03-01T00:00:00Z' }
        $r.Source | Should -Be 'run'
        $r.When | Should -Be ([datetime]::new(2026, 3, 1, 0, 0, 0, [DateTimeKind]::Utc))
    }
    It 'ignores missing signals' {
        (Get-LatestActivity -Signals @{ modified = '2026-01-01T00:00:00Z'; run = $null }).Source | Should -Be 'modified'
        Get-LatestActivity -Signals @{ modified = $null; run = $null } | Should -BeNullOrEmpty
    }
}

Describe 'Get-LatestLaunchByApp' {
    BeforeAll {
        $script:AppA = '11111111-1111-1111-1111-111111111111'
        $script:AppB = '22222222-2222-2222-2222-222222222222'
        $script:Recs = @(
            [pscustomobject]@{ createdDateTime = '2026-03-01T10:00:00Z'; operation = 'LaunchPowerApp'; auditData = [pscustomobject]@{ AppName = "/providers/Microsoft.PowerApps/apps/$AppA" } }
            [pscustomobject]@{ createdDateTime = '2026-04-01T10:00:00Z'; operation = 'LaunchPowerApp'; auditData = [pscustomobject]@{ PropertyCollection = @([pscustomobject]@{ Name = 'resource.id'; Value = $AppA.ToUpper() }) } }
            [pscustomobject]@{ createdDateTime = '2026-05-01T10:00:00Z'; operation = 'LaunchPowerApp'; auditData = [pscustomobject]@{ AppName = '33333333-3333-3333-3333-333333333333' } }
        )
    }
    It 'keeps the latest launch per known app, wherever the id sits in the event' {
        $r = Get-LatestLaunchByApp -Records $Recs -AppIds @($AppA, $AppB)
        $r.Count | Should -Be 1
        $r[$AppA] | Should -Be ([datetime]::new(2026, 4, 1, 10, 0, 0, [DateTimeKind]::Utc))
    }
    It 'returns nothing for no records' {
        (Get-LatestLaunchByApp -Records @() -AppIds @($AppA)).Count | Should -Be 0
    }
}

Describe 'Get-ActiveExemption' {
    BeforeAll {
        $script:Ex = @(
            [pscustomobject]@{ assetId = 'a'; reason = 'forever' }
            [pscustomobject]@{ assetId = 'b'; reason = 'temporary'; expires = '2026-06-01' }
        )
    }
    It 'matches an exemption without an expiry' {
        (Get-ActiveExemption -Exemptions $Ex -AssetId 'a' -AsOf $Last).reason | Should -Be 'forever'
    }
    It 'matches before expiry and not after' {
        (Get-ActiveExemption -Exemptions $Ex -AssetId 'b' -AsOf $Last).reason | Should -Be 'temporary'
        Get-ActiveExemption -Exemptions $Ex -AssetId 'b' -AsOf ([datetime]'2026-07-01') | Should -BeNullOrEmpty
    }
    It 'returns nothing for other assets or an empty list' {
        Get-ActiveExemption -Exemptions $Ex -AssetId 'c' -AsOf $Last | Should -BeNullOrEmpty
        Get-ActiveExemption -Exemptions @() -AssetId 'a' -AsOf $Last | Should -BeNullOrEmpty
    }
}

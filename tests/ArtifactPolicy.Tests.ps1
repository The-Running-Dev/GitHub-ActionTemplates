#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'actions' '_lib' 'Functions.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    $script:PolicyScript = Join-Path $PSScriptRoot '..' 'actions' 'artifact-policy' 'artifact-policy.ps1'
}

Describe 'Artifact upload decisions' {
    It '<Policy> on <Status> with required=<Required> selects upload=<Upload>' -ForEach @(
        @{ Policy = 'never'; Status = 'success'; Required = $false; Upload = $false }
        @{ Policy = 'failure'; Status = 'success'; Required = $false; Upload = $false }
        @{ Policy = 'always'; Status = 'success'; Required = $false; Upload = $true }
        @{ Policy = 'never'; Status = 'failure'; Required = $false; Upload = $false }
        @{ Policy = 'failure'; Status = 'failure'; Required = $false; Upload = $true }
        @{ Policy = 'always'; Status = 'failure'; Required = $false; Upload = $true }
        @{ Policy = 'never'; Status = 'success'; Required = $true; Upload = $true }
        @{ Policy = 'failure'; Status = 'success'; Required = $true; Upload = $true }
        @{ Policy = 'always'; Status = 'success'; Required = $true; Upload = $true }
        @{ Policy = 'never'; Status = 'failure'; Required = $true; Upload = $false }
        @{ Policy = 'failure'; Status = 'failure'; Required = $true; Upload = $false }
        @{ Policy = 'always'; Status = 'failure'; Required = $true; Upload = $false }
        @{ Policy = 'always'; Status = 'cancelled'; Required = $false; Upload = $false }
        @{ Policy = 'always'; Status = 'cancelled'; Required = $true; Upload = $false }
        @{ Policy = 'always'; Status = 'skipped'; Required = $false; Upload = $false }
        @{ Policy = 'always'; Status = 'skipped'; Required = $true; Upload = $false }
    ) {
        $decision = Get-ArtifactPolicy -Policy $Policy -Status $Status -Required $Required -RetentionDays 3 -RequiredRetentionDays 7
        $decision.Upload | Should -Be $Upload
        $decision.Required | Should -Be $Required
        $decision.RetentionDays | Should -Be $(if ($Required) { 7 } else { 3 })
    }

    It 'rejects invalid lifetime <_> even when uploads are disabled' -ForEach @('0', '-1', '1.5', '91', 'abc', '999999999999999') {
        { Get-ArtifactPolicy -RetentionDays $_ } | Should -Throw '*integer from 1 to 90*'
        { Get-ArtifactPolicy -RequiredRetentionDays $_ } | Should -Throw '*integer from 1 to 90*'
    }

    It 'rejects misspelled policies instead of silently skipping output' {
        { Get-ArtifactPolicy -Policy 'alway' } | Should -Throw
    }

    It 'maps action inputs to required transfer outputs and summary' {
        $result = Invoke-ActionScript $PolicyScript -Environment @{
            INPUT_POLICY = 'never'; INPUT_REQUIRED = 'true'; INPUT_STATUS = 'success'
            INPUT_RETENTION_DAYS = '3'; INPUT_REQUIRED_RETENTION_DAYS = '7'
        }
        $result.ExitCode | Should -Be 0
        $result.Outputs['upload'] | Should -Be 'true'
        $result.Outputs['required'] | Should -Be 'true'
        $result.Outputs['retention-days'] | Should -Be '7'
        $result.Summary | Should -Match 'retention: \*\*7 day'
    }

    It 'retains failed-job diagnostics without making them required transport' {
        $result = Invoke-ActionScript $PolicyScript -Environment @{
            INPUT_POLICY = 'failure'; INPUT_STATUS = 'failure'; INPUT_RETENTION_DAYS = '3'
        }
        $result.ExitCode | Should -Be 0
        $result.Outputs['upload'] | Should -Be 'true'
        $result.Outputs['required'] | Should -Be 'false'
    }
}

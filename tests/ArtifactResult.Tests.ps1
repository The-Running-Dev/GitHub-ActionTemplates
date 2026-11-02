#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    $script:ResultScript = Join-Path $PSScriptRoot '..' 'actions' 'artifact-result' 'artifact-result.ps1'
}
Describe 'Unavailable artifact transport' {
    It 'warns and records a missing optional download without failing validation' {
        $result = Invoke-ActionScript $ResultScript -Environment @{ INPUT_OUTCOME = 'failure'; INPUT_REQUIRED = 'false' }
        $result.ExitCode | Should -Be 0
        $result.Summary | Should -Match 'no download is available'
        $result.Log | Should -Match '::warning::'
    }
    It 'fails clearly when a required transfer is unavailable' {
        $result = Invoke-ActionScript $ResultScript -Environment @{ INPUT_OUTCOME = 'failure'; INPUT_REQUIRED = 'true' }
        $result.ExitCode | Should -Not -Be 0
        $result.Summary | Should -Match 'cannot proceed'
    }
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'Fixture.Module.psd1') -Force
}

Describe 'Get-FixtureSum' {
    It 'adds the numbers' {
        Get-FixtureSum -Number 1, 2, 3 | Should -Be 6
    }

    It 'returns 0 for no numbers' {
        Get-FixtureSum | Should -Be 0
    }
}

Describe 'Get-FixtureGreeting' {
    It 'greets by name' {
        Get-FixtureGreeting -Name 'Octo' | Should -Be 'Hello, Octo.'
    }
}

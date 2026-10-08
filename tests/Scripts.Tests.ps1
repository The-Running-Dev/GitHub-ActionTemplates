#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

Describe 'Get-ChangelogSection' {
    BeforeAll {
        $script:Script = Join-Path $PSScriptRoot '..' 'scripts' 'Get-ChangelogSection.ps1'
        $script:Changelog = Join-Path $TestDrive 'CHANGELOG.md'
        Set-Content $Changelog @'
# Changelog

## [Unreleased]

## [1.1.0] - 2026-02-01

### Added
- Something new.

## [1.0.0] - 2026-01-01

## [0.9.0] - 2025-12-01

- Last entry.
'@
    }

    It 'returns the section body' {
        $notes = & $Script -Version 'v1.1.0' -Path $Changelog
        $notes | Should -Be "### Added`n- Something new."
    }

    It 'returns the last section' {
        & $Script -Version '0.9.0' -Path $Changelog | Should -Be '- Last entry.'
    }

    It 'fails for an empty section' {
        { & $Script -Version '1.0.0' -Path $Changelog } | Should -Throw '*is empty*'
    }

    It 'fails for a missing section' {
        { & $Script -Version '2.0.0' -Path $Changelog } | Should -Throw '*has no*'
    }

    It 'has notes for every version in the repository CHANGELOG' {
        $path = Join-Path $PSScriptRoot '..' 'CHANGELOG.md'
        $versions = Select-String -LiteralPath $path -Pattern '^##\s+\[(\d[^\]]*)\]' | ForEach-Object { $_.Matches[0].Groups[1].Value }

        $versions | Should -Not -BeNullOrEmpty
        foreach ($version in $versions) { { & $Script -Version $version -Path $path } | Should -Not -Throw }
    }
}

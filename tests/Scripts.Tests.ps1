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

Describe 'Initialize-ReleaseSigningKey' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
        $script:Script = Join-Path $PSScriptRoot '..' 'scripts' 'Initialize-ReleaseSigningKey.ps1'

        # A gh that keeps the repository's environment, branch policies and secrets in files under
        # STUB_LOG, and appends each call to gh.txt.
        $script:Stubs = Join-Path $TestDrive 'stubs'
        New-Item -ItemType Directory $Stubs | Out-Null
        Set-Content (Join-Path $Stubs 'gh.ps1') @'
$log = $env:STUB_LOG
Add-Content -LiteralPath (Join-Path $log 'gh.txt') -Value ($args -join ' ')
$environment = Join-Path $log 'environment.json'
$policies = Join-Path $log 'policies.txt'
$secret = Join-Path $log 'secret.txt'
if ($args[0] -eq 'auth') { exit 0 }
if ($args[0] -eq 'api' -and $args[1] -eq '-X' -and $args[2] -eq 'PUT') {
    Set-Content -LiteralPath $environment '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
    exit 0
}
if ($args[0] -eq 'api' -and $args[1] -eq '-X' -and $args[2] -eq 'POST') {
    Add-Content -LiteralPath $policies (($args | Where-Object { $_ -like 'name=*' }) -replace '^name=')
    exit 0
}
if ($args[0] -eq 'api' -and $args[1] -like '*/deployment-branch-policies') {
    if (Test-Path -LiteralPath $policies) { Get-Content -LiteralPath $policies }
    exit 0
}
if ($args[0] -eq 'api') {
    if (-not (Test-Path -LiteralPath $environment)) { exit 1 }
    Get-Content -LiteralPath $environment -Raw
    exit 0
}
if ($args[0] -eq 'secret' -and $args[1] -eq 'set') {
    Set-Content -LiteralPath $secret -Value ([string]::Concat(@($input))) -NoNewline
    Set-Content -LiteralPath (Join-Path $log 'secret-name.txt') $args[2]
    exit 0
}
if ($args[0] -eq 'secret' -and $args[1] -eq 'list') {
    if (Test-Path -LiteralPath $secret) { Get-Content -LiteralPath (Join-Path $log 'secret-name.txt') }
    exit 0
}
exit 1
'@

        function script:New-Folder([string] $Name) {
            $path = Join-Path $TestDrive "$Name-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
            New-Item -ItemType Directory $path | Out-Null
            return $path
        }

        function script:Invoke-Initialize([string] $Log, [string[]] $Arguments) {
            $environment = @{ PATH = "$Stubs$([IO.Path]::PathSeparator)$env:PATH"; STUB_LOG = $Log }
            Use-Environment $environment {
                $output = pwsh -NoProfile -NonInteractive -File $Script -Repository 'Octo-Org/Sample.Repo' @Arguments 2>&1
                [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
            }
        }

        function script:Get-GhCall([string] $Log) { Get-Content -LiteralPath (Join-Path $Log 'gh.txt') }
    }

    It 'creates the key, backs it up, restricts the environment and stores the secret' {
        $log = New-Folder 'log'; $keys = New-Folder 'keys'; $backup = New-Folder 'backup'
        $key = Join-Path $keys 'sample.repo-release-signing'
        $signers = Join-Path $keys 'allowed_signers'

        $result = Invoke-Initialize $log @('-KeyPath', $key, '-BackupDirectory', $backup, '-AllowedSignersPath', $signers)

        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Get-FileHash (Join-Path $backup 'sample.repo-release-signing')).Hash | Should -Be (Get-FileHash $key).Hash
        Get-Content (Join-Path $log 'secret.txt') -Raw | Should -Be (Get-Content $key -Raw)
        Get-Content (Join-Path $log 'secret-name.txt') | Should -Be 'RELEASE_SIGNING_KEY'
        Get-Content (Join-Path $log 'policies.txt') | Should -Be 'main'
        Get-GhCall $log | Should -Contain 'secret set RELEASE_SIGNING_KEY -R Octo-Org/Sample.Repo -e release'
        $public = ((ssh-keygen -y -P '' -f $key) -split '\s+')[0..1] -join ' '
        $line = "release-workflow@Sample.Repo namespaces=`"git`" $public"
        $result.Output | Should -Match ([regex]::Escape($line))
        Get-Content $signers | Should -Be $line
    }

    It 'reuses the key and changes nothing already in place' {
        $log = New-Folder 'log'; $keys = New-Folder 'keys'; $backup = New-Folder 'backup'
        $key = Join-Path $keys 'sample.repo-release-signing'
        $signers = Join-Path $keys 'allowed_signers'
        $arguments = @('-KeyPath', $key, '-BackupDirectory', $backup, '-AllowedSignersPath', $signers)
        (Invoke-Initialize $log $arguments).ExitCode | Should -Be 0
        $before = Get-FileHash $key
        Remove-Item (Join-Path $log 'gh.txt')

        $result = Invoke-Initialize $log $arguments

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'Reusing existing key'
        (Get-FileHash $key).Hash | Should -Be $before.Hash
        Get-GhCall $log | Where-Object { $_ -match '-X (PUT|POST)' } | Should -BeNullOrEmpty
        @(Get-Content $signers).Count | Should -Be 1
    }

    It 'leaves an environment restricted to protected branches as it is' {
        $log = New-Folder 'log'; $keys = New-Folder 'keys'
        Set-Content (Join-Path $log 'environment.json') '{"deployment_branch_policy":{"protected_branches":true,"custom_branch_policies":false}}'

        $result = Invoke-Initialize $log @('-KeyPath', (Join-Path $keys 'key'), '-BackupDirectory', 'SKIP')

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'protected branches only'
        Get-GhCall $log | Where-Object { $_ -match '-X (PUT|POST)' } | Should -BeNullOrEmpty
    }

    It 'restricts a key other accounts can read to its owner' -Skip:(-not $IsWindows) {
        $log = New-Folder 'log'; $keys = New-Folder 'keys'
        $key = Join-Path $keys 'key'
        ssh-keygen -q -t ed25519 -N '' -f $key
        icacls $key /grant '*S-1-1-0:R' /Q | Out-Null

        $result = Invoke-Initialize $log @('-KeyPath', $key, '-BackupDirectory', 'SKIP')

        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Get-Acl $key).Access.IdentityReference.Value | Should -Be ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
        Test-Path (Join-Path $log 'secret.txt') | Should -BeTrue
    }

    It 'refuses a key with a passphrase' {
        $log = New-Folder 'log'; $keys = New-Folder 'keys'
        $key = Join-Path $keys 'key'
        ssh-keygen -q -t ed25519 -N 'a passphrase' -f $key

        $result = Invoke-Initialize $log @('-KeyPath', $key, '-BackupDirectory', 'SKIP')

        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'passphrase-less'
        Test-Path (Join-Path $log 'secret.txt') | Should -BeFalse
    }

    It 'refuses a backup that differs from the key' {
        $log = New-Folder 'log'; $keys = New-Folder 'keys'; $backup = New-Folder 'backup'
        Set-Content (Join-Path $backup 'key') 'something else'

        $result = Invoke-Initialize $log @('-KeyPath', (Join-Path $keys 'key'), '-BackupDirectory', $backup)

        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'differs from'
        Test-Path (Join-Path $log 'secret.txt') | Should -BeFalse
    }
}

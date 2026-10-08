#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

# Names that may hold credentials are never printed, whatever their prefix.
$sensitive = 'TOKEN|SECRET|PASSWORD|PASSWD|KEY|CREDENTIAL|AUTH'

function Write-Group([string] $Title, [scriptblock] $Body) {
    Write-Host "::group::$Title"
    try { & $Body } finally { Write-Host '::endgroup::' }
}

function Write-EnvironmentVariable([string] $Pattern) {
    Get-ChildItem env: |
        Where-Object { $_.Name -match $Pattern -and $_.Name -notmatch $sensitive } |
        Sort-Object Name |
        ForEach-Object { Write-Host "$($_.Name)=$($_.Value)" }
}

Write-Group 'GitHub' { Write-EnvironmentVariable '^GITHUB_' }
Write-Group 'Runner' { Write-EnvironmentVariable '^(RUNNER_|ImageOS$|ImageVersion$)' }

Write-Group 'Tools' {
    $tools = [ordered]@{
        git    = '--version'
        pwsh   = '--version'
        node   = '--version'
        npm    = '--version'
        dotnet = '--version'
        docker = '--version'
        python = '--version'
    }
    foreach ($tool in $tools.Keys) {
        if (Get-Command $tool -CommandType Application -ErrorAction SilentlyContinue) {
            $output = & $tool $tools[$tool] 2>&1 | Select-Object -First 1
            Write-Host ("{0,-7} {1}" -f $tool, $output)
        }
        else {
            Write-Host ("{0,-7} (not installed)" -f $tool)
        }
    }
    # A tool that fails to report its version must not fail the step through the runner's
    # `exit $LASTEXITCODE` wrapper.
    $global:LASTEXITCODE = 0
}

Write-Group 'Disk' {
    Get-PSDrive -PSProvider FileSystem |
        Where-Object { $null -ne $_.Free } |
        ForEach-Object { Write-Host ("{0,-12} {1,8:N1} GB free" -f $_.Root, ($_.Free / 1GB)) }
}

$workspace = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }
Write-Group "Workspace ($workspace)" {
    Get-ChildItem -LiteralPath $workspace -Force -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object { Write-Host ($(if ($_.PSIsContainer) { "$($_.Name)/" } else { $_.Name })) }
}

if ((Get-ActionInput 'include-event' 'false') -eq 'true' -and $env:GITHUB_EVENT_PATH -and (Test-Path -LiteralPath $env:GITHUB_EVENT_PATH)) {
    Write-Group 'Event payload' { Get-Content -LiteralPath $env:GITHUB_EVENT_PATH -Raw | Write-Host }
}

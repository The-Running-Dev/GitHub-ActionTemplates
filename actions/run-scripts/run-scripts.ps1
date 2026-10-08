#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$scripts = Split-ActionList (Get-ActionInput 'scripts')
$workingDirectory = Get-ActionInput 'working-directory'

if (-not $scripts) { throw "No scripts given. Set 'scripts' to one or more script paths." }

$location = if ($workingDirectory) { Resolve-WorkspacePath $workingDirectory $workspace 'working-directory' } else { $workspace }
if (-not (Test-Path -LiteralPath $location -PathType Container)) { throw "The working-directory '$workingDirectory' does not exist." }

# Every path is checked before the first script runs, so a typo fails fast.
$paths = foreach ($script in $scripts) {
    $path = Resolve-WorkspacePath $script $workspace 'script'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $hint = if ($script -match '\s') { ' Pass script paths only; put commands and arguments in a script file.' } else { '' }
        throw "The script '$script' does not exist.$hint"
    }
    $path
}

Push-Location -LiteralPath $location
try {
    foreach ($path in $paths) {
        $name = [System.IO.Path]::GetRelativePath($workspace, $path).Replace('\', '/')
        Write-Host "::group::$name"
        try {
            $global:LASTEXITCODE = 0
            & $path
            # A native script that fails sets $LASTEXITCODE without throwing.
            if ($LASTEXITCODE -ne 0) { throw "$name exited with code $LASTEXITCODE." }
        }
        finally { Write-Host '::endgroup::' }
    }
}
finally { Pop-Location }

$names = ($scripts | ForEach-Object { '`' + $_ + '`' }) -join ', '
Add-ActionSummary "Ran $(@($paths).Count) script(s): $names."

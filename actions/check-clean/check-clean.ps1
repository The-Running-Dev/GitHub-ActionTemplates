#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$paths = Split-ActionList (Get-ActionInput 'paths')

foreach ($path in $paths) { [void] (Resolve-WorkspacePath $path $workspace 'path') }

# Untracked files count too: a build that writes a new file the repository should commit is not clean.
$arguments = @('-C', $workspace, 'status', '--porcelain', '--untracked-files=all')
if ($paths) { $arguments += @('--') + $paths }
$changes = @(git @arguments | Where-Object { $_ })

Set-ActionOutput 'clean' $(if ($changes) { 'false' } else { 'true' })

$scope = if ($paths) { ($paths | ForEach-Object { '`' + $_ + '`' }) -join ', ' } else { 'the repository' }
if (-not $changes) {
    Add-ActionSummary "No changes in $scope."
    Write-Host "No changes in $scope."
    return
}

Write-Host '::group::git diff'
git -C $workspace --no-pager diff --stat @(if ($paths) { @('--') + $paths })
Write-Host '::endgroup::'

$list = ($changes | Select-Object -First 50 | ForEach-Object { "- ``$_``" }) -join "`n"
Add-ActionSummary "### Uncommitted changes`n`n$($changes.Count) changed file(s) in ${scope}:`n`n$list"
foreach ($change in $changes) { Write-Host $change }
throw "$($changes.Count) file(s) changed in $scope. Run the build locally and commit the result."

#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }
$path = Get-ActionInput 'path'
$workingDirectory = Get-ActionInput 'working-directory' '.'
$spa = (Get-ActionInput 'spa' 'false') -eq 'true'

if (-not $path) { throw "Set 'path' to the built site folder." }
$base = Resolve-WorkspacePath $workingDirectory $workspace -Name 'working-directory' -AllowRoot
$site = Resolve-WorkspacePath (Join-Path $base $path) $workspace -Name 'path'

if (-not (Test-Path -LiteralPath $site -PathType Container)) { throw "The site folder '$path' does not exist; check the build and 'output'." }
$index = Join-Path $site 'index.html'
$notFound = Join-Path $site '404.html'

if ($spa) {
    if (-not (Test-Path -LiteralPath $index)) { throw "'spa' is on but '$path' has no index.html to serve for unknown paths." }
    if (Test-Path -LiteralPath $notFound) { Write-Host '404.html exists; leaving it.' }
    else {
        Copy-Item -LiteralPath $index -Destination $notFound
        Write-Host 'Copied index.html to 404.html for client-side routes.'
    }
}

$files = @(Get-ChildItem -LiteralPath $site -File -Recurse -Force)
if (-not $files.Count) { throw "The site folder '$path' is empty." }
if (-not (Test-Path -LiteralPath $index)) { Write-ActionAnnotation warning "'$path' has no index.html; the site root will answer 404." }

$size = [long] ($files | Measure-Object Length -Sum).Sum
# GitHub Pages sites may be at most 1 GB.
if ($size -gt 1GB) { Write-ActionAnnotation warning "The site is $([math]::Round($size / 1MB)) MB; GitHub Pages sites may be at most 1 GB." }

$relative = [System.IO.Path]::GetRelativePath($workspace, $site).Replace('\', '/')
Set-ActionOutput 'path' $relative
Set-ActionOutput 'files' "$($files.Count)"
Set-ActionOutput 'size' "$size"

$megabytes = [math]::Round($size / 1MB, 2)
Add-ActionSummary "Site ``$relative``: $($files.Count) file(s), $megabytes MB$(if ($spa) { ', single-page app (404.html serves unknown paths)' })."

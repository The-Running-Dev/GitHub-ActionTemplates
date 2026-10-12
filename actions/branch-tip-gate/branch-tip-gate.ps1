#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$context = Get-ActionContext
$sha = Get-ActionInput 'sha' $context.Sha
$branch = Get-ActionInput 'branch' $context.Branch
$repository = Get-ActionInput 'repository' $env:GITHUB_REPOSITORY
$require = Get-ActionInput 'require-tip' 'all'

if ($require -notin 'all', 'latest', 'none') { throw "The require-tip '$require' must be 'all', 'latest' or 'none'." }

function Write-Decision([bool] $IsTip, [string] $Head, [bool] $Publish, [bool] $Latest) {
    Set-ActionOutput 'is-tip' $IsTip.ToString().ToLowerInvariant()
    Set-ActionOutput 'head' $Head
    Set-ActionOutput 'publish' $Publish.ToString().ToLowerInvariant()
    Set-ActionOutput 'latest' $Latest.ToString().ToLowerInvariant()
}

# A tag points at one commit for good; only branches move on.
if (-not $branch) {
    Write-Host 'Not a branch build; nothing to compare.'
    Write-Decision $true $sha $true $true
    return
}
if ($require -eq 'none') {
    Write-Host "require-tip is 'none'; publishing without checking '$branch'."
    Write-Decision $true $sha $true $true
    return
}
if (-not $sha) { throw "Set 'sha' to the commit that was built." }
if (-not $repository) { throw "Set 'repository' to owner/name." }

$encoded = [uri]::EscapeDataString($branch)
$head = "$(gh api "repos/$repository/branches/$encoded" --jq '.commit.sha')".Trim()
if ($head -notmatch '^[0-9a-f]{40}$') { throw "Could not read the head of '$branch' in $repository (got '$head')." }

if ($head -eq $sha) {
    Write-Host "$sha is the tip of '$branch'."
    Write-Decision $true $head $true $true
    return
}

$short = $sha.Substring(0, [math]::Min(7, $sha.Length))
$headShort = $head.Substring(0, 7)
if ($require -eq 'all') {
    Write-Host "::notice::$short is no longer the tip of '$branch' ($headShort is); nothing is published. The newer run publishes."
    Add-ActionSummary "Skipped publishing: ``$short`` is no longer the tip of ``$branch`` (``$headShort`` is)."
    Write-Decision $false $head $false $false
}
else {
    Write-Host "::notice::$short is no longer the tip of '$branch' ($headShort is); publishing without 'latest'."
    Add-ActionSummary "Publishing without ``latest``: ``$short`` is no longer the tip of ``$branch`` (``$headShort`` is)."
    Write-Decision $false $head $true $false
}

#Requires -Version 7.2
<#
.SYNOPSIS
Publishes a vX.Y.Z tag: checks the tag is on the default branch, creates or updates the GitHub Release
with the matching CHANGELOG.md section, and moves the major tag (vX) to the same commit.
Needs GH_TOKEN with contents: write and a checkout with full history.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Tag,
    [Parameter(Mandatory)][string] $DefaultBranch,
    [string] $Repository = $env:GITHUB_REPOSITORY
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$commit = git rev-parse "$Tag^{commit}"
if ($LASTEXITCODE -ne 0) { throw "Tag $Tag does not exist." }
git merge-base --is-ancestor $commit "origin/$DefaultBranch"
if ($LASTEXITCODE -ne 0) { throw "Tag $Tag ($commit) is not on $DefaultBranch." }

$notes = Join-Path ([System.IO.Path]::GetTempPath()) "release-notes-$Tag.md"
& (Join-Path $PSScriptRoot 'Get-ChangelogSection.ps1') -Version $Tag | Set-Content -LiteralPath $notes

gh release view $Tag *> $null
if ($LASTEXITCODE -eq 0) {
    gh release edit $Tag --notes-file $notes
}
else {
    gh release create $Tag --verify-tag --title $Tag --notes-file $notes
}
if ($LASTEXITCODE -ne 0) { throw 'Creating the release failed.' }

$major = ($Tag -split '\.')[0]
gh api "repos/$Repository/git/ref/tags/$major" --silent 2>$null
if ($LASTEXITCODE -eq 0) {
    gh api --method PATCH "repos/$Repository/git/refs/tags/$major" -f "sha=$commit" -F force=true --silent
}
else {
    gh api --method POST "repos/$Repository/git/refs" -f "ref=refs/tags/$major" -f "sha=$commit" --silent
}
if ($LASTEXITCODE -ne 0) { throw "Moving $major failed." }

Write-Host "$major -> $commit"
if ($env:GITHUB_STEP_SUMMARY) {
    "Released ``$Tag`` and moved ``$major`` to ``$commit``." >> $env:GITHUB_STEP_SUMMARY
}

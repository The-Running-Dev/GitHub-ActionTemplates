#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$prefix = Get-ActionInput 'tag-prefix' 'v'
$workingDirectory = Get-ActionInput 'working-directory' '.'
$tag = Get-ActionInput 'tag'

if (-not $tag) {
    $context = Get-ActionContext
    if ($context.IsTag) { $tag = $context.RefName }
}

if (-not $tag) {
    Write-Host 'Not a tag build; nothing to check.'
    Set-ActionOutput 'checked' 'false'
    Set-ActionOutput 'version' ''
    return
}

if (-not $tag.StartsWith($prefix)) {
    throw "Tag '$tag' does not start with the tag prefix '$prefix'."
}

$manifest = Get-ActionInput 'manifest'
$manifestPath = if ($manifest) { Join-Path $workingDirectory $manifest } else { Find-Manifest $workingDirectory }

$tagVersion = Format-SemVer (ConvertTo-SemVer $tag.Substring($prefix.Length))
$manifestVersion = Format-SemVer (ConvertTo-SemVer (Get-ManifestVersion $manifestPath))

if ($tagVersion -ne $manifestVersion) {
    Write-Host "::error file=$manifestPath::Tag '$tag' does not match version '$manifestVersion' in '$manifestPath'."
    throw "Tag '$tag' does not match version '$manifestVersion' in '$manifestPath'."
}

Write-Host "Tag '$tag' matches '$manifestPath' ($manifestVersion)."
Set-ActionOutput 'checked' 'true'
Set-ActionOutput 'version' $manifestVersion

#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$image = (Get-ActionInput 'image').ToLowerInvariant()
$kinds = @((Get-ActionInput 'tags' 'sha latest') -split '[\s,;]+' | Where-Object { $_ })
$version = Get-ActionInput 'version'
$allowLatest = (Get-ActionInput 'latest' 'true') -eq 'true'
$tagPrefix = Get-ActionInput 'tag-prefix' 'v'
$extraLabels = Split-ActionList (Get-ActionInput 'labels')

if (-not $image) { throw "Set 'image' to the image name, for example ghcr.io/owner/name." }
if ($image -notmatch '^[a-z0-9]+([._/:-][a-z0-9]+)*$') { throw "The image '$image' is not a valid image name. Give it without a tag." }

$known = 'sha', 'short-sha', 'version', 'minor', 'major', 'date', 'branch', 'latest'
$unknown = @($kinds | Where-Object { $_ -notin $known })
if ($unknown) { throw "Unknown tag kind(s): $($unknown -join ', '). Use $($known -join ', ')." }
if (-not $kinds) { throw "Set 'tags' to one or more tag kinds: $($known -join ', ')." }

$context = Get-ActionContext
$semver = if ($version) { ConvertTo-SemVer $version } else { $null }

# A tag build is stable when its version (or, without one, its tag name) has no prerelease part.
$isStable = if ($semver) { -not $semver.Prerelease }
elseif ($context.IsTag) {
    try { -not (ConvertTo-SemVer ($context.RefName -replace "^$([regex]::Escape($tagPrefix))", '')).Prerelease }
    catch { $true }
}
else { $true }
$latestApplies = $allowLatest -and ($context.IsDefaultBranch -or ($context.IsTag -and $isStable))

$names = [System.Collections.Generic.List[string]]::new()
foreach ($kind in $kinds) {
    $name = switch ($kind) {
        'sha' { $context.Sha }
        'short-sha' { $context.ShortSha }
        'version' {
            if (-not $semver) { throw "The 'version' tag needs the 'version' input." }
            Format-SemVer $semver
        }
        { $_ -in 'minor', 'major' } {
            if (-not $semver) { throw "The '$kind' tag needs the 'version' input." }
            if ($semver.Prerelease) { Write-Host "Skipping the '$kind' tag: $version is a prerelease."; $null }
            elseif ($kind -eq 'minor') { "$($semver.Major).$($semver.Minor)" }
            else { "$($semver.Major)" }
        }
        'date' { [DateTime]::UtcNow.ToString('yyyyMMdd') }
        'branch' {
            if ($context.Branch) { ConvertTo-Slug $context.Branch }
            else { Write-Host "Skipping the 'branch' tag: the run is not for a branch."; $null }
        }
        'latest' {
            if ($latestApplies) { 'latest' }
            else { Write-Host "Skipping the 'latest' tag: only stable default-branch and tag builds get it."; $null }
        }
    }
    if ($name -and -not $names.Contains($name)) { $names.Add($name) }
}

$server = if ($env:GITHUB_SERVER_URL) { $env:GITHUB_SERVER_URL } else { 'https://github.com' }
$labels = [ordered]@{
    'org.opencontainers.image.source'   = "$server/$env:GITHUB_REPOSITORY"
    'org.opencontainers.image.revision' = $context.Sha
    'org.opencontainers.image.created'  = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    'org.opencontainers.image.version'  = if ($version) { $version } else { $context.Sha }
    'org.opencontainers.image.title'    = ($image -split '/')[-1]
}
foreach ($line in $extraLabels) {
    if ($line -notmatch '^(?<key>[^=\s]+)=(?<value>.*)$') { throw "The label '$line' must be key=value." }
    $labels[$Matches['key']] = $Matches['value']
}

$tags = @($names | ForEach-Object { "${image}:$_" })
Set-ActionOutput 'image' $image
Set-ActionOutput 'tags' ($tags -join "`n")
Set-ActionOutput 'tag-names' ($names -join ' ')
Set-ActionOutput 'labels' (($labels.Keys | ForEach-Object { "$_=$($labels[$_])" }) -join "`n")
Set-ActionOutput 'latest' $(if ($names.Contains('latest')) { 'true' } else { 'false' })

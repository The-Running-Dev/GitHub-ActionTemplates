#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$tarballInput = Get-ActionInput 'tarball'
$registry = (Get-ActionInput 'registry' 'https://registry.npmjs.org').TrimEnd('/')
$access = Get-ActionInput 'access'
$provenance = (Get-ActionInput 'provenance' 'true') -eq 'true'
$distTag = Get-ActionInput 'dist-tag'
$dryRun = (Get-ActionInput 'dry-run' 'false') -eq 'true'

if (-not $tarballInput) { throw "Set 'tarball' to the packed .tgz file." }
if ($access -and $access -notin 'public', 'restricted') { throw "The access '$access' must be 'public' or 'restricted'." }
if ($registry -notmatch '^https://') { throw "The registry '$registry' must be an https:// URL." }

$tarballs = @(Find-WorkspaceFile -Pattern @($tarballInput) -Workspace $workspace)
if ($tarballs.Count -ne 1) { throw "'$tarballInput' matched $($tarballs.Count) files; it must match exactly one tarball." }
$tarball = $tarballs[0]

# The manifest inside the tarball is what gets published, so the dist-tag is chosen from it.
$manifest = Get-TarballManifest $tarball
$name = $manifest.name
$version = $manifest.version
$isPrerelease = ConvertTo-SemVer $version | ForEach-Object { [bool] $_.Prerelease }
if (-not $distTag) { $distTag = if ($isPrerelease) { 'next' } else { 'latest' } }
if (-not $isPrerelease -and $distTag -ne 'latest') { Write-Host "::notice::Publishing release version $version under '$distTag', not 'latest'." }

$isGitHubPackages = $registry -match '^https://npm\.pkg\.github\.com'
if ($provenance -and $isGitHubPackages) {
    Write-Host '::notice::GitHub Packages does not support npm provenance; publishing without it.'
    $provenance = $false
}

$arguments = @('publish', $tarball, '--registry', "$registry/", '--tag', $distTag)
if ($access) { $arguments += @('--access', $access) }
if ($provenance) { $arguments += '--provenance' }
if ($dryRun) { $arguments += '--dry-run' }

# A user config of its own, so an .npmrc from setup-node or the repository cannot change the target.
# The token stays in the environment; the file only references it.
$userConfig = Join-Path ([System.IO.Path]::GetTempPath()) "ghat-npmrc-$([guid]::NewGuid().ToString('N'))"
$hostPath = $registry -replace '^https:', ''
$lines = @("registry=$registry/")
if ($env:NODE_AUTH_TOKEN) { $lines += "$hostPath/:_authToken=`${NODE_AUTH_TOKEN}" }
elseif (-not $dryRun) { Write-Host '::notice::No token given; publishing with npm trusted publishing (OIDC).' }
Set-Content -LiteralPath $userConfig -Value $lines -Encoding utf8

try {
    Write-Host "npm $($arguments -join ' ')"
    npm @arguments --userconfig $userConfig
}
finally { Remove-Item -LiteralPath $userConfig -ErrorAction SilentlyContinue }

Set-ActionOutput 'name' $name
Set-ActionOutput 'version' $version
Set-ActionOutput 'dist-tag' $distTag
Set-ActionOutput 'published' $(if ($dryRun) { 'false' } else { 'true' })

$verb = if ($dryRun) { 'Dry run: would publish' } else { 'Published' }
$target = if ($isGitHubPackages) { 'GitHub Packages' } else { $registry }
Add-ActionSummary "$verb ``$name@$version`` to $target under ``$distTag``$(if ($provenance) { ' with provenance' })."

#Requires -Version 7.2
<#
.SYNOPSIS
Self-test: extracts the docs-template, docs-node and pages-app Pages artifacts and checks each
site has its fixture marker, pages and build values.
#>
[CmdletBinding()]
param(
    [string] $ArtifactPath = 'artifacts',
    [string] $SitePath = 'sites'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$failures = 0
foreach ($check in @(
    @{ Name = 'docs-template'; Marker = 'docs-build-fixture-marker'; Page = 'second/index.html' }
    @{ Name = 'docs-node'; Marker = 'docs-node-fixture-marker'; Page = 'index.html' }
    # pages.yml: the base-path input, a build variable and the single-page-app 404.html.
    @{ Name = 'pages-app'; Marker = 'pages-app-fixture-marker from-env'; Page = '404.html'; Contains = '<base href="/self-test/">' }
)) {
    $site = Join-Path $SitePath $check.Name
    New-Item -ItemType Directory -Path $site -Force | Out-Null
    tar -xf (Join-Path $ArtifactPath $check.Name 'artifact.tar') -C $site
    if ($LASTEXITCODE -ne 0) { throw "Extracting $($check.Name) failed." }

    $index = Join-Path $site 'index.html'
    $html = if (Test-Path $index) { Get-Content $index -Raw } else { '' }
    $ok = $html.Contains($check.Marker) -and (Test-Path (Join-Path $site $check.Page)) -and (-not $check.Contains -or $html.Contains($check.Contains))
    Write-Host "$(if ($ok) { 'ok  ' } else { 'FAIL' }) $($check.Name)"
    if (-not $ok) { $failures++ }
}
if ($failures) { throw "$failures site(s) are missing their pages." }

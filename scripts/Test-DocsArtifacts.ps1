#Requires -Version 7.2
<#
.SYNOPSIS
Self-test: extracts the docs-template and docs-node Pages artifacts and checks each site has its
fixture marker and pages.
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
)) {
    $site = Join-Path $SitePath $check.Name
    New-Item -ItemType Directory -Path $site -Force | Out-Null
    tar -xf (Join-Path $ArtifactPath $check.Name 'artifact.tar') -C $site
    if ($LASTEXITCODE -ne 0) { throw "Extracting $($check.Name) failed." }

    $index = Join-Path $site 'index.html'
    $ok = (Test-Path $index) -and (Get-Content $index -Raw).Contains($check.Marker) -and (Test-Path (Join-Path $site $check.Page))
    Write-Host "$(if ($ok) { 'ok  ' } else { 'FAIL' }) $($check.Name)"
    if (-not $ok) { $failures++ }
}
if ($failures) { throw "$failures site(s) are missing their pages." }

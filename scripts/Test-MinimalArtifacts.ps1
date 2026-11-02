#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if (-not $env:GITHUB_REPOSITORY -or -not $env:GITHUB_RUN_ID) { throw 'A workflow run is required.' }
$response = & gh api --paginate --slurp "repos/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID/artifacts?per_page=100"
if ($LASTEXITCODE) { throw 'Could not inspect workflow artifacts.' }
$pages = ($response -join "`n") | ConvertFrom-Json
$unexpected = @($pages | ForEach-Object { $_.artifacts } | Where-Object { $_.name -like 'minimal-*' -or $_.name -like '*.dockerbuild' })
if ($unexpected.Count) { throw "Unexpected default uploads: $($unexpected.name -join ', ')" }
Write-Host 'Default validation and packing created no optional artifacts or Docker build records.'

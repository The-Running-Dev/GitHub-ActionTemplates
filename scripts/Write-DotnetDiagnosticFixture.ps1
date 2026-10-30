#Requires -Version 7.2
# Harmless post-build evidence used to exercise the optional workflow upload.
$ErrorActionPreference = 'Stop'
$destination = Join-Path $env:GITHUB_WORKSPACE '.selftest/dotnet-diagnostics'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Set-Content -LiteralPath (Join-Path $destination 'probe.json') -Value '{"fixture":"dotnet-diagnostics"}'
Set-Content -LiteralPath (Join-Path $destination 'installer.log') -Value 'fixture installer evidence'

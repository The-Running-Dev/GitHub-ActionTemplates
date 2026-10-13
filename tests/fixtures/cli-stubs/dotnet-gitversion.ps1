# Stands in for GitVersion in the version tests. Prints STUB_SEMVER as GitVersion's JSON, or exits
# with 1 when STUB_SEMVER is empty. Appends the arguments to $env:STUB_LOG/gitversion.txt.
if ($env:STUB_LOG) { Add-Content -LiteralPath (Join-Path $env:STUB_LOG 'gitversion.txt') -Value ($args -join ' ') }
if (-not $env:STUB_SEMVER) { Write-Output 'GitVersion failed'; exit 1 }
Write-Output "{`n  `"Major`": 0,`n  `"SemVer`": `"$env:STUB_SEMVER`",`n  `"FullSemVer`": `"$env:STUB_SEMVER`"`n}"
exit 0

# Stands in for the GitHub CLI in the github-release tests. Appends each call's arguments (and the
# notes file's text) to $env:STUB_LOG/gh.txt. `release view` succeeds only when STUB_RELEASE_EXISTS
# is 'true', or after this stub "created" the release.
$log = Join-Path $env:STUB_LOG 'gh.txt'
$created = Join-Path $env:STUB_LOG 'created'
Add-Content -LiteralPath $log -Value ($args -join ' ')

$notes = [array]::IndexOf($args, '--notes-file')
if ($notes -ge 0) { Add-Content -LiteralPath $log -Value "NOTES: $((Get-Content -LiteralPath $args[$notes + 1] -Raw).Trim())" }

if ($args[0] -eq 'release' -and $args[1] -eq 'view') {
    if ($env:STUB_RELEASE_EXISTS -ne 'true' -and -not (Test-Path -LiteralPath $created)) { exit 1 }
    if ($args -contains 'url') { Write-Output "https://github.com/$env:GITHUB_REPOSITORY/releases/tag/$($args[2])" }
    exit 0
}
if ($args[0] -eq 'release' -and $args[1] -eq 'create') { Set-Content -LiteralPath $created -Value '' }
exit 0

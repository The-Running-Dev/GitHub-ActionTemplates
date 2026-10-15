# Stands in for the GitHub CLI in the github-release, branch-tip-gate and pages-env tests. Appends each call's
# arguments (and the notes file's text) to $env:STUB_LOG/gh.txt. `release view` succeeds only when
# STUB_RELEASE_EXISTS is 'true', or after this stub "created" the release. `api repos/<owner>/<name>/branches/<branch>`
# prints STUB_BRANCH_HEAD, and `api repos/<owner>/<name>/pages` prints STUB_PAGES_URL (a 404 when it is empty).
# drift-report reads canned API responses from STUB_API_DIR.
$log = Join-Path $env:STUB_LOG 'gh.txt'
$created = Join-Path $env:STUB_LOG 'created'
Add-Content -LiteralPath $log -Value ($args -join ' ')

$notes = [array]::IndexOf($args, '--notes-file')
if ($notes -ge 0) { Add-Content -LiteralPath $log -Value "NOTES: $((Get-Content -LiteralPath $args[$notes + 1] -Raw).Trim())" }

# With STUB_API_DIR set, `api <path>` serves <dir>/<path>.json (the query string dropped; wrapped
# in a page array for --slurp) or, with the raw Accept header, the file <dir>/<path>; a missing
# file is a 404.
if ($env:STUB_API_DIR -and $args[0] -eq 'api') {
    $path = ($args[1] -split '\?', 2)[0]
    $raw = $args -contains 'Accept: application/vnd.github.raw'
    $file = Join-Path $env:STUB_API_DIR ($raw ? $path : "$path.json")
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Write-Output '{"message":"Not Found","status":"404"}'
        Write-Error 'gh: Not Found (HTTP 404)' -ErrorAction Continue
        exit 1
    }
    $text = Get-Content -LiteralPath $file -Raw
    Write-Output ($args -contains '--slurp' ? "[$text]" : $text)
    exit 0
}

if ($args[0] -eq 'release' -and $args[1] -eq 'view') {
    if ($env:STUB_RELEASE_EXISTS -ne 'true' -and -not (Test-Path -LiteralPath $created)) { exit 1 }
    if ($args -contains 'url') { Write-Output "https://github.com/$env:GITHUB_REPOSITORY/releases/tag/$($args[2])" }
    exit 0
}
if ($args[0] -eq 'api' -and $args[1] -match '^repos/[^/]+/[^/]+/branches/') {
    if (-not $env:STUB_BRANCH_HEAD) { exit 1 }
    Write-Output $env:STUB_BRANCH_HEAD
    exit 0
}
if ($args[0] -eq 'api' -and $args[1] -match '^repos/[^/]+/[^/]+/pages$') {
    if (-not $env:STUB_PAGES_URL) {
        [Console]::Error.WriteLine('gh: Not Found (HTTP 404)')
        exit 1
    }
    Write-Output $env:STUB_PAGES_URL
    exit 0
}
if ($args[0] -eq 'release' -and $args[1] -eq 'create') { Set-Content -LiteralPath $created -Value '' }
exit 0

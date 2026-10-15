#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$namePattern = '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'

# The runner checks remote actions out under _actions/<owner>/<name>/<ref>.
function Get-LibraryRepository {
    if ($env:GITHUB_ACTION_REPOSITORY) { return $env:GITHUB_ACTION_REPOSITORY }
    $parts = $PSScriptRoot -split '[\\/]'
    $index = [array]::IndexOf($parts, '_actions')
    if ($index -ge 0 -and $parts.Count -gt $index + 2) { return "$($parts[$index + 1])/$($parts[$index + 2])" }
    return "$env:GITHUB_REPOSITORY"
}

# Calls the GitHub API through gh. Writes the parsed JSON (the items of every page with
# -Paginate), or the text with -Raw; nothing for a 404 or, with -Optional, any failure.
function Invoke-GitHubApi([string] $Path, [switch] $Paginate, [switch] $Raw, [switch] $Optional) {
    $arguments = @('api', $Path)
    if ($Paginate) { $arguments += '--paginate', '--slurp' }
    if ($Raw) { $arguments += '-H', 'Accept: application/vnd.github.raw' }

    $errorFile = New-TemporaryFile
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        $output = gh @arguments 2>$errorFile.FullName
        $code = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        $message = (Get-Content -LiteralPath $errorFile.FullName -Raw) ?? ''
    }
    finally {
        Remove-Item -LiteralPath $errorFile.FullName -Force -ErrorAction SilentlyContinue
    }

    if ($code -ne 0) {
        if ($Optional -or $message -match '\(HTTP 404\)') { return }
        throw "gh api $Path failed: $($message.Trim())"
    }

    $text = @($output) -join "`n"
    if ($Raw) { return $text }
    $json = ConvertFrom-Json $text -NoEnumerate -Depth 64
    if (-not $Paginate) { return $json }
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($page in $json) { foreach ($item in $page) { $items.Add($item) } }
    return $items.ToArray()
}

function Get-OwnerRepository([string] $Owner) {
    $account = Invoke-GitHubApi "users/$Owner"
    if (-not $account) { throw "The owner '$Owner' does not exist or cannot be read." }

    if ($account.type -eq 'Organization') { $path = "orgs/$Owner/repos?type=all&per_page=100" }
    else {
        # A user's private repositories are only listed for that user's own token.
        $viewer = Invoke-GitHubApi 'user' -Optional
        $path = if ($viewer -and $viewer.login -eq $Owner) { 'user/repos?affiliation=owner&per_page=100' } else { "users/$Owner/repos?type=owner&per_page=100" }
    }

    $repositories = @(Invoke-GitHubApi $path -Paginate)
    return @($repositories | Where-Object { -not $_.archived -and -not $_.fork } | ForEach-Object full_name | Sort-Object)
}

$library = Get-ActionInput 'library' (Get-LibraryRepository)
$owner = Get-ActionInput 'owner' ("$env:GITHUB_REPOSITORY" -split '/', 2)[0]
$listed = Split-ActionList (Get-ActionInput 'repositories')
$failOnDrift = (Get-ActionInput 'fail-on-drift' 'false') -eq 'true'
$reportInput = Get-ActionInput 'report'

if ($library -notmatch $namePattern) { throw "The library '$library' must be owner/name." }
foreach ($name in $listed) { if ($name -notmatch $namePattern) { throw "The repository '$name' must be owner/name." } }
if (-not $listed -and $owner -notmatch '^[A-Za-z0-9-]+$') { throw "The owner '$owner' is not a GitHub user or organisation name." }
$reportPath = if ($reportInput) { Resolve-WorkspacePath $reportInput $env:GITHUB_WORKSPACE -Name 'report' }

# Releases are the stable vX.Y.Z tags; moving tags such as v1 resolve to one of them.
$tags = @(Invoke-GitHubApi "repos/$library/tags?per_page=100" -Paginate)
if (-not $tags) { throw "Could not read the tags of $library." }
$tagSha = @{}
$releases = foreach ($tag in $tags) {
    $tagSha[$tag.name] = $tag.commit.sha
    if ($tag.name -match '^v(\d+)\.(\d+)\.(\d+)$') {
        [pscustomobject]@{ Name = $tag.name; Sha = $tag.commit.sha; Version = [version]::new([int] $Matches[1], [int] $Matches[2], [int] $Matches[3]) }
    }
}
$releases = @($releases | Sort-Object Version -Descending)
if (-not $releases) { throw "$library has no vX.Y.Z release tags." }
$latest = $releases[0]
Write-Host "Latest release of ${library}: $($latest.Name) ($($latest.Sha.Substring(0, 7)))"

$branchSha = @{}
function Resolve-Reference([string] $Ref) {
    if ($tagSha.ContainsKey($Ref)) { return [pscustomobject]@{ Sha = $tagSha[$Ref]; Kind = 'tag' } }
    if ($Ref -match '^[0-9a-f]{40}$') { return [pscustomobject]@{ Sha = $Ref; Kind = 'sha' } }
    if (-not $branchSha.ContainsKey($Ref)) {
        $commit = Invoke-GitHubApi "repos/$library/commits/$([uri]::EscapeDataString($Ref))"
        $branchSha[$Ref] = if ($commit) { $commit.sha } else { '' }
    }
    if ($branchSha[$Ref]) { return [pscustomobject]@{ Sha = $branchSha[$Ref]; Kind = 'branch' } }
    return [pscustomobject]@{ Sha = ''; Kind = 'unknown' }
}

$repositories = if ($listed) { $listed } else { Get-OwnerRepository $owner }
$source = if ($listed) { 'the repositories input' } else { $owner }
Write-Host "Scanning $(@($repositories).Count) repositories of $source."

$escaped = [regex]::Escape($library)
$usesPattern = "(?im)^\s*-?\s*uses:\s*['""]?$escaped(?<path>/[^@\s'""]*)?@(?<ref>[^\s'""#]+)"

$entries = [System.Collections.Generic.List[object]]::new()
$unused = [System.Collections.Generic.List[string]]::new()
foreach ($repository in $repositories) {
    $files = @(Invoke-GitHubApi "repos/$repository/contents/.github/workflows")
    if (-not $files) { Write-Host "${repository}: no workflows (or not readable)."; continue }
    $before = $entries.Count

    foreach ($file in @($files | Where-Object { $_.type -eq 'file' -and $_.name -match '\.ya?ml$' })) {
        $text = Invoke-GitHubApi "repos/$repository/contents/$($file.path)" -Raw
        if (-not $text) { continue }

        $found = [regex]::Matches($text, $usesPattern) | Group-Object { $_.Groups['ref'].Value }
        foreach ($group in $found) {
            $ref = $group.Name
            $uses = @($group.Group | ForEach-Object { $_.Groups['path'].Value.TrimStart('/') } | ForEach-Object { if ($_) { $_ } else { '.' } } | Sort-Object -Unique)
            $resolved = Resolve-Reference $ref
            $release = $releases | Where-Object Sha -EQ $resolved.Sha | Select-Object -First 1
            $behind = if ($release) { @($releases | Where-Object { $_.Version -gt $release.Version }).Count } else { $null }

            $status = if ($resolved.Kind -eq 'unknown') { 'unknown' }
            elseif ($resolved.Kind -eq 'branch') { 'branch' }
            elseif (-not $release) { 'unreleased' }
            elseif ($behind -eq 0) { 'current' }
            else { 'behind' }

            $entries.Add([pscustomobject][ordered]@{
                    repository = $repository
                    workflow   = $file.path
                    uses       = $uses
                    ref        = $ref
                    sha        = $resolved.Sha
                    version    = if ($release) { $release.Name } else { '' }
                    behind     = $behind
                    status     = $status
                })
        }
    }
    if ($entries.Count -eq $before -and $repository -ne $library) { $unused.Add($repository) }
}

$current = @($entries | Where-Object status -EQ 'current').Count
$drifted = $entries.Count - $current
$using = @($entries | ForEach-Object repository | Sort-Object -Unique).Count

$order = @{ unknown = 0; branch = 1; unreleased = 2; behind = 3; current = 4 }
$sorted = @($entries | Sort-Object { $order[$_.status] }, repository, workflow)

foreach ($entry in $sorted | Where-Object status -NE 'current') {
    $detail = switch ($entry.status) {
        'behind' { "$($entry.version), $($entry.behind) release(s) behind $($latest.Name)" }
        'branch' { "the branch '$($entry.ref)'" }
        'unreleased' { 'a commit that is not a release' }
        default { 'a ref that does not exist' }
    }
    Write-ActionAnnotation warning "$($entry.repository) $($entry.workflow) uses $library@$($entry.ref), $detail." -Title 'Drift'
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("### Drift report for $library")
$lines.Add('')
$lines.Add("Latest release: ``$($latest.Name)``. Scanned $(@($repositories).Count) repositories of $source; $using use the library in $($entries.Count) workflow reference(s), $current current and $drifted not.")
if ($sorted) {
    $lines.Add('')
    $lines.Add('| Repository | Workflow | Uses | Ref | Version | Status |')
    $lines.Add('|---|---|---|---|---|---|')
    foreach ($entry in $sorted) {
        $status = if ($entry.status -eq 'behind') { "behind $($entry.behind)" } else { $entry.status }
        $uses = ($entry.uses | ForEach-Object { "``$(Format-MarkdownCell $_ 80)``" }) -join '<br>'
        $lines.Add("| $(Format-MarkdownCell $entry.repository) | ``$(Format-MarkdownCell $entry.workflow 120)`` | $uses | ``$(Format-MarkdownCell $entry.ref 60)`` | $($entry.version) | $status |")
    }
}
if ($unused.Count) {
    $lines.Add('')
    $lines.Add("<details><summary>$($unused.Count) repositories with workflows that do not use the library</summary>")
    $lines.Add('')
    foreach ($name in $unused) { $lines.Add("- $(Format-MarkdownCell $name)") }
    $lines.Add('')
    $lines.Add('</details>')
}
$lines.Add('')
$lines.Add('Only repositories the token can read are scanned.')
Add-ActionSummary ($lines -join "`n")

if ($reportPath) {
    New-Item -ItemType Directory -Path (Split-Path $reportPath) -Force | Out-Null
    [ordered]@{
        library      = $library
        latest       = $latest.Name
        repositories = @($repositories)
        references   = $sorted
        unused       = @($unused)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8
    Write-Host "Wrote $reportPath"
}

Set-ActionOutput 'latest' $latest.Name
Set-ActionOutput 'repositories' "$(@($repositories).Count)"
Set-ActionOutput 'references' "$($entries.Count)"
Set-ActionOutput 'current' "$current"
Set-ActionOutput 'drifted' "$drifted"

if ($failOnDrift -and $drifted -gt 0) { throw "$drifted workflow reference(s) to $library are not on $($latest.Name)." }

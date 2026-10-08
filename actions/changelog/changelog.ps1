#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$page = Get-ActionInput 'path'
$frontMatter = @((Get-ActionInput 'front-matter') -split '\r?\n' | ForEach-Object TrimEnd | Where-Object { $_ })
$title = Get-ActionInput 'title' 'Changelog'
$ref = Get-ActionInput 'ref' 'HEAD'
$exclude = Get-ActionInput 'exclude' '(?i)update changelog'
$repository = Get-ActionInput 'repository' $env:GITHUB_REPOSITORY

if (-not $page) { throw "Set 'path' to the page to write." }
$pagePath = Resolve-WorkspacePath $page $workspace 'path'

# A container job's checkout belongs to another user, and git refuses to read it without this.
if ($env:GITHUB_ACTIONS -eq 'true') {
    git config --global --add safe.directory $workspace
}

$shallow = git -C $workspace rev-parse --is-shallow-repository 2>$null
if ($LASTEXITCODE -ne 0) { throw "'$workspace' is not a git repository." }
if ($shallow -eq 'true') { throw "The checkout is shallow, so the changelog would be incomplete. Check out with 'fetch-depth: 0'." }

# A control character no commit subject contains separates the date from the subject.
$separator = [char] 0x1f
# An em dash between the date and the subject, kept out of the source so the file stays ASCII.
$dash = [char] 0x2014
$log = git -C $workspace log --date=short "--pretty=format:%ad$separator%s" $ref
if ($LASTEXITCODE -ne 0) { throw "git log $ref failed." }

# '<' and '>' would open a JSX tag in MDX; brackets and backslashes would break the link text.
function ConvertTo-MarkdownText([string] $Text) {
    $Text.Replace('<', '&lt;').Replace('>', '&gt;').Replace('\', '\\').Replace('[', '\[').Replace(']', '\]')
}

$entries = foreach ($line in @($log)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $date, $subject = $line -split [regex]::Escape([string] $separator), 2
    if ($exclude -and $subject -match $exclude) { continue }

    $text = ConvertTo-MarkdownText $subject
    $pullRequest = [regex]::Match($subject, '\(#(?<number>\d+)\)\s*$')
    if ($pullRequest.Success -and $repository) {
        "- **$date** $dash [$text](https://github.com/$repository/pull/$($pullRequest.Groups['number'].Value))"
    }
    else {
        "- **$date** $dash $text"
    }
}
$entries = @($entries)

$content = [System.Collections.Generic.List[string]]::new()
if ($frontMatter) { $content.AddRange([string[]] (@('---') + $frontMatter + @('---', ''))) }
$content.AddRange([string[]] @("# $title", '', 'One entry per merged change, newest first, generated from the git history.', ''))
if ($entries) { $content.AddRange([string[]] $entries) }

New-Item -ItemType Directory -Path (Split-Path $pagePath) -Force | Out-Null
Set-Content -LiteralPath $pagePath -Value $content -Encoding utf8NoBOM

$relative = [System.IO.Path]::GetRelativePath($workspace, $pagePath).Replace('\', '/')
Write-Host "Wrote $($entries.Count) entries to '$relative'"
Set-ActionOutput 'entries' "$($entries.Count)"
Add-ActionSummary "Wrote the changelog page ``$relative`` with $($entries.Count) entries."

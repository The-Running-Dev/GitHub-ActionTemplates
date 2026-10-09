#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$tag = Get-ActionInput 'tag'
$patterns = Split-ActionList (Get-ActionInput 'files')
$changelog = Get-ActionInput 'changelog' 'CHANGELOG.md'
$tagPrefix = Get-ActionInput 'tag-prefix' 'v'
$title = Get-ActionInput 'title'
$prerelease = Get-ActionInput 'prerelease' 'auto'
$draft = (Get-ActionInput 'draft' 'false') -eq 'true'

if (-not $tag) {
    if ($env:GITHUB_REF_TYPE -ne 'tag') { throw "Set 'tag', or run on a tag push." }
    $tag = $env:GITHUB_REF_NAME
}
if (-not $env:GITHUB_REPOSITORY) { throw 'GITHUB_REPOSITORY is not set.' }
if ($prerelease -notin 'auto', 'true', 'false') { throw "The prerelease '$prerelease' must be 'auto', 'true' or 'false'." }

$version = if ($tagPrefix -and $tag.StartsWith($tagPrefix)) { $tag.Substring($tagPrefix.Length) } else { $tag }
if ($prerelease -eq 'auto') {
    $parsed = try { ConvertTo-SemVer $version } catch { $null }
    $prerelease = if ($parsed -and $parsed.Prerelease) { 'true' } else { 'false' }
}

# Every attachment is found before anything is published.
$files = @()
if ($patterns) {
    $files = @(Find-WorkspaceFile -Pattern $patterns -Workspace $workspace)
    if (-not $files) { throw "No files found to attach for: $($patterns -join ', ')." }
}

$notesFile = $null
$changelogPath = if ($changelog) { Resolve-WorkspacePath $changelog $workspace 'changelog' }
if ($changelogPath -and (Test-Path -LiteralPath $changelogPath -PathType Leaf)) {
    $notes = Get-ChangelogSection -Path $changelogPath -Version $version
    $notesFile = Join-Path ([System.IO.Path]::GetTempPath()) "ghat-notes-$([guid]::NewGuid().ToString('N')).md"
    Set-Content -LiteralPath $notesFile -Value $notes -Encoding utf8
    Write-Host "Notes from $changelog [$version]"
}
else { Write-Host 'No CHANGELOG; GitHub generates the notes.' }

$repository = @('--repo', $env:GITHUB_REPOSITORY)
try {
    $PSNativeCommandUseErrorActionPreference = $false
    gh release view $tag @repository --json tagName *> $null
    $exists = $LASTEXITCODE -eq 0
    $global:LASTEXITCODE = 0
    $PSNativeCommandUseErrorActionPreference = $true

    if ($exists) {
        Write-Host "Updating the existing release $tag"
        if ($notesFile) { gh release edit $tag @repository --notes-file $notesFile | Out-Host }
        if ($files) { gh release upload $tag @files @repository --clobber | Out-Host }
    }
    else {
        Write-Host "Creating release $tag"
        $arguments = @('release', 'create', $tag) + $files + $repository + @('--verify-tag', '--title', $(if ($title) { $title } else { $tag }))
        $arguments += if ($notesFile) { @('--notes-file', $notesFile) } else { '--generate-notes' }
        if ($prerelease -eq 'true') { $arguments += '--prerelease' }
        if ($draft) { $arguments += '--draft' }
        gh @arguments | Out-Host
    }

    $url = (gh release view $tag @repository --json url --jq .url) -join ''
}
finally { if ($notesFile) { Remove-Item -LiteralPath $notesFile -ErrorAction SilentlyContinue } }

Set-ActionOutput 'url' $url
Set-ActionOutput 'created' $(if ($exists) { 'false' } else { 'true' })

$names = ($files | ForEach-Object { '`' + [System.IO.Path]::GetFileName($_) + '`' }) -join ', '
$action = if ($exists) { 'Updated' } else { 'Created' }
$summary = "$action release [$tag]($url)"
if ($prerelease -eq 'true') { $summary += ' (prerelease)' }
if ($files) { $summary += " with $names" }
Add-ActionSummary "$summary."

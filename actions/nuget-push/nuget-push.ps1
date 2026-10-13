#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$patterns = Split-ActionList (Get-ActionInput 'packages' 'dist-nuget/*.nupkg')
$source = Get-ActionInput 'source' 'github'
$apiKey = Get-ActionInput 'api-key'
$skipDuplicate = (Get-ActionInput 'skip-duplicate' 'true') -eq 'true'
$symbols = (Get-ActionInput 'symbols' 'true') -eq 'true'
$dryRun = (Get-ActionInput 'dry-run' 'false') -eq 'true'

$isGitHub = $false
$url = switch ($source) {
    'github' {
        $owner = if ($env:GITHUB_REPOSITORY_OWNER) { $env:GITHUB_REPOSITORY_OWNER } else { "$env:GITHUB_REPOSITORY".Split('/')[0] }
        if (-not $owner) { throw 'The repository owner is unknown; set GITHUB_REPOSITORY_OWNER or a feed URL as the source.' }
        "https://nuget.pkg.github.com/$owner/index.json"
    }
    'nuget.org' { 'https://api.nuget.org/v3/index.json' }
    default { $source }
}
if ($url -notmatch '^https://') { throw "The source '$source' must be 'github', 'nuget.org' or an https:// feed URL." }
if ($url -match '^https://nuget\.pkg\.github\.com/') { $isGitHub = $true }
if (-not $apiKey -and -not $dryRun) { throw "Set 'api-key' to push to $url." }
if ($apiKey) { Write-Host "::add-mask::$apiKey" }

$packages = @(Find-WorkspaceFile -Pattern $patterns -Workspace $workspace | Where-Object { $_.EndsWith('.nupkg', [System.StringComparison]::OrdinalIgnoreCase) })
if (-not $packages) { throw "'$($patterns -join ', ')' matched no .nupkg files." }

# GitHub Packages rejects symbol packages, and nuget.org takes them from the .snupkg next to the .nupkg.
$noSymbols = $isGitHub -or -not $symbols
$rows = [System.Collections.Generic.List[string]]::new()
foreach ($package in $packages) {
    $name = [System.IO.Path]::GetFileName($package)
    $arguments = @('nuget', 'push', $package, '--source', $url)
    if ($skipDuplicate) { $arguments += '--skip-duplicate' }
    if ($noSymbols) { $arguments += '--no-symbols' }

    if ($dryRun) {
        Write-Host "Dry run: dotnet $($arguments -join ' ')"
    }
    else {
        Write-Host "dotnet $($arguments -join ' ') --api-key ***"
        dotnet @arguments --api-key $apiKey
        if ($LASTEXITCODE) { throw "Pushing $name failed with exit code $LASTEXITCODE." }
    }
    $symbolPackage = [System.IO.Path]::ChangeExtension($package, '.snupkg')
    $withSymbols = -not $noSymbols -and (Test-Path -LiteralPath $symbolPackage -PathType Leaf)
    $rows.Add("| ``$name`` | $(if ($withSymbols) { 'yes' } else { 'no' }) |")
}

Set-ActionOutput 'published' $(if ($dryRun) { 'false' } else { 'true' })
Set-ActionOutput 'count' "$($packages.Count)"
Set-ActionOutput 'source' $url

$target = if ($isGitHub) { 'GitHub Packages' } elseif ($url -eq 'https://api.nuget.org/v3/index.json') { 'nuget.org' } else { $url }
$verb = if ($dryRun) { 'Dry run: would push' } else { 'Pushed' }
Add-ActionSummary (@("### $verb $($packages.Count) package(s) to $target", '', '| Package | Symbols |', '|---|---|') + $rows -join "`n")

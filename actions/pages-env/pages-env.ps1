#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$repository = Get-ActionInput 'repository' $env:GITHUB_REPOSITORY
$basePath = Get-ActionInput 'base-path'

if ($repository -notmatch '^(?<owner>[^/\s]+)/(?<name>[^/\s]+)$') { throw "Set 'repository' to owner/name (got '$repository')." }
$owner = $Matches['owner'].ToLowerInvariant()
$name = $Matches['name']

function ConvertTo-BasePath([string] $Path) {
    $trimmed = $Path.Trim().Trim('/')
    if (-not $trimmed) { return '/' }
    return "/$trimmed/"
}

function ConvertFrom-VariableList([string] $Value, [string] $InputName) {
    $number = 0
    foreach ($line in $Value -split "`r?`n") {
        $number++
        if (-not $line.Trim() -or $line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch '^\s*(?<key>[A-Za-z_][A-Za-z0-9_]*)=(?<value>.*)$') {
            # The line is not echoed: it may hold a secret.
            throw "Line $number of '$InputName' is not KEY=value."
        }
        $key = $Matches['key']
        if ($key -match '^(GITHUB_|RUNNER_|ACTIONS_)' -or $key -in 'NODE_OPTIONS', 'PATH', 'CI', 'PAGES_URL', 'PAGES_ORIGIN', 'PAGES_BASE_PATH') {
            throw "The '$InputName' variable '$key' is reserved."
        }
        [pscustomobject]@{ Key = $key; Value = $Matches['value'] }
    }
}

# The Pages settings know about custom domains; a repository without Pages yet (or a token
# without `pages: read`) gets the default github.io address.
$PSNativeCommandUseErrorActionPreference = $false
$htmlUrl = "$(gh api "repos/$repository/pages" --jq '.html_url' 2>$null)".Trim()
$found = $LASTEXITCODE -eq 0 -and $htmlUrl -match '^https?://'
$global:LASTEXITCODE = 0
$PSNativeCommandUseErrorActionPreference = $true

if ($found) {
    $uri = [uri] $htmlUrl
    $origin = $uri.GetLeftPart([System.UriPartial]::Authority)
    $defaultPath = ConvertTo-BasePath $uri.AbsolutePath
    $source = 'Pages settings'
}
else {
    $origin = "https://$owner.github.io"
    $defaultPath = if ($name.ToLowerInvariant() -eq "$owner.github.io") { '/' } else { "/$name/" }
    $source = 'default github.io address'
}

$path = if ($basePath) { ConvertTo-BasePath $basePath } else { $defaultPath }
$url = "$origin$path"

$plain = @(ConvertFrom-VariableList (Get-ActionInput 'env') 'env')
$secret = @(ConvertFrom-VariableList (Get-ActionInput 'secret-env') 'secret-env')
foreach ($variable in $secret) { if ($variable.Value) { Write-Host "::add-mask::$($variable.Value)" } }

$variables = @(
    [pscustomobject]@{ Key = 'PAGES_URL'; Value = $url }
    [pscustomobject]@{ Key = 'PAGES_ORIGIN'; Value = $origin }
    [pscustomobject]@{ Key = 'PAGES_BASE_PATH'; Value = $path }
) + $plain + $secret

if ($env:GITHUB_ENV) {
    foreach ($variable in $variables) {
        $delimiter = 'ghadelimiter_' + [guid]::NewGuid().ToString('N')
        Add-Content -LiteralPath $env:GITHUB_ENV -Encoding utf8 -Value "$($variable.Key)<<$delimiter`n$($variable.Value)`n$delimiter"
    }
}

Set-ActionOutput 'url' $url
Set-ActionOutput 'origin' $origin
Set-ActionOutput 'base-path' $path

$names = @($plain + $secret | ForEach-Object Key)
Write-Host "Site $url (from the $(if ($basePath) { 'base-path input' } else { $source }))."
if ($names) { Write-Host "Exported $($names -join ', ')." }
$summary = "Pages site: $url"
if ($names) { $summary += "`n`nBuild variables: " + (($names | ForEach-Object { "``$_``" }) -join ', ') }
Add-ActionSummary $summary

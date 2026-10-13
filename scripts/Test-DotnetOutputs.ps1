#Requires -Version 7.2
<#
.SYNOPSIS
Self-test: checks the outputs of the version (gitversion), nuget-feed, dotnet-pack and nuget-push
actions, passed in through environment variables by the self-test workflow.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-That([bool] $Condition, [string] $Message) {
    if ($Condition) { Write-Host "ok   $Message" } else { Write-Host "FAIL $Message"; $failures.Add($Message) }
}

$semver = '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
Assert-That ($env:GITVERSION_VERSION -match $semver) "gitversion strategy '$env:GITVERSION_VERSION'"
if ($env:GITHUB_REF_TYPE -eq 'tag') {
    Assert-That ($env:GITVERSION_VERSION -eq $env:GITHUB_REF_NAME.TrimStart('v')) 'gitversion strategy matches the tag'
}

$config = Get-Content -LiteralPath $env:FEED_CONFIG -Raw
$xml = [xml] $config
$sources = @($xml.configuration.packageSources.add | ForEach-Object { $_.key })
Assert-That ($sources -contains 'github' -and $sources -contains 'fixture') "nuget-feed sources '$($sources -join ', ')'"
$password = $xml.SelectSingleNode('/configuration/packageSourceCredentials/fixture/add[@key="ClearTextPassword"]')
Assert-That ($password -and $password.value -eq '%NUGET_FEED_TOKEN%') 'nuget-feed writes the token variable, not a token'

$version = "1.4.2-selftest.$env:GITHUB_RUN_NUMBER"
$packages = @($env:PACK_PACKAGES -split "`n" | ForEach-Object Trim | Where-Object { $_ })
Assert-That ($env:PACK_COUNT -eq '1') "dotnet-pack count '$env:PACK_COUNT'"
Assert-That ($packages -contains "dist-nuget/Fixture.Calculator.$version.nupkg") "dotnet-pack packages '$($packages -join ', ')'"

Assert-That ($env:PUSH_PUBLISHED -eq 'false') "nuget-push dry run published '$env:PUSH_PUBLISHED'"
Assert-That ($env:PUSH_COUNT -eq '1') "nuget-push count '$env:PUSH_COUNT'"
Assert-That ($env:PUSH_SOURCE -eq 'https://api.nuget.org/v3/index.json') "nuget-push source '$env:PUSH_SOURCE'"

if ($failures.Count) { throw "$($failures.Count) check(s) failed." }

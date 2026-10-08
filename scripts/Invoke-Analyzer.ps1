#Requires -Version 7.2
<#
.SYNOPSIS
Runs PSScriptAnalyzer over the repository with PSScriptAnalyzerSettings.psd1 and fails on any finding.
Findings are written as workflow annotations.
#>
[CmdletBinding()]
param(
    [string] $Path = (Join-Path $PSScriptRoot '..'),
    [string] $Settings = (Join-Path $PSScriptRoot '..' 'PSScriptAnalyzerSettings.psd1')
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable PSScriptAnalyzer | Where-Object Version -ge '1.22.0')) {
    Install-Module PSScriptAnalyzer -MinimumVersion 1.22.0 -Scope CurrentUser -Force
}

$results = Invoke-ScriptAnalyzer -Path $Path -Recurse -Settings $Settings
foreach ($result in $results) {
    $level = if ($result.Severity -eq 'Error') { 'error' } else { 'warning' }
    Write-Host "::$level file=$($result.ScriptPath),line=$($result.Line)::$($result.RuleName): $($result.Message)"
}
if ($results) { throw "PSScriptAnalyzer reported $(@($results).Count) issue(s)." }
Write-Host 'PSScriptAnalyzer: no issues.'

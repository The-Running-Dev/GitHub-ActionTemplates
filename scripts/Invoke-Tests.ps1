#Requires -Version 7.2
<#
.SYNOPSIS
Runs the Pester tests in tests/, installing Pester 5.5+ when it is missing.
#>
[CmdletBinding()]
param(
    [string] $Path = (Join-Path $PSScriptRoot '..' 'tests')
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable Pester | Where-Object Version -ge '5.5.0')) {
    Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck
}
Import-Module Pester -MinimumVersion 5.5.0

$configuration = New-PesterConfiguration
$configuration.Run.Path = $Path
$configuration.Run.Exit = $true
$configuration.Output.Verbosity = 'Detailed'
if ($env:GITHUB_ACTIONS -eq 'true') { $configuration.Output.CIFormat = 'GithubActions' }
Invoke-Pester -Configuration $configuration

#Requires -Version 7.2
<#
.SYNOPSIS
Prints the CHANGELOG.md section for a version ("## [1.2.3] ..." up to the next "## ").
Fails when the section is missing or empty, so a release cannot ship without notes.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Version,
    [string] $Path = (Join-Path $PSScriptRoot '..' 'CHANGELOG.md')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'actions' '_lib' 'Functions.psm1') -Force

Get-ChangelogSection -Path $Path -Version $Version

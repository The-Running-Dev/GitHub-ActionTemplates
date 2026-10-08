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

$Version = $Version.TrimStart('v')
$lines = Get-Content -LiteralPath $Path
$heading = '^##\s+\[' + [regex]::Escape($Version) + '\]'

$start = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $heading) { $start = $i; break }
}

if ($start -lt 0) {
    throw "CHANGELOG has no '## [$Version]' section."
}

$body = [System.Collections.Generic.List[string]]::new()
for ($i = $start + 1; $i -lt $lines.Count -and $lines[$i] -notmatch '^##\s'; $i++) {
    $body.Add($lines[$i])
}

$text = ($body -join "`n").Trim()
if (-not $text) {
    throw "CHANGELOG section '## [$Version]' is empty."
}

$text

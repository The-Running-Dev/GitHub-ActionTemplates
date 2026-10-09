#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$needsInput = Get-ActionInput 'needs'
$allowSkipped = (Get-ActionInput 'allow-skipped' 'true') -eq 'true'

if (-not $needsInput) { throw "Set 'needs' to `${{ toJSON(needs) }}." }
try { $needs = $needsInput | ConvertFrom-Json -AsHashtable }
catch { throw "'needs' is not valid JSON: $($_.Exception.Message)" }
if ($needs -isnot [System.Collections.IDictionary] -or -not $needs.Count) { throw "'needs' has no jobs. Pass `${{ toJSON(needs) }} from a job with 'needs'." }

$rows = [System.Collections.Generic.List[string]]::new()
$bad = [System.Collections.Generic.List[string]]::new()
foreach ($name in $needs.Keys | Sort-Object) {
    $result = "$($needs[$name].result)"
    $ok = $result -eq 'success' -or ($allowSkipped -and $result -eq 'skipped')
    if (-not $ok) { $bad.Add("$name ($result)") }
    $icon = if ($ok) { "`u{2705}" } else { "`u{274C}" }
    $rows.Add("| $name | $icon $result |")
}

Set-ActionOutput 'result' $(if ($bad.Count) { 'failure' } else { 'success' })
Add-ActionSummary ("| Job | Result |`n|---|---|`n" + ($rows -join "`n"))

if ($bad.Count) { throw "Required job(s) did not succeed: $($bad -join ', ')." }
Write-Host "All $($needs.Count) required job(s) succeeded."

#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force
$outcome = Get-ActionInput 'outcome'
$required = Get-ActionInput 'required' 'false'
if ($outcome -notin @('success', 'failure', 'skipped', 'cancelled')) { throw 'Invalid upload outcome.' }
if ($required -notin @('true', 'false')) { throw 'required must be true or false.' }
if ($outcome -eq 'failure') {
    if ($required -eq 'true') {
        Add-ActionSummary '**Required artifact transfer failed. Publishing/deployment cannot proceed.**'
        throw 'Required artifact transfer failed.'
    }
    Add-ActionSummary '**Optional artifact upload failed; no download is available. Build/test validation is unchanged.**'
    Write-ActionAnnotation -Level warning -Message 'Optional artifact upload failed; see the upload step for details.'
}
elseif ($outcome -eq 'success') { Add-ActionSummary 'Artifact upload completed; see the upload step for its download link and expiry.' }

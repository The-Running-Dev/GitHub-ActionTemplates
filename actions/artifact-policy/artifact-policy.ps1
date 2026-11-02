#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$required = Get-ActionInput 'required' 'false'
if ($required -notin @('true', 'false')) { throw "required must be true or false." }
$decision = Get-ArtifactPolicy -Policy (Get-ActionInput 'policy' 'never') `
    -Required ($required -eq 'true') -Status (Get-ActionInput 'status' 'success') `
    -RetentionDays (Get-ActionInput 'retention-days' '1') `
    -RequiredRetentionDays (Get-ActionInput 'required-retention-days' '1')

Set-ActionOutput 'upload' $decision.Upload.ToString().ToLowerInvariant()
Set-ActionOutput 'required' $decision.Required.ToString().ToLowerInvariant()
Set-ActionOutput 'retention-days' "$($decision.RetentionDays)"
Add-ActionSummary "Artifact policy: ``$($decision.Policy)``; upload: **$($decision.Upload)**; required: **$($decision.Required)**; retention: **$($decision.RetentionDays) day(s)**."

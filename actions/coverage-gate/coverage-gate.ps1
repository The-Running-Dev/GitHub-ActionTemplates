#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$defaultReports = '**/coverage.cobertura.xml', '**/cobertura-coverage.xml', '**/cobertura.xml', '**/jacoco.xml', '**/pester-coverage.xml', '**/lcov.info'
$patterns = Split-ActionList (Get-ActionInput 'reports' ($defaultReports -join "`n"))
$minimumInput = Get-ActionInput 'minimum' '0'
$title = Get-ActionInput 'title' 'Coverage'

$minimum = 0.0
if (-not [double]::TryParse($minimumInput, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref] $minimum) -or $minimum -lt 0 -or $minimum -gt 100) {
    throw "The minimum '$minimumInput' must be a number from 0 to 100."
}
if (-not $patterns) { throw "Set 'reports' to one or more coverage report paths." }

# Patterns are relative to the working directory, which must be inside the workspace.
$workingDirectory = Get-ActionInput 'working-directory' '.'
$base = if ($workingDirectory -in '.', './') { $workspace } else { Resolve-WorkspacePath $workingDirectory $workspace 'working-directory' }
$files = Find-WorkspaceFile -Pattern $patterns -Workspace $base
if (-not $files) {
    Set-ActionOutput 'coverage' ''
    Set-ActionOutput 'covered' '0'
    Set-ActionOutput 'total' '0'
    $message = "No coverage report found for: $($patterns -join ', ')."
    if ($minimum -gt 0) {
        Set-ActionOutput 'passed' 'false'
        Add-ActionSummary "### $title`n`n$message"
        throw "$message A minimum of $minimum% is set, so a report is required."
    }
    Set-ActionOutput 'passed' 'true'
    Write-Host "::warning::$message"
    Add-ActionSummary "### $title`n`n$message"
    return
}

$reports = @($files | ForEach-Object { Get-CoverageReport $_ })
$covered = [long] ($reports | Measure-Object Covered -Sum).Sum
$total = [long] ($reports | Measure-Object Total -Sum).Sum

function Format-Percent([long] $Covered, [long] $Total) {
    if ($Total -eq 0) { return 'n/a' }
    return ([math]::Round(100.0 * $Covered / $Total, 2)).ToString('0.##', [cultureinfo]::InvariantCulture) + '%'
}

# Reports with no coverable lines measured nothing, so they cannot meet a minimum.
$percent = if ($total -gt 0) { [math]::Round(100.0 * $covered / $total, 2) } else { 0.0 }
$passed = $total -gt 0 -and $percent -ge $minimum
if ($minimum -eq 0) { $passed = $true }

Set-ActionOutput 'coverage' $(if ($total -gt 0) { $percent.ToString('0.##', [cultureinfo]::InvariantCulture) } else { '' })
Set-ActionOutput 'covered' "$covered"
Set-ActionOutput 'total' "$total"
Set-ActionOutput 'passed' $(if ($passed) { 'true' } else { 'false' })

$rows = foreach ($report in $reports) {
    $name = [System.IO.Path]::GetRelativePath($workspace, $report.Path).Replace('\', '/')
    "| ``$name`` | $($report.Format) | $($report.Covered) / $($report.Total) | $(Format-Percent $report.Covered $report.Total) |"
}
$overall = Format-Percent $covered $total
$status = if ($minimum -eq 0) { "Line coverage **$overall**." }
elseif ($passed) { "Line coverage **$overall** meets the $minimum% minimum." }
else { "Line coverage **$overall** is below the $minimum% minimum." }

Add-ActionSummary ("### $title`n`n$status`n`n| Report | Format | Lines | Coverage |`n|---|---|---|---|`n" + ($rows -join "`n"))
Write-Host $status.Replace('**', '')

if (-not $passed) {
    if ($total -eq 0) { throw "The coverage reports have no coverable lines, so the $minimum% minimum cannot be met." }
    throw "Line coverage $overall is below the $minimum% minimum."
}

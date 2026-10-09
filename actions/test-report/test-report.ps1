#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$patterns = Split-ActionList (Get-ActionInput 'results')
$title = Get-ActionInput 'title' 'Tests'
$failOnFailure = (Get-ActionInput 'fail-on-failure' 'false') -eq 'true'
$failOnMissing = (Get-ActionInput 'fail-on-missing' 'false') -eq 'true'
$annotate = (Get-ActionInput 'annotate' 'true') -eq 'true'

if (-not $patterns) { throw "Set 'results' to one or more test results paths." }

# Patterns are relative to the working directory, which must be inside the workspace.
$workingDirectory = Get-ActionInput 'working-directory' '.'
$base = if ($workingDirectory -in '.', './') { $workspace } else { Resolve-WorkspacePath $workingDirectory $workspace 'working-directory' }
$files = Find-WorkspaceFile -Pattern $patterns -Workspace $base
if (-not $files) {
    foreach ($name in 'total', 'passed', 'failed', 'skipped') { Set-ActionOutput $name '0' }
    $message = "No test results found for: $($patterns -join ', ')."
    Add-ActionSummary "### $title`n`n$message"
    if ($failOnMissing) { throw $message }
    Write-Host "::warning::$message"
    return
}

$results = @($files | ForEach-Object { Get-TestResult $_ })
$total = [int] ($results | Measure-Object Total -Sum).Sum
$passed = [int] ($results | Measure-Object Passed -Sum).Sum
$failed = [int] ($results | Measure-Object Failed -Sum).Sum
$skipped = [int] ($results | Measure-Object Skipped -Sum).Sum

Set-ActionOutput 'total' "$total"
Set-ActionOutput 'passed' "$passed"
Set-ActionOutput 'failed' "$failed"
Set-ActionOutput 'skipped' "$skipped"

$icon = if ($failed) { "`u{274C}" } else { "`u{2705}" }
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("### $icon $title")
$lines.Add('')
$lines.Add("$passed passed, $failed failed, $skipped skipped ($total total).")
$lines.Add('')
$lines.Add('| Results | Format | Passed | Failed | Skipped |')
$lines.Add('|---|---|---|---|---|')
foreach ($result in $results) {
    $name = [System.IO.Path]::GetRelativePath($workspace, $result.Path).Replace('\', '/')
    $lines.Add("| ``$name`` | $($result.Format) | $($result.Passed) | $($result.Failed) | $($result.Skipped) |")
}

$failures = @($results | ForEach-Object { $_.Failures })
if ($failures) {
    $lines.Add('')
    $lines.Add("<details open><summary>Failed tests ($($failures.Count))</summary>")
    $lines.Add('')
    $lines.Add('| Test | Message |')
    $lines.Add('|---|---|')
    foreach ($failure in $failures | Select-Object -First 50) {
        $lines.Add("| $(Format-MarkdownCell $failure.Name 120) | $(Format-MarkdownCell $failure.Message) |")
    }
    if ($failures.Count -gt 50) { $lines.Add("| `u{2026} and $($failures.Count - 50) more | |") }
    $lines.Add('')
    $lines.Add('</details>')
}
Add-ActionSummary ($lines -join "`n")

if ($annotate) {
    foreach ($failure in $failures | Select-Object -First 10) {
        $message = "$($failure.Name): $($failure.Message)"
        if ($message.Length -gt 1000) { $message = $message.Substring(0, 999) + "`u{2026}" }
        Write-ActionAnnotation error $message -Title $title
    }
}

Write-Host "$title`: $passed passed, $failed failed, $skipped skipped ($total total)."
if ($failOnFailure -and $failed) { throw "$failed test(s) failed." }

#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$paths = Split-ActionList (Get-ActionInput 'paths' '.')
$exclude = Split-ActionList (Get-ActionInput 'exclude')
$parse = (Get-ActionInput 'parse' 'true') -eq 'true'
$analyzer = (Get-ActionInput 'analyzer' 'false') -eq 'true'
$settings = Get-ActionInput 'analyzer-settings'
$analyzerVersion = Get-ActionInput 'analyzer-version' '1.25.0'

if (-not $parse -and -not $analyzer) { throw "Nothing to do: set 'parse' or 'analyzer' to 'true'." }

function Get-RelativePath([string] $Path) { [System.IO.Path]::GetRelativePath($workspace, $Path).Replace('\', '/') }

function Test-Excluded([string] $Relative) {
    if ($Relative -match '(^|/)(\.git|node_modules)(/|$)') { return $true }
    foreach ($pattern in $exclude) {
        $pattern = $pattern.Replace('\', '/') -replace '^\./', ''
        if ($Relative -like $pattern -or $Relative -like "$pattern/*") { return $true }
    }
    return $false
}

$files = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($entry in $paths) {
    # The workspace root itself is allowed here; Resolve-WorkspacePath only accepts paths inside it.
    $full = if ($entry -in '.', './') { $workspace } else { Resolve-WorkspacePath $entry $workspace 'path' }
    if (Test-Path -LiteralPath $full -PathType Leaf) { [void] $files.Add($full); continue }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "The path '$entry' does not exist." }
    # Walked by hand so .git, node_modules and excluded folders are never entered.
    $folders = [System.Collections.Generic.Stack[string]]::new()
    $folders.Push($full)
    while ($folders.Count) {
        $current = $folders.Pop()
        foreach ($child in [System.IO.Directory]::EnumerateDirectories($current)) {
            if (-not (Test-Excluded (Get-RelativePath $child))) { $folders.Push($child) }
        }
        foreach ($file in [System.IO.Directory]::EnumerateFiles($current)) {
            if ([System.IO.Path]::GetExtension($file) -in '.ps1', '.psm1', '.psd1' -and -not (Test-Excluded (Get-RelativePath $file))) {
                [void] $files.Add($file)
            }
        }
    }
}
$files = @($files)

$problems = [System.Collections.Generic.List[object]]::new()

if ($parse) {
    foreach ($file in $files) {
        $tokens = $null; $errors = $null
        [void] [System.Management.Automation.Language.Parser]::ParseFile($file, [ref] $tokens, [ref] $errors)
        foreach ($parseError in $errors) {
            $problems.Add([pscustomobject]@{
                    File    = Get-RelativePath $file
                    Line    = $parseError.Extent.StartLineNumber
                    Column  = $parseError.Extent.StartColumnNumber
                    Rule    = 'ParseError'
                    Message = $parseError.Message
                })
        }
    }
}

if ($analyzer -and $files) {
    Install-PowerShellModule -Name PSScriptAnalyzer -Version $analyzerVersion
    $parameters = @{}
    if ($settings) {
        $settingsPath = Resolve-WorkspacePath $settings $workspace 'analyzer-settings'
        if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) { throw "The analyzer-settings file '$settings' does not exist." }
        $parameters.Settings = $settingsPath
    }
    else { $parameters.Severity = 'Error', 'Warning' }

    foreach ($file in $files) {
        foreach ($finding in Invoke-ScriptAnalyzer -Path $file @parameters) {
            $problems.Add([pscustomobject]@{
                    File    = Get-RelativePath $file
                    Line    = $finding.Line
                    Column  = $finding.Column
                    Rule    = $finding.RuleName
                    Message = $finding.Message
                })
        }
    }
}

foreach ($problem in $problems) {
    Write-ActionAnnotation error "$($problem.Rule): $($problem.Message)" -File $problem.File -Line $problem.Line -Column $problem.Column
}

Set-ActionOutput 'files' "$($files.Count)"
Set-ActionOutput 'errors' "$($problems.Count)"

$checks = @($(if ($parse) { 'parsed' }), $(if ($analyzer) { 'analyzed' }) | Where-Object { $_ }) -join ' and '
$summary = "PowerShell check: $($files.Count) file(s) $checks, $($problems.Count) problem(s)."
if ($problems.Count) {
    $rows = $problems | Select-Object -First 50 | ForEach-Object {
        "| ``$($_.File):$($_.Line)`` | $($_.Rule) | $(Format-MarkdownCell $_.Message) |"
    }
    $summary += "`n`n| Location | Rule | Message |`n|---|---|---|`n" + ($rows -join "`n")
}
Add-ActionSummary $summary

if (-not $files) { Write-Host "::warning::No PowerShell files found in: $($paths -join ', ')." }
if ($problems.Count) { throw "$($problems.Count) PowerShell problem(s) found." }
Write-Host $summary

#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$paths = Split-ActionList (Get-ActionInput 'path' 'tests')
$version = Get-ActionInput 'version' '5.7.1'
$tags = @((Get-ActionInput 'tags') -split ',' | ForEach-Object Trim | Where-Object { $_ })
$excludeTags = @((Get-ActionInput 'exclude-tags') -split ',' | ForEach-Object Trim | Where-Object { $_ })
$results = Get-ActionInput 'results' 'test-results/pester.xml'
$resultsFormat = Get-ActionInput 'results-format' 'NUnitXml'
$coverage = Split-ActionList (Get-ActionInput 'coverage')
$coverageFormat = Get-ActionInput 'coverage-format' 'JaCoCo'
$coverageOutput = Get-ActionInput 'coverage-output' 'coverage/pester-coverage.xml'
$allowEmpty = (Get-ActionInput 'allow-empty' 'false') -eq 'true'

if ($version -notmatch '^[56]\.') { throw "Pester $version is not supported; use a 5.x or 6.x version." }
if (-not $paths) { throw "Set 'path' to the test folders or files." }

function Get-RelativePath([string] $Path) { [System.IO.Path]::GetRelativePath($workspace, $Path).Replace('\', '/') }

$testPaths = foreach ($entry in $paths) {
    $full = Resolve-WorkspacePath $entry $workspace 'path'
    if (-not (Test-Path -LiteralPath $full)) { throw "The test path '$entry' does not exist." }
    $full
}
$coveragePaths = foreach ($entry in $coverage) {
    $full = Resolve-WorkspacePath $entry $workspace 'coverage'
    if (-not (Test-Path -LiteralPath $full)) { throw "The coverage path '$entry' does not exist." }
    $full
}

Install-PowerShellModule -Name Pester -Version $version

$configuration = New-PesterConfiguration
$configuration.Run.Path = [string[]] $testPaths
$configuration.Run.Exit = $false
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'
if ($env:GITHUB_ACTIONS -eq 'true') { $configuration.Output.CIFormat = 'GithubActions' }
if ($tags) { $configuration.Filter.Tag = [string[]] $tags }
if ($excludeTags) { $configuration.Filter.ExcludeTag = [string[]] $excludeTags }

$resultsPath = ''
if ($results) {
    $resultsPath = Resolve-WorkspacePath $results $workspace 'results'
    [void] (New-Item -ItemType Directory -Force -Path (Split-Path $resultsPath))
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputPath = $resultsPath
    $configuration.TestResult.OutputFormat = $resultsFormat
}

$coveragePath = ''
if ($coveragePaths) {
    $coveragePath = Resolve-WorkspacePath $coverageOutput $workspace 'coverage-output'
    [void] (New-Item -ItemType Directory -Force -Path (Split-Path $coveragePath))
    $configuration.CodeCoverage.Enabled = $true
    $configuration.CodeCoverage.Path = [string[]] $coveragePaths
    $configuration.CodeCoverage.OutputPath = $coveragePath
    $configuration.CodeCoverage.OutputFormat = $coverageFormat
}

# Without test files Pester 5 writes an error and Pester 6 throws, so neither is called.
$testFiles = @($testPaths | ForEach-Object {
        if (Test-Path -LiteralPath $_ -PathType Leaf) { $_ }
        else { Get-ChildItem -LiteralPath $_ -Recurse -File -Filter '*.Tests.ps1' }
    })
$run = if ($testFiles) { Invoke-Pester -Configuration $configuration }
if (-not $run) { $run = [pscustomobject]@{ TotalCount = 0; PassedCount = 0; FailedCount = 0; SkippedCount = 0; CodeCoverage = $null; Containers = @() } }

$covered = ''
if ($coveragePaths -and $run.CodeCoverage) {
    $covered = '{0:0.##}' -f $run.CodeCoverage.CoveragePercent
}

Set-ActionOutput 'total' "$($run.TotalCount)"
Set-ActionOutput 'passed' "$($run.PassedCount)"
Set-ActionOutput 'failed' "$($run.FailedCount)"
Set-ActionOutput 'skipped' "$($run.SkippedCount)"
Set-ActionOutput 'results' $(if ($resultsPath -and (Test-Path -LiteralPath $resultsPath)) { Get-RelativePath $resultsPath } else { '' })
Set-ActionOutput 'coverage-report' $(if ($coveragePath -and (Test-Path -LiteralPath $coveragePath)) { Get-RelativePath $coveragePath } else { '' })
Set-ActionOutput 'coverage' $covered

$summary = "Pester $version`: $($run.PassedCount) passed, $($run.FailedCount) failed, $($run.SkippedCount) skipped"
if ($covered) { $summary += ", $covered% line coverage" }
Add-ActionSummary "$summary."

# A container that fails to load (a syntax error, a throwing BeforeAll) has no failed tests of its own.
$failedContainers = @($run.Containers | Where-Object Result -eq 'Failed')
if ($run.FailedCount -gt 0 -or $failedContainers.Count -gt 0) {
    $message = "$($run.FailedCount) test(s) failed"
    if ($failedContainers) { $message += "; $($failedContainers.Count) test file(s) failed to run: " + (($failedContainers | ForEach-Object { Get-RelativePath "$($_.Item)" }) -join ', ') }
    throw "$message."
}
if ($run.TotalCount -eq 0 -and -not $allowEmpty) {
    throw "No tests ran in: $($paths -join ', '). Check 'path' and the tag filters, or set 'allow-empty' to 'true'."
}
Write-Host "$summary."

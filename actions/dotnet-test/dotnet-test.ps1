#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$folder = Resolve-WorkspacePath (Get-ActionInput 'working-directory' '.') $workspace 'working-directory' -AllowRoot
$configuration = Get-ActionInput 'configuration' 'Release'
$runTests = (Get-ActionInput 'test' 'true') -eq 'true'
$filter = Get-ActionInput 'filter'
$coverage = (Get-ActionInput 'coverage' 'false') -eq 'true'
$windowsTargeting = (Get-ActionInput 'enable-windows-targeting' 'false') -eq 'true'
$resultsInput = Get-ActionInput 'results-directory' 'TestResults'
$split = (Get-ActionInput 'split-by-platform' 'false') -eq 'true'

$solution = Find-DotnetProject -Folder $folder -Workspace $workspace -Solution (Get-ActionInput 'solution')
$relativeSolution = [System.IO.Path]::GetRelativePath($workspace, $solution).Replace('\', '/')
$results = Resolve-WorkspacePath $resultsInput $workspace 'results-directory'
$relativeResults = [System.IO.Path]::GetRelativePath($workspace, $results).Replace('\', '/')

$common = @(if ($windowsTargeting) { '-p:EnableWindowsTargeting=true' })

function Invoke-Dotnet([string[]] $Arguments, [switch] $AllowFailure) {
    Write-Host "dotnet $($Arguments -join ' ')"
    dotnet @Arguments
    if ($LASTEXITCODE -and -not $AllowFailure) { throw "dotnet $($Arguments[0]) failed with exit code $LASTEXITCODE." }
}

# Evaluates MSBuild properties of a project. One property prints its value; several print JSON.
function Get-DotnetProperty([string] $Project, [string[]] $Name, [string[]] $Extra = @()) {
    $arguments = @('msbuild', $Project) + @($Name | ForEach-Object { "-getProperty:$_" }) + $common + $Extra
    $output = (& dotnet @arguments) -join "`n"
    if ($LASTEXITCODE) { throw "dotnet msbuild could not evaluate '$Project' (exit code $LASTEXITCODE)." }
    if ($Name.Count -eq 1) { return @{ $Name[0] = $output.Trim() } }
    $properties = @{}
    ($output | ConvertFrom-Json).Properties.PSObject.Properties | ForEach-Object { $properties[$_.Name] = "$($_.Value)" }
    return $properties
}

# The test projects of the solution that this platform runs: on Windows those with a Windows-only
# target framework, elsewhere the others. Needs the restore, since test SDK packages set IsTestProject.
function Get-PlatformTestProject {
    $projects = if ($solution -match '\.(slnx?)$') {
        $root = Split-Path -Parent $solution
        $listed = @(& dotnet sln $solution list)
        if ($LASTEXITCODE) { throw "dotnet sln list failed with exit code $LASTEXITCODE." }
        # The list follows a "Project(s)" header and a dashed line.
        $start = [array]::FindIndex([string[]] $listed, [Predicate[string]] { param($line) $line -match '^-+$' }) + 1
        @($listed | Select-Object -Skip $start | Where-Object { $_.Trim() } | ForEach-Object { [System.IO.Path]::GetFullPath((Join-Path $root $_.Trim())) })
    }
    else { @($solution) }

    foreach ($project in $projects) {
        $properties = Get-DotnetProperty $project @('IsTestProject', 'TargetFramework', 'TargetFrameworks')
        $frameworks = if ($properties.TargetFrameworks) { $properties.TargetFrameworks } else { $properties.TargetFramework }
        $isTest = $properties.IsTestProject
        # A multi-targeting project imports its package props per framework, so ask one framework.
        if (-not $isTest -and $properties.TargetFrameworks) {
            $first = $properties.TargetFrameworks.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)[0].Trim()
            $isTest = (Get-DotnetProperty $project @('IsTestProject') @("-p:TargetFramework=$first")).IsTestProject
        }
        if ($isTest -ne 'true') { continue }
        $windowsOnly = Test-WindowsTargetFramework $frameworks
        $relative = [System.IO.Path]::GetRelativePath($workspace, $project).Replace('\', '/')
        if ($windowsOnly -eq [bool] $IsWindows) { Write-Host "Testing $relative ($frameworks)."; $project }
        else { Write-Host "Skipping $relative ($frameworks): it is tested on $(if ($windowsOnly) { 'Windows' } else { 'the other runners' })." }
    }
}

$platform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'macOS' } else { 'Linux' }
$exitCode = 0
Push-Location -LiteralPath $folder
try {
    Invoke-Dotnet (@('restore', $solution) + $common + (Split-CommandLine (Get-ActionInput 'restore-args')))

    # Split by platform, only this platform's test projects (and what they reference) are built and tested.
    $targets = if ($split) { @(Get-PlatformTestProject) } else { @($solution) }
    foreach ($target in $targets) {
        Invoke-Dotnet (@('build', $target, '--no-restore', '--configuration', $configuration) + $common + (Split-CommandLine (Get-ActionInput 'build-args')))
    }

    Set-ActionOutput 'solution' $relativeSolution
    if (-not $targets) {
        Set-ActionOutput 'results' ''
        Set-ActionOutput 'coverage-report' ''
        Add-ActionSummary "No test project of ``$relativeSolution`` runs on $platform; nothing was built or tested."
        return
    }
    if (-not $runTests) {
        Set-ActionOutput 'results' ''
        Set-ActionOutput 'coverage-report' ''
        Add-ActionSummary "Built ``$relativeSolution`` ($configuration); tests were not run."
        return
    }

    # Results from an earlier run would be reported again.
    if (Test-Path -LiteralPath $results) { Remove-Item -LiteralPath $results -Recurse -Force }

    # A failing test run still writes its results, so the outputs are set before failing the step.
    $PSNativeCommandUseErrorActionPreference = $false
    foreach ($target in $targets) {
        $arguments = @('test', $target, '--no-build', '--configuration', $configuration, '--logger', 'trx', '--results-directory', $results) + $common
        if ($filter) { $arguments += @('--filter', $filter) }
        if ($coverage) { $arguments += @('--collect', 'XPlat Code Coverage') }
        $arguments += Split-CommandLine (Get-ActionInput 'test-args')
        Invoke-Dotnet $arguments -AllowFailure
        if ($LASTEXITCODE -and -not $exitCode) { $exitCode = $LASTEXITCODE }
    }
    $PSNativeCommandUseErrorActionPreference = $true
}
finally { Pop-Location }

$trx = @(Get-ChildItem -LiteralPath $results -Filter '*.trx' -File -ErrorAction SilentlyContinue)
Set-ActionOutput 'results' $(if ($trx) { "$relativeResults/*.trx" } else { '' })

$coverageReport = ''
if ($coverage) {
    # Coverlet writes <results>/<guid>/coverage.cobertura.xml per test project; the TRX "In" folders hold copies.
    $reports = @(Get-ChildItem -Path (Join-Path $results '*' 'coverage.cobertura.xml') -File -ErrorAction SilentlyContinue | ForEach-Object FullName)
    if ($reports) {
        $merged = Merge-CoberturaReport -Path $reports -Destination (Join-Path $results 'coverage.cobertura.xml')
        $coverageReport = "$relativeResults/coverage.cobertura.xml"
        Write-Host "Merged $($merged.Reports) coverage report(s): $($merged.Covered)/$($merged.Total) lines covered."
    }
    else {
        Write-Host '::warning::No coverage was collected. Each test project needs a reference to the coverlet.collector package.'
    }
}
Set-ActionOutput 'coverage-report' $coverageReport

$outcome = if ($exitCode) { "failed (exit code $exitCode)" } else { 'passed' }
$scope = if ($split) { " ($($targets.Count) $platform test project(s))" } else { '' }
Add-ActionSummary "Built and tested ``$relativeSolution``$scope ($configuration): $outcome."

if ($exitCode) { throw "dotnet test failed with exit code $exitCode." }

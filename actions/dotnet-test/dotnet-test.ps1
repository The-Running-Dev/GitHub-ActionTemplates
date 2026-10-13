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

Push-Location -LiteralPath $folder
try {
    Invoke-Dotnet (@('restore', $solution) + $common + (Split-CommandLine (Get-ActionInput 'restore-args')))
    Invoke-Dotnet (@('build', $solution, '--no-restore', '--configuration', $configuration) + $common + (Split-CommandLine (Get-ActionInput 'build-args')))

    Set-ActionOutput 'solution' $relativeSolution
    if (-not $runTests) {
        Set-ActionOutput 'results' ''
        Set-ActionOutput 'coverage-report' ''
        Add-ActionSummary "Built ``$relativeSolution`` ($configuration); tests were not run."
        return
    }

    # Results from an earlier run would be reported again.
    if (Test-Path -LiteralPath $results) { Remove-Item -LiteralPath $results -Recurse -Force }

    $arguments = @('test', $solution, '--no-build', '--configuration', $configuration, '--logger', 'trx', '--results-directory', $results) + $common
    if ($filter) { $arguments += @('--filter', $filter) }
    if ($coverage) { $arguments += @('--collect', 'XPlat Code Coverage') }
    $arguments += Split-CommandLine (Get-ActionInput 'test-args')

    # A failing test run still writes its results, so the outputs are set before failing the step.
    $PSNativeCommandUseErrorActionPreference = $false
    Invoke-Dotnet $arguments -AllowFailure
    $exitCode = $LASTEXITCODE
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
Add-ActionSummary "Built and tested ``$relativeSolution`` ($configuration): $outcome."

if ($exitCode) { throw "dotnet test failed with exit code $exitCode." }

#Requires -Version 7.4
<#
.SYNOPSIS
Self-test: checks the node-ci, pwsh-ci, dotnet and npm-package artifacts. Each test run uploaded
readable results with every test passing and a coverage report, and the npm and NuGet packages
were packed with a computed prerelease version.
#>
[CmdletBinding()]
param(
    [string] $ArtifactPath = 'artifacts',
    [switch] $ExpectPackage,
    [switch] $ExpectNuGetPackage
)

$ErrorActionPreference = 'Stop'
$artifacts = $ArtifactPath
Import-Module (Join-Path $PSScriptRoot '..' 'actions' '_lib' 'Functions.psm1') -Force

$failures = [System.Collections.Generic.List[string]]::new()
function Test-Check([string] $Name, [scriptblock] $Check) {
    try {
        $detail = & $Check
        Write-Host "ok   $Name $detail"
    }
    catch {
        Write-Host "FAIL $Name $($_.Exception.Message)"
        $failures.Add($Name)
    }
}

function Test-Run([string] $Prefix, [string] $Results, [string] $Coverage, [int] $Expected, [int] $Tests) {
    $runs = @(Get-ChildItem -LiteralPath $artifacts -Directory -Filter "$Prefix-*")
    if ($runs.Count -ne $Expected) { $failures.Add($Prefix); Write-Host "FAIL $Prefix expected $Expected artifacts, found $($runs.Count)."; return }
    foreach ($run in $runs) {
        Test-Check "$($run.Name) results" {
            $files = @(Get-ChildItem -Path (Join-Path $run.FullName $Results) -File)
            if ($files.Count -ne 1) { throw "Expected one results file, found $($files.Count)." }
            $result = Get-TestResult $files[0].FullName
            if (-not $result.Total -or $result.Failed) { throw "$($result.Total) tests, $($result.Failed) failed." }
            if ($Tests -and $result.Total -ne $Tests) { throw "Expected $Tests tests, found $($result.Total)." }
            "($($result.Format), $($result.Passed)/$($result.Total) passed)"
        }
        Test-Check "$($run.Name) coverage" {
            $report = Get-CoverageReport (Join-Path $run.FullName $Coverage)
            if (-not $report.Total) { throw 'The report has no lines.' }
            "($($report.Format), $($report.Covered)/$($report.Total) lines)"
        }
    }
}

Test-Run 'ci-node' 'test-results/junit.xml' 'coverage/lcov.info' 2
Test-Run 'ci-pester' 'test-results/pester.xml' 'coverage/pester-coverage.xml' 2
# The test filter leaves out the fixture's slow test.
Test-Run 'ci-dotnet' '*.trx' 'coverage.cobertura.xml' 2 3

$diagnostics = @(Get-ChildItem -LiteralPath $artifacts -Directory -Filter 'ci-diagnostics-*')
if ($diagnostics.Count -ne 2) { throw "Expected 2 .NET diagnostic artifacts, found $($diagnostics.Count)." }
foreach ($diagnostic in $diagnostics) {
    Test-Check "$($diagnostic.Name) diagnostics" {
        $files = @(Get-ChildItem -LiteralPath $diagnostic.FullName -File -Recurse)
        if ($files.Count -ne 2) { throw 'Expected exactly the JSON and installer log fixture.' }
        $probe = Get-Content -LiteralPath (Join-Path $diagnostic.FullName 'probe.json') -Raw | ConvertFrom-Json
        if ($probe.fixture -ne 'dotnet-diagnostics') { throw 'Incorrect diagnostic JSON.' }
        $log = Get-Content -LiteralPath (Join-Path $diagnostic.FullName 'installer.log') -Raw
        if ($log.Trim() -ne 'fixture installer evidence') { throw 'Incorrect diagnostic log.' }
    }
}

if ($ExpectPackage) {
    Test-Check 'ci-npm-package' {
        $tarballs = @(Get-ChildItem -LiteralPath (Join-Path $artifacts 'ci-npm-package') -Filter '*.tgz')
        if ($tarballs.Count -ne 1) { throw "Expected one tarball, found $($tarballs.Count)." }
        $manifest = Get-TarballManifest $tarballs[0].FullName
        if ($manifest.name -ne 'fixture-npm-lib') { throw "Unexpected package name '$($manifest.name)'." }
        if ($manifest.version -notmatch '^2\.3\.4-(ci|pr)\.') { throw "Version '$($manifest.version)' is not a 2.3.4 prerelease." }
        if ($tarballs[0].Name -ne "fixture-npm-lib-$($manifest.version).tgz") { throw "Unexpected tarball name '$($tarballs[0].Name)'." }
        "($($manifest.name)@$($manifest.version))"
    }
}
else { Write-Host 'skip ci-npm-package (not built on tags)' }

if ($ExpectNuGetPackage) {
    Test-Check 'ci-nupkg' {
        $packages = @(Get-ChildItem -LiteralPath (Join-Path $artifacts 'ci-nupkg') -Filter '*.nupkg')
        if ($packages.Count -ne 1) { throw "Expected one package, found $($packages.Count)." }
        if ($packages[0].Name -notmatch '^Fixture\.Calculator\.1\.4\.2-(ci|pr)\.[0-9A-Za-z.-]+\.nupkg$') { throw "'$($packages[0].Name)' is not a 1.4.2 prerelease of Fixture.Calculator." }
        "($($packages[0].Name))"
    }
}
else { Write-Host 'skip ci-nupkg (not packed on tags)' }

if ($failures.Count) { throw "$($failures.Count) check(s) failed: $($failures -join ', ')." }

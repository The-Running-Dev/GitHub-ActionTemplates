#Requires -Version 7.4
<#
.SYNOPSIS
Self-test: checks the node-ci, pwsh-ci and npm-package artifacts. Each test run uploaded readable
results with every test passing and a coverage report, and the npm package was packed with a
computed prerelease version.
#>
[CmdletBinding()]
param(
    [string] $ArtifactPath = 'artifacts',
    [switch] $ExpectPackage
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

function Test-Run([string] $Prefix, [string] $Results, [string] $Coverage, [int] $Expected) {
    $runs = @(Get-ChildItem -LiteralPath $artifacts -Directory -Filter "$Prefix-*")
    if ($runs.Count -ne $Expected) { $failures.Add($Prefix); Write-Host "FAIL $Prefix expected $Expected artifacts, found $($runs.Count)."; return }
    foreach ($run in $runs) {
        Test-Check "$($run.Name) results" {
            $result = Get-TestResult (Join-Path $run.FullName $Results)
            if (-not $result.Total -or $result.Failed) { throw "$($result.Total) tests, $($result.Failed) failed." }
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

if ($failures.Count) { throw "$($failures.Count) check(s) failed: $($failures -join ', ')." }

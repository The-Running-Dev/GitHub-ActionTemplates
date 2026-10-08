#Requires -Version 7.2
<#
.SYNOPSIS
Self-test: checks the outputs of the context, version and assert-tag-version actions, passed in
through environment variables by the self-test workflow.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-That([bool] $Condition, [string] $Message) {
    if ($Condition) { Write-Host "ok   $Message" } else { Write-Host "FAIL $Message"; $failures.Add($Message) }
}

$semver = '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$'
Assert-That ($env:CONTEXT_IMAGE -eq $env:EXPECTED_IMAGE.ToLowerInvariant()) "context image '$env:CONTEXT_IMAGE'"
Assert-That ($env:CONTEXT_SHORT_SHA -eq $env:GITHUB_SHA.Substring(0, 7)) "context short-sha '$env:CONTEXT_SHORT_SHA'"
Assert-That ($env:CONTEXT_IS_PULL_REQUEST -eq $env:IS_PULL_REQUEST) "context is-pull-request '$env:CONTEXT_IS_PULL_REQUEST'"
if ($env:IS_PULL_REQUEST -eq 'true') {
    Assert-That ($env:CONTEXT_SHOULD_PUBLISH -eq 'false') 'pull requests are not published'
}
Assert-That ($env:TAG_VERSION -match $semver) "tag strategy '$env:TAG_VERSION'"
Assert-That ($env:RUN_NUMBER_VERSION -match $semver) "run-number strategy '$env:RUN_NUMBER_VERSION'"
if ($env:IS_TAG -ne 'true') {
    Assert-That ($env:TAG_VERSION -match '-') 'tag strategy is a prerelease outside tag builds'
    Assert-That ($env:MANIFEST_VERSION -like '2.3.4-*') "manifest strategy '$env:MANIFEST_VERSION'"
}
Assert-That ($env:ASSERT_CHECKED -eq 'true') "assert-tag-version checked '$env:ASSERT_CHECKED'"

if ($failures.Count) { throw "$($failures.Count) check(s) failed." }

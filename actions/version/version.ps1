#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$strategy = (Get-ActionInput 'strategy' 'tag').ToLowerInvariant()
$prefix = Get-ActionInput 'tag-prefix' 'v'
$label = Get-ActionInput 'prerelease-label' 'ci'
$prLabel = Get-ActionInput 'pr-label' 'pr'
$workingDirectory = Get-ActionInput 'working-directory' '.'

foreach ($value in $label, $prLabel) {
    if ($value -notmatch '^[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*$') {
        throw "Prerelease label '$value' may only contain [0-9A-Za-z-] separated by dots."
    }
}

$context = Get-ActionContext

function Get-GitVersion([string] $Path, [string] $ToolVersion) {
    if ($ToolVersion -notmatch '^\d+\.\d+\.\d+$') { throw "The gitversion-version must be Major.Minor.Patch; got '$ToolVersion'." }

    $shallow = git -C $Path rev-parse --is-shallow-repository
    if ($LASTEXITCODE -ne 0) { throw "'$Path' is not a git checkout." }
    if ($shallow -eq 'true') { throw 'GitVersion needs the full history. Check out with fetch-depth 0.' }

    # A dotnet-gitversion on PATH wins, then the repository's tool manifest, then a pinned install.
    $toolManifest = Join-Path $Path '.config' 'dotnet-tools.json'
    if (Get-Command dotnet-gitversion -ErrorAction SilentlyContinue) {
        $output = dotnet-gitversion $Path /output json
    }
    elseif ((Test-Path -LiteralPath $toolManifest) -and (Get-Content -Raw -LiteralPath $toolManifest) -match '"gitversion\.tool"') {
        Push-Location -LiteralPath $Path
        try {
            dotnet tool restore | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'dotnet tool restore failed.' }
            $output = dotnet tool run dotnet-gitversion /output json
        }
        finally { Pop-Location }
    }
    else {
        $temp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
        $toolPath = Join-Path $temp "gitversion-$ToolVersion"
        $tool = Join-Path $toolPath 'dotnet-gitversion'
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            Write-Host "Installing GitVersion.Tool $ToolVersion"
            dotnet tool install GitVersion.Tool --version $ToolVersion --tool-path $toolPath | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "Installing GitVersion.Tool $ToolVersion failed." }
        }
        $output = & $tool $Path /output json
    }
    if ($LASTEXITCODE -ne 0) { throw "GitVersion failed with exit code $LASTEXITCODE`n$($output -join "`n")" }

    $semVer = (($output -join "`n") | ConvertFrom-Json).SemVer
    if (-not $semVer) { throw "GitVersion did not return a SemVer.`n$($output -join "`n")" }
    return $semVer
}

$tagVersion = $null
if ($context.IsTag) {
    if (-not $context.RefName.StartsWith($prefix)) {
        throw "Tag '$($context.RefName)' does not start with the tag prefix '$prefix'."
    }
    $tagVersion = ConvertTo-SemVer $context.RefName.Substring($prefix.Length)
}

$source = $strategy
switch ($strategy) {
    'tag' {
        if ($tagVersion) {
            $base = $tagVersion
            $stable = $true
        }
        else {
            $latest = Get-LatestTagVersion -Prefix $prefix -Path $workingDirectory
            if (-not $latest) { $latest = ConvertTo-SemVer '0.0.0' }

            # The next build after a release is a prerelease of the next patch;
            # after a prerelease tag it stays on that version's core.
            $patch = if ($latest.Prerelease) { $latest.Patch } else { $latest.Patch + 1 }
            $base = ConvertTo-SemVer ('{0}.{1}.{2}' -f $latest.Major, $latest.Minor, $patch)
            $stable = $false
        }
        $suffix = if ($context.IsPullRequest) { "$prLabel.$($context.PullRequestNumber).$($context.RunNumber)" } else { "$label.$($context.RunNumber)" }
    }
    'manifest' {
        $manifest = Get-ActionInput 'manifest'
        $manifestPath = if ($manifest) { Join-Path $workingDirectory $manifest } else { Find-Manifest $workingDirectory }
        $base = ConvertTo-SemVer (Get-ManifestVersion $manifestPath)
        $source = "manifest ($manifestPath)"

        if ($tagVersion -and (Format-SemVer $tagVersion) -ne (Format-SemVer $base)) {
            throw "Tag '$($context.RefName)' does not match version '$(Format-SemVer $base)' in '$manifestPath'."
        }
        $stable = [bool] $tagVersion
        $suffix = if ($context.IsPullRequest) { "$prLabel.$($context.PullRequestNumber).$($context.RunNumber)" } else { "$label.$($context.RunNumber)" }
    }
    'run-number' {
        if ($tagVersion) {
            $base = $tagVersion
            $stable = $true
        }
        else {
            $baseVersion = Get-ActionInput 'base-version'
            if ($baseVersion -notmatch '^\d+\.\d+$') {
                throw "The run-number strategy needs 'base-version' as Major.Minor (for example 1.0); got '$baseVersion'."
            }
            $base = ConvertTo-SemVer "$baseVersion.$($context.RunNumber)"
            $stable = $context.IsDefaultBranch
        }
        $suffix = if ($context.IsPullRequest) { "$prLabel.$($context.PullRequestNumber)" } else { $label }
    }
    'gitversion' {
        $semVer = Get-GitVersion -Path $workingDirectory -ToolVersion (Get-ActionInput 'gitversion-version' '6.8.2')
        $base = ConvertTo-SemVer $semVer
        $source = "GitVersion ($semVer)"

        if ($tagVersion -and (Format-SemVer $tagVersion) -ne (Format-SemVer $base)) {
            throw "Tag '$($context.RefName)' does not match version '$(Format-SemVer $base)' from GitVersion."
        }
        # GitVersion already labels builds that are not releases, so its version is used as it is.
        $stable = $true
    }
    default {
        throw "Unknown strategy '$strategy'. Use tag, manifest, run-number, or gitversion."
    }
}

$version = Format-SemVer $base
if (-not $stable) {
    $suffix = $suffix.Replace('..', '.').Trim('.')
    $version = if ($base.Prerelease) { "$version.$suffix" } else { "$version-$suffix" }
}

$parsed = ConvertTo-SemVer $version

Set-ActionOutput 'version' $version
Set-ActionOutput 'major' "$($parsed.Major)"
Set-ActionOutput 'minor' "$($parsed.Minor)"
Set-ActionOutput 'patch' "$($parsed.Patch)"
Set-ActionOutput 'prerelease' $parsed.Prerelease
Set-ActionOutput 'is-prerelease' ([bool] $parsed.Prerelease).ToString().ToLowerInvariant()
Set-ActionOutput 'is-release' $context.IsTag.ToString().ToLowerInvariant()
Set-ActionOutput 'tag' "$prefix$version"

Add-ActionSummary @"
### Version ``$version``

| Strategy | Source | Event | Ref |
|---|---|---|---|
| $strategy | $source | $($context.EventName) | $($context.RefName) |
"@

#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$project = Get-ActionInput 'path' '.'
$version = Get-ActionInput 'version'
$destination = Get-ActionInput 'destination' 'dist-package'
$ignoreScripts = (Get-ActionInput 'ignore-scripts' 'false') -eq 'true'

$projectPath = if ($project -in '.', './') { $workspace } else { Resolve-WorkspacePath $project $workspace 'path' }
if (-not (Test-Path -LiteralPath (Join-Path $projectPath 'package.json') -PathType Leaf)) { throw "The path '$project' has no package.json." }
$destinationPath = Resolve-WorkspacePath $destination $workspace 'destination'
[void] (New-Item -ItemType Directory -Force -Path $destinationPath)

if ($version) {
    $version = $version.TrimStart('v')
    [void] (ConvertTo-SemVer $version)
}

Push-Location -LiteralPath $projectPath
try {
    if ($version) {
        Write-Host "Stamping version $version"
        # The version lifecycle scripts (often a test run) are for releasing by hand, not for stamping.
        npm version $version --no-git-tag-version --allow-same-version --ignore-scripts | Out-Host
    }
    $arguments = @('pack', '--json', '--pack-destination', $destinationPath)
    if ($ignoreScripts) { $arguments += '--ignore-scripts' }
    $output = @(npm @arguments)
}
finally { Pop-Location }

# Lifecycle scripts print to the same stdout, so the JSON is the last top-level "[" ... "]" block.
$start = -1
for ($i = $output.Count - 1; $i -ge 0; $i--) { if ($output[$i] -match '^\[\s*$') { $start = $i; break } }
$end = -1
if ($start -ge 0) { for ($i = $start + 1; $i -lt $output.Count; $i++) { if ($output[$i] -match '^\]\s*$') { $end = $i; break } } }
if ($end -lt 0) { throw "npm pack printed no JSON:`n$($output -join "`n")" }
$output | Select-Object -First $start | Out-Host
$output | Select-Object -Skip ($end + 1) | Out-Host
$packed = @(($output[$start..$end] -join "`n") | ConvertFrom-Json)
if ($packed.Count -ne 1) { throw "npm pack returned $($packed.Count) packages; expected one." }
$tarball = Join-Path $destinationPath $packed[0].filename
if (-not (Test-Path -LiteralPath $tarball -PathType Leaf)) { throw "npm pack did not write '$tarball'." }

$relative = [System.IO.Path]::GetRelativePath($workspace, $tarball).Replace('\', '/')
Set-ActionOutput 'tarball' $relative
Set-ActionOutput 'name' $packed[0].name
Set-ActionOutput 'version' $packed[0].version

$size = '{0:0.#} kB' -f ($packed[0].size / 1KB)
Add-ActionSummary "Packed ``$($packed[0].name)@$($packed[0].version)`` ($($packed[0].entryCount) files, $size) to ``$relative``."

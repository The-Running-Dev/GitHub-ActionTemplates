#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$folder = Resolve-WorkspacePath (Get-ActionInput 'working-directory' '.') $workspace 'working-directory' -AllowRoot
$configuration = Get-ActionInput 'configuration' 'Release'
$version = (Get-ActionInput 'version').TrimStart('v')
$windowsTargeting = (Get-ActionInput 'enable-windows-targeting' 'false') -eq 'true'
$destination = Resolve-WorkspacePath (Get-ActionInput 'destination' 'dist-nuget') $workspace 'destination'

if ($version) { [void] (ConvertTo-SemVer $version) }
$solution = Find-DotnetProject -Folder $folder -Workspace $workspace -Solution (Get-ActionInput 'solution')

# Packages left from an earlier run would be published with this one.
if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
[void] (New-Item -ItemType Directory -Force -Path $destination)

# ContinuousIntegrationBuild makes the build deterministic and maps source paths for Source Link.
$arguments = @('pack', $solution, '--configuration', $configuration, '--output', $destination, '-p:ContinuousIntegrationBuild=true')
if ($version) { $arguments += "-p:Version=$version" }
if ($windowsTargeting) { $arguments += '-p:EnableWindowsTargeting=true' }
$arguments += Split-CommandLine (Get-ActionInput 'args')

Push-Location -LiteralPath $folder
try {
    Write-Host "dotnet $($arguments -join ' ')"
    dotnet @arguments
    if ($LASTEXITCODE) { throw "dotnet pack failed with exit code $LASTEXITCODE." }
}
finally { Pop-Location }

$files = @(Get-ChildItem -LiteralPath $destination -File | Where-Object Extension -in '.nupkg', '.snupkg' | Sort-Object Name)
$packages = @($files | Where-Object Extension -eq '.nupkg')
if (-not $packages) { throw "dotnet pack wrote no .nupkg to '$destination'. Set IsPackable in the projects to pack." }
if ($version) {
    # Package file names leave out build metadata.
    $fileVersion = $version.Split('+')[0]
    $stale = @($packages | Where-Object { -not $_.Name.EndsWith(".$fileVersion.nupkg", [System.StringComparison]::OrdinalIgnoreCase) })
    if ($stale) { throw "These packages do not have version $($fileVersion): $($stale.Name -join ', '). A project sets PackageVersion itself." }
}

$relative = @($files | ForEach-Object { [System.IO.Path]::GetRelativePath($workspace, $_.FullName).Replace('\', '/') })
Set-ActionOutput 'packages' ($relative -join "`n")
Set-ActionOutput 'count' "$($packages.Count)"
Set-ActionOutput 'destination' ([System.IO.Path]::GetRelativePath($workspace, $destination).Replace('\', '/'))

$rows = $files | ForEach-Object { "| ``$($_.Name)`` | $('{0:0.#} kB' -f ($_.Length / 1KB)) |" }
Add-ActionSummary (@("### Packed $($packages.Count) package(s)", '', '| Package | Size |', '|---|---|') + $rows -join "`n")

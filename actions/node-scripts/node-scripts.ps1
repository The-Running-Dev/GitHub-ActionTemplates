#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$project = Get-ActionInput 'path'
$scripts = @((Get-ActionInput 'scripts' 'build') -split '\s+' | Where-Object { $_ })
$setup = @((Get-ActionInput 'setup') -split '\s+' | Where-Object { $_ })
$dependencies = Split-ActionList (Get-ActionInput 'dependencies')
$packageManager = Get-ActionInput 'package-manager'
$browser = (Get-ActionInput 'browser' 'false') -eq 'true'

if (-not $project) { throw "Set 'path' to the Node project folder." }

function Resolve-Project([string] $Folder, [string] $Name) {
    $path = Resolve-WorkspacePath $Folder $workspace $Name
    if (-not (Test-Path -LiteralPath (Join-Path $path 'package.json') -PathType Leaf)) {
        throw "The $Name '$Folder' has no package.json."
    }
    return $path
}

function Invoke-Project([string] $Path, [string[]] $Scripts, [string[]] $Setup = @()) {
    $name = [System.IO.Path]::GetRelativePath($workspace, $Path).Replace('\', '/')
    $manager = Get-PackageManager $Path $packageManager
    Write-Host "::group::$name (${manager}: $((@($Setup) + @($Scripts)) -join ', '))"
    try {
        Push-Location -LiteralPath $Path
        try {
            # Setup scripts prepare the install (vendored packages, generated files), so they run first.
            foreach ($script in $Setup) { npm run $script }
            Install-NodePackage $Path $manager
            foreach ($script in $Scripts) { & $manager run $script }
        }
        finally { Pop-Location }
    }
    finally { Write-Host '::endgroup::' }
}

function Find-Chromium {
    foreach ($name in 'chromium', 'chromium-browser', 'google-chrome-stable', 'google-chrome') {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
    }
    return $null
}

# Paths are checked before anything is installed.
$projectPath = Resolve-Project $project 'path'
$dependencyPaths = @($dependencies | ForEach-Object { Resolve-Project $_ 'dependency' })

if ($browser) {
    $chromium = Find-Chromium
    if (-not $chromium) {
        if (-not ($IsLinux -and (Get-Command apt-get -ErrorAction SilentlyContinue))) {
            throw "No Chromium found, and it can only be installed with apt-get on Linux. Install a browser before this step."
        }
        # GitHub-hosted runners need sudo; a container job runs as root, which may have no sudo.
        $root = (id -u) -eq '0'
        function Invoke-AptGet {
            if ($root) { apt-get @args } else { sudo apt-get @args }
        }
        Write-Host '::group::Install Chromium'
        Invoke-AptGet update -qq
        # Without a font package pages render in a fallback font, which changes text metrics.
        Invoke-AptGet install -y -qq --no-install-recommends chromium fonts-liberation
        Write-Host '::endgroup::'
        $chromium = Find-Chromium
        if (-not $chromium) { throw 'Installing chromium did not put a browser on PATH.' }
    }
    Write-Host "Chromium: $chromium"
    $env:PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH = $chromium
    $env:PUPPETEER_EXECUTABLE_PATH = $chromium
    $env:CHROME_BIN = $chromium
}

foreach ($dependency in $dependencyPaths) { Invoke-Project $dependency @('build') }
Invoke-Project $projectPath $scripts $setup

$relative = [System.IO.Path]::GetRelativePath($workspace, $projectPath).Replace('\', '/')
Add-ActionSummary "Ran ``$((@($setup) + @($scripts)) -join '`, `')`` in ``$relative``."

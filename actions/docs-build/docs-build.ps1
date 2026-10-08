#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$temp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }

$builder = Get-ActionInput 'builder' 'template'
$source = Get-ActionInput 'source' 'docs'
$template = Get-ActionInput 'template'
$packageManager = Get-ActionInput 'package-manager'
$buildCommand = Get-ActionInput 'build-command' 'build'
$output = Get-ActionInput 'output' "$source/build"

if ($builder -notin 'template', 'node') { throw "Unknown builder '$builder'. Use 'template' or 'node'." }
if ($packageManager -and $packageManager -notin 'npm', 'pnpm', 'yarn') {
    throw "Unknown package-manager '$packageManager'. Use 'npm', 'pnpm' or 'yarn', or leave it empty to detect it."
}

$sourcePath = Resolve-WorkspacePath $source $workspace 'source'
$outputPath = Resolve-WorkspacePath $output $workspace 'output'
if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) { throw "The source folder '$source' does not exist." }
if ($outputPath -eq $sourcePath) { throw "The output folder must not be the source folder '$source'." }

function Get-RelativePath([string] $Path) {
    [System.IO.Path]::GetRelativePath($workspace, $Path).Replace('\', '/')
}

function New-TemplateRepository {
    # build node-template clones its template with git, so the bundled template becomes a
    # one-commit repository in the runner's temp folder, passed as a file:// URL so the
    # shallow clone is honoured.
    $repository = Join-Path $temp "docs-template-$([guid]::NewGuid().ToString('n'))"
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'template') -Destination $repository -Recurse
    git -C $repository init --quiet
    git -C $repository add --all
    git -C $repository -c user.name=docs-build -c user.email=docs-build@localhost -c commit.gpgsign=false commit --quiet -m 'docs template'
    # A [uri] cast reads a Unix path as a relative URI; the Absolute kind makes it file:///.
    return [uri]::new($repository, [System.UriKind]::Absolute).AbsoluteUri
}

if ($builder -eq 'template') {
    if (-not (Get-Command build -CommandType Application, ExternalScript -ErrorAction SilentlyContinue)) {
        throw "The 'template' builder runs 'build node-template' from the build-agent image. Run the job in a ghcr.io/the-running-dev/build-agent container, as the docs workflow does, or use builder 'node'."
    }

    $templateName = if ($template) { $template } else { 'bundled Docusaurus template' }
    if (-not $template) { $template = New-TemplateRepository }

    $arguments = @(
        'node-template'
        '-WorkingDir', $workspace
        '-AppDir', (Get-RelativePath $sourcePath)
        '-NodeTemplateRepositoryUrl', $template
        '-NodeTemplateDirPath', (Join-Path $temp "docs-template-clone-$([guid]::NewGuid().ToString('n'))")
    )
    if ($packageManager) { $arguments += '-PackageManager', $packageManager }

    Write-Host "Building '$source' with the $templateName"
    build @arguments
}
else {
    Push-Location -LiteralPath $sourcePath
    try {
        if (-not $packageManager) {
            $packageManager = if (Test-Path pnpm-lock.yaml) { 'pnpm' } elseif (Test-Path yarn.lock) { 'yarn' } else { 'npm' }
        }

        Write-Host "Building '$source' with $packageManager run $buildCommand"
        switch ($packageManager) {
            'npm' { if ((Test-Path package-lock.json) -or (Test-Path npm-shrinkwrap.json)) { npm ci } else { npm install } }
            'pnpm' { pnpm install --frozen-lockfile }
            'yarn' { yarn install }
        }
        & $packageManager run $buildCommand
    }
    finally { Pop-Location }
}

if (-not (Test-Path -LiteralPath (Join-Path $outputPath 'index.html') -PathType Leaf)) {
    throw "The build did not produce '$output/index.html'. Set 'output' to the folder the build writes the site to."
}

$relativeOutput = Get-RelativePath $outputPath
$files = @(Get-ChildItem -LiteralPath $outputPath -Recurse -File).Count

Set-ActionOutput 'path' $relativeOutput
Add-ActionSummary "Built the documentation in ``$source`` with the ``$builder`` builder: $files files in ``$relativeOutput``."

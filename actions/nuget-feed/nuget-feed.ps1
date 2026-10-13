#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$entries = Split-ActionList (Get-ActionInput 'sources' 'github')
$username = Get-ActionInput 'username'
if (-not $username) { $username = if ($env:GITHUB_ACTOR) { $env:GITHUB_ACTOR } else { 'github' } }
$tokenVariable = Get-ActionInput 'token-variable' 'NUGET_FEED_TOKEN'
$configInput = Get-ActionInput 'config-file'

if (-not $entries) { throw "Set 'sources' to at least one feed." }
if ($tokenVariable -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { throw "The token-variable '$tokenVariable' is not an environment variable name." }

$configFile = if ($configInput) {
    Resolve-WorkspacePath $configInput $workspace 'config-file'
}
elseif ($IsWindows) {
    Join-Path $env:APPDATA 'NuGet' 'NuGet.Config'
}
else {
    Join-Path $HOME '.nuget' 'NuGet' 'NuGet.Config'
}

$sources = foreach ($entry in $entries) {
    $name, $url = $entry.Split('=', 2) | ForEach-Object Trim
    if ($name -eq 'github' -and -not $url) {
        $owner = if ($env:GITHUB_REPOSITORY_OWNER) { $env:GITHUB_REPOSITORY_OWNER } else { "$env:GITHUB_REPOSITORY".Split('/')[0] }
        if (-not $owner) { throw "The repository owner is unknown, so 'github' cannot be resolved; use name=url." }
        $url = "https://nuget.pkg.github.com/$owner/index.json"
    }
    if (-not $name) { throw "The source '$entry' has no name." }
    if ($url -and $url -notmatch '^https://') { throw "The source '$name' must use https; got '$url'." }
    [pscustomobject]@{ Name = $name; Url = $url }
}

$document = [System.Xml.XmlDocument]::new()
$document.PreserveWhitespace = $false
if (Test-Path -LiteralPath $configFile -PathType Leaf) {
    $document.Load($configFile)
}
else {
    [void] $document.AppendChild($document.CreateXmlDeclaration('1.0', 'utf-8', $null))
}
$configuration = $document.SelectSingleNode('/configuration')
if (-not $configuration) { $configuration = $document.AppendChild($document.CreateElement('configuration')) }

function Get-Section([string] $Name) {
    $section = $configuration.SelectSingleNode($Name)
    if (-not $section) { $section = $configuration.AppendChild($document.CreateElement($Name)) }
    return $section
}

function Add-Setting([System.Xml.XmlNode] $Parent, [string] $Key, [string] $Value) {
    $element = $Parent.AppendChild($document.CreateElement('add'))
    $element.SetAttribute('key', $Key)
    $element.SetAttribute('value', $Value)
}

$rows = [System.Collections.Generic.List[string]]::new()
foreach ($source in $sources) {
    if ($source.Url) {
        $packageSources = Get-Section 'packageSources'
        $existing = @($packageSources.SelectNodes('add') | Where-Object { $_.GetAttribute('key') -eq $source.Name })
        foreach ($node in $existing) { [void] $packageSources.RemoveChild($node) }
        Add-Setting $packageSources $source.Name $source.Url
    }

    # NuGet names credential elements after the source, encoding characters an element name cannot hold.
    $credentials = Get-Section 'packageSourceCredentials'
    $elementName = [System.Xml.XmlConvert]::EncodeLocalName($source.Name)
    $existing = $credentials.SelectSingleNode($elementName)
    if ($existing) { [void] $credentials.RemoveChild($existing) }
    $element = $credentials.AppendChild($document.CreateElement($elementName))
    Add-Setting $element 'Username' $username
    Add-Setting $element 'ClearTextPassword' "%$tokenVariable%"

    $rows.Add("| ``$($source.Name)`` | $(if ($source.Url) { $source.Url } else { 'from the repository nuget.config' }) |")
}

$folder = Split-Path -Parent $configFile
if (-not (Test-Path -LiteralPath $folder)) { [void] (New-Item -ItemType Directory -Path $folder -Force) }
$settings = [System.Xml.XmlWriterSettings]@{ Indent = $true; Encoding = [System.Text.UTF8Encoding]::new($false) }
$writer = [System.Xml.XmlWriter]::Create($configFile, $settings)
try { $document.Save($writer) } finally { $writer.Dispose() }

Write-Host "Wrote $($sources.Count) feed(s) to $configFile; the token is read from `$$tokenVariable when dotnet runs."
Set-ActionOutput 'config-file' $configFile
Add-ActionSummary (@("### NuGet feeds (token from ``$tokenVariable``)", '', '| Source | URL |', '|---|---|') + $rows -join "`n")

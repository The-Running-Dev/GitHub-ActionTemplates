#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$mode = Get-ActionInput 'mode' 'save'
$image = Get-ActionInput 'image'
$temp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$folder = [System.IO.Path]::GetFullPath((Get-ActionInput 'path' (Join-Path $temp 'ghat-image')))

if ($mode -notin 'save', 'load') { throw "The mode '$mode' must be 'save' or 'load'." }

$archive = Join-Path $folder 'image.tar'
$manifest = Join-Path $folder 'image.json'

function Get-ImageId([string] $Reference) {
    $PSNativeCommandUseErrorActionPreference = $false
    $id = docker image inspect --format '{{.Id}}' $Reference 2>$null
    $found = $LASTEXITCODE -eq 0
    $global:LASTEXITCODE = 0
    if (-not $found) { return $null }
    return "$id".Trim()
}

if ($mode -eq 'save') {
    if (-not $image) { throw "Set 'image' to the image reference to save." }
    $id = Get-ImageId $image
    if (-not $id) { throw "The image '$image' does not exist locally." }

    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    docker save --output $archive $image
    @{ image = $image; id = $id } | ConvertTo-Json | Set-Content -LiteralPath $manifest -Encoding utf8

    $size = '{0:N1} MB' -f ((Get-Item -LiteralPath $archive).Length / 1MB)
    Set-ActionOutput 'image' $image
    Set-ActionOutput 'id' $id
    Set-ActionOutput 'path' $folder
    Add-ActionSummary "Saved ``$image`` ($id, $size)."
    return
}

if (-not (Test-Path -LiteralPath $archive -PathType Leaf) -or -not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "No saved image in '$folder'. It needs image.tar and image.json from the 'save' mode."
}
$saved = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
if ($image -and $image -ne $saved.image) { throw "The archive holds '$($saved.image)', not '$image'." }

docker load --input $archive | Out-Host
$id = Get-ImageId $saved.image
if ($id -ne $saved.id) { throw "The loaded image '$($saved.image)' has ID '$id', but the saved one had '$($saved.id)'." }

Set-ActionOutput 'image' $saved.image
Set-ActionOutput 'id' $id
Set-ActionOutput 'path' $folder
Add-ActionSummary "Loaded ``$($saved.image)``; its ID matches the tested image ($id)."

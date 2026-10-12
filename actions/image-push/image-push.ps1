#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$source = Get-ActionInput 'source'
$tags = @((Get-ActionInput 'tags') -split '\s+' | Where-Object { $_ })
$digest = Get-ActionInput 'digest'
$sign = (Get-ActionInput 'sign' 'false') -eq 'true'

if (-not $tags) { throw "Set 'tags' to the image references to push, one per line." }
if ($source -and $digest) { throw "Set 'source' to push a local image, or 'digest' for one Buildx already pushed, not both." }
if (-not $source -and -not $digest) { throw "Set 'source' to the local image to push." }
if ($digest -and $digest -notmatch '^sha256:[0-9a-f]{64}$') { throw "The digest '$digest' must be sha256:<64 hex characters>." }

# All tags name one repository; the digest belongs to that repository.
$repositories = @($tags | ForEach-Object { $_ -replace '(?<=[^/]):[^:/]+$', '' } | Sort-Object -Unique)
if ($repositories.Count -ne 1) { throw "The tags name more than one repository: $($repositories -join ', ')." }
$repository = $repositories[0]

if ($source) {
    foreach ($tag in $tags) {
        docker tag $source $tag
        Write-Host "Pushing $tag"
        $output = docker push $tag 2>&1 | Out-String
        # Per-layer progress repeats for every tag; the rest is worth keeping.
        $output -split '\r?\n' | Where-Object { $_ -and $_ -notmatch '^[0-9a-f]{12}: ' } | ForEach-Object { Write-Host $_ }
        $pushed = [regex]::Match($output, 'digest: (sha256:[0-9a-f]{64})')
        if ($pushed.Success) { $digest = $pushed.Groups[1].Value }
    }
    if (-not $digest) {
        $repoDigests = docker image inspect --format '{{json .RepoDigests}}' $source | ConvertFrom-Json
        $match = @($repoDigests | Where-Object { $_ -like "$repository@*" }) | Select-Object -First 1
        if ($match) { $digest = ($match -split '@', 2)[1] }
    }
    if (-not $digest) { throw "Pushed $repository but could not read its digest." }
}

$reference = "$repository@$digest"
if ($sign) {
    if (-not (Get-Command cosign -ErrorAction SilentlyContinue)) { throw 'sign needs cosign on the PATH (sigstore/cosign-installer).' }
    # Keyless: the workflow's OIDC token identifies the signer, so the job needs id-token: write.
    cosign sign --yes $reference
}

Set-ActionOutput 'image' $repository
Set-ActionOutput 'digest' $digest
Set-ActionOutput 'reference' $reference
Set-ActionOutput 'tags' ($tags -join "`n")

$names = ($tags | ForEach-Object { '`' + ($_ -replace '^.*:', '') + '`' }) -join ', '
Add-ActionSummary "Pushed ``$repository`` ($digest) as $names$(if ($sign) { ', signed with cosign' })."

#Requires -Version 7.2
<#
.SYNOPSIS
Self-test: checks the outputs of the container actions, passed in through environment variables by
the self-test workflow, and that the pushed digest is the one the local registry serves.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-That([bool] $Condition, [string] $Message) {
    if ($Condition) { Write-Host "ok   $Message" } else { Write-Host "FAIL $Message"; $failures.Add($Message) }
}

$image = 'localhost:5000/ghat/fixture'
$tags = @($env:META_TAGS -split '\r?\n' | Where-Object { $_ })
Assert-That ($tags -contains "${image}:$($env:GITHUB_SHA.Substring(0, 7))") "image-meta short-sha tag in '$($tags -join ', ')'"
Assert-That ($tags -contains "${image}:$env:GITHUB_SHA") 'image-meta sha tag'
Assert-That ($env:GATE_URL -match '^http://127\.0\.0\.1:\d+$') "image-gate url '$env:GATE_URL'"
Assert-That ($env:WEBHOOK_STATUS -eq '200') "webhook-deploy webhook-status '$env:WEBHOOK_STATUS'"
Assert-That ($env:HEALTH_STATUS -eq '200') "webhook-deploy health-status '$env:HEALTH_STATUS'"
Assert-That ($env:LOADED_IMAGE -eq 'ghat-fixture:build') "image-archive loaded '$env:LOADED_IMAGE'"
Assert-That ($env:PUSH_IMAGE -eq $image) "image-push image '$env:PUSH_IMAGE'"

foreach ($tag in $tags) {
    $name = ($tag -split ':')[-1]
    $response = Invoke-WebRequest -Method Head -Uri "http://localhost:5000/v2/ghat/fixture/manifests/$name" -Headers @{
        Accept = 'application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json'
    }
    $served = "$($response.Headers['Docker-Content-Digest'])"
    Assert-That ($served -eq $env:PUSH_DIGEST) "registry serves '$name' as $served (pushed $env:PUSH_DIGEST)"
}

$all = $env:TIP_ALL | ConvertFrom-Json
$latest = $env:TIP_LATEST | ConvertFrom-Json
Assert-That ($all.'is-tip' -eq 'false' -and $all.publish -eq 'false') "branch-tip-gate (all) on an old commit: publish '$($all.publish)'"
Assert-That ($all.head -match '^[0-9a-f]{40}$') "branch-tip-gate head '$($all.head)'"
Assert-That ($latest.publish -eq 'true' -and $latest.latest -eq 'false') "branch-tip-gate (latest) on an old commit: publish '$($latest.publish)', latest '$($latest.latest)'"

if ($failures.Count) { throw "$($failures.Count) check(s) failed." }

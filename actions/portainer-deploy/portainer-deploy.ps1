#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$apiKey = Get-ActionInput 'api-key'
$accessId = Get-ActionInput 'access-client-id'
$accessSecret = Get-ActionInput 'access-client-secret'
# Masked before anything else can print them.
foreach ($secret in $apiKey, $accessId, $accessSecret) { if ($secret) { Write-Host "::add-mask::$secret" } }

$image = Get-ActionInput 'image'
$digest = Get-ActionInput 'digest'
$portainerUrl = (Get-ActionInput 'portainer-url').TrimEnd('/')
$stackIdText = Get-ActionInput 'stack-id'
$endpointIdText = Get-ActionInput 'endpoint-id'
$variable = Get-ActionInput 'image-variable'
$imagesText = Get-ActionInput 'images'
$publicUrl = (Get-ActionInput 'public-url').TrimEnd('/')
$healthPath = Get-ActionInput 'health-path' '/health/ready'
$revision = (Get-ActionInput 'revision' $env:GITHUB_SHA).ToLowerInvariant()

function Get-Number([string] $Name, [string] $Default, [int] $Minimum) {
    $text = Get-ActionInput $Name $Default
    if ($text -notmatch '^\d+$' -or [int] $text -lt $Minimum) { throw "The $Name '$text' must be a whole number of at least $Minimum." }
    return [int] $text
}
$requestTimeout = Get-Number 'timeout' '30' 1
# The redeploy answers only after the git pull, the image pull and compose up.
$redeployTimeout = Get-Number 'redeploy-timeout' '600' 1
$healthTimeout = Get-Number 'health-timeout' '300' 1
$healthInterval = Get-Number 'health-interval' '10' 1

# Plain HTTP is accepted only for a loopback test server: the API key travels in a header.
function Test-BaseUrl([string] $Url) { $Url -match '^https://[^/\s]+$' -or $Url -match '^http://(127\.0\.0\.1|localhost)(:\d+)?$' }

# One variable per image, in order: the single image/digest/image-variable trio, or `images`
# (`VARIABLE=repository@sha256:digest`, one per line) for a stack that runs several images.
$assignments = [ordered]@{}
function Add-Assignment([string] $Variable, [string] $Repository, [string] $Digest) {
    if ($Digest -cnotmatch '^sha256:[a-f0-9]{64}$') { throw "The digest for $Variable must be a sha256 digest (sha256: and 64 hex characters); tags are not deployed." }
    if ($Repository -cnotmatch '^[a-z0-9][a-z0-9._/-]*(:\d+)?(/[a-z0-9._-]+)*$' -or $Repository -match '@') { throw "The image '$Repository' must be a lowercase repository without a tag or digest." }
    if ($Variable -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { throw "The image variable '$Variable' must be an environment variable name." }
    if ($assignments.Contains($Variable)) { throw "The image variable '$Variable' is listed twice." }
    $assignments[$Variable] = "$Repository@$Digest"
}
if ($imagesText) {
    if ($image -or $digest -or $variable) { throw 'Set images, or image, digest and image-variable, not both.' }
    foreach ($line in $imagesText -split '\r?\n') {
        $entry = $line.Trim()
        if (-not $entry) { continue }
        if ($entry -cnotmatch '^([A-Za-z_][A-Za-z0-9_]*)=([^@=\s]+)@(sha256:[a-f0-9]{64})$') { throw "The images line '$entry' must be VARIABLE=repository@sha256:digest." }
        Add-Assignment $Matches[1] $Matches[2] $Matches[3]
    }
    if ($assignments.Count -eq 0) { throw 'The images input has no entries.' }
}
elseif ($image -or $digest -or $variable) { Add-Assignment $variable $image $digest }
else { throw 'Set images, or image, digest and image-variable.' }
if (-not $apiKey -or -not $portainerUrl -or -not $stackIdText -or -not $endpointIdText -or -not $publicUrl) { throw 'Portainer is not configured: set portainer-url, stack-id, endpoint-id, api-key and public-url.' }
if (-not (Test-BaseUrl $portainerUrl)) { throw "The portainer-url '$portainerUrl' must be https://host with no path." }
if ($stackIdText -notmatch '^[1-9]\d*$') { throw "The stack-id '$stackIdText' must be a positive whole number." }
if ($endpointIdText -notmatch '^[1-9]\d*$') { throw "The endpoint-id '$endpointIdText' must be a positive whole number." }
if ([bool] $accessId -ne [bool] $accessSecret) { throw 'Set both access-client-id and access-client-secret, or neither.' }
if (-not (Test-BaseUrl $publicUrl)) { throw "The public-url '$publicUrl' must be https://host with no path." }
if ($healthPath -notmatch '^/\S*$') { throw "The health-path '$healthPath' must start with '/'." }
if ($revision -notmatch '^[0-9a-f]{40}([0-9a-f]{24})?$') { throw "The revision '$revision' must be a full commit SHA." }

$stackId = [int] $stackIdText
$endpointId = [int] $endpointIdText
$headers = @{ 'X-API-Key' = $apiKey }
if ($accessId) { $headers['CF-Access-Client-Id'] = $accessId; $headers['CF-Access-Client-Secret'] = $accessSecret }

# HttpClient rather than Invoke-WebRequest: redirects are not followed, so a Cloudflare Access login
# redirect shows up as such, and the API key never goes to the login host. Errors carry the status
# code only, because Portainer bodies can echo the stack env.
$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
function Invoke-Portainer([string] $Method, [string] $Path, [string] $Body, [string] $What, [int] $Timeout = $requestTimeout) {
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), "$portainerUrl$Path")
    foreach ($name in $headers.Keys) { [void] $request.Headers.TryAddWithoutValidation($name, $headers[$name]) }
    if ($Body) { $request.Content = [System.Net.Http.StringContent]::new($Body, [System.Text.Encoding]::UTF8, 'application/json') }
    $cancel = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($Timeout))
    try { $response = $client.SendAsync($request, $cancel.Token).GetAwaiter().GetResult() }
    catch {
        if ($cancel.IsCancellationRequested) { throw "Portainer did not answer within $Timeout s while $What; it may still be working, so check the stack before running again." }
        throw "Portainer is unreachable while $What ($($_.Exception.GetBaseException().GetType().Name))."
    }
    finally { $request.Dispose(); $cancel.Dispose() }

    $code = [int] $response.StatusCode
    $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $response.Dispose()
    if ($code -ge 300 -and $code -lt 400) { throw "Portainer answered HTTP $code while $What. A redirect usually means Cloudflare Access did not accept the service token." }
    if ($code -lt 200 -or $code -ge 300) { throw "Portainer answered HTTP $code while $What." }
    return $text
}

# Read with System.Text.Json so every value goes back byte for byte (ConvertFrom-Json turns
# date-like strings into dates).
$text = Invoke-Portainer GET "/api/stacks/$stackId" '' "reading stack $stackId"
try { $document = [System.Text.Json.JsonDocument]::Parse($text) }
catch { throw "Portainer answered stack $stackId with something other than JSON." }

$root = $document.RootElement
function Get-Property($Element, [string] $Name) {
    $value = [System.Text.Json.JsonElement]::new()
    if ($Element.ValueKind -eq 'Object' -and $Element.TryGetProperty($Name, [ref] $value) -and $value.ValueKind -ne 'Null') { return $value }
    return $null
}

$variables = [System.Collections.Generic.List[object]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$stackEnv = Get-Property $root 'Env'
if ($stackEnv) {
    foreach ($item in $stackEnv.EnumerateArray()) {
        $name = (Get-Property $item 'name')?.GetString()
        $valueElement = Get-Property $item 'value'
        $value = if (-not $valueElement) { '' } elseif ($valueElement.ValueKind -eq 'String') { $valueElement.GetString() } else { $valueElement.GetRawText() }
        if ($name -and $assignments.Contains($name)) { $value = $assignments[$name]; [void] $seen.Add($name) }
        $variables.Add([ordered]@{ name = $name; value = $value })
    }
}
foreach ($name in $assignments.Keys) { if (-not $seen.Contains($name)) { $variables.Add([ordered]@{ name = $name; value = $assignments[$name] }) } }

$git = Get-Property $root 'GitConfig'
if (-not $git) { throw "Stack $stackId is not a Git stack, so it cannot be redeployed from the repository." }
$referenceName = (Get-Property $git 'ReferenceName')?.GetString()
$authentication = Get-Property $git 'Authentication'
$prune = Get-Property (Get-Property $root 'Option') 'Prune'

$payload = [ordered]@{
    env                      = $variables
    prune                    = [bool] ($prune -and $prune.GetBoolean())
    pullImage                = $true
    repositoryReferenceName  = if ($referenceName) { $referenceName } else { 'refs/heads/main' }
    repositoryAuthentication = [bool] $authentication
}
# Portainer keeps the stored password when none is sent; the username and credential ID say which.
if ($authentication) {
    $username = Get-Property $authentication 'Username'
    $credentialId = Get-Property $authentication 'GitCredentialID'
    if ($username) { $payload['repositoryUsername'] = $username.GetString() }
    if ($credentialId -and $credentialId.GetInt32() -gt 0) { $payload['repositoryGitCredentialID'] = $credentialId.GetInt32() }
}
$document.Dispose()

$body = ConvertTo-Json $payload -Depth 5 -Compress
$reference = ($assignments.Values) -join ', '
foreach ($name in $assignments.Keys) { Write-Host "Setting $name to $($assignments[$name])." }
Write-Host "Redeploying stack $stackId with a pull."
Invoke-Portainer PUT "/api/stacks/$stackId/git/redeploy?endpointId=$endpointId" $body "redeploying stack $stackId" $redeployTimeout | Out-Null
$client.Dispose()
Write-Host "Portainer redeployed stack $stackId."
Set-ActionOutput 'image' $reference

$healthUrl = "$publicUrl$healthPath"
$deadline = [DateTime]::UtcNow.AddSeconds($healthTimeout)
$last = 'no answer yet'
while ($true) {
    try {
        $health = Invoke-WebRequest -Uri $healthUrl -SkipHttpErrorCheck -TimeoutSec $requestTimeout -ErrorAction Stop
        $code = [int] $health.StatusCode
        $reported = $null
        try {
            $json = [System.Text.Json.JsonDocument]::Parse("$($health.Content)")
            $reported = (Get-Property $json.RootElement 'revision')?.ToString()
            $json.Dispose()
        }
        catch { $reported = $null }

        if ($code -eq 200 -and $reported -and $reported.ToLowerInvariant() -eq $revision) { break }
        $last = if ($reported) { "HTTP $code, revision $($reported.Substring(0, [math]::Min(12, $reported.Length)))" } else { "HTTP $code without a revision" }
    }
    catch { $last = "no answer ($($_.Exception.GetType().Name))" }

    if ([DateTime]::UtcNow.AddSeconds($healthInterval) -gt $deadline) {
        throw "$healthUrl did not report $revision within $healthTimeout s (last: $last)."
    }
    Write-Host "$healthUrl answered $last; checking again in $healthInterval s."
    Start-Sleep -Seconds $healthInterval
}

Set-ActionOutput 'health-url' $healthUrl
Write-Host "$healthUrl reports $revision."
Add-ActionSummary "Deployed ``$reference`` to Portainer stack $stackId; $healthUrl reports revision ``$($revision.Substring(0, 12))``."

#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$token = Get-ActionInput 'token'
# Masked before anything else can print it.
if ($token) { Write-Host "::add-mask::$token" }

$app = Get-ActionInput 'app'
$digest = Get-ActionInput 'digest'
$revision = (Get-ActionInput 'revision' $env:GITHUB_SHA).ToLowerInvariant()
$repository = Get-ActionInput 'infra-repository' 'The-Running-Dev/SubZeroDev.Infra'
$workflow = Get-ActionInput 'workflow' 'deploy.yml'
$ref = Get-ActionInput 'ref' 'main'
$apiUrl = (Get-ActionInput 'api-url' 'https://api.github.com').TrimEnd('/')

function Get-Number([string] $Name, [string] $Default, [int] $Minimum) {
    $text = Get-ActionInput $Name $Default
    if ($text -notmatch '^\d+$' -or [int] $text -lt $Minimum) { throw "The $Name '$text' must be a whole number of at least $Minimum." }
    return [int] $text
}
$requestTimeout = Get-Number 'timeout' '30' 1
$findTimeout = Get-Number 'find-timeout' '120' 1
$runTimeout = Get-Number 'run-timeout' '1800' 1
$interval = Get-Number 'poll-interval' '5' 1

if (-not $token) { throw 'The token is not set: pass the Infra dispatch token from a secret.' }
if ($app -cnotmatch '^[a-z0-9][a-z0-9-]*$') { throw "The app '$app' must be lowercase letters, digits and hyphens." }
if ($digest -cnotmatch '^sha256:[a-f0-9]{64}$') { throw 'The digest must be a sha256 digest (sha256: and 64 hex characters); tags are not deployed.' }
if ($revision -notmatch '^[0-9a-f]{40}([0-9a-f]{24})?$') { throw "The revision '$revision' must be a full commit SHA." }
if ($repository -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') { throw "The infra-repository '$repository' must be owner/name." }
if ($workflow -notmatch '^[A-Za-z0-9._-]+\.ya?ml$') { throw "The workflow '$workflow' must be a workflow file name." }
if ($ref -notmatch '^[A-Za-z0-9._/-]+$') { throw "The ref '$ref' is not a branch name." }
# The token travels in a header: plain HTTP is accepted only for a loopback test server.
if ($apiUrl -notmatch '^https://[^/\s]+$' -and $apiUrl -notmatch '^http://(127\.0\.0\.1|localhost)(:\d+)?$') { throw "The api-url '$apiUrl' must be https://host with no path." }

$correlation = [guid]::NewGuid().ToString('N')
$title = "deploy $app $correlation"
Set-ActionOutput 'correlation' $correlation

$handler = [System.Net.Http.SocketsHttpHandler]::new()
$handler.AllowAutoRedirect = $false
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan

function Invoke-GitHub([string] $Method, [string] $Path, [string] $Body, [string] $What) {
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), "$apiUrl$Path")
    [void] $request.Headers.TryAddWithoutValidation('Authorization', "Bearer $token")
    [void] $request.Headers.TryAddWithoutValidation('Accept', 'application/vnd.github+json')
    [void] $request.Headers.TryAddWithoutValidation('X-GitHub-Api-Version', '2022-11-28')
    [void] $request.Headers.TryAddWithoutValidation('User-Agent', 'infra-deploy-action')
    if ($Body) { $request.Content = [System.Net.Http.StringContent]::new($Body, [System.Text.Encoding]::UTF8, 'application/json') }
    $cancel = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($requestTimeout))
    try { $response = $client.SendAsync($request, $cancel.Token).GetAwaiter().GetResult() }
    catch {
        if ($cancel.IsCancellationRequested) { throw "GitHub did not answer within $requestTimeout s while $What." }
        throw "GitHub is unreachable while $What ($($_.Exception.GetBaseException().GetType().Name))."
    }
    finally { $request.Dispose(); $cancel.Dispose() }
    $code = [int] $response.StatusCode
    $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $response.Dispose()
    if ($code -lt 200 -or $code -ge 300) {
        $hint = switch ($code) {
            401 { ' The token is not accepted.' }
            403 { ' The token may lack Actions write on the Infra repository.' }
            404 { ' The workflow, branch or repository was not found, or the token cannot see it.' }
            422 { ' The workflow rejected the inputs or the branch.' }
            default { '' }
        }
        throw "GitHub answered HTTP $code while $What.$hint"
    }
    return [pscustomobject]@{ Code = $code; Text = $text }
}

Write-Host "Dispatching $workflow in $repository for $app ($digest, revision $($revision.Substring(0, 12)))."
$payload = ConvertTo-Json @{
    ref                = $ref
    inputs             = [ordered]@{ app = $app; digest = $digest; revision = $revision; correlation = $correlation }
    return_run_details = $true
} -Depth 4 -Compress
$dispatch = Invoke-GitHub POST "/repos/$repository/actions/workflows/$workflow/dispatches" $payload 'dispatching the deploy'

# A plan that returns the run id needs no search; otherwise the run is found by its title.
$runId = $null
if ($dispatch.Text) {
    try {
        $answer = $dispatch.Text | ConvertFrom-Json -ErrorAction Stop
        if ($answer.workflow_run_id) { $runId = [string] $answer.workflow_run_id }
    }
    catch { Write-Verbose 'The dispatch answer was not JSON.' }
}

$watch = [System.Diagnostics.Stopwatch]::StartNew()
while (-not $runId) {
    $list = Invoke-GitHub GET "/repos/$repository/actions/workflows/$workflow/runs?event=workflow_dispatch&branch=$([uri]::EscapeDataString($ref))&per_page=30" '' 'looking for the deploy run'
    $match = @(($list.Text | ConvertFrom-Json).workflow_runs | Where-Object { $_.display_title -ceq $title }) | Select-Object -First 1
    if ($match) { $runId = [string] $match.id; break }
    if ($watch.Elapsed.TotalSeconds -ge $findTimeout) { throw "No run titled '$title' appeared within $findTimeout s; check the Infra repository's Actions tab, then run again." }
    Start-Sleep -Seconds $interval
}
if ($runId -notmatch '^\d+$') { throw 'GitHub returned a run id that is not a number.' }

$runUrl = "https://github.com/$repository/actions/runs/$runId"
Set-ActionOutput 'run-url' $runUrl
Write-Host "Infra run: $runUrl"

$watch.Restart()
while ($true) {
    $run = (Invoke-GitHub GET "/repos/$repository/actions/runs/$runId" '' 'reading the deploy run').Text | ConvertFrom-Json
    if ($run.status -eq 'completed') { break }
    if ($watch.Elapsed.TotalSeconds -ge $runTimeout) { throw "The Infra run did not finish within $runTimeout s; it may still be deploying, so check $runUrl before running again." }
    Start-Sleep -Seconds $interval
}
$client.Dispose()
if ($run.conclusion -ne 'success') { throw "The Infra deploy run ended '$($run.conclusion)': $runUrl" }

Write-Host "Infra deploy succeeded: $runUrl"
Add-ActionSummary "Deployed ``$app@$digest`` through the Infra deploy workflow: [run]($runUrl)."

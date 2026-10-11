#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$url = Get-ActionInput 'url'
$method = (Get-ActionInput 'method' 'POST').ToUpperInvariant()
$healthUrl = Get-ActionInput 'health-url'
$healthStatus = Get-ActionInput 'health-status' '200'
$healthExpect = Get-ActionInput 'health-expect'

function Get-Number([string] $Name, [string] $Default, [int] $Minimum) {
    $text = Get-ActionInput $Name $Default
    if ($text -notmatch '^\d+$' -or [int] $text -lt $Minimum) { throw "The $Name '$text' must be a whole number of at least $Minimum." }
    return [int] $text
}
$retries = Get-Number 'retries' '3' 0
$retryDelay = Get-Number 'retry-delay' '10' 0
$requestTimeout = Get-Number 'timeout' '30' 1
$healthTimeout = Get-Number 'health-timeout' '300' 1
$healthInterval = Get-Number 'health-interval' '10' 1
$consecutive = Get-Number 'health-consecutive' '1' 1

if (-not $url -and -not $healthUrl) { throw "Set 'url' to the redeploy webhook (a secret), 'health-url', or both." }
if ($url -and $url -notmatch '^https?://') { throw "The webhook URL must start with http:// or https://." }
if ($method -notin 'POST', 'GET', 'PUT') { throw "The method '$method' must be POST, GET or PUT." }
if ($healthUrl -and $healthUrl -notmatch '^https?://') { throw "The health-url '$healthUrl' must start with http:// or https://." }
$statuses = @($healthStatus -split '[\s,]+' | Where-Object { $_ })
if ($statuses -notcontains 'any' -and @($statuses | Where-Object { $_ -notmatch '^\d{3}$' })) { throw "The health-status '$healthStatus' must be status codes or 'any'." }

# The webhook URL usually carries its token, so it is masked and never written out.
if ($url) {
    Write-Host "::add-mask::$url"
    $attempt = 0
    $done = $false
    while (-not $done) {
        $attempt++
        try {
            $response = Invoke-WebRequest -Uri $url -Method $method -SkipHttpErrorCheck -TimeoutSec $requestTimeout -ErrorAction Stop
            $code = [int] $response.StatusCode
            if ($code -ge 200 -and $code -lt 300) { $done = $true; Write-Host "The webhook answered $code." }
            else { $problem = "answered $code" }
        }
        catch { $problem = "failed: $($_.Exception.Message.Replace($url, '***'))" }

        if (-not $done) {
            if ($attempt -gt $retries) { throw "The webhook $problem after $attempt attempt(s)." }
            Write-Host "The webhook $problem; retrying in $retryDelay s ($attempt of $($retries + 1))."
            Start-Sleep -Seconds $retryDelay
        }
    }
    Set-ActionOutput 'webhook-status' "$code"
}

if (-not $healthUrl) {
    Add-ActionSummary 'Called the redeploy webhook; no health URL to wait for.'
    return
}

$deadline = [DateTime]::UtcNow.AddSeconds($healthTimeout)
$passes = 0
$last = ''
while ($true) {
    try {
        $response = Invoke-WebRequest -Uri $healthUrl -SkipHttpErrorCheck -TimeoutSec $requestTimeout -ErrorAction Stop
        $code = [int] $response.StatusCode
        $statusOk = $statuses -contains 'any' -or $statuses -contains "$code"
        $bodyOk = -not $healthExpect -or "$($response.Content)".Contains($healthExpect)
        if ($statusOk -and $bodyOk) { $passes++ }
        else {
            $passes = 0
            $last = if (-not $statusOk) { "answered $code" } else { "answered $code without the expected text" }
        }
    }
    catch {
        $passes = 0
        $last = "did not answer: $($_.Exception.Message)"
    }

    if ($passes -ge $consecutive) { break }
    if ([DateTime]::UtcNow.AddSeconds($healthInterval) -gt $deadline) {
        throw "$healthUrl was not healthy after $healthTimeout s. Last check: $last."
    }
    Write-Host $(if ($passes) { "Healthy $passes of $consecutive time(s); checking again in $healthInterval s." } else { "$healthUrl $last; checking again in $healthInterval s." })
    Start-Sleep -Seconds $healthInterval
}

Set-ActionOutput 'health-status' "$code"
Write-Host "$healthUrl is healthy ($code)."
$what = if ($url) { 'Redeployed; ' } else { '' }
Add-ActionSummary "$what$healthUrl answered $code$(if ($healthExpect) { ' with the expected text' })$(if ($consecutive -gt 1) { " $consecutive times in a row" })."

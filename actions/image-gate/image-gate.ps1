#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$mode = Get-ActionInput 'mode' 'start'
$name = Get-ActionInput 'name' 'ghat-smoke'

if ($mode -notin 'start', 'stop') { throw "The mode '$mode' must be 'start' or 'stop'." }
if ($name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]*$') { throw "The container name '$name' may only hold letters, digits, '_', '.' and '-'." }

function Get-ContainerState {
    # Status and health in one call; health is empty when the image has no HEALTHCHECK.
    $PSNativeCommandUseErrorActionPreference = $false
    $text = docker inspect --format '{{.State.Status}}|{{.State.ExitCode}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}' $name 2>$null
    $found = $LASTEXITCODE -eq 0
    $global:LASTEXITCODE = 0
    if (-not $found) { return $null }
    $status, $exitCode, $health = "$text".Trim() -split '\|', 3
    [pscustomobject]@{ Status = $status; ExitCode = $exitCode; Health = $health }
}

function Write-ContainerLog {
    $PSNativeCommandUseErrorActionPreference = $false
    Write-Host "::group::Container log ($name)"
    docker logs --tail 200 $name 2>&1 | Out-Host
    Write-Host '::endgroup::'
    $global:LASTEXITCODE = 0
}

if ($mode -eq 'stop') {
    if (-not (Get-ContainerState)) { Write-Host "No container '$name' to stop."; return }
    Write-ContainerLog
    docker rm --force $name | Out-Null
    Write-Host "Removed container '$name'."
    return
}

$image = Get-ActionInput 'image'
$port = Get-ActionInput 'port'
$healthPath = Get-ActionInput 'health-path' '/'
$healthStatus = Get-ActionInput 'health-status' '200'
# Values may hold ';', so these two split on new lines only.
$environment = @((Get-ActionInput 'env') -split '\r?\n' | ForEach-Object Trim | Where-Object { $_ })
$options = @((Get-ActionInput 'options') -split '\r?\n' | ForEach-Object Trim | Where-Object { $_ })
$exec = Split-ActionList (Get-ActionInput 'exec')
$timeoutInput = Get-ActionInput 'timeout' '60'

if (-not $image) { throw "Set 'image' to the image to run." }
if ($port -and $port -notmatch '^\d{1,5}$') { throw "The port '$port' must be the container's port number." }
if (-not $healthPath.StartsWith('/')) { throw "The health-path '$healthPath' must start with '/'." }
$statuses = @($healthStatus -split '[\s,]+' | Where-Object { $_ })
if ($statuses -notcontains 'any' -and @($statuses | Where-Object { $_ -notmatch '^\d{3}$' })) { throw "The health-status '$healthStatus' must be status codes or 'any'." }
if ($timeoutInput -notmatch '^\d+$' -or [int] $timeoutInput -lt 1) { throw "The timeout '$timeoutInput' must be a whole number of seconds." }
$timeout = [int] $timeoutInput

# Every exec script is checked before the container starts, so a typo fails fast.
$scripts = foreach ($script in $exec) {
    $path = Resolve-WorkspacePath $script $workspace 'exec script'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "The exec script '$script' does not exist." }
    $path
}

foreach ($line in $environment) {
    if ($line -notmatch '^[A-Za-z_][A-Za-z0-9_]*=') { throw "The env line '$($line -replace '=.*', '=...')' must be NAME=value." }
}

# Arguments go through an env file, so values never reach the process list or the log.
$temp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$envFile = Join-Path $temp "ghat-smoke-$([guid]::NewGuid().ToString('N')).env"
Set-Content -LiteralPath $envFile -Value $environment -Encoding utf8

$arguments = @('run', '--detach', '--name', $name, '--env-file', $envFile)
foreach ($option in $options) { $arguments += @($option -split '\s+' | Where-Object { $_ }) }
if ($port) { $arguments += @('--publish', "127.0.0.1::$port") }
$arguments += $image

try {
    Write-Host "docker $($arguments -join ' ')"
    docker @arguments | Out-Null
}
finally { Remove-Item -LiteralPath $envFile -ErrorAction SilentlyContinue }

$url = ''
if ($port) {
    # One line per address; the IPv4 loopback one is what the probe uses.
    $binding = @(docker port $name "$port/tcp") | Where-Object { $_ -match '^127\.0\.0\.1:' } | Select-Object -First 1
    if (-not $binding) { throw "Docker did not publish port $port of '$name'." }
    $url = "http://$binding"
}
Set-ActionOutput 'container' $name
Set-ActionOutput 'url' $url

$deadline = [DateTime]::UtcNow.AddSeconds($timeout)
$last = ''
$ready = $false
$settled = $false
while (-not $ready) {
    $state = Get-ContainerState
    if (-not $state -or $state.Status -ne 'running') {
        Write-ContainerLog
        $detail = if ($state) { "$($state.Status), exit code $($state.ExitCode)" } else { 'gone' }
        throw "The container stopped before it was ready ($detail)."
    }
    if ($state.Health -eq 'unhealthy') { Write-ContainerLog; throw 'The image HEALTHCHECK reports the container unhealthy.' }

    if ($state.Health -and $state.Health -ne 'healthy') { $last = "HEALTHCHECK is $($state.Health)" }
    elseif (-not $port -and -not $state.Health) {
        # Nothing to probe: the container must still be running a few seconds after it started.
        if ($settled) { $ready = $true } else { Start-Sleep -Seconds 3; $settled = $true; continue }
    }
    elseif (-not $port) { $ready = $true }
    else {
        try {
            $response = Invoke-WebRequest -Uri "$url$healthPath" -SkipHttpErrorCheck -MaximumRedirection 0 -TimeoutSec 5 -ErrorAction Stop
            $code = [int] $response.StatusCode
            if ($statuses -contains 'any' -or $statuses -contains "$code") { $ready = $true }
            else { $last = "$healthPath answered $code" }
        }
        catch { $last = "$healthPath did not answer: $($_.Exception.Message)" }
    }

    if (-not $ready) {
        if ([DateTime]::UtcNow -ge $deadline) { Write-ContainerLog; throw "The container was not ready after $timeout s. Last check: $last." }
        Start-Sleep -Seconds 1
    }
}
Write-Host $(if ($port) { "Ready: $healthPath answered at $url." } else { 'Ready: the container is running.' })

$index = 0
foreach ($path in $scripts) {
    $index++
    $relative = [System.IO.Path]::GetRelativePath($workspace, $path).Replace('\', '/')
    $target = "/tmp/ghat-smoke-$index-$([System.IO.Path]::GetFileName($path))"
    docker cp $path "${name}:$target" | Out-Null
    $command = switch ([System.IO.Path]::GetExtension($path).ToLowerInvariant()) {
        '.ps1' { @('pwsh', '-NoProfile', '-NonInteractive', '-File', $target) }
        '.sh' { @('sh', $target) }
        default { @($target) }
    }
    Write-Host "::group::$relative (in the container)"
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        docker exec $name @command | Out-Host
        $code = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        $PSNativeCommandUseErrorActionPreference = $true
    }
    finally { Write-Host '::endgroup::' }
    if ($code -ne 0) { throw "$relative exited with code $code in the container." }
}

$state = Get-ContainerState
if (-not $state -or $state.Status -ne 'running') { Write-ContainerLog; throw 'The container stopped during the smoke test.' }

$checks = @(if ($state.Health) { 'HEALTHCHECK healthy' }; if ($port) { "``$healthPath`` answered" }; if ($scripts) { "$(@($scripts).Count) script(s) passed in the container" })
Add-ActionSummary "Smoke test of ``$image``: $(if ($checks) { $checks -join ', ' } else { 'the container started and kept running' })."

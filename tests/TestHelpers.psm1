#Requires -Version 7.2
# Helpers for running action scripts the way the runner does: a child pwsh process with
# INPUT_* / GITHUB_* environment variables and a GITHUB_OUTPUT file to read back.

Set-StrictMode -Version Latest

$script:DefaultEnvironment = [ordered]@{
    GITHUB_EVENT_NAME   = 'push'
    GITHUB_REF_TYPE     = 'branch'
    GITHUB_REF_NAME     = 'main'
    GITHUB_HEAD_REF     = ''
    GITHUB_REPOSITORY   = 'Octo-Org/Sample.Repo'
    GITHUB_SHA          = '0123456789abcdef0123456789abcdef01234567'
    GITHUB_RUN_NUMBER   = '42'
    GITHUB_EVENT_PATH   = ''
    GHAT_DEFAULT_BRANCH = 'main'
    GHAT_PR_NUMBER      = ''
}

function Use-Environment {
    <#
    .SYNOPSIS
    Runs a script block with environment variables set, restoring the previous values afterwards.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Environment,
        [Parameter(Mandatory)][scriptblock] $ScriptBlock
    )

    $saved = @{}
    foreach ($name in $Environment.Keys) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, [string] $Environment[$name])
    }

    try { & $ScriptBlock }
    finally {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
}

function New-ActionEnvironment {
    param([System.Collections.IDictionary] $Overrides = @{})

    $environment = [ordered]@{}
    foreach ($name in $script:DefaultEnvironment.Keys) { $environment[$name] = $script:DefaultEnvironment[$name] }
    foreach ($name in $Overrides.Keys) { $environment[$name] = $Overrides[$name] }

    return $environment
}

function ConvertFrom-ActionOutputFile {
    param([Parameter(Mandatory)][string] $Path)

    $outputs = @{}
    $lines = @(Get-Content -LiteralPath $Path)

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^(?<name>[^=<]+)<<(?<delimiter>.+)$') {
            $value = [System.Collections.Generic.List[string]]::new()
            while (++$i -lt $lines.Count -and $lines[$i] -ne $Matches['delimiter']) { $value.Add($lines[$i]) }
            $outputs[$Matches['name']] = $value -join "`n"
        }
        elseif ($line -match '^(?<name>[^=]+)=(?<value>.*)$') {
            $outputs[$Matches['name']] = $Matches['value']
        }
    }

    return $outputs
}

function Invoke-ActionScript {
    <#
    .SYNOPSIS
    Runs an action script in a child pwsh process and returns its exit code, outputs, log and summary.
    #>
    param(
        [Parameter(Mandatory)][string] $Script,
        [System.Collections.IDictionary] $Environment = @{},
        [string] $WorkingDirectory = (Get-Location).Path
    )

    $outputFile = New-TemporaryFile
    $summaryFile = New-TemporaryFile
    $variables = New-ActionEnvironment $Environment
    $variables['GITHUB_OUTPUT'] = $outputFile.FullName
    $variables['GITHUB_STEP_SUMMARY'] = $summaryFile.FullName
    # Same wrapper the runner generates for `shell: pwsh` steps, so a leaked $LASTEXITCODE
    # fails here as it does in a workflow.
    $wrapperFile = Join-Path ([System.IO.Path]::GetTempPath()) "ghat-step-$([guid]::NewGuid()).ps1"
    Set-Content -LiteralPath $wrapperFile -Value @(
        "`$ErrorActionPreference = 'stop'"
        "& '$($Script.Replace("'", "''"))'"
        'if ((Test-Path -LiteralPath variable:\LASTEXITCODE)) { exit $LASTEXITCODE }'
    )
    $command = ". '$($wrapperFile.Replace("'", "''"))'"
    # A local rather than a parameter inside the script block, which PSScriptAnalyzer cannot follow.
    $location = $WorkingDirectory

    try {
        $result = Use-Environment $variables {
            Push-Location -LiteralPath $location
            try {
                $log = & pwsh -NoProfile -NonInteractive -Command $command 2>&1 | Out-String
                [pscustomobject]@{ ExitCode = $LASTEXITCODE; Log = $log }
            }
            finally { Pop-Location }
        }

        [pscustomobject]@{
            ExitCode = $result.ExitCode
            Log      = $result.Log
            Outputs  = ConvertFrom-ActionOutputFile $outputFile.FullName
            Summary  = Get-Content -LiteralPath $summaryFile.FullName -Raw
        }
    }
    finally {
        Remove-Item -LiteralPath $outputFile.FullName, $summaryFile.FullName, $wrapperFile -ErrorAction SilentlyContinue
    }
}

function New-GitRepository {
    <#
    .SYNOPSIS
    Creates a repository with one commit per tag (and one when there are no tags).
    #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [string[]] $Tags = @()
    )

    $PSNativeCommandUseErrorActionPreference = $true
    New-Item -ItemType Directory -Path $Path -Force | Out-Null

    git -C $Path init --quiet --initial-branch main
    git -C $Path config user.name 'Test'
    git -C $Path config user.email 'test@example.com'
    git -C $Path config commit.gpgsign false
    git -C $Path config tag.gpgsign false

    $commits = [math]::Max(1, $Tags.Count)
    for ($i = 0; $i -lt $commits; $i++) {
        git -C $Path commit --quiet --allow-empty -m "commit $i"
        if ($i -lt $Tags.Count) { git -C $Path tag $Tags[$i] }
    }
    git -C $Path commit --quiet --allow-empty -m 'after last tag'

    return $Path
}

function Start-TestHttpServer {
    <#
    .SYNOPSIS
    Serves HTTP on a free loopback port from a thread job, for the probes in the container tests.
    .DESCRIPTION
    A raw TCP server rather than HttpListener, which on Windows rejects 127.0.0.1 without a URL
    reservation. Routes:
      /status/<code>           answers <code>
      /text/<text>             answers 200 with <text>
      /method/<method>         answers 200 for that method, 405 otherwise
      /flaky/<key>/<n>         answers 503 to the first <n> requests per key, then 200
    Stop it with Stop-TestHttpServer.
    #>
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port

    $job = Start-ThreadJob -ScriptBlock {
        $listener = $using:listener
        $hits = @{}
        while ($true) {
            try { $client = $listener.AcceptTcpClient() } catch { break }
            try {
                $stream = $client.GetStream()
                $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
                $method, $path = ("$($reader.ReadLine())" -split ' ')[0, 1]
                while ($reader.ReadLine()) { }

                $code, $body = switch -Regex ($path) {
                    '^/status/(\d{3})$' { [int] $Matches[1], "status $($Matches[1])" }
                    '^/text/(.+)$' { 200, [uri]::UnescapeDataString($Matches[1]) }
                    '^/method/([A-Z]+)$' { if ($method -eq $Matches[1]) { 200, 'ok' } else { 405, "not $method" } }
                    '^/flaky/([^/]+)/(\d+)$' {
                        $hits[$Matches[1]] = 1 + [int] $hits[$Matches[1]]
                        if ($hits[$Matches[1]] -le [int] $Matches[2]) { 503, 'not yet' } else { 200, 'ok' }
                    }
                    default { 404, 'not found' }
                }
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $head = "HTTP/1.1 $code Status`r`nContent-Type: text/plain`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
                $headBytes = [System.Text.Encoding]::ASCII.GetBytes($head)
                $stream.Write($headBytes, 0, $headBytes.Length)
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
            }
            catch { Write-Verbose "Request failed: $_" }
            finally { $client.Dispose() }
        }
    }

    [pscustomobject]@{ Url = "http://127.0.0.1:$port"; Port = $port; Listener = $listener; Job = $job }
}

function Stop-TestHttpServer {
    param([Parameter(Mandatory)] $Server)

    $Server.Listener.Stop()
    $Server.Job | Wait-Job -Timeout 5 | Out-Null
    $Server.Job | Remove-Job -Force
}

Export-ModuleMember -Function Use-Environment, Invoke-ActionScript, New-GitRepository, ConvertFrom-ActionOutputFile, Start-TestHttpServer, Stop-TestHttpServer

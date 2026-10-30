# Stands in for docker in the container action tests. Appends each call's arguments to
# $env:STUB_LOG/docker.txt (and the --env-file lines as ENV:). A `run` creates the container until
# `rm`; STUB_DOCKER_STATE sets what `inspect` reports for it (default `running|0|`).
$log = Join-Path $env:STUB_LOG 'docker.txt'
$container = Join-Path $env:STUB_LOG 'container'
Add-Content -LiteralPath $log -Value ($args -join ' ')

switch ($args[0]) {
    'run' {
        $envFile = [array]::IndexOf($args, '--env-file')
        if ($envFile -ge 0) { Get-Content -LiteralPath $args[$envFile + 1] | ForEach-Object { Add-Content -LiteralPath $log -Value "ENV: $_" } }
        Set-Content -LiteralPath $container -Value ''
        Write-Output 'f00dfeed'
    }
    'port' {
        # Bound where the last `run` published it: 127.0.0.1 by default, 0.0.0.0 for a remote daemon.
        if ($env:STUB_DOCKER_PORT -and (Get-Content -LiteralPath $log -Raw) -match '--publish 0\.0\.0\.0::') { Write-Output "0.0.0.0:$env:STUB_DOCKER_PORT"; Write-Output "[::]:$env:STUB_DOCKER_PORT" }
        elseif ($env:STUB_DOCKER_PORT) { Write-Output "127.0.0.1:$env:STUB_DOCKER_PORT"; Write-Output "[::1]:$env:STUB_DOCKER_PORT" }
    }
    'inspect' {
        if (-not (Test-Path -LiteralPath $container)) { [Console]::Error.WriteLine('Error: No such object'); exit 1 }
        Write-Output $(if ($env:STUB_DOCKER_STATE) { $env:STUB_DOCKER_STATE } else { 'running|0|' })
    }
    'image' {
        if ($env:STUB_IMAGE_MISSING -eq 'true') { [Console]::Error.WriteLine('Error: No such image'); exit 1 }
        if ("$args" -match 'RepoDigests') { Write-Output '[]' }
        else { Write-Output $(if ($env:STUB_IMAGE_ID) { $env:STUB_IMAGE_ID } else { "sha256:$('a' * 64)" }) }
    }
    'save' { Set-Content -LiteralPath $args[2] -Value 'image tarball' }
    'load' { Write-Output 'Loaded image: stub' }
    'exec' {
        Write-Output 'exec ran'
        if ($env:STUB_EXEC_EXIT) { exit [int] $env:STUB_EXEC_EXIT }
    }
    'logs' { Write-Output 'stub container log' }
    'rm' { Remove-Item -LiteralPath $container -ErrorAction SilentlyContinue }
    'push' {
        Write-Output "The push refers to repository [$($args[1] -replace ':[^:/]+$', '')]"
        Write-Output '0123456789ab: Pushed'
        Write-Output "$($args[1] -replace '^.*:', ''): digest: sha256:$('b' * 64) size: 855"
    }
}
exit 0

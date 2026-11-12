#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Tests for actions/portainer-deploy against a fake Portainer: a raw TCP server (HttpListener on
# Windows rejects 127.0.0.1 without a URL reservation) that records every request.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    $script:Script = Join-Path $PSScriptRoot '..' 'actions' 'portainer-deploy' 'portainer-deploy.ps1'
    $script:Sha = 'a' * 40
    $script:OldSha = 'c' * 40
    $script:Digest = "sha256:$('b' * 64)"
    $script:Image = 'ghcr.io/owner/app'
    $script:Token = 'ptr_test-only-api-key-sentinel'
    $script:AccessId = 'access-id-sentinel.access'
    $script:AccessSecret = 'access-secret-sentinel'
    $script:StartEnv = @(
        [ordered]@{ name = 'POSTGRES_PASSWORD'; value = 'secret-pw-sentinel' }
        [ordered]@{ name = 'APP_IMAGE'; value = "$Image@sha256:$('0' * 64)" }
        [ordered]@{ name = 'STARTED'; value = '2026-01-02T03:04:05Z' }
        [ordered]@{ name = 'GREETING'; value = "h$([char] 0xE9)llo `"quoted`" $([char] 0x2713)" }
    )
    function Get-Flat([string] $Text) { $Text -replace '\s*\r?\n\s*\|\s*', ' ' }

    # State is shared with the server thread: tests set the answers, the server records the calls.
    function Start-FakePortainer {
        $state = [hashtable]::Synchronized(@{
                Calls = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
                Stack = (ConvertTo-Json @{ Env = $StartEnv; GitConfig = @{ ReferenceName = 'refs/heads/release'; Authentication = @{ Username = 'reader'; Password = '' } }; Option = @{ Prune = $true } } -Depth 5)
                ReadStatus = 200; PutStatus = 200; Revision = $Sha; Redeployed = $false
            })
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()

        $job = Start-ThreadJob -ScriptBlock {
            $listener = $using:listener
            $state = $using:state
            while ($true) {
                try { $client = $listener.AcceptTcpClient() } catch { break }
                try {
                    $stream = $client.GetStream()
                    $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $false, 1, $true)
                    $method, $path = ("$($reader.ReadLine())" -split ' ')[0, 1]
                    $headers = @{}
                    while ($line = $reader.ReadLine()) {
                        $name, $value = $line -split ':\s*', 2
                        $headers[$name.ToLowerInvariant()] = $value
                    }
                    $body = [System.Text.StringBuilder]::new()
                    $length = [int] $headers['content-length']
                    $bytes = 0
                    while ($bytes -lt $length) {
                        $char = [char] $reader.Read()
                        [void] $body.Append($char)
                        $bytes = [System.Text.Encoding]::UTF8.GetByteCount($body.ToString())
                    }
                    $state.Calls.Enqueue([pscustomobject]@{ Method = $method; Path = $path; Headers = $headers; Body = $body.ToString() })

                    $code, $text = switch -Regex ("$method $path") {
                        '^GET /api/stacks/7$' { if ($state.ReadStatus -eq 200) { 200, $state.Stack } else { $state.ReadStatus, '{"message":"secret-pw-sentinel"}' } }
                        '^PUT /api/stacks/7/git/redeploy\?endpointId=3$' {
                            if ($state.PutDelay) { Start-Sleep -Seconds $state.PutDelay }
                            if ($state.PutStatus -eq 200) { $state.Redeployed = $true }
                            $state.PutStatus, '{}'
                        }
                        '^GET /health/ready$' {
                            # The old build answers until the redeploy, so a match proves the poll waited for it.
                            $reported = if ($state.Redeployed) { $state.Revision } else { $using:OldSha }
                            200, "{`"status`":`"ready`",`"revision`":`"$reported`"}"
                        }
                        default { 404, '{}' }
                    }
                    $payload = [System.Text.Encoding]::UTF8.GetBytes($text)
                    $location = if ($code -eq 302) { "Location: https://login.example.test/`r`n" } else { '' }
                    $head = "HTTP/1.1 $code Status`r`nContent-Type: application/json`r`n$($location)Content-Length: $($payload.Length)`r`nConnection: close`r`n`r`n"
                    $headBytes = [System.Text.Encoding]::ASCII.GetBytes($head)
                    $stream.Write($headBytes, 0, $headBytes.Length)
                    $stream.Write($payload, 0, $payload.Length)
                    $stream.Flush()
                }
                catch { Write-Verbose "Request failed: $_" }
                finally { $client.Dispose() }
            }
        }

        [pscustomobject]@{ Url = "http://127.0.0.1:$($listener.LocalEndpoint.Port)"; State = $state; Listener = $listener; Job = $job }
    }

    function Invoke-Deploy($Fake, [hashtable] $Overrides = @{}) {
        $environment = @{
            INPUT_IMAGE = $Image; INPUT_DIGEST = $Digest; INPUT_PORTAINER_URL = $Fake.Url; INPUT_STACK_ID = '7'; INPUT_ENDPOINT_ID = '3'
            INPUT_API_KEY = $Token; INPUT_ACCESS_CLIENT_ID = $AccessId; INPUT_ACCESS_CLIENT_SECRET = $AccessSecret
            INPUT_IMAGE_VARIABLE = 'APP_IMAGE'; INPUT_PUBLIC_URL = $Fake.Url; INPUT_HEALTH_PATH = '/health/ready'
            INPUT_REVISION = $Sha; INPUT_HEALTH_TIMEOUT = '3'; INPUT_HEALTH_INTERVAL = '1'
        }
        foreach ($name in $Overrides.Keys) { $environment[$name] = $Overrides[$name] }
        Invoke-ActionScript $Script -Environment $environment
    }

    # The log with the mask commands removed: what a reader would see if masking failed.
    function Get-Unmasked([string] $Log) { $Log -replace '::add-mask::.*', '' }
}

Describe 'portainer-deploy' {
    BeforeEach { $script:Fake = Start-FakePortainer }
    AfterEach {
        $Fake.Listener.Stop()
        $Fake.Job | Wait-Job -Timeout 5 | Out-Null
        $Fake.Job | Remove-Job -Force
    }

    It 'changes only the image variable, redeploys with a pull and waits for the revision' {
        $result = Invoke-Deploy $Fake

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['image'] | Should -Be "$Image@$Digest"
        $result.Outputs['health-url'] | Should -Be "$($Fake.Url)/health/ready"

        $calls = @($Fake.State.Calls.ToArray())
        $put = @($calls | Where-Object Method -EQ 'PUT')
        $put.Count | Should -Be 1
        $body = $put[0].Body | ConvertFrom-Json -AsHashtable -DateKind String
        $body.env.Count | Should -Be 4
        for ($i = 0; $i -lt 4; $i++) {
            $body.env[$i].name | Should -BeExactly $StartEnv[$i].name
            $expected = if ($StartEnv[$i].name -eq 'APP_IMAGE') { "$Image@$Digest" } else { $StartEnv[$i].value }
            $body.env[$i].value | Should -BeExactly $expected
        }
        $body.pullImage | Should -BeTrue
        $body.prune | Should -BeTrue
        $body.repositoryReferenceName | Should -Be 'refs/heads/release'
        $body.repositoryAuthentication | Should -BeTrue
        $body.repositoryUsername | Should -Be 'reader'
        $body.Keys | Should -Not -Contain 'repositoryPassword'
        $body.Keys | Should -Not -Contain 'repositoryGitCredentialID'
        $put[0].Headers['content-type'] | Should -Match '^application/json'
        $result.Summary | Should -Match ([regex]::Escape("``$Image@$Digest``"))
    }

    It 'sends the API key and the Cloudflare Access headers to Portainer only' {
        $result = Invoke-Deploy $Fake

        $result.ExitCode | Should -Be 0 -Because $result.Log
        foreach ($call in $Fake.State.Calls.ToArray()) {
            if ($call.Path -like '/api/*') {
                $call.Headers['x-api-key'] | Should -BeExactly $Token
                $call.Headers['cf-access-client-id'] | Should -BeExactly $AccessId
                $call.Headers['cf-access-client-secret'] | Should -BeExactly $AccessSecret
            }
            else {
                $call.Headers.Keys | Should -Not -Contain 'x-api-key'
                $call.Headers.Keys | Should -Not -Contain 'cf-access-client-secret'
            }
        }
    }

    It 'masks the credentials and prints no secret or env value' {
        $result = Invoke-Deploy $Fake

        $result.ExitCode | Should -Be 0 -Because $result.Log
        foreach ($secret in $Token, $AccessId, $AccessSecret) { $result.Log | Should -Match ([regex]::Escape("::add-mask::$secret")) }
        $log = Get-Unmasked $result.Log
        foreach ($secret in $Token, $AccessId, $AccessSecret, 'secret-pw-sentinel') { $log | Should -Not -Match ([regex]::Escape($secret)) }
    }

    It 'keeps a stored Git credential and non-string env values' {
        $Fake.State.Stack = '{"Env":[{"name":"PORT","value":8080},{"name":"APP_IMAGE","value":"old"}],"GitConfig":{"ReferenceName":"refs/heads/main","Authentication":{"Username":"","GitCredentialID":5}},"Option":{}}'

        $result = Invoke-Deploy $Fake

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $body = (@($Fake.State.Calls.ToArray() | Where-Object Method -EQ 'PUT')[0].Body | ConvertFrom-Json -AsHashtable)
        $body.env[0].value | Should -BeExactly '8080'
        $body.env[1].value | Should -BeExactly "$Image@$Digest"
        $body.repositoryAuthentication | Should -BeTrue
        $body.repositoryGitCredentialID | Should -Be 5
        $body.prune | Should -BeFalse
    }

    It 'says the redeploy may still be running when Portainer answers too late' {
        $Fake.State.PutDelay = 3

        $result = Invoke-Deploy $Fake @{ INPUT_REDEPLOY_TIMEOUT = '1' }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'did not answer within 1 s while redeploying stack 7; it may still be working'
    }

    It 'adds the image variable when the stack does not have it' {
        $Fake.State.Stack = '{"Env":[{"name":"A","value":"1"}],"GitConfig":{"ReferenceName":"refs/heads/main"}}'

        $result = Invoke-Deploy $Fake

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $body = (@($Fake.State.Calls.ToArray() | Where-Object Method -EQ 'PUT')[0].Body | ConvertFrom-Json -AsHashtable)
        $body.env.Count | Should -Be 2
        $body.env[0].name | Should -Be 'A'
        $body.env[1].name | Should -Be 'APP_IMAGE'
        $body.env[1].value | Should -Be "$Image@$Digest"
        $body.repositoryAuthentication | Should -BeFalse
        $body.prune | Should -BeFalse
        $body.Keys | Should -Not -Contain 'repositoryUsername'
    }

    It 'pins several images in one redeploy and adds the ones the stack lacks' {
        $other = "sha256:$('d' * 64)"
        $images = "APP_IMAGE=$Image@$Digest`r`n
  WEB_IMAGE=ghcr.io/owner/web@$other  "
        $result = Invoke-Deploy $Fake @{ INPUT_IMAGE = ''; INPUT_DIGEST = ''; INPUT_IMAGE_VARIABLE = ''; INPUT_IMAGES = $images }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['image'] | Should -Be "$Image@$Digest, ghcr.io/owner/web@$other"
        $put = @($Fake.State.Calls.ToArray() | Where-Object Method -EQ 'PUT')
        $put.Count | Should -Be 1
        $body = $put[0].Body | ConvertFrom-Json -AsHashtable -DateKind String
        $body.env.Count | Should -Be 5
        $body.env[1].value | Should -Be "$Image@$Digest"
        $body.env[0].value | Should -BeExactly $StartEnv[0].value
        $body.env[4].name | Should -Be 'WEB_IMAGE'
        $body.env[4].value | Should -Be "ghcr.io/owner/web@$other"
    }
    It 'fails when the site never reports the revision' {
        $Fake.State.Revision = 'd' * 40

        $result = Invoke-Deploy $Fake @{ INPUT_HEALTH_TIMEOUT = '2' }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match "did not report $Sha within 2 s \(last: HTTP 200, revision dddddddddddd\)"
    }

    It 'reports only the status when Portainer answers <Code> to the <Step>' -ForEach @(
        @{ Step = 'read'; Code = 401; Message = 'HTTP 401 while reading stack 7' }
        @{ Step = 'read'; Code = 302; Message = 'HTTP 302 while reading stack 7. A redirect usually means Cloudflare Access' }
        @{ Step = 'redeploy'; Code = 500; Message = 'HTTP 500 while redeploying stack 7' }
    ) {
        if ($Step -eq 'read') { $Fake.State.ReadStatus = $Code } else { $Fake.State.PutStatus = $Code }

        $result = Invoke-Deploy $Fake

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
        Get-Unmasked $result.Log | Should -Not -Match 'sentinel'
        if ($Step -eq 'read') { @($Fake.State.Calls.ToArray() | Where-Object Method -EQ 'PUT').Count | Should -Be 0 }
    }

    It 'reports an unreachable Portainer without the key' {
        $result = Invoke-Deploy $Fake @{ INPUT_PORTAINER_URL = 'http://127.0.0.1:9' }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'Portainer is unreachable while reading stack 7'
        Get-Unmasked $result.Log | Should -Not -Match 'sentinel'
    }

    It 'refuses <Name> before calling Portainer' -ForEach @(
        @{ Name = 'a tag as the digest'; Overrides = @{ INPUT_DIGEST = 'latest' }; Message = 'must be a sha256 digest' }
        @{ Name = 'a short digest'; Overrides = @{ INPUT_DIGEST = 'sha256:abc' }; Message = 'must be a sha256 digest' }
        @{ Name = 'a sha1 digest'; Overrides = @{ INPUT_DIGEST = "sha1:$('b' * 40)" }; Message = 'must be a sha256 digest' }
        @{ Name = 'a digest with a suffix'; Overrides = @{ INPUT_DIGEST = "sha256:$('b' * 64)x" }; Message = 'must be a sha256 digest' }
        @{ Name = 'an image with a tag'; Overrides = @{ INPUT_IMAGE = 'ghcr.io/owner/app:latest' }; Message = 'without a tag or digest' }
        @{ Name = 'an uppercase image'; Overrides = @{ INPUT_IMAGE = 'ghcr.io/Owner/app' }; Message = 'without a tag or digest' }
        @{ Name = 'a missing API key'; Overrides = @{ INPUT_API_KEY = '' }; Message = 'Portainer is not configured' }
        @{ Name = 'a missing stack ID'; Overrides = @{ INPUT_STACK_ID = '' }; Message = 'Portainer is not configured' }
        @{ Name = 'a missing image variable'; Overrides = @{ INPUT_IMAGE_VARIABLE = '' }; Message = 'must be an environment variable name' }
        @{ Name = 'no image at all'; Overrides = @{ INPUT_IMAGE = ''; INPUT_DIGEST = ''; INPUT_IMAGE_VARIABLE = '' }; Message = 'Set images, or image, digest and image-variable.' }
        @{ Name = 'images together with image'; Overrides = @{ INPUT_IMAGES = "A=ghcr.io/owner/a@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }; Message = 'not both' }
        @{ Name = 'an images line without a digest'; Overrides = @{ INPUT_IMAGE = ''; INPUT_DIGEST = ''; INPUT_IMAGE_VARIABLE = ''; INPUT_IMAGES = 'A=ghcr.io/owner/a:latest' }; Message = 'must be VARIABLE=repository@sha256:digest' }
        @{ Name = 'an images variable listed twice'; Overrides = @{ INPUT_IMAGE = ''; INPUT_DIGEST = ''; INPUT_IMAGE_VARIABLE = ''; INPUT_IMAGES = "A=ghcr.io/owner/a@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb`nA=ghcr.io/owner/b@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" }; Message = 'listed twice' }
        @{ Name = 'plain HTTP to a remote Portainer'; Overrides = @{ INPUT_PORTAINER_URL = 'http://portainer.example.test' }; Message = 'must be https://host' }
        @{ Name = 'a Portainer URL with a path'; Overrides = @{ INPUT_PORTAINER_URL = 'https://portainer.example.test/api' }; Message = 'must be https://host' }
        @{ Name = 'half an Access token'; Overrides = @{ INPUT_ACCESS_CLIENT_SECRET = '' }; Message = 'Set both access-client-id and access-client-secret' }
        @{ Name = 'a bad variable name'; Overrides = @{ INPUT_IMAGE_VARIABLE = 'APP-IMAGE' }; Message = "The image variable 'APP-IMAGE'" }
        @{ Name = 'a short revision'; Overrides = @{ INPUT_REVISION = 'abc123' }; Message = "The revision 'abc123'" }
        @{ Name = 'a health path without a slash'; Overrides = @{ INPUT_HEALTH_PATH = 'health' }; Message = "The health-path 'health'" }
        @{ Name = 'a zero health timeout'; Overrides = @{ INPUT_HEALTH_TIMEOUT = '0' }; Message = "The health-timeout '0'" }
    ) {
        $result = Invoke-Deploy $Fake $Overrides

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
        $Fake.State.Calls.Count | Should -Be 0
        Get-Unmasked $result.Log | Should -Not -Match 'sentinel'
    }

    It 'fails on a stack that is not a Git stack' {
        $Fake.State.Stack = '{"Env":[]}'

        $result = Invoke-Deploy $Fake

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'Stack 7 is not a Git stack'
        @($Fake.State.Calls.ToArray() | Where-Object Method -EQ 'PUT').Count | Should -Be 0
    }
}

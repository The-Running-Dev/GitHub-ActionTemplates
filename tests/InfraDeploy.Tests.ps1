#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Tests for actions/infra-deploy against a fake GitHub API: a raw TCP server on loopback that
# records every request and builds the run title from the correlation it was dispatched with.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    $script:Script = Join-Path $PSScriptRoot '..' 'actions' 'infra-deploy' 'infra-deploy.ps1'
    $script:Sha = 'a' * 40
    $script:Digest = "sha256:$('b' * 64)"
    $script:Token = 'ghp_test-only-dispatch-token-sentinel'

    function Get-Flat([string] $Text) { $Text -replace '\s*\r?\n\s*\|\s*', ' ' }

    function Start-FakeGitHub {
        $state = [hashtable]::Synchronized(@{
                Calls = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
                DispatchStatus = 204; DispatchBody = ''; Correlation = ''; App = ''
                Appear = $true; Conclusion = 'success'; PollsBeforeDone = 1; Polls = 0
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
                        [void] $body.Append([char] $reader.Read())
                        $bytes = [System.Text.Encoding]::UTF8.GetByteCount($body.ToString())
                    }
                    $state.Calls.Enqueue([pscustomobject]@{ Method = $method; Path = $path; Headers = $headers; Body = $body.ToString() })

                    $code, $text = switch -Regex ("$method $path") {
                        '^POST /repos/owner/infra/actions/workflows/deploy\.yml/dispatches$' {
                            $sent = $body.ToString() | ConvertFrom-Json
                            $state.Correlation = $sent.inputs.correlation
                            $state.App = $sent.inputs.app
                            $state.DispatchStatus, $state.DispatchBody
                        }
                        '^GET /repos/owner/infra/actions/workflows/deploy\.yml/runs\?' {
                            $runs = @(@{ id = 1; display_title = 'deploy other other-correlation' })
                            if ($state.Appear) { $runs += @{ id = 4242; display_title = "deploy $($state.App) $($state.Correlation)" } }
                            200, (ConvertTo-Json @{ workflow_runs = $runs } -Depth 4 -Compress)
                        }
                        '^GET /repos/owner/infra/actions/runs/4242$' {
                            $state.Polls++
                            $done = $state.Polls -ge $state.PollsBeforeDone
                            $status = if ($done) { 'completed' } else { 'in_progress' }
                            $conclusion = if ($done) { $state.Conclusion } else { $null }
                            200, (ConvertTo-Json @{ id = 4242; status = $status; conclusion = $conclusion } -Compress)
                        }
                        default { 404, '{}' }
                    }
                    $payload = [System.Text.Encoding]::UTF8.GetBytes($text)
                    $head = "HTTP/1.1 $code Status`r`nContent-Type: application/json`r`nContent-Length: $($payload.Length)`r`nConnection: close`r`n`r`n"
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

    function Invoke-InfraDeploy($Fake, [hashtable] $Overrides = @{}) {
        $environment = @{
            INPUT_APP = 'my-app'; INPUT_DIGEST = $Digest; INPUT_TOKEN = $Token; INPUT_REVISION = $Sha
            INPUT_INFRA_REPOSITORY = 'owner/infra'; INPUT_API_URL = $Fake.Url
            INPUT_FIND_TIMEOUT = '2'; INPUT_RUN_TIMEOUT = '10'; INPUT_POLL_INTERVAL = '1'
        }
        foreach ($name in $Overrides.Keys) { $environment[$name] = $Overrides[$name] }
        Invoke-ActionScript $Script -Environment $environment
    }

    function Get-Unmasked([string] $Log) { $Log -replace '::add-mask::.*', '' }
}

Describe 'infra-deploy' {
    BeforeEach { $script:Fake = Start-FakeGitHub }
    AfterEach {
        $Fake.Listener.Stop()
        $Fake.Job | Wait-Job -Timeout 5 | Out-Null
        $Fake.Job | Remove-Job -Force
    }

    It 'dispatches the deploy, finds the run by its title and mirrors success' {
        $result = Invoke-InfraDeploy $Fake

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['run-url'] | Should -Be 'https://github.com/owner/infra/actions/runs/4242'
        $result.Outputs['correlation'] | Should -Be $Fake.State.Correlation
        $calls = @($Fake.State.Calls.ToArray())
        $post = @($calls | Where-Object Method -EQ 'POST')
        $post.Count | Should -Be 1
        $sent = $post[0].Body | ConvertFrom-Json
        $sent.ref | Should -Be 'main'
        $sent.inputs.app | Should -Be 'my-app'
        $sent.inputs.digest | Should -Be $Digest
        $sent.inputs.revision | Should -Be $Sha
        $sent.inputs.correlation | Should -Match '^[0-9a-f]{32}$'
        $post[0].Headers['authorization'] | Should -Be "Bearer $Token"
        $result.Summary | Should -Match 'my-app'
    }

    It 'uses the run id the dispatch returns and skips the search' {
        $Fake.State.DispatchStatus = 200
        $Fake.State.DispatchBody = '{"workflow_run_id":4242}'

        $result = Invoke-InfraDeploy $Fake

        $result.ExitCode | Should -Be 0 -Because $result.Log
        @($Fake.State.Calls.ToArray() | Where-Object { $_.Path -match '/runs\?' }).Count | Should -Be 0
    }

    It 'waits until the run is completed' {
        $Fake.State.PollsBeforeDone = 3

        $result = Invoke-InfraDeploy $Fake

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $Fake.State.Polls | Should -Be 3
    }

    It 'fails when the Infra run does not succeed' {
        $Fake.State.Conclusion = 'failure'

        $result = Invoke-InfraDeploy $Fake

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match "ended 'failure'"
        Get-Flat $result.Log | Should -Match ([regex]::Escape('https://github.com/owner/infra/actions/runs/4242'))
    }

    It 'fails when the run never appears' {
        $Fake.State.Appear = $false

        $result = Invoke-InfraDeploy $Fake

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'appeared within 2 s'
    }

    It 'fails when the run does not finish in time' {
        $Fake.State.PollsBeforeDone = 1000

        $result = Invoke-InfraDeploy $Fake @{ INPUT_RUN_TIMEOUT = '2' }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'did not finish within 2 s'
    }

    It 'reports the status and a hint when GitHub refuses the dispatch, without the token' {
        $Fake.State.DispatchStatus = 403
        $Fake.State.DispatchBody = '{"message":"leaky-sentinel"}'

        $result = Invoke-InfraDeploy $Fake

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'HTTP 403'
        Get-Flat $result.Log | Should -Match 'lack Actions write'
        Get-Unmasked $result.Log | Should -Not -Match 'sentinel'
    }

    It 'masks the token before anything else is printed' {
        $result = Invoke-InfraDeploy $Fake

        $result.Log | Should -Match ([regex]::Escape("::add-mask::$Token"))
        Get-Unmasked $result.Log | Should -Not -Match 'dispatch-token-sentinel'
    }

    It 'refuses <Name> before calling GitHub' -ForEach @(
        @{ Name = 'a tag as the digest'; Overrides = @{ INPUT_DIGEST = 'latest' }; Message = 'must be a sha256 digest' }
        @{ Name = 'a short digest'; Overrides = @{ INPUT_DIGEST = 'sha256:abc' }; Message = 'must be a sha256 digest' }
        @{ Name = 'a missing token'; Overrides = @{ INPUT_TOKEN = '' }; Message = 'The token is not set' }
        @{ Name = 'an uppercase app'; Overrides = @{ INPUT_APP = 'My-App' }; Message = "The app 'My-App'" }
        @{ Name = 'an app with a space'; Overrides = @{ INPUT_APP = 'my app' }; Message = "The app 'my app'" }
        @{ Name = 'a short revision'; Overrides = @{ INPUT_REVISION = 'abc123' }; Message = "The revision 'abc123'" }
        @{ Name = 'a bad repository'; Overrides = @{ INPUT_INFRA_REPOSITORY = 'owner' }; Message = 'must be owner/name' }
        @{ Name = 'a workflow path'; Overrides = @{ INPUT_WORKFLOW = '../deploy.yml' }; Message = 'must be a workflow file name' }
        @{ Name = 'plain HTTP to a remote API'; Overrides = @{ INPUT_API_URL = 'http://api.example.test' }; Message = 'must be https://host' }
        @{ Name = 'a zero poll interval'; Overrides = @{ INPUT_POLL_INTERVAL = '0' }; Message = "The poll-interval '0'" }
    ) {
        $result = Invoke-InfraDeploy $Fake $Overrides

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
        $Fake.State.Calls.Count | Should -Be 0
        Get-Unmasked $result.Log | Should -Not -Match 'sentinel'
    }
}

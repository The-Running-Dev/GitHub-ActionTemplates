#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Tests for the actions container.yml uses. docker, gh and cosign are stubs (tests/fixtures/cli-stubs);
# the HTTP probes go to a local test server. self-test.yml runs the same actions against real Docker.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    $script:Actions = Join-Path $PSScriptRoot '..' 'actions'
    $script:Stubs = Join-Path $PSScriptRoot 'fixtures' 'cli-stubs'
    $script:Server = Start-TestHttpServer
    $script:Sha = '0123456789abcdef0123456789abcdef01234567'
    $script:PullRequest = @{
        GITHUB_EVENT_NAME = 'pull_request'; GITHUB_REF_NAME = '7/merge'; GITHUB_HEAD_REF = 'feature/Add-Thing'; GHAT_PR_NUMBER = '7'
    }
    function Get-Flat([string] $Text) { $Text -replace '\s*\r?\n\s*\|\s*', ' ' }

    function New-Workspace([string] $Name) {
        $path = Join-Path $TestDrive "$Name-$([guid]::NewGuid().ToString('n'))"
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        return $path
    }

    function Set-File([string] $Path, [string] $Text) {
        New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
        Set-Content -LiteralPath $Path -Value $Text
    }

    # Runs an action with the CLI stubs first on the PATH; the result carries each stub's log.
    function Invoke-Action([string] $Name, [hashtable] $Environment = @{}, [string] $Workspace = (New-Workspace $Name)) {
        $log = New-Workspace 'log'
        $Environment['GITHUB_WORKSPACE'] = $Workspace
        $Environment['RUNNER_TEMP'] = $log
        $Environment['STUB_LOG'] = $log
        $Environment['PATH'] = "$Stubs$([System.IO.Path]::PathSeparator)$env:PATH"
        $result = Invoke-ActionScript (Join-Path $Actions $Name "$Name.ps1") -Environment $Environment -WorkingDirectory $Workspace
        foreach ($tool in 'docker', 'gh', 'cosign') {
            $file = Join-Path $log "$tool.txt"
            $text = if (Test-Path $file) { Get-Content $file -Raw } else { '' }
            $result | Add-Member -NotePropertyName ((Get-Culture).TextInfo.ToTitleCase($tool)) -NotePropertyValue $text
        }
        $result | Add-Member -NotePropertyName Temp -NotePropertyValue $log -PassThru
    }
}

AfterAll {
    Stop-TestHttpServer $Server
}

Describe 'image-meta' {
    It 'tags a default-branch build with the SHA and latest' {
        $result = Invoke-Action 'image-meta' @{ INPUT_IMAGE = 'ghcr.io/Octo-Org/App' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['image'] | Should -Be 'ghcr.io/octo-org/app'
        $result.Outputs['tags'] | Should -Be "ghcr.io/octo-org/app:$Sha`nghcr.io/octo-org/app:latest"
        $result.Outputs['tag-names'] | Should -Be "$Sha latest"
        $result.Outputs['latest'] | Should -Be 'true'
    }

    It 'writes the OCI labels and extra ones' {
        $result = Invoke-Action 'image-meta' @{ INPUT_IMAGE = 'ghcr.io/octo-org/app'; INPUT_LABELS = "org.opencontainers.image.title=App`nteam=web" }

        $labels = $result.Outputs['labels'] -split "`n"
        $labels | Should -Contain 'org.opencontainers.image.source=https://github.com/Octo-Org/Sample.Repo'
        $labels | Should -Contain "org.opencontainers.image.revision=$Sha"
        $labels | Should -Contain "org.opencontainers.image.version=$Sha"
        $labels | Should -Contain 'org.opencontainers.image.title=App'
        $labels | Should -Contain 'team=web'
        $labels | Where-Object { $_ -like 'org.opencontainers.image.created=*' } | Should -Match '=\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
    }

    It 'gives a stable tag build version, minor, major and latest' {
        $result = Invoke-Action 'image-meta' @{
            INPUT_IMAGE = 'ghcr.io/octo-org/app'; INPUT_TAGS = 'version minor major latest'; INPUT_VERSION = '1.2.3'
            GITHUB_REF_TYPE = 'tag'; GITHUB_REF_NAME = 'v1.2.3'
        }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['tag-names'] | Should -Be '1.2.3 1.2 1 latest'
        $result.Outputs['labels'] -split "`n" | Should -Contain 'org.opencontainers.image.version=1.2.3'
    }

    It 'gives a prerelease tag build only its version' {
        $result = Invoke-Action 'image-meta' @{
            INPUT_IMAGE = 'ghcr.io/octo-org/app'; INPUT_TAGS = 'version minor major latest'; INPUT_VERSION = '2.0.0-rc.1'
            GITHUB_REF_TYPE = 'tag'; GITHUB_REF_NAME = 'v2.0.0-rc.1'
        }

        $result.Outputs['tag-names'] | Should -Be '2.0.0-rc.1'
        $result.Outputs['latest'] | Should -Be 'false'
    }

    It 'reads stability from the tag name when there is no version' {
        $stable = Invoke-Action 'image-meta' @{ INPUT_IMAGE = 'ghcr.io/octo-org/app'; GITHUB_REF_TYPE = 'tag'; GITHUB_REF_NAME = 'v3.1.0' }
        $prerelease = Invoke-Action 'image-meta' @{ INPUT_IMAGE = 'ghcr.io/octo-org/app'; GITHUB_REF_TYPE = 'tag'; GITHUB_REF_NAME = 'v3.1.0-beta.2' }

        $stable.Outputs['latest'] | Should -Be 'true'
        $prerelease.Outputs['latest'] | Should -Be 'false'
    }

    It 'keeps latest off pull requests and other branches' {
        $pr = Invoke-Action 'image-meta' (@{ INPUT_IMAGE = 'ghcr.io/octo-org/app'; INPUT_TAGS = 'short-sha branch latest' } + $PullRequest)
        $branch = Invoke-Action 'image-meta' @{ INPUT_IMAGE = 'ghcr.io/octo-org/app'; GITHUB_REF_NAME = 'develop' }

        $pr.Outputs['tag-names'] | Should -Be '0123456 feature-add-thing'
        $branch.Outputs['latest'] | Should -Be 'false'
    }

    It 'withholds latest when told to' {
        $result = Invoke-Action 'image-meta' @{ INPUT_IMAGE = 'ghcr.io/octo-org/app'; INPUT_LATEST = 'false' }

        $result.Outputs['tag-names'] | Should -Be $Sha
        $result.Outputs['latest'] | Should -Be 'false'
    }

    It 'tags the date as yyyyMMdd' {
        $result = Invoke-Action 'image-meta' @{ INPUT_IMAGE = 'ghcr.io/octo-org/app'; INPUT_TAGS = 'date, short-sha' }

        $result.Outputs['tag-names'] | Should -Match '^\d{8} 0123456$'
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'a missing image'; Environment = @{}; Message = "Set 'image'" }
        @{ Name = 'an image with a tag'; Environment = @{ INPUT_IMAGE = 'ghcr.io/o/app:v1 x' }; Message = 'is not a valid image name' }
        @{ Name = 'an unknown tag kind'; Environment = @{ INPUT_IMAGE = 'ghcr.io/o/app'; INPUT_TAGS = 'sha edge' }; Message = 'Unknown tag kind(s): edge' }
        @{ Name = 'a version tag without a version'; Environment = @{ INPUT_IMAGE = 'ghcr.io/o/app'; INPUT_TAGS = 'version' }; Message = "The 'version' tag needs the 'version' input" }
        @{ Name = 'a label without a value'; Environment = @{ INPUT_IMAGE = 'ghcr.io/o/app'; INPUT_LABELS = 'team' }; Message = "The label 'team' must be key=value" }
    ) {
        $result = Invoke-Action 'image-meta' $Environment.Clone()

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
    }
}

Describe 'branch-tip-gate' {
    It 'publishes everything from the branch tip' {
        $result = Invoke-Action 'branch-tip-gate' @{ STUB_BRANCH_HEAD = $Sha }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Gh | Should -Match 'api repos/Octo-Org/Sample\.Repo/branches/main --jq \.commit\.sha'
        $result.Outputs['is-tip'] | Should -Be 'true'
        $result.Outputs['publish'] | Should -Be 'true'
        $result.Outputs['latest'] | Should -Be 'true'
    }

    It 'publishes nothing from an older commit by default' {
        $result = Invoke-Action 'branch-tip-gate' @{ STUB_BRANCH_HEAD = 'f' * 40 }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['is-tip'] | Should -Be 'false'
        $result.Outputs['head'] | Should -Be ('f' * 40)
        $result.Outputs['publish'] | Should -Be 'false'
        $result.Outputs['latest'] | Should -Be 'false'
        $result.Log | Should -Match '::notice::0123456 is no longer the tip of ''main'' \(fffffff is\)'
        $result.Summary | Should -Match 'Skipped publishing'
    }

    It 'publishes an older commit without latest when require-tip is latest' {
        $result = Invoke-Action 'branch-tip-gate' @{ STUB_BRANCH_HEAD = 'f' * 40; INPUT_REQUIRE_TIP = 'latest' }

        $result.Outputs['publish'] | Should -Be 'true'
        $result.Outputs['latest'] | Should -Be 'false'
    }

    It 'escapes the branch name' {
        $result = Invoke-Action 'branch-tip-gate' @{ STUB_BRANCH_HEAD = $Sha; INPUT_BRANCH = 'release/1.x' }

        $result.Gh | Should -Match 'branches/release%2F1\.x '
    }

    It 'does not check <Name>' -ForEach @(
        @{ Name = 'tag builds'; Environment = @{ GITHUB_REF_TYPE = 'tag'; GITHUB_REF_NAME = 'v1.0.0' } }
        @{ Name = 'with require-tip none'; Environment = @{ INPUT_REQUIRE_TIP = 'none' } }
    ) {
        $result = Invoke-Action 'branch-tip-gate' $Environment.Clone()

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Gh | Should -BeNullOrEmpty
        $result.Outputs['publish'] | Should -Be 'true'
        $result.Outputs['latest'] | Should -Be 'true'
    }

    It 'fails when the branch head cannot be read' {
        $result = Invoke-Action 'branch-tip-gate' @{ STUB_BRANCH_HEAD = '' }

        $result.ExitCode | Should -Not -Be 0
    }

    It 'rejects an unknown require-tip' {
        $result = Invoke-Action 'branch-tip-gate' @{ INPUT_REQUIRE_TIP = 'some' }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match "The require-tip 'some' must be"
    }
}

Describe 'image-archive' {
    It 'saves the image with its ID and loads it back' {
        $folder = Join-Path (New-Workspace 'archive') 'image'
        $save = Invoke-Action 'image-archive' @{ INPUT_IMAGE = 'ghcr.io/o/app:abc'; INPUT_PATH = $folder }

        $save.ExitCode | Should -Be 0 -Because $save.Log
        $save.Docker | Should -Match 'save --output \S+image\.tar ghcr\.io/o/app:abc'
        $save.Outputs['id'] | Should -Be "sha256:$('a' * 64)"
        (Get-Content (Join-Path $folder 'image.json') -Raw | ConvertFrom-Json).image | Should -Be 'ghcr.io/o/app:abc'

        $load = Invoke-Action 'image-archive' @{ INPUT_MODE = 'load'; INPUT_PATH = $folder }

        $load.ExitCode | Should -Be 0 -Because $load.Log
        $load.Docker | Should -Match 'load --input \S+image\.tar'
        $load.Outputs['image'] | Should -Be 'ghcr.io/o/app:abc'
    }

    It 'fails when the loaded image is not the one saved' {
        $folder = Join-Path (New-Workspace 'archive') 'image'
        Invoke-Action 'image-archive' @{ INPUT_IMAGE = 'ghcr.io/o/app:abc'; INPUT_PATH = $folder } | Out-Null

        $result = Invoke-Action 'image-archive' @{ INPUT_MODE = 'load'; INPUT_PATH = $folder; STUB_IMAGE_ID = "sha256:$('c' * 64)" }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'but the saved one had'
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'saving a missing image'; Environment = @{ INPUT_IMAGE = 'nope:1'; STUB_IMAGE_MISSING = 'true' }; Message = "The image 'nope:1' does not exist locally" }
        @{ Name = 'saving without an image'; Environment = @{}; Message = "Set 'image'" }
        @{ Name = 'loading an empty folder'; Environment = @{ INPUT_MODE = 'load' }; Message = 'No saved image in' }
        @{ Name = 'an unknown mode'; Environment = @{ INPUT_MODE = 'copy' }; Message = "The mode 'copy' must be" }
    ) {
        $environment = $Environment.Clone()
        $environment['INPUT_PATH'] = Join-Path (New-Workspace 'archive') 'image'
        $result = Invoke-Action 'image-archive' $environment

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
    }
}

Describe 'image-push' {
    It 'tags and pushes every reference and reports the digest' {
        $result = Invoke-Action 'image-push' @{ INPUT_SOURCE = 'ghcr.io/o/app:abc'; INPUT_TAGS = "ghcr.io/o/app:abc`nghcr.io/o/app:latest" }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Docker | Should -Match 'tag ghcr\.io/o/app:abc ghcr\.io/o/app:latest'
        $result.Docker | Should -Match 'push ghcr\.io/o/app:abc'
        $result.Docker | Should -Match 'push ghcr\.io/o/app:latest'
        $result.Log | Should -Not -Match '0123456789ab: Pushed'
        $result.Outputs['image'] | Should -Be 'ghcr.io/o/app'
        $result.Outputs['digest'] | Should -Be "sha256:$('b' * 64)"
        $result.Outputs['reference'] | Should -Be "ghcr.io/o/app@sha256:$('b' * 64)"
        $result.Cosign | Should -BeNullOrEmpty
    }

    It 'keeps a registry port apart from the tag' {
        $result = Invoke-Action 'image-push' @{ INPUT_SOURCE = 'app:1'; INPUT_TAGS = 'localhost:5000/o/app:1 localhost:5000/o/app:latest' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['image'] | Should -Be 'localhost:5000/o/app'
    }

    It 'signs the digest of an image Buildx pushed without pushing again' {
        $digest = "sha256:$('d' * 64)"
        $result = Invoke-Action 'image-push' @{ INPUT_DIGEST = $digest; INPUT_TAGS = 'ghcr.io/o/app:1'; INPUT_SIGN = 'true' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Docker | Should -BeNullOrEmpty
        $result.Cosign | Should -Match "sign --yes ghcr\.io/o/app@$digest"
        $result.Outputs['digest'] | Should -Be $digest
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'no tags'; Environment = @{ INPUT_SOURCE = 'app:1' }; Message = "Set 'tags'" }
        @{ Name = 'no source or digest'; Environment = @{ INPUT_TAGS = 'ghcr.io/o/app:1' }; Message = "Set 'source'" }
        @{ Name = 'both source and digest'; Environment = @{ INPUT_TAGS = 'ghcr.io/o/app:1'; INPUT_SOURCE = 'app:1'; INPUT_DIGEST = "sha256:$('d' * 64)" }; Message = 'not both' }
        @{ Name = 'a malformed digest'; Environment = @{ INPUT_TAGS = 'ghcr.io/o/app:1'; INPUT_DIGEST = 'sha256:abc' }; Message = 'must be sha256:<64 hex characters>' }
        @{ Name = 'two repositories'; Environment = @{ INPUT_TAGS = 'ghcr.io/o/app:1 ghcr.io/o/other:1'; INPUT_SOURCE = 'app:1' }; Message = 'more than one repository' }
    ) {
        $result = Invoke-Action 'image-push' $Environment.Clone()

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
        $result.Docker | Should -BeNullOrEmpty
    }
}

Describe 'image-gate' {
    It 'starts the container, waits for the probe and runs the exec scripts' {
        $workspace = New-Workspace 'gate'
        Set-File (Join-Path $workspace 'smoke/check.sh') 'echo ok'
        Set-File (Join-Path $workspace 'smoke/Check.ps1') 'Write-Output ok'
        $result = Invoke-Action 'image-gate' @{
            INPUT_IMAGE = 'app:1'; INPUT_PORT = '8080'; INPUT_HEALTH_PATH = '/text/ready'; INPUT_EXEC = "smoke/check.sh`nsmoke/Check.ps1"
            INPUT_ENV = "MODE=test`nLIST=a;b"; INPUT_OPTIONS = "--tmpfs /data`n--read-only"; STUB_DOCKER_PORT = "$($Server.Port)"
        } $workspace

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Docker | Should -Match 'run --detach --name ghat-smoke --env-file \S+ --tmpfs /data --read-only --publish 127\.0\.0\.1::8080 app:1'
        $result.Docker | Should -Match 'ENV: MODE=test'
        $result.Docker | Should -Match 'ENV: LIST=a;b'
        $result.Docker | Should -Match 'cp \S+check\.sh ghat-smoke:/tmp/ghat-smoke-1-check\.sh'
        $result.Docker | Should -Match 'exec ghat-smoke sh /tmp/ghat-smoke-1-check\.sh'
        $result.Docker | Should -Match 'exec ghat-smoke pwsh -NoProfile -NonInteractive -File /tmp/ghat-smoke-2-Check\.ps1'
        $result.Outputs['url'] | Should -Be $Server.Url
        $result.Outputs['container'] | Should -Be 'ghat-smoke'
        @(Get-ChildItem $result.Temp -Filter '*.env') | Should -BeNullOrEmpty -Because 'the env file is deleted once the container runs'
        $result.Summary | Should -Match '2 script\(s\) passed in the container'
    }

    It 'accepts any status when told to' {
        $result = Invoke-Action 'image-gate' @{ INPUT_IMAGE = 'app:1'; INPUT_PORT = '80'; INPUT_HEALTH_PATH = '/status/401'; INPUT_HEALTH_STATUS = 'any'; STUB_DOCKER_PORT = "$($Server.Port)" }

        $result.ExitCode | Should -Be 0 -Because $result.Log
    }

    It 'waits for a healthy HEALTHCHECK when there is no port' {
        $result = Invoke-Action 'image-gate' @{ INPUT_IMAGE = 'app:1'; STUB_DOCKER_STATE = 'running|0|healthy' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['url'] | Should -Be ''
        $result.Summary | Should -Match 'HEALTHCHECK healthy'
    }

    It 'fails with the container log when <Name>' -ForEach @(
        @{ Name = 'the container exits'; State = 'exited|3|'; Message = 'The container stopped before it was ready (exited, exit code 3)' }
        @{ Name = 'the HEALTHCHECK fails'; State = 'running|0|unhealthy'; Message = 'reports the container unhealthy' }
    ) {
        $result = Invoke-Action 'image-gate' @{ INPUT_IMAGE = 'app:1'; STUB_DOCKER_STATE = $State }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
        $result.Log | Should -Match 'stub container log'
    }

    It 'gives up when the probe never answers as expected' {
        $result = Invoke-Action 'image-gate' @{ INPUT_IMAGE = 'app:1'; INPUT_PORT = '80'; INPUT_HEALTH_PATH = '/status/500'; INPUT_TIMEOUT = '1'; STUB_DOCKER_PORT = "$($Server.Port)" }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'not ready after 1 s\. Last check: /status/500 answered 500'
    }

    It 'fails when an exec script fails' {
        $workspace = New-Workspace 'gate'
        Set-File (Join-Path $workspace 'check.sh') 'exit 1'
        $result = Invoke-Action 'image-gate' @{ INPUT_IMAGE = 'app:1'; INPUT_EXEC = 'check.sh'; STUB_DOCKER_STATE = 'running|0|healthy'; STUB_EXEC_EXIT = '4' } $workspace

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'check\.sh exited with code 4 in the container'
    }

    It 'rejects <Name> before starting anything' -ForEach @(
        @{ Name = 'a missing exec script'; Environment = @{ INPUT_IMAGE = 'app:1'; INPUT_EXEC = 'nope.sh' }; Message = "The exec script 'nope.sh' does not exist" }
        @{ Name = 'an env line without a name'; Environment = @{ INPUT_IMAGE = 'app:1'; INPUT_ENV = 'secret-value' }; Message = 'must be NAME=value' }
        @{ Name = 'a port that is not a number'; Environment = @{ INPUT_IMAGE = 'app:1'; INPUT_PORT = '80/tcp' }; Message = "The port '80/tcp'" }
        @{ Name = 'a relative health path'; Environment = @{ INPUT_IMAGE = 'app:1'; INPUT_HEALTH_PATH = 'health' }; Message = "must start with '/'" }
        @{ Name = 'a bad status list'; Environment = @{ INPUT_IMAGE = 'app:1'; INPUT_HEALTH_STATUS = '2xx' }; Message = "The health-status '2xx'" }
        @{ Name = 'no image'; Environment = @{}; Message = "Set 'image'" }
        @{ Name = 'an unsafe container name'; Environment = @{ INPUT_IMAGE = 'app:1'; INPUT_NAME = '-x' }; Message = 'may only hold letters' }
    ) {
        $result = Invoke-Action 'image-gate' $Environment.Clone()

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
        $result.Docker | Should -Not -Match '(?m)^run '
    }

    It 'stops the container after printing its log' {
        $log = New-Workspace 'log'
        Set-Content (Join-Path $log 'container') ''
        $result = Invoke-ActionScript (Join-Path $Actions 'image-gate' 'image-gate.ps1') -Environment @{
            INPUT_MODE = 'stop'; STUB_LOG = $log; PATH = "$Stubs$([System.IO.Path]::PathSeparator)$env:PATH"
        }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Log | Should -Match 'stub container log'
        Get-Content (Join-Path $log 'docker.txt') -Raw | Should -Match 'rm --force ghat-smoke'
    }

    It 'has nothing to stop when no container started' {
        $result = Invoke-Action 'image-gate' @{ INPUT_MODE = 'stop' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Log | Should -Match "No container 'ghat-smoke' to stop"
    }
}

Describe 'webhook-deploy' {
    It 'calls the webhook and waits for the expected text' {
        $result = Invoke-Action 'webhook-deploy' @{
            INPUT_URL = "$($Server.Url)/method/POST"; INPUT_HEALTH_URL = "$($Server.Url)/text/build-$Sha"; INPUT_HEALTH_EXPECT = $Sha
            INPUT_HEALTH_INTERVAL = '1'; INPUT_HEALTH_CONSECUTIVE = '2'
        }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['webhook-status'] | Should -Be '200'
        $result.Outputs['health-status'] | Should -Be '200'
        $result.Log | Should -Match ([regex]::Escape("::add-mask::$($Server.Url)/method/POST"))
        $result.Summary | Should -Match '2 times in a row'
    }

    It 'retries the webhook until it answers' {
        $result = Invoke-Action 'webhook-deploy' @{ INPUT_URL = "$($Server.Url)/flaky/hook-$([guid]::NewGuid().ToString('n'))/2"; INPUT_RETRY_DELAY = '0' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        ([regex]::Matches($result.Log, 'answered 503; retrying')).Count | Should -Be 2
    }

    It 'gives up after the retries without printing the URL' {
        $url = "$($Server.Url)/status/500"
        $result = Invoke-Action 'webhook-deploy' @{ INPUT_URL = $url; INPUT_RETRIES = '1'; INPUT_RETRY_DELAY = '0' }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'The webhook answered 500 after 2 attempt\(s\)'
        ($result.Log -replace [regex]::Escape("::add-mask::$url"), '') | Should -Not -Match ([regex]::Escape($url))
    }

    It 'sends the chosen method' {
        $result = Invoke-Action 'webhook-deploy' @{ INPUT_URL = "$($Server.Url)/method/GET"; INPUT_METHOD = 'get'; INPUT_RETRIES = '0' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
    }

    It 'fails when the health URL never has the expected text' {
        $result = Invoke-Action 'webhook-deploy' @{
            INPUT_HEALTH_URL = "$($Server.Url)/text/old"; INPUT_HEALTH_EXPECT = 'new'; INPUT_HEALTH_TIMEOUT = '1'; INPUT_HEALTH_INTERVAL = '1'
        }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'was not healthy after 1 s\. Last check: answered 200 without the expected text'
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'neither a webhook nor a health URL'; Environment = @{}; Message = "Set 'url'" }
        @{ Name = 'a webhook that is not http'; Environment = @{ INPUT_URL = 'ftp://example.com' }; Message = 'must start with http:// or https://' }
        @{ Name = 'an unknown method'; Environment = @{ INPUT_URL = 'https://example.com'; INPUT_METHOD = 'DELETE' }; Message = "The method 'DELETE'" }
        @{ Name = 'a negative retry count'; Environment = @{ INPUT_URL = 'https://example.com'; INPUT_RETRIES = '-1' }; Message = "The retries '-1'" }
    ) {
        $result = Invoke-Action 'webhook-deploy' $Environment.Clone()

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
    }
}

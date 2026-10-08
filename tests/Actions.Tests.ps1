#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    $script:Actions = Join-Path $PSScriptRoot '..' 'actions'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    $script:PullRequest = @{
        GITHUB_EVENT_NAME = 'pull_request'; GITHUB_REF_NAME = '7/merge'; GITHUB_HEAD_REF = 'feature/Add-Thing'; GHAT_PR_NUMBER = '7'
    }
}

Describe 'version' {
    BeforeAll {
        $script:Script = Join-Path $Actions 'version' 'version.ps1'
        $script:Released = New-GitRepository (Join-Path $TestDrive 'released') -Tags 'v1.2.3'
        $script:Candidate = New-GitRepository (Join-Path $TestDrive 'candidate') -Tags 'v1.2.3', 'v2.0.0-rc.1'
        $script:Untagged = New-GitRepository (Join-Path $TestDrive 'untagged')

        function Invoke-Version([hashtable] $Environment, [string] $WorkingDirectory = $Released) {
            Invoke-ActionScript $Script -Environment $Environment -WorkingDirectory $WorkingDirectory
        }
    }

    Context 'tag strategy' {
        It 'uses the tag on tag builds' {
            $result = Invoke-Version @{ INPUT_STRATEGY = 'tag'; GITHUB_REF_TYPE = 'tag'; GITHUB_REF_NAME = 'v1.2.3' }

            $result.ExitCode | Should -Be 0
            $result.Outputs['version'] | Should -Be '1.2.3'
            $result.Outputs['is-release'] | Should -Be 'true'
            $result.Outputs['is-prerelease'] | Should -Be 'false'
            $result.Outputs['tag'] | Should -Be 'v1.2.3'
            $result.Summary | Should -Match '1\.2\.3'
        }

        It 'builds a prerelease of the next patch on the default branch' {
            $result = Invoke-Version @{ INPUT_STRATEGY = 'tag' }

            $result.Outputs['version'] | Should -Be '1.2.4-ci.42'
            $result.Outputs['major'] | Should -Be '1'
            $result.Outputs['patch'] | Should -Be '4'
            $result.Outputs['prerelease'] | Should -Be 'ci.42'
            $result.Outputs['is-release'] | Should -Be 'false'
        }

        It 'stays on the core version after a prerelease tag' {
            (Invoke-Version @{ INPUT_STRATEGY = 'tag' } $Candidate).Outputs['version'] | Should -Be '2.0.0-ci.42'
        }

        It 'starts at 0.0.1 without tags' {
            $result = Invoke-Version @{ INPUT_STRATEGY = 'tag' } $Untagged
            $result.Outputs['version'] | Should -Be '0.0.1-ci.42'
            # The failed `git describe` must not become the step's exit code.
            $result.ExitCode | Should -Be 0
        }

        It 'labels pull request builds with the PR number' {
            (Invoke-Version ($PullRequest + @{ INPUT_STRATEGY = 'tag' })).Outputs['version'] | Should -Be '1.2.4-pr.7.42'
        }

        It 'honours a custom tag prefix and labels' {
            $result = Invoke-Version @{ INPUT_STRATEGY = 'tag'; INPUT_TAG_PREFIX = 'release-'; INPUT_PRERELEASE_LABEL = 'nightly'; GITHUB_REF_TYPE = 'tag'; GITHUB_REF_NAME = 'release-3.0.0' }
            $result.Outputs['version'] | Should -Be '3.0.0'
            $result.Outputs['tag'] | Should -Be 'release-3.0.0'
        }

        It 'fails on a tag without the prefix' {
            $result = Invoke-Version @{ INPUT_STRATEGY = 'tag'; GITHUB_REF_TYPE = 'tag'; GITHUB_REF_NAME = '1.2.3' }
            $result.ExitCode | Should -Not -Be 0
            $result.Log | Should -Match 'does not start with the tag prefix'
        }
    }

    Context 'manifest strategy' {
        It 'reads <Directory> on the default branch' -ForEach @(
            @{ Directory = 'npm-lib'; Expected = '2.3.4-ci.42' }
            @{ Directory = 'dotnet-lib'; Expected = '3.4.5-ci.42' }
            @{ Directory = 'pwsh-module'; Expected = '4.5.6-ci.42' }
            @{ Directory = 'python-lib'; Expected = '5.6.7-rc.1.ci.42' }
            @{ Directory = 'plain'; Expected = '6.7.8-ci.42' }
        ) {
            $result = Invoke-Version @{ INPUT_STRATEGY = 'manifest'; INPUT_WORKING_DIRECTORY = (Join-Path $Fixtures $Directory) }
            $result.ExitCode | Should -Be 0
            $result.Outputs['version'] | Should -Be $Expected
        }

        It 'uses an explicit manifest path' {
            $result = Invoke-Version @{ INPUT_STRATEGY = 'manifest'; INPUT_WORKING_DIRECTORY = $Fixtures; INPUT_MANIFEST = 'plain/VERSION' }
            $result.Outputs['version'] | Should -Be '6.7.8-ci.42'
        }

        It 'returns the manifest version on a matching tag' {
            $result = Invoke-Version @{ INPUT_STRATEGY = 'manifest'; INPUT_WORKING_DIRECTORY = (Join-Path $Fixtures 'npm-lib'); GITHUB_REF_TYPE = 'tag'; GITHUB_REF_NAME = 'v2.3.4' }
            $result.Outputs['version'] | Should -Be '2.3.4'
            $result.Outputs['is-release'] | Should -Be 'true'
        }

        It 'fails when the tag does not match the manifest' {
            $result = Invoke-Version @{ INPUT_STRATEGY = 'manifest'; INPUT_WORKING_DIRECTORY = (Join-Path $Fixtures 'npm-lib'); GITHUB_REF_TYPE = 'tag'; GITHUB_REF_NAME = 'v9.9.9' }
            $result.ExitCode | Should -Not -Be 0
            $result.Log | Should -Match 'does not match version'
        }
    }

    Context 'run-number strategy' {
        It 'is stable on the default branch' {
            (Invoke-Version @{ INPUT_STRATEGY = 'run-number'; INPUT_BASE_VERSION = '1.0' }).Outputs['version'] | Should -Be '1.0.42'
        }

        It 'is a prerelease on other branches' {
            (Invoke-Version @{ INPUT_STRATEGY = 'run-number'; INPUT_BASE_VERSION = '1.0'; GITHUB_REF_NAME = 'develop' }).Outputs['version'] | Should -Be '1.0.42-ci'
        }

        It 'labels pull requests' {
            (Invoke-Version ($PullRequest + @{ INPUT_STRATEGY = 'run-number'; INPUT_BASE_VERSION = '1.0' })).Outputs['version'] | Should -Be '1.0.42-pr.7'
        }

        It 'requires base-version as Major.Minor' {
            $result = Invoke-Version @{ INPUT_STRATEGY = 'run-number'; INPUT_BASE_VERSION = '1.0.0' }
            $result.ExitCode | Should -Not -Be 0
            $result.Log | Should -Match 'base-version'
        }
    }

    It 'rejects an unknown strategy' {
        $result = Invoke-Version @{ INPUT_STRATEGY = 'calendar' }
        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match 'Unknown strategy'
    }

    It 'rejects an invalid prerelease label' {
        $result = Invoke-Version @{ INPUT_STRATEGY = 'tag'; INPUT_PRERELEASE_LABEL = 'bad label' }
        $result.ExitCode | Should -Not -Be 0
    }
}

Describe 'assert-tag-version' {
    BeforeAll {
        $script:Script = Join-Path $Actions 'assert-tag-version' 'assert-tag-version.ps1'
        $script:Module = Join-Path $Fixtures 'pwsh-module'
    }

    It 'skips builds that are not for a tag' {
        $result = Invoke-ActionScript $Script -Environment @{ INPUT_WORKING_DIRECTORY = $Module }
        $result.ExitCode | Should -Be 0
        $result.Outputs['checked'] | Should -Be 'false'
    }

    It 'passes when the current tag matches' {
        $result = Invoke-ActionScript $Script -Environment @{ INPUT_WORKING_DIRECTORY = $Module; GITHUB_REF_TYPE = 'tag'; GITHUB_REF_NAME = 'v4.5.6' }
        $result.ExitCode | Should -Be 0
        $result.Outputs['checked'] | Should -Be 'true'
        $result.Outputs['version'] | Should -Be '4.5.6'
    }

    It 'checks an explicit tag on any build' {
        $result = Invoke-ActionScript $Script -Environment @{ INPUT_WORKING_DIRECTORY = $Fixtures; INPUT_MANIFEST = 'npm-lib/package.json'; INPUT_TAG = 'v2.3.4' }
        $result.Outputs['checked'] | Should -Be 'true'
    }

    It 'fails with an annotation when the tag does not match' {
        $result = Invoke-ActionScript $Script -Environment @{ INPUT_WORKING_DIRECTORY = $Module; INPUT_TAG = 'v4.5.7' }
        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match '::error file=.*does not match'
    }
}

Describe 'context' {
    BeforeAll {
        $script:Script = Join-Path $Actions 'context' 'context.ps1'
    }

    It 'describes a default-branch push' {
        $result = Invoke-ActionScript $Script

        $result.ExitCode | Should -Be 0
        $result.Outputs['owner'] | Should -Be 'octo-org'
        $result.Outputs['repository'] | Should -Be 'Sample.Repo'
        $result.Outputs['short-sha'] | Should -Be '0123456'
        $result.Outputs['ref-slug'] | Should -Be 'main'
        $result.Outputs['is-default-branch'] | Should -Be 'true'
        $result.Outputs['should-publish'] | Should -Be 'true'
        $result.Outputs['image'] | Should -Be 'ghcr.io/octo-org/sample.repo'
    }

    It 'describes a pull request' {
        $result = Invoke-ActionScript $Script -Environment $PullRequest

        $result.Outputs['is-pull-request'] | Should -Be 'true'
        $result.Outputs['should-publish'] | Should -Be 'false'
        $result.Outputs['branch'] | Should -Be 'feature/Add-Thing'
        $result.Outputs['ref-slug'] | Should -Be 'feature-add-thing'
    }

    It 'describes a tag' {
        $result = Invoke-ActionScript $Script -Environment @{ GITHUB_REF_TYPE = 'tag'; GITHUB_REF_NAME = 'v1.2.3' }

        $result.Outputs['is-tag'] | Should -Be 'true'
        $result.Outputs['should-publish'] | Should -Be 'true'
        $result.Outputs['branch'] | Should -Be ''
        $result.Outputs['ref-slug'] | Should -Be 'v1-2-3'
    }

    It 'does not publish feature branches' {
        (Invoke-ActionScript $Script -Environment @{ GITHUB_REF_NAME = 'feature/x' }).Outputs['should-publish'] | Should -Be 'false'
    }

    It 'builds the image from <Registry> and <Name>' -ForEach @(
        @{ Registry = 'registry.example.com/'; Name = 'Web'; Expected = 'registry.example.com/octo-org/web' }
        @{ Registry = ''; Name = 'web'; Expected = 'ghcr.io/octo-org/web' }
    ) {
        $result = Invoke-ActionScript $Script -Environment @{ INPUT_REGISTRY = $Registry; INPUT_IMAGE_NAME = $Name }
        $result.Outputs['image'] | Should -Be $Expected
    }
}

Describe 'debug' {
    It 'prints the context without values of sensitive variables' {
        $result = Invoke-ActionScript (Join-Path $Actions 'debug' 'debug.ps1') -Environment @{
            GITHUB_SAMPLE_SETTING = 'visible-value'
            GITHUB_SAMPLE_TOKEN   = 'hidden-value'
        }

        $result.ExitCode | Should -Be 0
        $result.Log | Should -Match 'GITHUB_SAMPLE_SETTING=visible-value'
        $result.Log | Should -Not -Match 'hidden-value'
        $result.Log | Should -Match '::group::Tools'
    }
}

Describe 'docs-build' {
    BeforeAll {
        $script:Script = Join-Path $Actions 'docs-build' 'docs-build.ps1'

        # A workspace with the fixture copied to <workspace>/docs, so builds never write into tests/.
        function New-DocsWorkspace([string] $Fixture) {
            $workspace = Join-Path $TestDrive "workspace-$([guid]::NewGuid().ToString('n'))"
            New-Item -ItemType Directory -Path $workspace | Out-Null
            Copy-Item -LiteralPath (Join-Path $Fixtures $Fixture) -Destination (Join-Path $workspace 'docs') -Recurse
            return $workspace
        }

        function Invoke-DocsBuild([string] $Workspace, [hashtable] $Environment = @{}) {
            $temp = Join-Path $TestDrive "temp-$([guid]::NewGuid().ToString('n'))"
            New-Item -ItemType Directory -Path $temp | Out-Null
            $Environment['GITHUB_WORKSPACE'] = $Workspace
            $Environment['RUNNER_TEMP'] = $temp
            Invoke-ActionScript $Script -Environment $Environment -WorkingDirectory $Workspace
        }
    }

    Context 'node builder' {
        It 'installs and builds the folder''s own project' {
            $workspace = New-DocsWorkspace 'docs-node'

            $result = Invoke-DocsBuild $workspace @{ INPUT_BUILDER = 'node' }

            $result.ExitCode | Should -Be 0 -Because $result.Log
            $result.Outputs['path'] | Should -Be 'docs/build'
            Join-Path $workspace 'docs' 'build' 'index.html' | Should -FileContentMatch 'docs-node-fixture-marker'
            $result.Summary | Should -Match '`node` builder: 1 files'
        }

        It 'fails when the build does not write index.html to the output folder' {
            $workspace = New-DocsWorkspace 'docs-node'

            $result = Invoke-DocsBuild $workspace @{ INPUT_BUILDER = 'node'; INPUT_OUTPUT = 'docs/dist' }

            $result.ExitCode | Should -Not -Be 0
            $result.Log | Should -Match ([regex]::Escape("did not produce 'docs/dist/index.html'"))
        }
    }

    Context 'template builder' {
        It 'runs build node-template with the bundled template' {
            $workspace = New-DocsWorkspace 'docusaurus'
            $log = Join-Path $TestDrive 'stub-log'
            New-Item -ItemType Directory -Path $log | Out-Null
            $stub = Join-Path $Fixtures 'build-agent-stub'

            $result = Invoke-DocsBuild $workspace @{
                PATH                  = "$stub$([System.IO.Path]::PathSeparator)$env:PATH"
                STUB_LOG              = $log
                INPUT_PACKAGE_MANAGER = 'pnpm'
            }

            $result.ExitCode | Should -Be 0 -Because $result.Log
            $result.Outputs['path'] | Should -Be 'docs/build'
            $arguments = @(Get-Content (Join-Path $log 'args.txt'))
            $arguments[0] | Should -Be 'node-template'
            $arguments[$arguments.IndexOf('-WorkingDir') + 1] | Should -Be ([System.IO.Path]::GetFullPath($workspace))
            $arguments[$arguments.IndexOf('-AppDir') + 1] | Should -Be 'docs'
            $arguments[$arguments.IndexOf('-PackageManager') + 1] | Should -Be 'pnpm'
            $arguments[$arguments.IndexOf('-NodeTemplateRepositoryUrl') + 1] | Should -BeLike 'file:///*'
            $template = @(Get-Content (Join-Path $log 'template.txt'))
            $template | Should -Contain 'docusaurus.config.ts'
            $template | Should -Contain 'pnpm-lock.yaml'
        }

        It 'moves the site to the output folder' {
            $workspace = New-DocsWorkspace 'docusaurus'
            $log = Join-Path $TestDrive 'stub-log-output'
            New-Item -ItemType Directory -Path $log | Out-Null
            $stale = Join-Path $workspace 'artifacts' 'docs'
            New-Item -ItemType Directory -Path $stale -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $stale 'stale.html') -Value 'stale'

            $result = Invoke-DocsBuild $workspace @{
                PATH         = "$(Join-Path $Fixtures 'build-agent-stub')$([System.IO.Path]::PathSeparator)$env:PATH"
                STUB_LOG     = $log
                INPUT_OUTPUT = 'artifacts/docs'
            }

            $result.ExitCode | Should -Be 0 -Because $result.Log
            $result.Outputs['path'] | Should -Be 'artifacts/docs'
            Join-Path $stale 'index.html' | Should -FileContentMatch 'stub site'
            Join-Path $stale 'stale.html' | Should -Not -Exist
            Join-Path $workspace 'docs' 'build' | Should -Not -Exist
        }

        It 'explains where the build command comes from when it is missing' -Skip:([bool] (Get-Command build -ErrorAction SilentlyContinue)) {
            $result = Invoke-DocsBuild (New-DocsWorkspace 'docusaurus')

            $result.ExitCode | Should -Not -Be 0
            $result.Log | Should -Match 'build-agent'
        }
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'an unknown builder'; Environment = @{ INPUT_BUILDER = 'hugo' }; Message = "Unknown builder 'hugo'" }
        @{ Name = 'an unknown package manager'; Environment = @{ INPUT_PACKAGE_MANAGER = 'bun' }; Message = "Unknown package-manager 'bun'" }
        @{ Name = 'a source outside the workspace'; Environment = @{ INPUT_SOURCE = '../elsewhere' }; Message = "source '../elsewhere' must be inside the workspace" }
        @{ Name = 'a missing source'; Environment = @{ INPUT_SOURCE = 'missing' }; Message = "source folder 'missing' does not exist" }
        @{ Name = 'the source as the output'; Environment = @{ INPUT_OUTPUT = 'docs' }; Message = 'must not be the source folder' }
    ) {
        $result = Invoke-DocsBuild (New-DocsWorkspace 'docs-node') $Environment

        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match ([regex]::Escape($Message))
    }
}

Describe 'run-scripts' {
    BeforeAll {
        $script:Script = Join-Path $Actions 'run-scripts' 'run-scripts.ps1'

        # A workspace whose build folder holds the given scripts; each first appends its name to ran.txt.
        function New-ScriptWorkspace([hashtable] $Scripts) {
            $workspace = Join-Path $TestDrive "scripts-$([guid]::NewGuid().ToString('n'))"
            New-Item -ItemType Directory -Path (Join-Path $workspace 'build') -Force | Out-Null
            foreach ($name in $Scripts.Keys) {
                Set-Content -LiteralPath (Join-Path $workspace 'build' $name) -Value @(
                    "Add-Content -LiteralPath (Join-Path `$env:GITHUB_WORKSPACE 'ran.txt') -Value '$name'"
                    $Scripts[$name]
                )
            }
            return $workspace
        }

        function Invoke-RunScript([string] $Workspace, [string] $Scripts, [hashtable] $Environment = @{}) {
            $Environment['GITHUB_WORKSPACE'] = $Workspace
            $Environment['INPUT_SCRIPTS'] = $Scripts
            Invoke-ActionScript $Script -Environment $Environment -WorkingDirectory $Workspace
        }

        function Get-Ran([string] $Workspace) {
            $ran = Join-Path $Workspace 'ran.txt'
            if (Test-Path -LiteralPath $ran) { @(Get-Content -LiteralPath $ran) } else { @() }
        }
    }

    It 'runs the scripts in order from the workspace root' {
        $workspace = New-ScriptWorkspace @{ 'one.ps1' = "Set-Content -LiteralPath where.txt -Value (Get-Location).Path"; 'two.ps1' = '' }

        $result = Invoke-RunScript $workspace "./build/one.ps1`n  build/two.ps1  `n"

        $result.ExitCode | Should -Be 0 -Because $result.Log
        Get-Ran $workspace | Should -Be @('one.ps1', 'two.ps1')
        Get-Content -LiteralPath (Join-Path $workspace 'where.txt') | Should -Be ([System.IO.Path]::GetFullPath($workspace))
        $result.Summary | Should -Match ([regex]::Escape('Ran 2 script(s): `./build/one.ps1`, `build/two.ps1`.'))
    }

    It 'accepts a semicolon-separated list and a working-directory' {
        $workspace = New-ScriptWorkspace @{ 'one.ps1' = 'Set-Content -LiteralPath where.txt -Value done'; 'two.ps1' = '' }

        $result = Invoke-RunScript $workspace 'build/one.ps1; build/two.ps1' @{ INPUT_WORKING_DIRECTORY = 'build' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        Get-Ran $workspace | Should -Be @('one.ps1', 'two.ps1')
        Join-Path $workspace 'build' 'where.txt' | Should -Exist
    }

    It 'stops at a script that <Name>' -ForEach @(
        @{ Name = 'throws'; Body = 'throw "broken"' }
        @{ Name = 'exits non-zero'; Body = 'exit 3' }
        @{ Name = 'runs a failing native command before a passing one'; Body = "pwsh -NoProfile -Command 'exit 4'`npwsh -NoProfile -Command 'exit 0'" }
    ) {
        $workspace = New-ScriptWorkspace @{ 'bad.ps1' = $Body; 'after.ps1' = '' }

        $result = Invoke-RunScript $workspace "build/bad.ps1`nbuild/after.ps1"

        $result.ExitCode | Should -Not -Be 0
        Get-Ran $workspace | Should -Be @('bad.ps1')
    }

    It 'checks every path before running any script' {
        $workspace = New-ScriptWorkspace @{ 'one.ps1' = '' }

        $result = Invoke-RunScript $workspace "build/one.ps1`nbuild/missing.ps1"

        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match ([regex]::Escape("script 'build/missing.ps1' does not exist"))
        Get-Ran $workspace | Should -BeNullOrEmpty
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'a command instead of a path'; Scripts = 'npm --prefix site ci'; Message = 'Pass script paths only' }
        @{ Name = 'a script outside the workspace'; Scripts = '../outside.ps1'; Message = "script '../outside.ps1' must be inside the workspace" }
        @{ Name = 'an empty list'; Scripts = " `n ; "; Message = 'No scripts given' }
    ) {
        $result = Invoke-RunScript (New-ScriptWorkspace @{}) $Scripts

        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match ([regex]::Escape($Message))
    }
}

Describe 'changelog' {
    BeforeAll {
        $script:Script = Join-Path $Actions 'changelog' 'changelog.ps1'
        $script:Dash = [char] 0x2014
        $script:History = New-GitRepository (Join-Path $TestDrive 'history')
        foreach ($subject in 'feat: add <thing> [beta] (#12)', 'chore: update changelog (#13)', 'fix: direct commit') {
            git -C $History commit --quiet --allow-empty -m $subject
        }

        function Invoke-Changelog([string] $Workspace, [hashtable] $Environment) {
            $Environment['GITHUB_WORKSPACE'] = $Workspace
            # Keeps the action from adding a safe.directory to the global git config.
            $Environment['GITHUB_ACTIONS'] = ''
            Invoke-ActionScript $Script -Environment $Environment -WorkingDirectory $Workspace
        }
    }

    It 'writes one entry per commit, newest first, with pull request links' {
        $result = Invoke-Changelog $History @{ INPUT_PATH = 'docs/changelog.md'; INPUT_FRONT_MATTER = "slug: changelog`nsidebar_position: 9" }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $lines = @(Get-Content -LiteralPath (Join-Path $History 'docs' 'changelog.md'))
        $lines[0..3] | Should -Be @('---', 'slug: changelog', 'sidebar_position: 9', '---')
        $lines | Should -Contain '# Changelog'
        $entries = @($lines | Where-Object { $_ -like '- *' })
        # The three commits above after New-GitRepository's two, less the changelog update.
        $entries.Count | Should -Be 4
        $entries[0] | Should -Match ('^- \*\*\d{4}-\d{2}-\d{2}\*\* ' + [regex]::Escape("$Dash fix: direct commit") + '$')
        $entries[1] | Should -Match ([regex]::Escape("** $Dash [feat: add &lt;thing&gt; \[beta\] (#12)](https://github.com/Octo-Org/Sample.Repo/pull/12)") + '$')
        $entries[3] | Should -Match ([regex]::Escape("** $Dash commit 0") + '$')
        $result.Outputs['entries'] | Should -Be '4'
    }

    It 'writes no front matter by default and takes a title' {
        $result = Invoke-Changelog $History @{ INPUT_PATH = 'CHANGES.md'; INPUT_TITLE = 'Release history' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        (Get-Content -LiteralPath (Join-Path $History 'CHANGES.md'))[0] | Should -Be '# Release history'
    }

    It 'fails on a shallow checkout' {
        $shallow = Join-Path $TestDrive 'shallow'
        git clone --quiet --depth 1 ([uri]::new($History).AbsoluteUri) $shallow

        $result = Invoke-Changelog $shallow @{ INPUT_PATH = 'changelog.md' }

        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match 'fetch-depth: 0'
    }

    It 'rejects a page outside the workspace' {
        $result = Invoke-Changelog $History @{ INPUT_PATH = '../changelog.md' }

        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match 'must be inside the workspace'
    }
}

Describe 'node-scripts' {
    BeforeAll {
        $script:Script = Join-Path $Actions 'node-scripts' 'node-scripts.ps1'

        # package.json scripts that append to <workspace>/order.txt, so the run order can be read back.
        function New-NodeProject([string] $Path, [string[]] $Scripts, [hashtable] $Overrides = @{}) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            $name = (Split-Path $Path -Leaf).ToLowerInvariant()
            $commands = [ordered]@{}
            foreach ($script in $Scripts) {
                $commands[$script] = "node -e `"require('fs').appendFileSync('../order.txt', '${name}:$script\n')`""
            }
            foreach ($script in $Overrides.Keys) { $commands[$script] = $Overrides[$script] }
            [ordered]@{ name = $name; version = '1.0.0'; private = $true; scripts = $commands } |
                ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Path 'package.json')
        }

        function Invoke-NodeScript([string] $Workspace, [hashtable] $Environment) {
            $Environment['GITHUB_WORKSPACE'] = $Workspace
            Invoke-ActionScript $Script -Environment $Environment -WorkingDirectory $Workspace
        }
    }

    It 'builds the dependencies, then runs the scripts in order' {
        $workspace = Join-Path $TestDrive 'ordered'
        New-NodeProject (Join-Path $workspace 'engine') 'build'
        New-NodeProject (Join-Path $workspace 'site') 'check', 'merge'

        $result = Invoke-NodeScript $workspace @{ INPUT_PATH = 'site'; INPUT_SCRIPTS = "check merge"; INPUT_DEPENDENCIES = 'engine' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        @(Get-Content -LiteralPath (Join-Path $workspace 'order.txt')) | Should -Be @('engine:build', 'site:check', 'site:merge')
        $result.Summary | Should -Match ([regex]::Escape('Ran `check`, `merge` in `site`.'))
    }

    It 'stops at a failing script' {
        $workspace = Join-Path $TestDrive 'failing'
        New-NodeProject (Join-Path $workspace 'site') 'merge' @{ check = 'node -e "process.exit(2)"' }

        $result = Invoke-NodeScript $workspace @{ INPUT_PATH = 'site'; INPUT_SCRIPTS = "check`nmerge" }

        $result.ExitCode | Should -Not -Be 0
        Join-Path $workspace 'order.txt' | Should -Not -Exist
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'a folder without package.json'; Environment = @{ INPUT_PATH = 'empty' }; Message = "path 'empty' has no package.json" }
        @{ Name = 'a dependency without package.json'; Environment = @{ INPUT_PATH = 'site'; INPUT_DEPENDENCIES = 'empty' }; Message = "dependency 'empty' has no package.json" }
        @{ Name = 'a project outside the workspace'; Environment = @{ INPUT_PATH = '../site' }; Message = 'must be inside the workspace' }
        @{ Name = 'an unknown package manager'; Environment = @{ INPUT_PATH = 'site'; INPUT_PACKAGE_MANAGER = 'bun' }; Message = 'bun' }
    ) {
        $workspace = Join-Path $TestDrive "rejects-$([guid]::NewGuid().ToString('n'))"
        New-Item -ItemType Directory -Path (Join-Path $workspace 'empty') -Force | Out-Null
        New-NodeProject (Join-Path $workspace 'site') 'build'

        $result = Invoke-NodeScript $workspace $Environment.Clone()

        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match ([regex]::Escape($Message))
        Join-Path $workspace 'order.txt' | Should -Not -Exist
    }
}

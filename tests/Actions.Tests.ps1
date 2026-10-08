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
            (Invoke-Version @{ INPUT_STRATEGY = 'tag' } $Untagged).Outputs['version'] | Should -Be '0.0.1-ci.42'
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

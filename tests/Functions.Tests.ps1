#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'actions' '_lib' 'Functions.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
}

Describe 'ConvertTo-SemVer' {
    It 'parses <Version> as <Expected>' -ForEach @(
        @{ Version = '1.2.3'; Expected = '1.2.3' }
        @{ Version = '1.2'; Expected = '1.2.0' }
        @{ Version = '0.0.0'; Expected = '0.0.0' }
        @{ Version = '1.2.3-rc.1+build.5'; Expected = '1.2.3-rc.1' }
        @{ Version = ' 10.20.30 '; Expected = '10.20.30' }
    ) {
        Format-SemVer (ConvertTo-SemVer $Version) | Should -Be $Expected
    }

    It 'rejects <Version>' -ForEach @(
        @{ Version = 'v1.2.3' }
        @{ Version = '1' }
        @{ Version = '01.2.3' }
        @{ Version = '1.2.3.4' }
        @{ Version = '1.2.3-' }
        @{ Version = '1.2.3-rc..1' }
    ) {
        { ConvertTo-SemVer $Version } | Should -Throw '*not a valid semantic version*'
    }
}

Describe 'Get-ManifestVersion' {
    It 'reads <File>' -ForEach @(
        @{ File = 'npm-lib/package.json'; Expected = '2.3.4' }
        @{ File = 'dotnet-lib/Fixture.DotnetLib.csproj'; Expected = '3.4.5' }
        @{ File = 'pwsh-module/Fixture.Module.psd1'; Expected = '4.5.6' }
        @{ File = 'python-lib/pyproject.toml'; Expected = '5.6.7-rc.1' }
        @{ File = 'plain/VERSION'; Expected = '6.7.8' }
    ) {
        Get-ManifestVersion (Join-Path $Fixtures $File) | Should -Be $Expected
    }

    It 'prefers <Version> over <VersionPrefix>' {
        $path = Join-Path $TestDrive 'Both.csproj'
        Set-Content $path '<Project><PropertyGroup><VersionPrefix>1.0.0</VersionPrefix><Version>2.0.0</Version></PropertyGroup></Project>'
        Get-ManifestVersion $path | Should -Be '2.0.0'
    }

    It 'rejects MSBuild expressions' {
        $path = Join-Path $TestDrive 'Expression.csproj'
        Set-Content $path '<Project><PropertyGroup><Version>$(BaseVersion).1</Version></PropertyGroup></Project>'
        { Get-ManifestVersion $path } | Should -Throw '*MSBuild expression*'
    }

    It 'fails when the manifest has no version' {
        $path = Join-Path $TestDrive 'package.json'
        Set-Content $path '{ "name": "no-version" }'
        { Get-ManifestVersion $path } | Should -Throw '*No version found*'
    }

    It 'fails when the manifest does not exist' {
        { Get-ManifestVersion (Join-Path $TestDrive 'missing.json') } | Should -Throw '*does not exist*'
    }
}

Describe 'Find-Manifest' {
    It 'finds <Expected> in <Directory>' -ForEach @(
        @{ Directory = 'npm-lib'; Expected = 'package.json' }
        @{ Directory = 'dotnet-lib'; Expected = 'Fixture.DotnetLib.csproj' }
        @{ Directory = 'pwsh-module'; Expected = 'Fixture.Module.psd1' }
        @{ Directory = 'python-lib'; Expected = 'pyproject.toml' }
        @{ Directory = 'plain'; Expected = 'VERSION' }
    ) {
        Split-Path (Find-Manifest (Join-Path $Fixtures $Directory)) -Leaf | Should -Be $Expected
    }

    It 'skips ambiguous project files' {
        $path = New-Item -ItemType Directory (Join-Path $TestDrive 'two-projects')
        Set-Content (Join-Path $path 'A.csproj') '<Project />'
        Set-Content (Join-Path $path 'B.csproj') '<Project />'
        { Find-Manifest $path } | Should -Throw '*No version manifest found*'
    }
}

Describe 'ConvertTo-Slug' {
    It 'turns <Value> into <Expected>' -ForEach @(
        @{ Value = 'main'; Expected = 'main' }
        @{ Value = 'feature/Add_Thing'; Expected = 'feature-add-thing' }
        @{ Value = '--Release--1.2--'; Expected = 'release-1-2' }
        @{ Value = ''; Expected = '' }
    ) {
        ConvertTo-Slug $Value | Should -Be $Expected
    }

    It 'caps the slug at 63 characters without a trailing dash' {
        $slug = ConvertTo-Slug (('a' * 62) + '/b')
        $slug.Length | Should -BeLessOrEqual 63
        $slug | Should -Not -Match '-$'
    }
}

Describe 'Get-ActionContext' {
    It 'treats a push to the default branch as publishable' {
        $context = Use-Environment @{
            GITHUB_EVENT_NAME = 'push'; GITHUB_REF_TYPE = 'branch'; GITHUB_REF_NAME = 'main'
            GITHUB_REPOSITORY = 'Octo/Repo'; GITHUB_SHA = 'abcdef1234567'; GHAT_DEFAULT_BRANCH = 'main'
            GHAT_PR_NUMBER = ''; GITHUB_EVENT_PATH = ''; GITHUB_HEAD_REF = ''
        } { Get-ActionContext }

        $context.IsDefaultBranch | Should -BeTrue
        $context.ShouldPublish | Should -BeTrue
        $context.Branch | Should -Be 'main'
        $context.ShortSha | Should -Be 'abcdef1'
        $context.Owner | Should -Be 'Octo'
        $context.Repository | Should -Be 'Repo'
    }

    It 'does not publish pull requests and reports the head branch' {
        $context = Use-Environment @{
            GITHUB_EVENT_NAME = 'pull_request'; GITHUB_REF_TYPE = 'branch'; GITHUB_REF_NAME = '7/merge'
            GITHUB_HEAD_REF = 'feature/x'; GHAT_DEFAULT_BRANCH = 'main'; GHAT_PR_NUMBER = '7'; GITHUB_EVENT_PATH = ''
        } { Get-ActionContext }

        $context.IsPullRequest | Should -BeTrue
        $context.ShouldPublish | Should -BeFalse
        $context.IsDefaultBranch | Should -BeFalse
        $context.Branch | Should -Be 'feature/x'
        $context.PullRequestNumber | Should -Be '7'
    }

    It 'publishes tags' {
        $context = Use-Environment @{
            GITHUB_EVENT_NAME = 'push'; GITHUB_REF_TYPE = 'tag'; GITHUB_REF_NAME = 'v1.0.0'
            GHAT_DEFAULT_BRANCH = 'main'; GHAT_PR_NUMBER = ''; GITHUB_EVENT_PATH = ''; GITHUB_HEAD_REF = ''
        } { Get-ActionContext }

        $context.IsTag | Should -BeTrue
        $context.ShouldPublish | Should -BeTrue
        $context.Branch | Should -Be ''
    }

    It 'does not publish other branches' {
        $context = Use-Environment @{
            GITHUB_EVENT_NAME = 'push'; GITHUB_REF_TYPE = 'branch'; GITHUB_REF_NAME = 'develop'
            GHAT_DEFAULT_BRANCH = 'main'; GHAT_PR_NUMBER = ''; GITHUB_EVENT_PATH = ''; GITHUB_HEAD_REF = ''
        } { Get-ActionContext }

        $context.ShouldPublish | Should -BeFalse
    }

    It 'falls back to the event payload' {
        $payload = Join-Path $TestDrive 'event.json'
        Set-Content $payload '{ "repository": { "default_branch": "trunk" }, "pull_request": { "number": 12 } }'

        $context = Use-Environment @{
            GITHUB_EVENT_NAME = 'pull_request'; GITHUB_REF_TYPE = 'branch'; GITHUB_REF_NAME = '12/merge'
            GHAT_DEFAULT_BRANCH = ''; GHAT_PR_NUMBER = ''; GITHUB_EVENT_PATH = $payload; GITHUB_HEAD_REF = 'fix'
        } { Get-ActionContext }

        $context.DefaultBranch | Should -Be 'trunk'
        $context.PullRequestNumber | Should -Be '12'
    }
}

Describe 'Get-LatestTagVersion' {
    It 'returns the nearest version tag' {
        $repo = New-GitRepository (Join-Path $TestDrive 'tags') -Tags 'v1.0.0', 'v1.1.0', 'not-a-version'
        Format-SemVer (Get-LatestTagVersion -Path $repo) | Should -Be '1.1.0'
    }

    It 'returns nothing when there are no tags' {
        $repo = New-GitRepository (Join-Path $TestDrive 'no-tags')
        Get-LatestTagVersion -Path $repo | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-WorkspacePath' {
    BeforeAll {
        $script:Workspace = Join-Path $TestDrive 'work'
    }

    It 'resolves <Path> inside the workspace' -ForEach @(
        @{ Path = 'docs'; Expected = 'docs' }
        @{ Path = 'docs/site/'; Expected = 'docs/site' }
        @{ Path = './a/../docs'; Expected = 'docs' }
    ) {
        Resolve-WorkspacePath $Path $Workspace | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $Workspace $Expected)))
    }

    It 'accepts an absolute path inside the workspace' {
        $inside = Join-Path $Workspace 'docs'
        Resolve-WorkspacePath $inside $Workspace | Should -Be ([System.IO.Path]::GetFullPath($inside))
    }

    It 'rejects <Path>' -ForEach @(
        @{ Path = '.' }
        @{ Path = '../elsewhere' }
        @{ Path = 'docs/../../elsewhere' }
        @{ Path = '../work-other/docs' }
    ) {
        { Resolve-WorkspacePath $Path $Workspace 'source' } | Should -Throw '*source*must be a folder inside the workspace*'
    }

    It 'rejects an absolute path outside the workspace' {
        { Resolve-WorkspacePath (Join-Path $TestDrive 'other') $Workspace } | Should -Throw '*inside the workspace*'
    }
}

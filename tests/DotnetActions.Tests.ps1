#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Tests for the actions used by dotnet.yml. The .NET CLI is the dotnet.ps1 stub, so no SDK is needed.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    $script:Actions = Join-Path $PSScriptRoot '..' 'actions'
    $script:Stubs = Join-Path $PSScriptRoot 'fixtures' 'cli-stubs'
    # The error view wraps long messages onto "| " lines; tests match on the joined text.
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

    # Runs an action with the CLI stubs first on PATH; the result gets the stub's log as .Dotnet.
    function Invoke-Action([string] $Name, [string] $Workspace, [hashtable] $Environment = @{}) {
        $log = New-Workspace 'log'
        $Environment['GITHUB_WORKSPACE'] = $Workspace
        $Environment['PATH'] = "$Stubs$([System.IO.Path]::PathSeparator)$env:PATH"
        $Environment['STUB_LOG'] = $log
        $result = Invoke-ActionScript (Join-Path $Actions $Name "$Name.ps1") -Environment $Environment -WorkingDirectory $Workspace
        $dotnet = Join-Path $log 'dotnet.txt'
        $result | Add-Member -NotePropertyName Dotnet -NotePropertyValue $(if (Test-Path $dotnet) { Get-Content $dotnet -Raw } else { '' }) -PassThru
    }

    function New-Solution([string] $Name) {
        $workspace = New-Workspace $Name
        Set-File (Join-Path $workspace 'App.slnx') '<Solution />'
        return $workspace
    }
}

Describe 'dotnet-test' {
    It 'restores, builds and tests the solution, reporting TRX results' {
        $workspace = New-Solution 'test'

        $result = Invoke-Action 'dotnet-test' $workspace @{ INPUT_FILTER = 'Category!=Slow'; INPUT_TEST_ARGS = '--blame "--logger:console;verbosity=normal"' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $lines = $result.Dotnet.Trim() -split '\r?\n'
        $lines[0] | Should -Match '^restore .*App\.slnx$'
        $lines[1] | Should -Match '^build .*App\.slnx --no-restore --configuration Release$'
        $lines[2] | Should -Match '^test .*App\.slnx --no-build --configuration Release --logger trx --results-directory .*TestResults --filter Category!=Slow --blame --logger:console;verbosity=normal$'
        $result.Outputs['results'] | Should -Be 'TestResults/*.trx'
        $result.Outputs['coverage-report'] | Should -Be ''
        $result.Outputs['solution'] | Should -Be 'App.slnx'
        $result.Summary | Should -Match 'passed'
    }

    It 'merges the coverage of each test project, ignoring the copies under In' {
        $workspace = New-Solution 'coverage'

        $result = Invoke-Action 'dotnet-test' $workspace @{ INPUT_COVERAGE = 'true'; STUB_COVERAGE_PROJECTS = 'a,b' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Dotnet | Should -Match '--collect XPlat Code Coverage'
        $result.Outputs['coverage-report'] | Should -Be 'TestResults/coverage.cobertura.xml'
        $result.Log | Should -Match 'Merged 2 coverage report\(s\): 2/2 lines covered'
        $merged = [xml] (Get-Content -Raw (Join-Path $workspace 'TestResults' 'coverage.cobertura.xml'))
        $merged.coverage.'lines-valid' | Should -Be '2'
    }

    It 'warns when coverage was asked for but not collected' {
        $workspace = New-Solution 'nocoverage'

        $result = Invoke-Action 'dotnet-test' $workspace @{ INPUT_COVERAGE = 'true' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Log | Should -Match '::warning::No coverage was collected'
        $result.Outputs['coverage-report'] | Should -Be ''
    }

    It 'sets the outputs before failing on failed tests' {
        $workspace = New-Solution 'failing'

        $result = Invoke-Action 'dotnet-test' $workspace @{ STUB_TEST_EXIT = '1' }

        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match 'dotnet test failed with exit code 1'
        $result.Outputs['results'] | Should -Be 'TestResults/*.trx'
        $result.Summary | Should -Match 'failed \(exit code 1\)'
    }

    It 'clears results left from an earlier run' {
        $workspace = New-Solution 'stale'
        Set-File (Join-Path $workspace 'TestResults' 'old.trx') '<TestRun />'

        $result = Invoke-Action 'dotnet-test' $workspace

        $result.ExitCode | Should -Be 0 -Because $result.Log
        Join-Path $workspace 'TestResults' 'old.trx' | Should -Not -Exist
    }

    It 'only builds when test is false, with Windows targeting and extra arguments' {
        $workspace = New-Workspace 'build'
        Set-File (Join-Path $workspace 'src' 'App' 'App.csproj') '<Project />'

        $result = Invoke-Action 'dotnet-test' $workspace @{
            INPUT_WORKING_DIRECTORY = 'src/App'; INPUT_TEST = 'false'; INPUT_ENABLE_WINDOWS_TARGETING = 'true'
            INPUT_CONFIGURATION = 'Debug'; INPUT_RESTORE_ARGS = '--locked-mode'; INPUT_BUILD_ARGS = '-p:Foo=1;Bar=2'
        }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $lines = $result.Dotnet.Trim() -split '\r?\n'
        $lines.Count | Should -Be 2
        $lines[0] | Should -Match 'App\.csproj -p:EnableWindowsTargeting=true --locked-mode$'
        $lines[1] | Should -Match '--configuration Debug -p:EnableWindowsTargeting=true -p:Foo=1;Bar=2$'
        $result.Outputs['solution'] | Should -Be 'src/App/App.csproj'
        $result.Outputs['results'] | Should -Be ''
    }

    It 'fails when the folder has several solutions' {
        $workspace = New-Solution 'several'
        Set-File (Join-Path $workspace 'Other.slnx') '<Solution />'

        $result = Invoke-Action 'dotnet-test' $workspace

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match "set 'solution'"
        $result.Dotnet | Should -BeNullOrEmpty
    }
}

Describe 'dotnet-pack' {
    It 'packs with the version and lists the packages' {
        $workspace = New-Solution 'pack'
        Set-File (Join-Path $workspace 'dist-nuget' 'Old.0.1.0.nupkg') 'old'

        $result = Invoke-Action 'dotnet-pack' $workspace @{ INPUT_VERSION = 'v1.4.2-ci.7'; STUB_PACKAGES = 'Lib.Core,Lib.Extras' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Dotnet | Should -Match '^pack .*App\.slnx --configuration Release --output .*dist-nuget -p:ContinuousIntegrationBuild=true -p:Version=1\.4\.2-ci\.7'
        $result.Outputs['count'] | Should -Be '2'
        $result.Outputs['destination'] | Should -Be 'dist-nuget'
        ($result.Outputs['packages'] -split "`n") | Should -Be @(
            'dist-nuget/Lib.Core.1.4.2-ci.7.nupkg', 'dist-nuget/Lib.Core.1.4.2-ci.7.snupkg'
            'dist-nuget/Lib.Extras.1.4.2-ci.7.nupkg', 'dist-nuget/Lib.Extras.1.4.2-ci.7.snupkg'
        )
        Join-Path $workspace 'dist-nuget' 'Old.0.1.0.nupkg' | Should -Not -Exist
        $result.Summary | Should -Match 'Packed 2 package'
    }

    It 'accepts build metadata, which package file names leave out' {
        $workspace = New-Solution 'metadata'

        $result = Invoke-Action 'dotnet-pack' $workspace @{ INPUT_VERSION = '2.0.0+sha.abc'; STUB_PACKAGES = 'Lib' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['packages'] | Should -Match 'Lib\.2\.0\.0\.nupkg'
    }

    It 'keeps the projects version when version is empty' {
        $workspace = New-Solution 'noversion'

        $result = Invoke-Action 'dotnet-pack' $workspace @{ STUB_PACKAGES = 'Lib'; STUB_PACKAGE_VERSION = '3.1.0'; INPUT_ARGS = '--include-symbols' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Dotnet | Should -Not -Match 'Version='
        $result.Dotnet.Trim() | Should -Match '--include-symbols$'
    }

    It 'fails when a project sets its own package version' {
        $workspace = New-Solution 'mismatch'

        # The stub names packages after the last -p:Version, as a project's own PackageVersion would win.
        $result = Invoke-Action 'dotnet-pack' $workspace @{ INPUT_VERSION = '1.0.0'; INPUT_ARGS = '-p:Version=9.9.9'; STUB_PACKAGES = 'Lib' }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'do not have version 1\.0\.0: Lib\.9\.9\.9\.nupkg'
    }

    It 'fails when nothing is packable' {
        $workspace = New-Solution 'empty'

        $result = Invoke-Action 'dotnet-pack' $workspace

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'wrote no \.nupkg'
    }

    It 'rejects a version that is not semantic' {
        $workspace = New-Solution 'badversion'

        $result = Invoke-Action 'dotnet-pack' $workspace @{ INPUT_VERSION = '1.2.3.4'; STUB_PACKAGES = 'Lib' }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'not a valid semantic version'
        $result.Dotnet | Should -BeNullOrEmpty
    }
}

Describe 'nuget-push' {
    BeforeAll {
        $script:Packages = New-Workspace 'packages'
        Set-File (Join-Path $Packages 'dist-nuget' 'Lib.1.0.0.nupkg') 'nupkg'
        Set-File (Join-Path $Packages 'dist-nuget' 'Lib.1.0.0.snupkg') 'snupkg'
        Set-File (Join-Path $Packages 'dist-nuget' 'Lib.Extras.1.0.0.nupkg') 'nupkg'
    }

    It 'pushes to GitHub Packages of the owner without symbols' {
        $result = Invoke-Action 'nuget-push' $Packages @{ INPUT_API_KEY = 'secret-key'; GITHUB_REPOSITORY_OWNER = 'Octo-Org' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $lines = $result.Dotnet.Trim() -split '\r?\n'
        $lines.Count | Should -Be 2
        $lines[0] | Should -Match '^nuget push .*Lib\.1\.0\.0\.nupkg --source https://nuget\.pkg\.github\.com/Octo-Org/index\.json --skip-duplicate --no-symbols --api-key secret-key$'
        $result.Log | Should -Match '::add-mask::secret-key'
        $result.Log | Should -Match '--api-key \*\*\*'
        $result.Outputs['published'] | Should -Be 'true'
        $result.Outputs['count'] | Should -Be '2'
        $result.Outputs['source'] | Should -Be 'https://nuget.pkg.github.com/Octo-Org/index.json'
        $result.Summary | Should -Match 'GitHub Packages'
    }

    It 'pushes symbols to nuget.org, and duplicates fail without skip-duplicate' {
        $result = Invoke-Action 'nuget-push' $Packages @{ INPUT_SOURCE = 'nuget.org'; INPUT_API_KEY = 'key'; INPUT_SKIP_DUPLICATE = 'false'; INPUT_PACKAGES = 'dist-nuget/Lib.1.0.0.nupkg' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Dotnet.Trim() | Should -Match '--source https://api\.nuget\.org/v3/index\.json --api-key key$'
        $result.Summary | Should -Match '\| `Lib\.1\.0\.0\.nupkg` \| yes \|'
    }

    It 'lists the pushes on a dry run without a key' {
        $result = Invoke-Action 'nuget-push' $Packages @{ INPUT_SOURCE = 'https://feed.example/v3/index.json'; INPUT_DRY_RUN = 'true' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Dotnet | Should -BeNullOrEmpty
        $result.Log | Should -Match 'Dry run: dotnet nuget push'
        $result.Outputs['published'] | Should -Be 'false'
    }

    It 'fails when the push fails' {
        $result = Invoke-Action 'nuget-push' $Packages @{ INPUT_API_KEY = 'key'; STUB_PUSH_EXIT = '1' }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'Pushing Lib\.1\.0\.0\.nupkg failed with exit code 1'
        $result.Outputs.Keys | Should -Not -Contain 'published'
    }

    It 'fails for <Case>' -ForEach @(
        @{ Case = 'a missing key'; Environment = @{}; Message = "Set 'api-key'" }
        @{ Case = 'an http feed'; Environment = @{ INPUT_SOURCE = 'http://feed.example/index.json'; INPUT_API_KEY = 'k' }; Message = 'must be' }
        @{ Case = 'no packages'; Environment = @{ INPUT_PACKAGES = 'none/*.nupkg'; INPUT_API_KEY = 'k' }; Message = 'matched no .nupkg' }
    ) {
        $result = Invoke-Action 'nuget-push' $Packages $Environment

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
        $result.Dotnet | Should -BeNullOrEmpty
    }
}

Describe 'nuget-feed' {
    BeforeAll {
        function Get-FeedCredential([xml] $Config, [string] $Element) {
            $node = $Config.configuration.packageSourceCredentials.SelectSingleNode($Element)
            @{
                Username = $node.SelectSingleNode("add[@key='Username']").value
                Password = $node.SelectSingleNode("add[@key='ClearTextPassword']").value
            }
        }
    }

    It 'adds GitHub Packages to the user-level config by default' {
        $workspace = New-Workspace 'feed'
        $profileFolder = New-Workspace 'profile'

        $result = Invoke-Action 'nuget-feed' $workspace @{
            APPDATA = $profileFolder; HOME = $profileFolder; GITHUB_REPOSITORY_OWNER = 'Octo-Org'; GITHUB_ACTOR = 'octocat'
        }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $expected = if ($IsWindows) { Join-Path $profileFolder 'NuGet' 'NuGet.Config' } else { Join-Path $profileFolder '.nuget' 'NuGet' 'NuGet.Config' }
        $result.Outputs['config-file'] | Should -Be $expected
        $config = [xml] (Get-Content -Raw $expected)
        $config.configuration.packageSources.add.key | Should -Be 'github'
        $config.configuration.packageSources.add.value | Should -Be 'https://nuget.pkg.github.com/Octo-Org/index.json'
        $credential = Get-FeedCredential $config 'github'
        $credential.Username | Should -Be 'octocat'
        $credential.Password | Should -Be '%NUGET_FEED_TOKEN%'
    }

    It 'updates a repository config, keeping its other settings' {
        $workspace = New-Workspace 'repo'
        Set-File (Join-Path $workspace 'nuget.config') @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="team feed" value="https://old.example/index.json" />
  </packageSources>
  <packageSourceCredentials>
    <team_x0020_feed><add key="Username" value="old" /></team_x0020_feed>
  </packageSourceCredentials>
</configuration>
'@

        $result = Invoke-Action 'nuget-feed' $workspace @{
            INPUT_CONFIG_FILE = 'nuget.config'; INPUT_SOURCES = "team feed=https://new.example/index.json`nlicensing"
            INPUT_USERNAME = 'bot'; INPUT_TOKEN_VARIABLE = 'FEED_PAT'
        }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $config = [xml] (Get-Content -Raw (Join-Path $workspace 'nuget.config'))
        $config.configuration.packageSources.SelectSingleNode('clear') | Should -Not -BeNullOrEmpty
        $config.configuration.packageSources.add.key | Should -Be @('nuget.org', 'team feed')
        $config.configuration.packageSources.SelectSingleNode("add[@key='team feed']").value | Should -Be 'https://new.example/index.json'
        @($config.configuration.packageSourceCredentials.ChildNodes).Count | Should -Be 2
        (Get-FeedCredential $config 'team_x0020_feed').Password | Should -Be '%FEED_PAT%'
        (Get-FeedCredential $config 'licensing').Username | Should -Be 'bot'
        $result.Summary | Should -Match 'from the repository nuget.config'
    }

    It 'fails for <Case>' -ForEach @(
        @{ Case = 'an http feed'; Environment = @{ INPUT_SOURCES = 'x=http://feed.example/index.json' }; Message = "must use https" }
        @{ Case = 'a bad variable name'; Environment = @{ INPUT_TOKEN_VARIABLE = 'MY-TOKEN' }; Message = 'not an environment variable name' }
        @{ Case = 'a config outside the workspace'; Environment = @{ INPUT_CONFIG_FILE = '../nuget.config' }; Message = 'must be inside the workspace' }
        @{ Case = 'an unnamed source'; Environment = @{ INPUT_SOURCES = '=https://feed.example/index.json' }; Message = 'has no name' }
    ) {
        $workspace = New-Workspace 'bad'

        $result = Invoke-Action 'nuget-feed' $workspace $Environment

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
    }
}

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Tests for the CI actions used by node-ci.yml, pwsh-ci.yml and npm-package.yml.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    $script:Actions = Join-Path $PSScriptRoot '..' 'actions'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    $script:Stubs = Join-Path $Fixtures 'cli-stubs'
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

    function Invoke-Action([string] $Name, [string] $Workspace, [hashtable] $Environment = @{}) {
        $Environment['GITHUB_WORKSPACE'] = $Workspace
        Invoke-ActionScript (Join-Path $Actions $Name "$Name.ps1") -Environment $Environment -WorkingDirectory $Workspace
    }
}

Describe 'pwsh-check' {
    BeforeAll {
        $script:AnalyzerVersion = Get-Module -ListAvailable PSScriptAnalyzer | Sort-Object Version -Descending | Select-Object -First 1 |
            ForEach-Object { "$($_.Version)" }
        if (-not $AnalyzerVersion) { $script:AnalyzerVersion = '1.25.0' }
    }

    It 'passes clean files and counts them' {
        $workspace = New-Workspace 'clean'
        Set-File (Join-Path $workspace 'src/Good.ps1') 'Write-Output "ok"'
        Set-File (Join-Path $workspace 'src/Good.psd1') '@{ ModuleVersion = "1.0.0" }'
        Set-File (Join-Path $workspace 'node_modules/pkg/Bad.ps1') 'function {'

        $result = Invoke-Action 'pwsh-check' $workspace

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['files'] | Should -Be '2'
        $result.Outputs['errors'] | Should -Be '0'
    }

    It 'fails on a syntax error with an annotation on its line' {
        $workspace = New-Workspace 'syntax'
        Set-File (Join-Path $workspace 'scripts/Bad.ps1') "Write-Output 'ok'`nfunction Get-Thing {"

        $result = Invoke-Action 'pwsh-check' $workspace

        $result.ExitCode | Should -Not -Be 0
        $result.Outputs['errors'] | Should -Be '1'
        $result.Log | Should -Match '::error file=scripts/Bad\.ps1,line=2,col=\d+::ParseError'
        $result.Summary | Should -Match 'scripts/Bad\.ps1:2'
    }

    It 'skips excluded paths' {
        $workspace = New-Workspace 'exclude'
        Set-File (Join-Path $workspace 'vendor/lib/Bad.ps1') 'function {'
        Set-File (Join-Path $workspace 'Good.ps1') 'Write-Output "ok"'

        $result = Invoke-Action 'pwsh-check' $workspace @{ INPUT_EXCLUDE = './vendor' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['files'] | Should -Be '1'
    }

    It 'checks only the given paths' {
        $workspace = New-Workspace 'paths'
        Set-File (Join-Path $workspace 'tools/Good.ps1') 'Write-Output "ok"'
        Set-File (Join-Path $workspace 'other/Bad.ps1') 'function {'

        $result = Invoke-Action 'pwsh-check' $workspace @{ INPUT_PATHS = 'tools' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['files'] | Should -Be '1'
    }

    It 'fails on analyzer findings' {
        $workspace = New-Workspace 'analyzer'
        Set-File (Join-Path $workspace 'Unused.ps1') "function Get-Thing {`n    `$unused = 1`n    Write-Output 'x'`n}"

        $result = Invoke-Action 'pwsh-check' $workspace @{ INPUT_ANALYZER = 'true'; INPUT_ANALYZER_VERSION = $AnalyzerVersion }

        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match '::error file=Unused\.ps1,line=2,col=\d+::PSUseDeclaredVarsMoreThanAssignments'
    }

    It 'uses an analyzer settings file' {
        $workspace = New-Workspace 'settings'
        Set-File (Join-Path $workspace 'Unused.ps1') "function Get-Thing {`n    `$unused = 1`n    Write-Output 'x'`n}"
        Set-File (Join-Path $workspace 'Settings.psd1') "@{ ExcludeRules = @('PSUseDeclaredVarsMoreThanAssignments') }"

        $result = Invoke-Action 'pwsh-check' $workspace @{
            INPUT_ANALYZER = 'true'; INPUT_ANALYZER_VERSION = $AnalyzerVersion; INPUT_ANALYZER_SETTINGS = 'Settings.psd1'
        }

        $result.ExitCode | Should -Be 0 -Because $result.Log
    }

    It 'rejects a missing path' {
        $result = Invoke-Action 'pwsh-check' (New-Workspace 'missing') @{ INPUT_PATHS = 'nope' }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match "The path 'nope' does not exist"
    }
}

Describe 'pester' {
    BeforeAll {
        # The version this suite runs under is installed, so the action does not download one.
        $script:PesterVersion = "$((Get-Module Pester).Version)"

        function New-ModuleWorkspace {
            $workspace = New-Workspace 'module'
            Copy-Item -Path (Join-Path $Fixtures 'pwsh-module' '*') -Destination $workspace -Recurse
            return $workspace
        }
    }

    It 'runs the tests and writes results and coverage' {
        $workspace = New-ModuleWorkspace

        $result = Invoke-Action 'pester' $workspace @{ INPUT_VERSION = $PesterVersion; INPUT_COVERAGE = 'Fixture.Module.psm1' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['total'] | Should -Be '3'
        $result.Outputs['passed'] | Should -Be '3'
        $result.Outputs['failed'] | Should -Be '0'
        $result.Outputs['results'] | Should -Be 'test-results/pester.xml'
        $result.Outputs['coverage-report'] | Should -Be 'coverage/pester-coverage.xml'
        [double] $result.Outputs['coverage'] | Should -BeGreaterThan 50
        Join-Path $workspace 'test-results/pester.xml' | Should -Exist
        ([xml] (Get-Content (Join-Path $workspace 'coverage/pester-coverage.xml') -Raw)).DocumentElement.LocalName | Should -Be 'report'
        $result.Summary | Should -Match '3 passed, 0 failed, 0 skipped'
    }

    It 'fails when a test fails' {
        $workspace = New-ModuleWorkspace
        Set-File (Join-Path $workspace 'tests/Failing.Tests.ps1') "Describe 'x' { It 'fails' { 1 | Should -Be 2 } }"

        $result = Invoke-Action 'pester' $workspace @{ INPUT_VERSION = $PesterVersion }

        $result.ExitCode | Should -Not -Be 0
        $result.Outputs['failed'] | Should -Be '1'
        Get-Flat $result.Log | Should -Match '1 test\(s\) failed'
    }

    It 'fails when a test file cannot run' {
        $workspace = New-ModuleWorkspace
        Set-File (Join-Path $workspace 'tests/Broken.Tests.ps1') "BeforeAll { throw 'no setup' }`nDescribe 'x' { It 'y' { } }"

        $result = Invoke-Action 'pester' $workspace @{ INPUT_VERSION = $PesterVersion }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'failed to run: tests/Broken\.Tests\.ps1'
    }

    It 'fails when no tests ran unless allow-empty is set' {
        $workspace = New-Workspace 'empty'
        New-Item -ItemType Directory -Path (Join-Path $workspace 'tests') | Out-Null

        $failed = Invoke-Action 'pester' $workspace @{ INPUT_VERSION = $PesterVersion }
        $allowed = Invoke-Action 'pester' $workspace @{ INPUT_VERSION = $PesterVersion; INPUT_ALLOW_EMPTY = 'true' }

        $failed.ExitCode | Should -Not -Be 0
        Get-Flat $failed.Log | Should -Match 'No tests ran in: tests'
        $allowed.ExitCode | Should -Be 0 -Because $allowed.Log
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'a missing test path'; Environment = @{ INPUT_PATH = 'nope' }; Message = "The test path 'nope' does not exist" }
        @{ Name = 'Pester 4'; Environment = @{ INPUT_VERSION = '4.10.1' }; Message = 'Pester 4.10.1 is not supported' }
    ) {
        $result = Invoke-Action 'pester' (New-ModuleWorkspace) $Environment.Clone()

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
    }
}

Describe 'coverage-gate' {
    BeforeAll {
        function New-CoverageWorkspace {
            $workspace = New-Workspace 'coverage'
            Set-File (Join-Path $workspace 'web/coverage/lcov.info') "SF:a.js`nLF:10`nLH:8`nend_of_record"
            Set-File (Join-Path $workspace 'api/coverage.cobertura.xml') '<coverage lines-covered="6" lines-valid="10"/>'
            return $workspace
        }
    }

    It 'combines the reports it finds by default' {
        $result = Invoke-Action 'coverage-gate' (New-CoverageWorkspace)

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['coverage'] | Should -Be '70'
        $result.Outputs['covered'] | Should -Be '14'
        $result.Outputs['total'] | Should -Be '20'
        $result.Outputs['passed'] | Should -Be 'true'
        $result.Summary | Should -Match 'web/coverage/lcov\.info'
        $result.Summary | Should -Match 'api/coverage\.cobertura\.xml'
    }

    It 'passes at the minimum' {
        $result = Invoke-Action 'coverage-gate' (New-CoverageWorkspace) @{ INPUT_MINIMUM = '70' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Summary | Should -Match 'meets the 70% minimum'
    }

    It 'fails below the minimum' {
        $result = Invoke-Action 'coverage-gate' (New-CoverageWorkspace) @{ INPUT_MINIMUM = '75.5' }

        $result.ExitCode | Should -Not -Be 0
        $result.Outputs['passed'] | Should -Be 'false'
        Get-Flat $result.Log | Should -Match 'Line coverage 70% is below the 75\.5% minimum'
    }

    It 'reads only the given reports' {
        $result = Invoke-Action 'coverage-gate' (New-CoverageWorkspace) @{ INPUT_REPORTS = 'web/coverage/lcov.info'; INPUT_MINIMUM = '80' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['coverage'] | Should -Be '80'
    }

    It 'finds reports under the working directory' {
        $result = Invoke-Action 'coverage-gate' (New-CoverageWorkspace) @{ INPUT_WORKING_DIRECTORY = 'web' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['coverage'] | Should -Be '80'
        $result.Summary | Should -Match 'web/coverage/lcov\.info'
    }

    It 'warns when no report is found and there is no minimum' {
        $result = Invoke-Action 'coverage-gate' (New-Workspace 'none')

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Log | Should -Match '::warning::No coverage report found'
        $result.Outputs['coverage'] | Should -Be ''
    }

    It 'fails when no report is found and a minimum is set' {
        $result = Invoke-Action 'coverage-gate' (New-Workspace 'none') @{ INPUT_MINIMUM = '50' }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'a report is required'
    }

    It 'rejects the minimum <Minimum>' -ForEach @(@{ Minimum = 'high' }, @{ Minimum = '101' }) {
        $result = Invoke-Action 'coverage-gate' (New-CoverageWorkspace) @{ INPUT_MINIMUM = $Minimum }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match 'must be a number from 0 to 100'
    }
}

Describe 'test-report' {
    BeforeAll {
        function New-ResultsWorkspace {
            $workspace = New-Workspace 'results'
            Set-File (Join-Path $workspace 'test-results/junit.xml') ('<testsuites><testsuite name="s"><testcase name="passes"/>' +
                '<testcase name="fails"><failure message="expected 1 | got 2"/></testcase><testcase name="skips"><skipped/></testcase></testsuite></testsuites>')
            Set-File (Join-Path $workspace 'test-results/pester.xml') ('<test-results><test-suite><results>' +
                '<test-case name="Module.works" executed="True" result="Success"/></results></test-suite></test-results>')
            return $workspace
        }
    }

    It 'summarises the results and annotates failures without failing' {
        $result = Invoke-Action 'test-report' (New-ResultsWorkspace) @{ INPUT_RESULTS = 'test-results/*.xml' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['total'] | Should -Be '4'
        $result.Outputs['passed'] | Should -Be '2'
        $result.Outputs['failed'] | Should -Be '1'
        $result.Outputs['skipped'] | Should -Be '1'
        $result.Summary | Should -Match '2 passed, 1 failed, 1 skipped \(4 total\)'
        $result.Summary | Should -Match ([regex]::Escape('| fails | expected 1 \| got 2 |'))
        $result.Log | Should -Match '::error title=Tests::fails: expected 1 \| got 2'
    }

    It 'fails on failed tests when fail-on-failure is set' {
        $result = Invoke-Action 'test-report' (New-ResultsWorkspace) @{ INPUT_RESULTS = '**/junit.xml'; INPUT_FAIL_ON_FAILURE = 'true' }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match '1 test\(s\) failed'
    }

    It 'reads results relative to the working directory' {
        $result = Invoke-Action 'test-report' (New-ResultsWorkspace) @{ INPUT_RESULTS = 'pester.xml'; INPUT_WORKING_DIRECTORY = 'test-results' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['total'] | Should -Be '1'
        $result.Summary | Should -Match 'test-results/pester\.xml'
    }

    It 'does not annotate when annotate is off' {
        $result = Invoke-Action 'test-report' (New-ResultsWorkspace) @{ INPUT_RESULTS = '**/junit.xml'; INPUT_ANNOTATE = 'false' }

        $result.Log | Should -Not -Match '::error'
    }

    It 'warns when no results are found, or fails when fail-on-missing is set' {
        $workspace = New-Workspace 'none'

        $warned = Invoke-Action 'test-report' $workspace @{ INPUT_RESULTS = '**/junit.xml' }
        $failed = Invoke-Action 'test-report' $workspace @{ INPUT_RESULTS = '**/junit.xml'; INPUT_FAIL_ON_MISSING = 'true' }

        $warned.ExitCode | Should -Be 0 -Because $warned.Log
        $warned.Log | Should -Match '::warning::No test results found'
        $failed.ExitCode | Should -Not -Be 0
    }
}

Describe 'check-clean' {
    BeforeAll {
        function New-CleanRepository {
            $path = New-GitRepository (Join-Path $TestDrive "repo-$([guid]::NewGuid().ToString('n'))")
            Set-File (Join-Path $path 'src/a.txt') 'a'
            Set-File (Join-Path $path 'docs/b.txt') 'b'
            git -C $path add -A
            git -C $path commit --quiet -m 'files'
            return $path
        }
    }

    It 'passes a clean working tree' {
        $result = Invoke-Action 'check-clean' (New-CleanRepository)

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['clean'] | Should -Be 'true'
    }

    It 'fails on <Name> and lists the file' -ForEach @(
        @{ Name = 'a modified file'; File = 'src/a.txt' }
        @{ Name = 'an untracked file'; File = 'src/new.txt' }
    ) {
        $workspace = New-CleanRepository
        Set-File (Join-Path $workspace $File) 'changed'

        $result = Invoke-Action 'check-clean' $workspace

        $result.ExitCode | Should -Not -Be 0
        $result.Outputs['clean'] | Should -Be 'false'
        $result.Summary | Should -Match ([regex]::Escape($File))
    }

    It 'checks only the given paths' {
        $workspace = New-CleanRepository
        Set-File (Join-Path $workspace 'docs/b.txt') 'changed'

        $result = Invoke-Action 'check-clean' $workspace @{ INPUT_PATHS = 'src' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
    }
}

Describe 'needs-gate' {
    It 'passes when every job <Name>' -ForEach @(
        @{ Name = 'succeeded'; Needs = '{"test":{"result":"success","outputs":{}},"lint":{"result":"success","outputs":{}}}' }
        @{ Name = 'succeeded or was skipped'; Needs = '{"test":{"result":"success"},"deploy":{"result":"skipped"}}' }
    ) {
        $result = Invoke-Action 'needs-gate' (New-Workspace 'gate') @{ INPUT_NEEDS = $Needs }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['result'] | Should -Be 'success'
    }

    It 'fails when <Name>' -ForEach @(
        @{ Name = 'a job failed'; Needs = '{"test":{"result":"failure"},"lint":{"result":"success"}}'; Environment = @{}; Message = 'test (failure)' }
        @{ Name = 'a job was cancelled'; Needs = '{"test":{"result":"cancelled"}}'; Environment = @{}; Message = 'test (cancelled)' }
        @{ Name = 'a job was skipped and skips are not allowed'; Needs = '{"test":{"result":"skipped"}}'; Environment = @{ INPUT_ALLOW_SKIPPED = 'false' }; Message = 'test (skipped)' }
    ) {
        $environment = $Environment.Clone()
        $environment['INPUT_NEEDS'] = $Needs

        $result = Invoke-Action 'needs-gate' (New-Workspace 'gate') $environment

        $result.ExitCode | Should -Not -Be 0
        $result.Outputs['result'] | Should -Be 'failure'
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'invalid JSON'; Needs = 'nope'; Message = 'not valid JSON' }
        @{ Name = 'no jobs'; Needs = '{}'; Message = 'has no jobs' }
    ) {
        $result = Invoke-Action 'needs-gate' (New-Workspace 'gate') @{ INPUT_NEEDS = $Needs }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match $Message
    }
}

Describe 'npm-pack' {
    BeforeAll {
        function New-PackageWorkspace {
            $workspace = New-Workspace 'pack'
            Copy-Item -Path (Join-Path $Fixtures 'npm-lib') -Destination (Join-Path $workspace 'lib') -Recurse
            return $workspace
        }
    }

    It 'packs the package.json version' {
        $workspace = New-PackageWorkspace

        $result = Invoke-Action 'npm-pack' $workspace @{ INPUT_PATH = 'lib' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['tarball'] | Should -Be 'dist-package/fixture-npm-lib-2.3.4.tgz'
        $result.Outputs['name'] | Should -Be 'fixture-npm-lib'
        $result.Outputs['version'] | Should -Be '2.3.4'
        Join-Path $workspace 'dist-package/fixture-npm-lib-2.3.4.tgz' | Should -Exist
    }

    It 'stamps the given version' {
        $workspace = New-PackageWorkspace

        $result = Invoke-Action 'npm-pack' $workspace @{ INPUT_PATH = 'lib'; INPUT_VERSION = 'v2.4.0-ci.42'; INPUT_DESTINATION = 'out' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['tarball'] | Should -Be 'out/fixture-npm-lib-2.4.0-ci.42.tgz'
        (Get-Content (Join-Path $workspace 'lib/package.json') -Raw | ConvertFrom-Json).version | Should -Be '2.4.0-ci.42'
    }

    It 'shows the output of a prepack script and still reads the JSON' {
        $workspace = New-PackageWorkspace
        $manifest = Get-Content (Join-Path $workspace 'lib/package.json') -Raw | ConvertFrom-Json -AsHashtable
        $manifest.scripts['prepack'] = 'node -e "console.log(String.fromCharCode(91)); console.log(\"built\")"'
        $manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $workspace 'lib/package.json')

        $result = Invoke-Action 'npm-pack' $workspace @{ INPUT_PATH = 'lib' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Log | Should -Match 'built'
        $result.Outputs['version'] | Should -Be '2.3.4'
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'an invalid version'; Environment = @{ INPUT_PATH = 'lib'; INPUT_VERSION = 'next' }; Message = "'next' is not a valid semantic version" }
        @{ Name = 'a folder without package.json'; Environment = @{ INPUT_PATH = 'missing' }; Message = "The path 'missing' has no package.json" }
    ) {
        $result = Invoke-Action 'npm-pack' (New-PackageWorkspace) $Environment.Clone()

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
    }
}

Describe 'npm-publish' {
    BeforeAll {
        # Real tarballs from the npm-lib fixture: a release and a prerelease.
        $script:Packed = New-Workspace 'packed'
        $lib = Join-Path $Packed 'lib'
        Copy-Item -Path (Join-Path $Fixtures 'npm-lib') -Destination $lib -Recurse
        New-Item -ItemType Directory -Path (Join-Path $Packed 'release'), (Join-Path $Packed 'prerelease') | Out-Null
        Push-Location $lib
        try {
            npm pack --pack-destination (Join-Path $Packed 'release') --silent | Out-Null
            npm version 3.0.0-rc.1 --no-git-tag-version --ignore-scripts | Out-Null
            npm pack --pack-destination (Join-Path $Packed 'prerelease') --silent | Out-Null
        }
        finally { Pop-Location }

        function Invoke-Publish([hashtable] $Environment) {
            $log = New-Workspace 'log'
            $Environment['PATH'] = "$Stubs$([System.IO.Path]::PathSeparator)$env:PATH"
            $Environment['STUB_LOG'] = $log
            if (-not $Environment.ContainsKey('NODE_AUTH_TOKEN')) { $Environment['NODE_AUTH_TOKEN'] = '' }
            $result = Invoke-Action 'npm-publish' $Packed $Environment
            $npm = Join-Path $log 'npm.txt'
            $result | Add-Member -NotePropertyName Npm -NotePropertyValue $(if (Test-Path $npm) { Get-Content $npm -Raw } else { '' }) -PassThru
        }
    }

    It 'publishes a release under latest with provenance' {
        $result = Invoke-Publish @{ INPUT_TARBALL = 'release/*.tgz'; NODE_AUTH_TOKEN = 'secret-token' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Npm | Should -Match 'ARGS: publish .*fixture-npm-lib-2\.3\.4\.tgz --registry https://registry\.npmjs\.org/ --tag latest --provenance --userconfig'
        $result.Npm | Should -Match ([regex]::Escape('CONFIG: //registry.npmjs.org/:_authToken=${NODE_AUTH_TOKEN}'))
        $result.Npm | Should -Not -Match 'secret-token'
        $result.Npm | Should -Match 'TOKEN: set'
        $result.Outputs['dist-tag'] | Should -Be 'latest'
        $result.Outputs['published'] | Should -Be 'true'
    }

    It 'publishes a prerelease under next' {
        $result = Invoke-Publish @{ INPUT_TARBALL = 'prerelease/fixture-npm-lib-3.0.0-rc.1.tgz'; INPUT_PROVENANCE = 'false' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Npm | Should -Match '--tag next'
        $result.Npm | Should -Not -Match '--provenance'
        $result.Npm | Should -Not -Match '_authToken'
        $result.Log | Should -Match 'trusted publishing'
        $result.Outputs['version'] | Should -Be '3.0.0-rc.1'
    }

    It 'publishes to GitHub Packages without provenance' {
        $result = Invoke-Publish @{ INPUT_TARBALL = 'release/*.tgz'; INPUT_REGISTRY = 'https://npm.pkg.github.com'; INPUT_ACCESS = 'restricted'; NODE_AUTH_TOKEN = 't' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Npm | Should -Match '--registry https://npm\.pkg\.github\.com/ --tag latest --access restricted --userconfig'
        $result.Npm | Should -Match ([regex]::Escape('CONFIG: //npm.pkg.github.com/:_authToken=${NODE_AUTH_TOKEN}'))
        $result.Log | Should -Match 'does not support npm provenance'
    }

    It 'passes dry-run and an explicit dist-tag' {
        $result = Invoke-Publish @{ INPUT_TARBALL = 'release/*.tgz'; INPUT_DRY_RUN = 'true'; INPUT_DIST_TAG = 'beta'; INPUT_PROVENANCE = 'false' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Npm | Should -Match '--tag beta --dry-run'
        $result.Outputs['published'] | Should -Be 'false'
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'a pattern matching two tarballs'; Environment = @{ INPUT_TARBALL = '**/*.tgz' }; Message = 'matched 2 files' }
        @{ Name = 'a missing tarball'; Environment = @{ INPUT_TARBALL = 'nope.tgz' }; Message = 'matched 0 files' }
        @{ Name = 'an unknown access'; Environment = @{ INPUT_TARBALL = 'release/*.tgz'; INPUT_ACCESS = 'open' }; Message = "access 'open'" }
        @{ Name = 'an http registry'; Environment = @{ INPUT_TARBALL = 'release/*.tgz'; INPUT_REGISTRY = 'http://example.com' }; Message = 'must be an https:// URL' }
    ) {
        $result = Invoke-Publish $Environment.Clone()

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
        $result.Npm | Should -BeNullOrEmpty
    }
}

Describe 'github-release' {
    BeforeAll {
        function New-ReleaseWorkspace([switch] $NoChangelog) {
            $workspace = New-Workspace 'release'
            if (-not $NoChangelog) {
                Set-File (Join-Path $workspace 'CHANGELOG.md') "# Changelog`n`n## [1.2.0] - 2026-10-01`n`n- Added a thing.`n`n## [1.1.0] - 2026-09-01`n`n- Older."
            }
            Set-File (Join-Path $workspace 'dist/app-1.2.0.tgz') 'tarball'
            return $workspace
        }

        function Invoke-Release([string] $Workspace, [hashtable] $Environment) {
            $log = New-Workspace 'log'
            $Environment['PATH'] = "$Stubs$([System.IO.Path]::PathSeparator)$env:PATH"
            $Environment['STUB_LOG'] = $log
            if (-not $Environment.ContainsKey('STUB_RELEASE_EXISTS')) { $Environment['STUB_RELEASE_EXISTS'] = 'false' }
            $result = Invoke-Action 'github-release' $Workspace $Environment
            $gh = Join-Path $log 'gh.txt'
            $result | Add-Member -NotePropertyName Gh -NotePropertyValue $(if (Test-Path $gh) { Get-Content $gh -Raw } else { '' }) -PassThru
        }
    }

    It 'creates the release for the pushed tag with CHANGELOG notes and files' {
        $result = Invoke-Release (New-ReleaseWorkspace) @{ GITHUB_REF_TYPE = 'tag'; GITHUB_REF_NAME = 'v1.2.0'; INPUT_FILES = 'dist/*.tgz' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Gh | Should -Match 'release create v1\.2\.0 \S+app-1\.2\.0\.tgz --repo Octo-Org/Sample\.Repo --verify-tag --title v1\.2\.0 --notes-file'
        $result.Gh | Should -Match 'NOTES: - Added a thing\.'
        $result.Gh | Should -Not -Match 'Older'
        $result.Gh | Should -Not -Match '--prerelease'
        $result.Outputs['created'] | Should -Be 'true'
        $result.Outputs['url'] | Should -Be 'https://github.com/Octo-Org/Sample.Repo/releases/tag/v1.2.0'
    }

    It 'marks a prerelease tag as a prerelease and generates notes without a CHANGELOG' {
        $result = Invoke-Release (New-ReleaseWorkspace -NoChangelog) @{ INPUT_TAG = 'v2.0.0-rc.1'; INPUT_TITLE = 'Two' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Gh | Should -Match 'release create v2\.0\.0-rc\.1 --repo Octo-Org/Sample\.Repo --verify-tag --title Two --generate-notes --prerelease'
    }

    It 'updates an existing release' {
        $result = Invoke-Release (New-ReleaseWorkspace) @{ INPUT_TAG = 'v1.2.0'; INPUT_FILES = 'dist/*.tgz'; STUB_RELEASE_EXISTS = 'true' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Gh | Should -Match 'release edit v1\.2\.0 --repo Octo-Org/Sample\.Repo --notes-file'
        $result.Gh | Should -Match 'release upload v1\.2\.0 \S+app-1\.2\.0\.tgz --repo Octo-Org/Sample\.Repo --clobber'
        $result.Gh | Should -Not -Match 'release create'
        $result.Outputs['created'] | Should -Be 'false'
    }

    It 'fails before publishing when <Name>' -ForEach @(
        @{ Name = 'the CHANGELOG has no section for the version'; Environment = @{ INPUT_TAG = 'v9.9.9' }; Message = "no '## [9.9.9]' section" }
        @{ Name = 'a file pattern matches nothing'; Environment = @{ INPUT_TAG = 'v1.2.0'; INPUT_FILES = 'missing/*.zip' }; Message = 'No files found to attach' }
        @{ Name = 'there is no tag'; Environment = @{}; Message = "Set 'tag', or run on a tag push" }
    ) {
        $result = Invoke-Release (New-ReleaseWorkspace) $Environment.Clone()

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
        $result.Gh | Should -BeNullOrEmpty
    }
}

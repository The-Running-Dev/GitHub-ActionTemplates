#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Tests for the actions pages.yml uses. gh is a stub (tests/fixtures/cli-stubs); self-test.yml
# builds tests/fixtures/pages-app with the real workflow.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    $script:Actions = Join-Path $PSScriptRoot '..' 'actions'
    $script:Stubs = Join-Path $PSScriptRoot 'fixtures' 'cli-stubs'

    function New-Workspace([string] $Name) {
        $path = Join-Path $TestDrive "$Name-$([guid]::NewGuid().ToString('n'))"
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        return $path
    }

    function Set-File([string] $Path, [string] $Text) {
        New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
        Set-Content -LiteralPath $Path -Value $Text
    }

    # Runs an action with the gh stub first on the PATH; the result carries the stub's log and
    # the variables the action exported through GITHUB_ENV.
    function Invoke-Action([string] $Name, [hashtable] $Environment = @{}, [string] $Workspace = (New-Workspace $Name)) {
        $log = New-Workspace 'log'
        $envFile = Join-Path $log 'github-env'
        New-Item -ItemType File -Path $envFile | Out-Null
        $Environment['GITHUB_WORKSPACE'] = $Workspace
        $Environment['GITHUB_ENV'] = $envFile
        $Environment['STUB_LOG'] = $log
        $Environment['PATH'] = "$Stubs$([System.IO.Path]::PathSeparator)$env:PATH"
        $result = Invoke-ActionScript (Join-Path $Actions $Name "$Name.ps1") -Environment $Environment -WorkingDirectory $Workspace
        $gh = Join-Path $log 'gh.txt'
        $result | Add-Member -NotePropertyName Gh -NotePropertyValue $(if (Test-Path $gh) { Get-Content $gh -Raw } else { '' })
        $result | Add-Member -NotePropertyName Env -NotePropertyValue (ConvertFrom-ActionOutputFile $envFile) -PassThru
    }
}

Describe 'pages-env' {
    It 'falls back to the github.io address without Pages settings' {
        $result = Invoke-Action 'pages-env'

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Gh | Should -Match 'api repos/Octo-Org/Sample\.Repo/pages --jq \.html_url'
        $result.Outputs['url'] | Should -Be 'https://octo-org.github.io/Sample.Repo/'
        $result.Outputs['origin'] | Should -Be 'https://octo-org.github.io'
        $result.Outputs['base-path'] | Should -Be '/Sample.Repo/'
        $result.Env['PAGES_URL'] | Should -Be 'https://octo-org.github.io/Sample.Repo/'
        $result.Env['PAGES_ORIGIN'] | Should -Be 'https://octo-org.github.io'
        $result.Env['PAGES_BASE_PATH'] | Should -Be '/Sample.Repo/'
        $result.Log | Should -Match 'default github\.io address'
    }

    It 'serves a user or organisation site from the root' {
        $result = Invoke-Action 'pages-env' @{ GITHUB_REPOSITORY = 'Octo-Org/octo-org.github.io' }

        $result.Outputs['url'] | Should -Be 'https://octo-org.github.io/'
        $result.Outputs['base-path'] | Should -Be '/'
    }

    It 'reads a custom domain from the Pages settings' {
        $result = Invoke-Action 'pages-env' @{ STUB_PAGES_URL = 'https://www.example.com/' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['url'] | Should -Be 'https://www.example.com/'
        $result.Outputs['origin'] | Should -Be 'https://www.example.com'
        $result.Outputs['base-path'] | Should -Be '/'
    }

    It 'normalises the base-path input <Value>' -ForEach @(
        @{ Value = 'docs'; Expected = '/docs/' }
        @{ Value = '/docs'; Expected = '/docs/' }
        @{ Value = '/a/b/'; Expected = '/a/b/' }
        @{ Value = '/'; Expected = '/' }
    ) {
        $result = Invoke-Action 'pages-env' @{ STUB_PAGES_URL = 'https://octo-org.github.io/Sample.Repo/'; INPUT_BASE_PATH = $Value }

        $result.Outputs['base-path'] | Should -Be $Expected
        $result.Outputs['url'] | Should -Be "https://octo-org.github.io$Expected"
        $result.Env['PAGES_BASE_PATH'] | Should -Be $Expected
    }

    It 'exports the build variables and masks the secret ones' {
        $result = Invoke-Action 'pages-env' @{
            INPUT_ENV        = "VITE_API_URL=https://api.example.com/v1?x=1`n# comment`n`nEMPTY="
            INPUT_SECRET_ENV = "VITE_KEY=s3cr3t=value`r`nOTHER=two"
        }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Env['VITE_API_URL'] | Should -Be 'https://api.example.com/v1?x=1'
        $result.Env['EMPTY'] | Should -Be ''
        $result.Env['VITE_KEY'] | Should -Be 's3cr3t=value'
        $result.Env['OTHER'] | Should -Be 'two'
        $result.Log | Should -Match '::add-mask::s3cr3t=value'
        $result.Log | Should -Match '::add-mask::two'
        $result.Log | Should -Not -Match '::add-mask::https'
        $result.Summary | Should -Match 'VITE_API_URL'
        $result.Summary | Should -Not -Match 's3cr3t'
    }

    It 'rejects a line that is not KEY=value without echoing it' {
        $result = Invoke-Action 'pages-env' @{ INPUT_SECRET_ENV = "OK=1`nnot a variable s3cr3t" }

        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match "Line 2 of 'secret-env' is not KEY=value"
        $result.Log | Should -Not -Match 's3cr3t'
    }

    It 'rejects the reserved variable <Name>' -ForEach @(
        @{ Name = 'GITHUB_TOKEN' }
        @{ Name = 'NODE_OPTIONS' }
        @{ Name = 'PAGES_BASE_PATH' }
        @{ Name = 'path' }
    ) {
        $result = Invoke-Action 'pages-env' @{ INPUT_ENV = "$Name=x" }

        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match "variable '$Name' is reserved"
    }
}

Describe 'pages-check' {
    It 'checks a built site and reports its size' {
        $workspace = New-Workspace 'site'
        Set-File (Join-Path $workspace 'app' 'dist' 'index.html') '<p>home</p>'
        Set-File (Join-Path $workspace 'app' 'dist' 'assets' 'app.js') 'console.log(1)'

        $result = Invoke-Action 'pages-check' @{ INPUT_PATH = 'dist'; INPUT_WORKING_DIRECTORY = 'app' } $workspace

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['path'] | Should -Be 'app/dist'
        $result.Outputs['files'] | Should -Be '2'
        [long] $result.Outputs['size'] | Should -BeGreaterThan 0
        $result.Summary | Should -Match 'Site `app/dist`: 2 file\(s\)'
        Join-Path $workspace 'app' 'dist' '404.html' | Should -Not -Exist
    }

    It 'copies index.html to 404.html for a single-page app' {
        $workspace = New-Workspace 'spa'
        Set-File (Join-Path $workspace 'dist' 'index.html') '<div id="app"></div>'

        $result = Invoke-Action 'pages-check' @{ INPUT_PATH = 'dist'; INPUT_SPA = 'true' } $workspace

        $result.ExitCode | Should -Be 0 -Because $result.Log
        Get-Content (Join-Path $workspace 'dist' '404.html') -Raw | Should -Match 'id="app"'
        $result.Outputs['files'] | Should -Be '2'
    }

    It 'keeps an existing 404.html' {
        $workspace = New-Workspace 'own-404'
        Set-File (Join-Path $workspace 'dist' 'index.html') 'home'
        Set-File (Join-Path $workspace 'dist' '404.html') 'custom'

        $result = Invoke-Action 'pages-check' @{ INPUT_PATH = 'dist'; INPUT_SPA = 'true' } $workspace

        $result.ExitCode | Should -Be 0 -Because $result.Log
        (Get-Content (Join-Path $workspace 'dist' '404.html') -Raw).Trim() | Should -Be 'custom'
    }

    It 'warns when the site has no index.html' {
        $workspace = New-Workspace 'no-index'
        Set-File (Join-Path $workspace 'dist' 'other.html') 'x'

        $result = Invoke-Action 'pages-check' @{ INPUT_PATH = 'dist' } $workspace

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Log | Should -Match "::warning::'dist' has no index\.html"
    }

    It 'fails <Name>' -ForEach @(
        @{ Name = 'for a missing folder'; Files = @(); Environment = @{ INPUT_PATH = 'dist' }; Message = 'does not exist' }
        @{ Name = 'for an empty folder'; Files = @('dist/'); Environment = @{ INPUT_PATH = 'dist' }; Message = 'is empty' }
        @{ Name = 'for a single-page app without index.html'; Files = @('dist/a.html'); Environment = @{ INPUT_PATH = 'dist'; INPUT_SPA = 'true' }; Message = 'no index\.html' }
        @{ Name = 'for a folder outside the workspace'; Files = @(); Environment = @{ INPUT_PATH = '../elsewhere' }; Message = 'must be inside the workspace' }
    ) {
        $workspace = New-Workspace 'bad'
        foreach ($file in $Files) {
            $full = Join-Path $workspace $file
            if ($file.EndsWith('/')) { New-Item -ItemType Directory -Path $full -Force | Out-Null } else { Set-File $full 'x' }
        }

        $result = Invoke-Action 'pages-check' $Environment.Clone() $workspace

        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match $Message
    }
}

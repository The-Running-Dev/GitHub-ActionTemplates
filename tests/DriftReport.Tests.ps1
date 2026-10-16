#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Tests for the drift-report action. gh is a stub (tests/fixtures/cli-stubs) serving canned API
# responses from a folder.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    $script:Script = Join-Path $PSScriptRoot '..' 'actions' 'drift-report' 'drift-report.ps1'
    $script:Stubs = Join-Path $PSScriptRoot 'fixtures' 'cli-stubs'

    $script:ShaA = 'a' * 40
    $script:ShaB = 'b' * 40
    $script:ShaC = 'c' * 40
    $script:ShaD = 'd' * 40
    $script:ShaMain = 'e' * 40

    function New-Folder([string] $Name) {
        $path = Join-Path $TestDrive "$Name-$([guid]::NewGuid().ToString('n'))"
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        return $path
    }

    function Set-ApiFile([string] $Api, [string] $Path, $Value) {
        $file = Join-Path $Api $Path
        New-Item -ItemType Directory -Path (Split-Path $file) -Force | Out-Null
        $text = if ($Value -is [string]) { $Value } else { ConvertTo-Json -InputObject $Value -Depth 8 }
        Set-Content -LiteralPath $file -Value $text
    }

    function New-Repository([string] $Name, [switch] $Fork, [switch] $Archived) {
        @{ full_name = $Name; fork = [bool] $Fork; archived = [bool] $Archived }
    }

    function Set-WorkflowFile([string] $Api, [string] $Repository, [hashtable] $Files) {
        $listing = @($Files.Keys | Sort-Object | ForEach-Object { @{ name = $_; path = ".github/workflows/$_"; type = 'file' } })
        $listing += @{ name = 'templates'; path = '.github/workflows/templates'; type = 'dir' }
        Set-ApiFile $Api "repos/$Repository/contents/.github/workflows.json" $listing
        foreach ($name in $Files.Keys) { Set-ApiFile $Api "repos/$Repository/contents/.github/workflows/$name" $Files[$name] }
    }

    # Library Octo-Org/Templates with releases v1.0.0 (a), v1.1.0 (b), v1.2.0 (c), the moving tag
    # v1 at v1.2.0, a pre-release at d and the branch main at e.
    function New-Api([string] $Type = 'User', [string] $Viewer = 'Octo-Org') {
        $api = New-Folder 'api'
        Set-ApiFile $api 'repos/Octo-Org/Templates/tags.json' @(
            @{ name = 'v1.3.0-rc.1'; commit = @{ sha = $ShaD } }
            @{ name = 'v1.2.0'; commit = @{ sha = $ShaC } }
            @{ name = 'v1'; commit = @{ sha = $ShaC } }
            @{ name = 'v1.1.0'; commit = @{ sha = $ShaB } }
            @{ name = 'v1.0.0'; commit = @{ sha = $ShaA } }
        )
        Set-ApiFile $api 'repos/Octo-Org/Templates/commits/main.json' @{ sha = $ShaMain }
        Set-ApiFile $api 'users/Octo-Org.json' @{ login = 'Octo-Org'; type = $Type }
        if ($Viewer) { Set-ApiFile $api 'user.json' @{ login = $Viewer } }

        $repositories = @(
            New-Repository 'Octo-Org/App'
            New-Repository 'Octo-Org/Legacy'
            New-Repository 'Octo-Org/Old'
            New-Repository 'Octo-Org/Plain'
            New-Repository 'Octo-Org/Forked' -Fork
            New-Repository 'Octo-Org/Retired' -Archived
        )
        $listing = switch ($Type) { 'Organization' { 'orgs/Octo-Org/repos.json' } default { if ($Viewer -eq 'Octo-Org') { 'user/repos.json' } else { 'users/Octo-Org/repos.json' } } }
        Set-ApiFile $api $listing $repositories

        Set-WorkflowFile $api 'Octo-Org/App' @{
            'ci.yml' = @'
jobs:
  build:
    uses: Octo-Org/Templates/.github/workflows/dotnet.yml@v1 # pinned to the major
  check:
    steps:
      - uses: 'octo-org/templates/actions/version@v1'
      - uses: Octo-Org/Templates-Other/actions/x@v0
      - uses: actions/checkout@v5
'@
        }
        Set-WorkflowFile $api 'Octo-Org/Old' @{
            'release.yml' = "jobs:`n  r:`n    uses: Octo-Org/Templates/.github/workflows/npm-package.yml@v1.0.0`n"
            'nightly.yaml' = "jobs:`n  n:`n    steps:`n      - uses: Octo-Org/Templates/actions/context@main`n      - uses: `"Octo-Org/Templates/actions/debug@$ShaB`"`n      - uses: Octo-Org/Templates/actions/gates@$ShaD`n      - uses: Octo-Org/Templates/actions/gates@v9`n"
        }
        Set-WorkflowFile $api 'Octo-Org/Legacy' @{ 'build.yml' = "jobs:`n  b:`n    steps:`n      - uses: actions/checkout@v5`n" }
        Set-WorkflowFile $api 'Octo-Org/Retired' @{ 'ci.yml' = "jobs:`n  r:`n    uses: Octo-Org/Templates/.github/workflows/dotnet.yml@v1.0.0`n" }
        return $api
    }

    function Invoke-Drift([string] $Api, [hashtable] $Environment = @{}) {
        $workspace = New-Folder 'workspace'
        $log = New-Folder 'log'
        $Environment['GITHUB_WORKSPACE'] = $workspace
        $Environment['STUB_LOG'] = $log
        $Environment['STUB_API_DIR'] = $Api
        $Environment['PATH'] = "$Stubs$([System.IO.Path]::PathSeparator)$env:PATH"
        if (-not $Environment.ContainsKey('INPUT_LIBRARY') -and -not $Environment.ContainsKey('GITHUB_ACTION_REPOSITORY')) { $Environment['INPUT_LIBRARY'] = 'Octo-Org/Templates' }

        $result = Invoke-ActionScript $Script -Environment $Environment -WorkingDirectory $workspace
        $gh = Join-Path $log 'gh.txt'
        $result | Add-Member -NotePropertyName Gh -NotePropertyValue $(if (Test-Path $gh) { Get-Content $gh -Raw } else { '' })
        $result | Add-Member -NotePropertyName Workspace -NotePropertyValue $workspace -PassThru
    }
}

Describe 'drift-report' {
    It 'reports the ref each workflow pins and how far it is behind' {
        $result = Invoke-Drift (New-Api) @{ INPUT_REPORT = 'out/drift.json' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['latest'] | Should -Be 'v1.2.0'
        $result.Outputs['repositories'] | Should -Be '4'
        $result.Outputs['references'] | Should -Be '6'
        $result.Outputs['current'] | Should -Be '1'
        $result.Outputs['drifted'] | Should -Be '5'

        $report = Get-Content (Join-Path $result.Workspace 'out' 'drift.json') -Raw | ConvertFrom-Json
        $report.library | Should -Be 'Octo-Org/Templates'
        $report.latest | Should -Be 'v1.2.0'
        $report.repositories | Should -Be @('Octo-Org/App', 'Octo-Org/Legacy', 'Octo-Org/Old', 'Octo-Org/Plain')
        $report.unused | Should -Be @('Octo-Org/Legacy')
        $byRef = @{}
        foreach ($entry in $report.references) { $byRef["$($entry.repository) $($entry.ref)"] = $entry }

        $app = $byRef['Octo-Org/App v1']
        $app.status | Should -Be 'current'
        $app.version | Should -Be 'v1.2.0'
        $app.workflow | Should -Be '.github/workflows/ci.yml'
        $app.uses | Should -Be @('.github/workflows/dotnet.yml', 'actions/version')

        $byRef['Octo-Org/Old v1.0.0'].status | Should -Be 'behind'
        $byRef['Octo-Org/Old v1.0.0'].behind | Should -Be 2
        $byRef["Octo-Org/Old $ShaB"].status | Should -Be 'behind'
        $byRef["Octo-Org/Old $ShaB"].version | Should -Be 'v1.1.0'
        $byRef["Octo-Org/Old $ShaB"].behind | Should -Be 1
        $byRef['Octo-Org/Old main'].status | Should -Be 'branch'
        $byRef['Octo-Org/Old main'].sha | Should -Be $ShaMain
        $byRef["Octo-Org/Old $ShaD"].status | Should -Be 'unreleased'
        $byRef['Octo-Org/Old v9'].status | Should -Be 'unknown'
        $report.references[0].status | Should -Be 'unknown'
    }

    It 'skips forks, archived repositories and other libraries' {
        $result = Invoke-Drift (New-Api)

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Gh | Should -Match 'api users/Octo-Org'
        $result.Gh | Should -Match 'api user/repos\?affiliation=owner&per_page=100 --paginate --slurp'
        $result.Gh | Should -Not -Match 'Octo-Org/Forked|Octo-Org/Retired'
        $result.Log | Should -Match 'Octo-Org/Plain: no workflows'
        $result.Summary | Should -Not -Match 'Templates-Other|checkout'
    }

    It 'writes the summary table and a warning for each drifted reference' {
        $result = Invoke-Drift (New-Api)

        $result.Summary | Should -Match '### Drift report for Octo-Org/Templates'
        $result.Summary | Should -Match 'Latest release: `v1\.2\.0`\. Scanned 4 repositories of Octo-Org; 2 use the library in 6 workflow reference\(s\), 1 current and 5 not\.'
        $result.Summary | Should -Match '\| Octo-Org/App \| `\.github/workflows/ci\.yml` \| `\.github/workflows/dotnet\.yml`<br>`actions/version` \| `v1` \| v1\.2\.0 \| current \|'
        $result.Summary | Should -Match '\| Octo-Org/Old \| `\.github/workflows/release\.yml` \| `\.github/workflows/npm-package\.yml` \| `v1\.0\.0` \| v1\.0\.0 \| behind 2 \|'
        $result.Summary | Should -Match 'Only repositories the token can read are scanned\.'
        $result.Log | Should -Match '::warning title=Drift::Octo-Org/Old \.github/workflows/release\.yml uses Octo-Org/Templates@v1\.0\.0, v1\.0\.0, 2 release\(s\) behind v1\.2\.0\.'
        $result.Log | Should -Match "uses Octo-Org/Templates@main, the branch 'main'\."
        $result.Log | Should -Not -Match '::warning.*Octo-Org/App'
        $result.Summary | Should -Match '<details><summary>1 repositories with workflows that do not use the library</summary>\s+- Octo-Org/Legacy'
    }

    It 'lists an organisation''s repositories' {
        $result = Invoke-Drift (New-Api -Type 'Organization')

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Gh | Should -Match 'api orgs/Octo-Org/repos\?type=all&per_page=100'
        $result.Outputs['references'] | Should -Be '6'
    }

    It 'lists only public repositories of a user the token does not belong to' {
        $result = Invoke-Drift (New-Api -Viewer '')

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Gh | Should -Match 'api users/Octo-Org/repos\?type=owner&per_page=100'
        $result.Outputs['repositories'] | Should -Be '4'
    }

    It 'scans the listed repositories instead of the owner''s' {
        $result = Invoke-Drift (New-Api) @{ INPUT_REPOSITORIES = "Octo-Org/App`nOcto-Org/Retired" }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Gh | Should -Not -Match 'api users/'
        $result.Outputs['repositories'] | Should -Be '2'
        $result.Outputs['references'] | Should -Be '2'
        $result.Summary | Should -Match 'repositories of the repositories input'
    }

    It 'reads the library from the action''s repository' {
        $result = Invoke-Drift (New-Api) @{ GITHUB_ACTION_REPOSITORY = 'Octo-Org/Templates'; INPUT_REPOSITORIES = 'Octo-Org/App' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Gh | Should -Match 'api repos/Octo-Org/Templates/tags'
        $result.Outputs['current'] | Should -Be '1'
    }

    It 'fails on drift when asked' {
        $result = Invoke-Drift (New-Api) @{ INPUT_FAIL_ON_DRIFT = 'true' }

        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match '5 workflow reference\(s\) to Octo-Org/Templates are not on v1\.2\.0\.'
        $result.Summary | Should -Match 'Drift report'
    }

    It 'passes with fail-on-drift when every reference is current' {
        $result = Invoke-Drift (New-Api) @{ INPUT_FAIL_ON_DRIFT = 'true'; INPUT_REPOSITORIES = 'Octo-Org/App' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['drifted'] | Should -Be '0'
    }

    It 'fails <Name>' -ForEach @(
        @{ Name = 'for a library that is not owner/name'; Environment = @{ INPUT_LIBRARY = 'Templates' }; Message = "library 'Templates' must be owner/name" }
        @{ Name = 'for a repository that is not owner/name'; Environment = @{ INPUT_REPOSITORIES = 'App' }; Message = "repository 'App' must be owner/name" }
        @{ Name = 'for a report outside the workspace'; Environment = @{ INPUT_REPORT = '../drift.json' }; Message = 'must be inside the workspace' }
        @{ Name = 'for a library without releases'; Environment = @{ INPUT_LIBRARY = 'Octo-Org/Missing' }; Message = 'Could not read the tags of Octo-Org/Missing' }
        @{ Name = 'for an unknown owner'; Environment = @{ INPUT_OWNER = 'nobody' }; Message = "owner 'nobody' does not exist" }
    ) {
        $result = Invoke-Drift (New-Api) $Environment.Clone()

        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match $Message
    }
}

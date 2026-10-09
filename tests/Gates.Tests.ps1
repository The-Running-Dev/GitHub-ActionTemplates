#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Tests for the gates action: the gate list derived from a repository's workflows, and the check
# of the committed .github/gates.json against it.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    $script:Script = Join-Path $PSScriptRoot '..' 'actions' 'gates' 'gates.ps1'
    function Get-Flat([string] $Text) { $Text -replace '\s*\r?\n\s*\|\s*', ' ' }

    function Set-File([string] $Path, [string] $Text) {
        New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
        Set-Content -LiteralPath $Path -Value $Text
    }

    function New-Workspace([string] $Workflow = $script:Workflow) {
        $path = Join-Path $TestDrive "gates-$([guid]::NewGuid().ToString('n'))"
        Set-File (Join-Path $path '.github/workflows/ci.yml') $Workflow
        Set-File (Join-Path $path 'app/package-lock.json') '{}'
        return $path
    }

    function Invoke-GateAction([string] $Workspace, [hashtable] $Environment = @{}) {
        $Environment['GITHUB_WORKSPACE'] = $Workspace
        Invoke-ActionScript $script:Script -Environment $Environment -WorkingDirectory $Workspace
    }

    function Get-GateList([string] $Workspace) {
        (Get-Content -LiteralPath (Join-Path $Workspace '.github/gates.json') -Raw | ConvertFrom-Json -AsHashtable)['gates']
    }

    $script:Workflow = @'
name: CI
on: [push]
jobs:
  node:
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/workflows/node-ci.yml@v0
    with:
      working-directory: app
      setup: vendor
      scripts: typecheck test
      pre-build: build/Prepare.ps1
      check-clean: true

  # A job with its own steps.
  custom:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      # verification: true
      - name: Lint docs
        working-directory: docs
        run: ./lint.sh

  pwsh:
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/workflows/pwsh-ci.yml@v0
    with:
      os: '["windows-latest"]'
      tests: |
        tools
        tests
      analyzer: true
      tags: Unit, Fast
      post-build: tools/Test-SpecSet.ps1
'@
}

Describe 'gates' {
    It 'writes the gates of library calls and marked steps, in workflow order' {
        $workspace = New-Workspace

        $result = Invoke-GateAction $workspace @{ INPUT_WRITE = 'true' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['status'] | Should -Be 'written'
        $gates = Get-GateList $workspace
        $gates | ForEach-Object { "$($_['name']) => $($_['command'])" } | Should -Be @(
            'node / build/Prepare.ps1 => pwsh -NoProfile -File ./build/Prepare.ps1'
            'node / vendor (setup) => cd app && npm run vendor'
            'node / install => cd app && npm ci'
            'node / typecheck => cd app && npm run typecheck'
            'node / test => cd app && npm run test'
            'custom / Lint docs => cd docs && ./lint.sh'
            "pwsh / PSScriptAnalyzer . => pwsh -NoProfile -Command ""Invoke-ScriptAnalyzer -Path '.' -Recurse -Severity Error, Warning -EnableExit"""
            "pwsh / Pester tools, tests => pwsh -NoProfile -Command ""Invoke-Pester -Configuration @{ Run = @{ Path = @('tools', 'tests'); Exit = [bool]1 }; Filter = @{ Tag = @('Unit', 'Fast') } }"""
            'pwsh / tools/Test-SpecSet.ps1 => pwsh -NoProfile -File ./tools/Test-SpecSet.ps1'
        )
    }

    It 'passes when the committed file matches, whatever its order' {
        $workspace = New-Workspace
        [void] (Invoke-GateAction $workspace @{ INPUT_WRITE = 'true' })
        $gates = @(Get-GateList $workspace)
        [array]::Reverse($gates)
        Set-File (Join-Path $workspace '.github/gates.json') (@{ gates = $gates } | ConvertTo-Json -Depth 5)

        $result = Invoke-GateAction $workspace

        $result.ExitCode | Should -Be 0 -Because $result.Log
        $result.Outputs['status'] | Should -Be 'match'
        $result.Outputs['count'] | Should -Be '9'
    }

    It 'fails when a workflow input changed and prints the expected file' {
        $workspace = New-Workspace
        [void] (Invoke-GateAction $workspace @{ INPUT_WRITE = 'true' })
        Set-File (Join-Path $workspace '.github/workflows/ci.yml') ($Workflow -replace 'scripts: typecheck test', 'scripts: typecheck lint test')

        $result = Invoke-GateAction $workspace

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match "out of date: 1 gate\(s\) missing, 0 not run"
        $result.Log | Should -Match '::error .*Missing gate: node / lint: cd app && npm run lint'
        $result.Summary | Should -Match '"command": "cd app && npm run lint"'
    }

    It 'fails on a gate no workflow runs' {
        $workspace = New-Workspace
        [void] (Invoke-GateAction $workspace @{ INPUT_WRITE = 'true' })
        $gates = @(Get-GateList $workspace) + @{ name = 'extra'; command = 'npm run extra' }
        Set-File (Join-Path $workspace '.github/gates.json') (@{ gates = $gates } | ConvertTo-Json -Depth 5)

        $result = Invoke-GateAction $workspace

        $result.ExitCode | Should -Not -Be 0
        $result.Log | Should -Match '::error .*No workflow runs gate: extra: npm run extra'
    }

    It 'fails on <Name>' -ForEach @(
        @{ Name = 'a missing file'; Content = $null; Message = "'.github/gates.json' does not exist" }
        @{ Name = 'invalid JSON'; Content = '{ gates'; Message = 'is not valid JSON' }
        @{ Name = 'a gate without a command'; Content = '{ "gates": [ { "name": "x" } ] }'; Message = "must be an object whose 'gates' is a list" }
    ) {
        $workspace = New-Workspace
        if ($Content) { Set-File (Join-Path $workspace '.github/gates.json') $Content }

        $result = Invoke-GateAction $workspace

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
    }

    It 'reads npm-package and self-repository calls with their defaults' {
        $workspace = New-Workspace @'
on: push
jobs:
  package:
    uses: $/.github/workflows/npm-package.yml
  module:
    uses: Someone/GitHub-ActionTemplates/.github/workflows/pwsh-ci.yml@main
  other:
    uses: Someone/Else/.github/workflows/node-ci.yml@v1
'@

        $result = Invoke-GateAction $workspace @{ INPUT_WRITE = 'true' }

        $result.ExitCode | Should -Be 0 -Because $result.Log
        Get-GateList $workspace | ForEach-Object { "$($_['name']) => $($_['command'])" } | Should -Be @(
            'package / install => npm install'
            'package / test => npm run test'
            "module / Pester tests => pwsh -NoProfile -Command ""Invoke-Pester -Configuration @{ Run = @{ Path = @('tests'); Exit = [bool]1 } }"""
        )
    }

    It 'rejects <Name>' -ForEach @(
        @{
            Name     = 'an expression in a library input'
            Workflow = "jobs:`n  node:`n    uses: The-Running-Dev/GitHub-ActionTemplates/.github/workflows/node-ci.yml@v0`n    with:`n      scripts: `${{ inputs.scripts }}"
            Message  = "job 'node' sets 'scripts' with an expression"
        }
        @{
            Name     = 'a marker that is not before a step'
            Workflow = "jobs:`n  a:`n    runs-on: ubuntu-latest`n    # verification: true`n    steps: []"
            Message  = "ci.yml:4: '# verification: true' must come right before a step"
        }
        @{
            Name     = 'a marked step without run'
            Workflow = "jobs:`n  a:`n    steps:`n      # verification: true`n      - uses: actions/checkout@v6"
            Message  = "ci.yml:5: the step marked '# verification: true' has no 'run'"
        }
        @{
            Name     = 'workflows without gates'
            Workflow = "jobs:`n  a:`n    steps:`n      - run: echo"
            Message  = 'No gates found'
        }
    ) {
        $result = Invoke-GateAction (New-Workspace $Workflow) @{ INPUT_WRITE = 'true' }

        $result.ExitCode | Should -Not -Be 0
        Get-Flat $result.Log | Should -Match ([regex]::Escape($Message))
    }

    It 'derives a Pester command that runs and fails on a failing test' -Skip:(-not (Get-Command bash -ErrorAction SilentlyContinue)) {
        $workspace = New-Workspace "jobs:`n  pwsh:`n    uses: The-Running-Dev/GitHub-ActionTemplates/.github/workflows/pwsh-ci.yml@v0"
        Set-File (Join-Path $workspace 'tests/Failing.Tests.ps1') "Describe 'x' { It 'fails' { 1 | Should -Be 2 } }"
        [void] (Invoke-GateAction $workspace @{ INPUT_WRITE = 'true' })
        $command = @(Get-GateList $workspace)[0]['command']

        Push-Location $workspace
        try { bash -c $command *> $null; $exitCode = $LASTEXITCODE }
        finally { Pop-Location }

        $exitCode | Should -Be 1
        Join-Path $workspace 'testResults.xml' | Should -Not -Exist
    }
}

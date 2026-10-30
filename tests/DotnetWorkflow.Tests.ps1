#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
BeforeAll {
    $script:Workflow = Get-Content (Join-Path $PSScriptRoot '../.github/workflows/dotnet.yml') -Raw
    $script:Diagnostics = [regex]::Match($Workflow, '(?ms)^      - name: Upload diagnostics\n(.*?)(?=^  pack:)').Value
}

Describe '.NET optional diagnostic upload contract' {
    It 'defaults to disabled without changing the test artifact upload' {
        $Workflow | Should -Match "(?s)diagnostic-artifact-paths:.*?type: string\s+default: ''"
        $Workflow | Should -Match 'if: \$\{\{ !cancelled\(\) && steps.test.outputs.results != '''' \}\}'
        $Workflow | Should -Match 'name: \$\{\{ inputs.artifact-name \}\}-\$\{\{ matrix.os \}\}'
    }

    It 'uploads independently of test outputs after success or failure, unless cancelled' {
        # Exact status-check contract: !cancelled overrides GitHub's implicit success().
        # A TRX output or success() dependency would skip the partial-evidence failure path.
        $Diagnostics | Should -Match 'if: \$\{\{ !cancelled\(\) && inputs.diagnostic-artifact-paths != '''' \}\}'
        $Diagnostics | Should -Not -Match 'steps.test|success\(\)|continue-on-error'
        $Diagnostics | Should -Match 'if-no-files-found: warn'
        $Diagnostics | Should -Match 'include-hidden-files: false'
    }

    It 'uses a separate matrix artifact and the existing retention setting' {
        $Diagnostics | Should -Match 'name: \$\{\{ inputs.diagnostic-artifact-name \}\}-\$\{\{ matrix.os \}\}'
        $Diagnostics | Should -Match 'path: \$\{\{ inputs.diagnostic-artifact-paths \}\}'
        $Diagnostics | Should -Match 'retention-days: \$\{\{ inputs.retention-days \}\}'
        $Diagnostics | Should -Match 'actions/upload-artifact@[0-9a-f]{40}'
    }
}

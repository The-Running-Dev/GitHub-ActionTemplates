#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
BeforeAll {
    $script:Workflow = Get-Content (Join-Path $PSScriptRoot '../.github/workflows/dotnet.yml') -Raw
    $script:Diagnostics = [regex]::Match($Workflow, '(?ms)^      - name: Upload diagnostics\n(.*?)(?=^  pack:)').Value
}

Describe '.NET optional diagnostic upload contract' {
    It 'requires an explicit safe path and preserves the test reporter' {
        $Workflow | Should -Match "(?s)diagnostic-artifact-paths:.*?type: string\s+default: ''"
        $Workflow | Should -Match 'if: \$\{\{ !cancelled\(\) && steps.test.outputs.results != '''' \}\}'
        $Workflow | Should -Match 'diagnostic-policy:\s+description:[^\r\n]+\s+type: string\s+default: failure'
        $Workflow | Should -Match 'name: \$\{\{ inputs.artifact-name \}\}-\$\{\{ matrix.os \}\}'
    }

    It 'uploads partial evidence by policy, independently of test outputs, unless cancelled' {
        # Exact status-check contract: !cancelled overrides GitHub's implicit success().
        # A TRX output or success() dependency would skip the partial-evidence failure path.
        $Diagnostics | Should -Match 'if: \$\{\{ !cancelled\(\) && steps.diagnostic-policy.outputs.upload == ''true'' && inputs.diagnostic-artifact-paths != '''' \}\}'
        $Diagnostics | Should -Not -Match 'steps.test|success\(\)'
        $Diagnostics | Should -Match 'continue-on-error: true'
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

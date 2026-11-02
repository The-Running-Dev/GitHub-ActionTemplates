#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
BeforeAll { $script:WorkflowRoot = Join-Path $PSScriptRoot '..' '.github' 'workflows' }
Describe 'Package consumers retain required transport' {
    It '<_> includes both registry and release-only consumers and branch prereleases' -ForEach @('dotnet.yml', 'npm-package.yml') {
        $workflow = Get-Content (Join-Path $WorkflowRoot $_) -Raw
        $policy = [regex]::Match($workflow, '(?ms)^      - name: package-policy\r?\n.*?(?=^      - name: Upload)').Value
        $policy | Should -Match 'inputs.publish &&'
        $policy | Should -Match 'inputs.publish-prereleases && steps.context.outputs.is-default-branch'
        $policy | Should -Match '\|\| \(inputs.github-release && steps.context.outputs.is-tag'
        $workflow | Should -Match 'continue-on-error: \$\{\{ steps.package-policy.outputs.required != ''true'' \}\}'
        $policy | Should -Match 'required-retention-days: \$\{\{ inputs.handoff-retention-days \}\}'
        $workflow | Should -Match 'upload-builds:\s+description:[^\r\n]+\s+type: boolean\s+default: false'
    }
}
Describe 'Default storage limits' {
    It 'disables Docker records on both build paths and keeps the required image archive' {
        $workflow = Get-Content (Join-Path $WorkflowRoot 'container.yml') -Raw
        $workflow | Should -Match 'upload-build-records:\s+description:[^\r\n]+\s+type: boolean\s+default: false'
        ([regex]::Matches($workflow, 'DOCKER_BUILD_RECORD_UPLOAD:')).Count | Should -Be 2
        $workflow | Should -Match 'retention-days: \$\{\{ inputs.handoff-retention-days \}\}'
        $workflow | Should -Match 'if-no-files-found: error'
    }
    It '<_> uploads a site for deployment or explicit opt-in, not every preview' -ForEach @('docs.yml', 'pages.yml') {
        $workflow = Get-Content (Join-Path $WorkflowRoot $_) -Raw
        $workflow | Should -Match 'required: \$\{\{ inputs.deploy && steps.context.outputs.should-publish == ''true'' \}\}'
        $workflow | Should -Match 'retention-days: \$\{\{ steps.site-policy.outputs.retention-days \}\}'
    }
}

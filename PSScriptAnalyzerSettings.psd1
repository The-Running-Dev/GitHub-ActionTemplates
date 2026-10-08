@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Action scripts write to the runner log, which is what Write-Host is for.
        'PSAvoidUsingWriteHost'
        # Set-ActionOutput appends to $GITHUB_OUTPUT; -WhatIf has no meaning there.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}

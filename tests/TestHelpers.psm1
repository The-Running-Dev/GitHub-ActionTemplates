#Requires -Version 7.2
# Helpers for running action scripts the way the runner does: a child pwsh process with
# INPUT_* / GITHUB_* environment variables and a GITHUB_OUTPUT file to read back.

Set-StrictMode -Version Latest

$script:DefaultEnvironment = [ordered]@{
    GITHUB_EVENT_NAME   = 'push'
    GITHUB_REF_TYPE     = 'branch'
    GITHUB_REF_NAME     = 'main'
    GITHUB_HEAD_REF     = ''
    GITHUB_REPOSITORY   = 'Octo-Org/Sample.Repo'
    GITHUB_SHA          = '0123456789abcdef0123456789abcdef01234567'
    GITHUB_RUN_NUMBER   = '42'
    GITHUB_EVENT_PATH   = ''
    GHAT_DEFAULT_BRANCH = 'main'
    GHAT_PR_NUMBER      = ''
}

function Use-Environment {
    <#
    .SYNOPSIS
    Runs a script block with environment variables set, restoring the previous values afterwards.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Environment,
        [Parameter(Mandatory)][scriptblock] $ScriptBlock
    )

    $saved = @{}
    foreach ($name in $Environment.Keys) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, [string] $Environment[$name])
    }

    try { & $ScriptBlock }
    finally {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
}

function New-ActionEnvironment {
    param([System.Collections.IDictionary] $Overrides = @{})

    $environment = [ordered]@{}
    foreach ($name in $script:DefaultEnvironment.Keys) { $environment[$name] = $script:DefaultEnvironment[$name] }
    foreach ($name in $Overrides.Keys) { $environment[$name] = $Overrides[$name] }

    return $environment
}

function ConvertFrom-ActionOutputFile {
    param([Parameter(Mandatory)][string] $Path)

    $outputs = @{}
    $lines = @(Get-Content -LiteralPath $Path)

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^(?<name>[^=<]+)<<(?<delimiter>.+)$') {
            $value = [System.Collections.Generic.List[string]]::new()
            while (++$i -lt $lines.Count -and $lines[$i] -ne $Matches['delimiter']) { $value.Add($lines[$i]) }
            $outputs[$Matches['name']] = $value -join "`n"
        }
        elseif ($line -match '^(?<name>[^=]+)=(?<value>.*)$') {
            $outputs[$Matches['name']] = $Matches['value']
        }
    }

    return $outputs
}

function Invoke-ActionScript {
    <#
    .SYNOPSIS
    Runs an action script in a child pwsh process and returns its exit code, outputs, log and summary.
    #>
    param(
        [Parameter(Mandatory)][string] $Script,
        [System.Collections.IDictionary] $Environment = @{},
        [string] $WorkingDirectory = (Get-Location).Path
    )

    $outputFile = New-TemporaryFile
    $summaryFile = New-TemporaryFile
    $variables = New-ActionEnvironment $Environment
    $variables['GITHUB_OUTPUT'] = $outputFile.FullName
    $variables['GITHUB_STEP_SUMMARY'] = $summaryFile.FullName
    # Locals rather than parameters inside the script block, which PSScriptAnalyzer cannot follow.
    $scriptPath = $Script
    $location = $WorkingDirectory

    try {
        $result = Use-Environment $variables {
            Push-Location -LiteralPath $location
            try {
                $log = & pwsh -NoProfile -NonInteractive -File $scriptPath 2>&1 | Out-String
                [pscustomobject]@{ ExitCode = $LASTEXITCODE; Log = $log }
            }
            finally { Pop-Location }
        }

        [pscustomobject]@{
            ExitCode = $result.ExitCode
            Log      = $result.Log
            Outputs  = ConvertFrom-ActionOutputFile $outputFile.FullName
            Summary  = Get-Content -LiteralPath $summaryFile.FullName -Raw
        }
    }
    finally {
        Remove-Item -LiteralPath $outputFile.FullName, $summaryFile.FullName -ErrorAction SilentlyContinue
    }
}

function New-GitRepository {
    <#
    .SYNOPSIS
    Creates a repository with one commit per tag (and one when there are no tags).
    #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [string[]] $Tags = @()
    )

    $PSNativeCommandUseErrorActionPreference = $true
    New-Item -ItemType Directory -Path $Path -Force | Out-Null

    git -C $Path init --quiet --initial-branch main
    git -C $Path config user.name 'Test'
    git -C $Path config user.email 'test@example.com'
    git -C $Path config commit.gpgsign false
    git -C $Path config tag.gpgsign false

    $commits = [math]::Max(1, $Tags.Count)
    for ($i = 0; $i -lt $commits; $i++) {
        git -C $Path commit --quiet --allow-empty -m "commit $i"
        if ($i -lt $Tags.Count) { git -C $Path tag $Tags[$i] }
    }
    git -C $Path commit --quiet --allow-empty -m 'after last tag'

    return $Path
}

Export-ModuleMember -Function Use-Environment, Invoke-ActionScript, New-GitRepository, ConvertFrom-ActionOutputFile

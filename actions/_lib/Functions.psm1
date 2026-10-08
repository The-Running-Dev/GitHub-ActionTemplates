#Requires -Version 7.2
# Shared helpers for the composite actions in this repository.
# Each action script imports this module from $PSScriptRoot/../_lib.

Set-StrictMode -Version Latest

function Get-ActionInput {
    <#
    .SYNOPSIS
    Reads an action input from its INPUT_<NAME> environment variable.
    Dashes in the name map to underscores (tag-prefix -> INPUT_TAG_PREFIX).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Name,
        [string] $Default = ''
    )

    $variable = 'INPUT_' + $Name.ToUpperInvariant().Replace('-', '_')
    $value = [Environment]::GetEnvironmentVariable($variable)

    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }

    return $value.Trim()
}

function Set-ActionOutput {
    <#
    .SYNOPSIS
    Writes a step output to $GITHUB_OUTPUT (and echoes it to the log).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Name,
        [AllowEmptyString()][string] $Value = ''
    )

    if ($env:GITHUB_OUTPUT) {
        if ($Value -match "[`r`n]") {
            $delimiter = 'ghadelimiter_' + [guid]::NewGuid().ToString('N')
            Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8 -Value "$Name<<$delimiter`n$Value`n$delimiter"
        }
        else {
            Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8 -Value "$Name=$Value"
        }
    }

    Write-Host "$Name=$Value"
}

function Add-ActionSummary {
    <#
    .SYNOPSIS
    Appends Markdown to the job summary when running on a runner.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Markdown)

    if ($env:GITHUB_STEP_SUMMARY) {
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Value $Markdown
    }
}

function ConvertTo-SemVer {
    <#
    .SYNOPSIS
    Parses Major.Minor[.Patch][-prerelease][+build]. A missing patch is treated as 0.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Version)

    $identifiers = '[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*'
    $pattern = "^(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)(?:\.(?<patch>0|[1-9]\d*))?(?:-(?<pre>$identifiers))?(?:\+(?<build>$identifiers))?$"

    if ($Version.Trim() -notmatch $pattern) {
        throw "'$Version' is not a valid semantic version."
    }

    [pscustomobject]@{
        Major      = [int] $Matches['major']
        Minor      = [int] $Matches['minor']
        Patch      = if ($Matches['patch']) { [int] $Matches['patch'] } else { 0 }
        Prerelease = if ($Matches['pre']) { $Matches['pre'] } else { '' }
        Build      = if ($Matches['build']) { $Matches['build'] } else { '' }
    }
}

function Format-SemVer {
    <#
    .SYNOPSIS
    Formats a parsed version as Major.Minor.Patch[-prerelease] (build metadata is dropped).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] $SemVer)

    $text = '{0}.{1}.{2}' -f $SemVer.Major, $SemVer.Minor, $SemVer.Patch

    if ($SemVer.Prerelease) { $text += "-$($SemVer.Prerelease)" }

    return $text
}

function Find-Manifest {
    <#
    .SYNOPSIS
    Locates the version manifest in a directory. Order: package.json, Directory.Build.props,
    a single *.csproj, a single *.psd1, Cargo.toml, pyproject.toml, VERSION.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Path = '.')

    foreach ($name in 'package.json', 'Directory.Build.props') {
        $candidate = Join-Path $Path $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    foreach ($filter in '*.csproj', '*.psd1') {
        $found = @(Get-ChildItem -LiteralPath $Path -Filter $filter -File)
        if ($found.Count -eq 1) { return $found[0].FullName }
    }

    foreach ($name in 'Cargo.toml', 'pyproject.toml', 'VERSION') {
        $candidate = Join-Path $Path $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    throw "No version manifest found in '$Path'. Set the 'manifest' input."
}

function Get-ManifestVersion {
    <#
    .SYNOPSIS
    Reads the version from package.json, MSBuild project/props files, PowerShell module
    manifests, TOML (Cargo/pyproject), or a plain text file containing only the version.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Manifest '$Path' does not exist."
    }

    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $version = $null

    if ($extension -eq '.json') {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
        $version = $json['version']
    }
    elseif ($extension -in '.csproj', '.fsproj', '.vbproj', '.props', '.targets') {
        [xml] $xml = Get-Content -LiteralPath $Path -Raw
        foreach ($element in 'Version', 'VersionPrefix') {
            $node = $xml.SelectSingleNode("//*[local-name()='$element' and normalize-space(.)!='']")
            if ($node) { $version = $node.InnerText; break }
        }
        if ($version -and $version.Contains('$(')) {
            throw "Version in '$Path' is an MSBuild expression ('$version'); set it to a literal value."
        }
    }
    elseif ($extension -eq '.psd1') {
        $data = Import-PowerShellDataFile -LiteralPath $Path
        $version = $data['ModuleVersion']
    }
    elseif ($extension -eq '.toml') {
        $match = Select-String -LiteralPath $Path -Pattern '^\s*version\s*=\s*"([^"]+)"' | Select-Object -First 1
        if ($match) { $version = $match.Matches[0].Groups[1].Value }
    }
    else {
        $version = Get-Content -LiteralPath $Path -Raw
    }

    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "No version found in '$Path'."
    }

    return "$version".Trim()
}

function ConvertTo-Slug {
    <#
    .SYNOPSIS
    Lowercases and replaces anything outside [a-z0-9] with '-', capped at 63 characters.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string] $Value)

    $slug = ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')

    if ($slug.Length -gt 63) { $slug = $slug.Substring(0, 63).TrimEnd('-') }

    return $slug
}

function Get-ActionContext {
    <#
    .SYNOPSIS
    Normalises the GitHub run context. Reads the default environment variables plus
    GHAT_DEFAULT_BRANCH / GHAT_PR_NUMBER (set by the action from the event), falling back
    to the event payload when those are not set.
    #>
    [CmdletBinding()]
    param()

    $eventName = "$env:GITHUB_EVENT_NAME"
    $refType = "$env:GITHUB_REF_TYPE"
    $refName = "$env:GITHUB_REF_NAME"
    $defaultBranch = "$env:GHAT_DEFAULT_BRANCH"
    $prNumber = "$env:GHAT_PR_NUMBER"

    if ((-not $defaultBranch -or -not $prNumber) -and $env:GITHUB_EVENT_PATH -and (Test-Path -LiteralPath $env:GITHUB_EVENT_PATH)) {
        $payload = Get-Content -LiteralPath $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json -AsHashtable -Depth 64
        if ($payload) {
            if (-not $defaultBranch -and $payload['repository']) { $defaultBranch = "$($payload['repository']['default_branch'])" }
            if (-not $prNumber -and $payload['pull_request']) { $prNumber = "$($payload['pull_request']['number'])" }
        }
    }

    $isPullRequest = $eventName -in 'pull_request', 'pull_request_target'
    $isTag = $refType -eq 'tag'
    $branch = if ($isPullRequest) { "$env:GITHUB_HEAD_REF" } elseif ($refType -eq 'branch') { $refName } else { '' }
    $isDefaultBranch = -not $isPullRequest -and $refType -eq 'branch' -and $defaultBranch -and $refName -eq $defaultBranch

    $owner, $repository = "$env:GITHUB_REPOSITORY" -split '/', 2
    $sha = "$env:GITHUB_SHA"

    [pscustomobject]@{
        EventName         = $eventName
        RefName           = $refName
        RefType           = $refType
        Branch            = $branch
        DefaultBranch     = $defaultBranch
        IsPullRequest     = $isPullRequest
        PullRequestNumber = $prNumber
        IsTag             = $isTag
        IsDefaultBranch   = [bool] $isDefaultBranch
        ShouldPublish     = -not $isPullRequest -and ($isTag -or [bool] $isDefaultBranch)
        Owner             = "$owner"
        Repository        = "$repository"
        Sha               = $sha
        ShortSha          = if ($sha.Length -ge 7) { $sha.Substring(0, 7) } else { $sha }
        RunNumber         = if ($env:GITHUB_RUN_NUMBER) { $env:GITHUB_RUN_NUMBER } else { '0' }
    }
}

function Get-LatestTagVersion {
    <#
    .SYNOPSIS
    Returns the nearest reachable tag matching <prefix><semver> as a parsed version, or $null.
    #>
    [CmdletBinding()]
    param(
        [string] $Prefix = 'v',
        [string] $Path = '.'
    )

    $PSNativeCommandUseErrorActionPreference = $false

    $shallow = git -C $Path rev-parse --is-shallow-repository 2>$null
    if ($shallow -eq 'true') {
        Write-Host "::warning::Repository is a shallow clone; tags may be missing. Use actions/checkout with 'fetch-depth: 0'."
    }

    $tag = git -C $Path describe --tags --abbrev=0 --match "$Prefix[0-9]*" 2>$null
    $found = $LASTEXITCODE -eq 0 -and $tag
    # No tag is an expected answer, but the runner's pwsh wrapper ends the step with
    # `exit $LASTEXITCODE`, so the failed probe must not leak out.
    $global:LASTEXITCODE = 0
    if (-not $found) { return $null }

    try {
        return ConvertTo-SemVer "$tag".Trim().Substring($Prefix.Length)
    }
    catch {
        Write-Host "::warning::Ignoring tag '$tag': $($_.Exception.Message)"
        return $null
    }
}

function Resolve-WorkspacePath {
    <#
    .SYNOPSIS
    Resolves a path relative to the workspace and fails when it is not strictly inside it.
    Inputs come from callers, so `..`, absolute paths elsewhere and the workspace root itself
    are rejected.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Workspace,
        [string] $Name = 'path'
    )

    $root = [System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetFullPath($Workspace))
    $full = [System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetFullPath($Path, $root))
    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    if (-not $full.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, $comparison)) {
        throw "The $Name '$Path' must be inside the workspace '$root'."
    }

    return $full
}

function Split-ActionList {
    <#
    .SYNOPSIS
    Splits a list input on new lines and semicolons, trimming entries and dropping empty ones.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([AllowEmptyString()][string] $Value)

    return @($Value -split '[
;]+' | ForEach-Object Trim | Where-Object { $_ })
}

function Get-PackageManager {
    <#
    .SYNOPSIS
    Returns the package manager for a Node project folder: the given one, or the one its lockfile
    implies (pnpm-lock.yaml, yarn.lock, else npm).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [string] $PackageManager = ''
    )

    if ($PackageManager) {
        if ($PackageManager -notin 'npm', 'pnpm', 'yarn') {
            throw "Unknown package-manager '$PackageManager'. Use 'npm', 'pnpm' or 'yarn', or leave it empty to detect it."
        }
        return $PackageManager
    }
    if (Test-Path -LiteralPath (Join-Path $Path 'pnpm-lock.yaml')) { return 'pnpm' }
    if (Test-Path -LiteralPath (Join-Path $Path 'yarn.lock')) { return 'yarn' }
    return 'npm'
}

function Install-NodePackage {
    <#
    .SYNOPSIS
    Installs a Node project's dependencies from its lockfile (npm ci, pnpm --frozen-lockfile,
    yarn install), or with npm install when an npm project has no lockfile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][ValidateSet('npm', 'pnpm', 'yarn')][string] $PackageManager
    )

    Push-Location -LiteralPath $Path
    try {
        switch ($PackageManager) {
            'npm' { if ((Test-Path package-lock.json) -or (Test-Path npm-shrinkwrap.json)) { npm ci } else { npm install } }
            'pnpm' { pnpm install --frozen-lockfile }
            'yarn' { yarn install }
        }
        if ($LASTEXITCODE -ne 0) { throw "$PackageManager install failed in '$Path'." }
    }
    finally { Pop-Location }
}

Export-ModuleMember -Function *-*

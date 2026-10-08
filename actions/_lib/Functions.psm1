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

    # setup-node ships pnpm and yarn only through corepack.
    if ($PackageManager -ne 'npm' -and -not (Get-Command $PackageManager -ErrorAction SilentlyContinue)) {
        if (-not (Get-Command corepack -ErrorAction SilentlyContinue)) { throw "$PackageManager is not installed and corepack is not available to provide it." }
        Write-Host "Enabling $PackageManager with corepack"
        corepack enable
    }

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

function Install-PowerShellModule {
    <#
    .SYNOPSIS
    Imports an exact version of a module, first installing it from the PowerShell Gallery for the
    current user when that version is missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Version
    )

    if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "The $Name version must be Major.Minor.Patch; got '$Version'." }

    if (-not (Get-Module -ListAvailable -Name $Name | Where-Object { "$($_.Version)" -eq $Version })) {
        Write-Host "Installing $Name $Version"
        Install-Module -Name $Name -RequiredVersion $Version -Repository PSGallery -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
    }
    Get-Module -Name $Name | Remove-Module -Force
    Import-Module -Name $Name -RequiredVersion $Version -Global -Force
}

function Find-WorkspaceFile {
    <#
    .SYNOPSIS
    Finds files inside the workspace. Entries are paths relative to the workspace and may contain
    wildcards; `**/` matches any number of folders (`**/coverage.xml`, `src/**/TEST-*.xml`).
    node_modules and .git folders are not searched by `**/`.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowEmptyCollection()][string[]] $Pattern = @(),
        [Parameter(Mandatory)][string] $Workspace
    )

    $root = [System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetFullPath($Workspace))
    $found = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($entry in $Pattern) {
        $normalized = $entry.Replace('\', '/')
        $index = $normalized.IndexOf('**/')

        if ($index -lt 0) {
            $full = Resolve-WorkspacePath $normalized $root 'path'
            if ($normalized.IndexOfAny([char[]] '*?[') -lt 0) {
                if (Test-Path -LiteralPath $full -PathType Leaf) { [void] $found.Add($full) }
            }
            else {
                Get-ChildItem -Path $full -File -ErrorAction SilentlyContinue | ForEach-Object { [void] $found.Add($_.FullName) }
            }
            continue
        }

        $base = $normalized.Substring(0, $index).TrimEnd('/')
        $rest = $normalized.Substring($index + 3)
        $folder = if ($base) { Resolve-WorkspacePath $base $root 'path' } else { $root }
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }

        $folders = [System.Collections.Generic.Stack[string]]::new()
        $folders.Push($folder)
        while ($folders.Count) {
            $current = $folders.Pop()
            foreach ($child in [System.IO.Directory]::EnumerateDirectories($current)) {
                if ([System.IO.Path]::GetFileName($child) -notin 'node_modules', '.git') { $folders.Push($child) }
            }
            foreach ($file in [System.IO.Directory]::EnumerateFiles($current)) {
                $relative = [System.IO.Path]::GetRelativePath($folder, $file).Replace('\', '/')
                if ($relative -like $rest -or $relative -like "*/$rest") { [void] $found.Add($file) }
            }
        }
    }

    return [string[]] @($found)
}

function Read-XmlFile {
    <#
    .SYNOPSIS
    Loads an XML file without resolving its DTD (JaCoCo reports reference one).
    #>
    [CmdletBinding()]
    [OutputType([xml])]
    param([Parameter(Mandatory)][string] $Path)

    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create($Path, $settings)
    try {
        $document = [System.Xml.XmlDocument]::new()
        $document.Load($reader)
        # A document enumerates its child nodes; return it as one object.
        return , $document
    }
    finally { $reader.Dispose() }
}

function Get-CoverageReport {
    <#
    .SYNOPSIS
    Reads the covered and total line counts from a Cobertura, JaCoCo or LCOV report.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $first = Get-Content -LiteralPath $Path -TotalCount 20 | Where-Object { $_.Trim() } | Select-Object -First 1
    if ($null -eq $first) { throw "The coverage report '$Path' is empty." }

    if (-not $first.TrimStart().StartsWith('<')) {
        $covered = 0L; $total = 0L; $isLcov = $false
        foreach ($line in Get-Content -LiteralPath $Path) {
            if ($line -match '^LF:(\d+)') { $total += [long] $Matches[1]; $isLcov = $true }
            elseif ($line -match '^LH:(\d+)') { $covered += [long] $Matches[1] }
        }
        if (-not $isLcov) { throw "'$Path' is not a Cobertura, JaCoCo or LCOV report." }
        $format = 'LCOV'
    }
    else {
        $root = (Read-XmlFile $Path).DocumentElement
        switch ($root.LocalName) {
            'coverage' {
                $format = 'Cobertura'
                if ($root.HasAttribute('lines-valid') -and $root.HasAttribute('lines-covered')) {
                    $total = [long] $root.GetAttribute('lines-valid')
                    $covered = [long] $root.GetAttribute('lines-covered')
                }
                else {
                    $lines = @($root.SelectNodes('//class/lines/line'))
                    $total = [long] $lines.Count
                    $covered = [long] @($lines | Where-Object { [long] $_.GetAttribute('hits') -gt 0 }).Count
                }
            }
            'report' {
                $format = 'JaCoCo'
                $counter = $root.SelectSingleNode("counter[@type='LINE']")
                if (-not $counter) { throw "The JaCoCo report '$Path' has no report-level LINE counter." }
                $covered = [long] $counter.GetAttribute('covered')
                $total = $covered + [long] $counter.GetAttribute('missed')
            }
            default { throw "'$Path' is not a Cobertura, JaCoCo or LCOV report (root element <$($root.LocalName)>)." }
        }
    }

    [pscustomobject]@{ Path = $Path; Format = $format; Covered = $covered; Total = $total }
}

function Get-TestResult {
    <#
    .SYNOPSIS
    Reads test outcomes from a JUnit, NUnit 2 (Pester NUnitXml), NUnit 3 or TRX results file.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $root = (Read-XmlFile $Path).DocumentElement
    $cases = [System.Collections.Generic.List[object]]::new()

    # Strict mode forbids .InnerText on a missing node.
    function Get-Text($Node) { if ($null -ne $Node) { $Node.InnerText } else { '' } }

    function Add-Case([string] $Name, [string] $Outcome, [string] $Message = '') {
        $cases.Add([pscustomobject]@{ Name = $Name; Outcome = $Outcome; Message = "$Message".Trim() })
    }

    switch -CaseSensitive ($root.LocalName) {
        { $_ -in 'testsuites', 'testsuite' } {
            $format = 'JUnit'
            foreach ($case in $root.SelectNodes('descendant-or-self::testcase')) {
                $failure = $case.SelectSingleNode('failure|error')
                if ($failure) {
                    $message = if ($failure.GetAttribute('message')) { $failure.GetAttribute('message') } else { $failure.InnerText }
                    Add-Case $case.GetAttribute('name') 'Failed' $message
                }
                elseif ($case.SelectSingleNode('skipped')) { Add-Case $case.GetAttribute('name') 'Skipped' }
                else { Add-Case $case.GetAttribute('name') 'Passed' }
            }
        }
        'test-results' {
            $format = 'NUnit 2'
            foreach ($case in $root.SelectNodes('//test-case')) {
                $outcome = if ($case.GetAttribute('executed') -eq 'False') { 'Skipped' }
                elseif ($case.GetAttribute('result') -in 'Failure', 'Error') { 'Failed' }
                elseif ($case.GetAttribute('result') -eq 'Success') { 'Passed' }
                else { 'Skipped' }
                Add-Case $case.GetAttribute('name') $outcome (Get-Text $case.SelectSingleNode('failure/message'))
            }
        }
        'test-run' {
            $format = 'NUnit 3'
            foreach ($case in $root.SelectNodes('//test-case')) {
                $outcome = switch ($case.GetAttribute('result')) {
                    'Failed' { 'Failed' }
                    { $_ -in 'Passed', 'Warning' } { 'Passed' }
                    default { 'Skipped' }
                }
                $name = if ($case.GetAttribute('fullname')) { $case.GetAttribute('fullname') } else { $case.GetAttribute('name') }
                Add-Case $name $outcome (Get-Text $case.SelectSingleNode('failure/message'))
            }
        }
        'TestRun' {
            $format = 'TRX'
            foreach ($case in $root.SelectNodes("//*[local-name()='UnitTestResult']")) {
                $outcome = switch ($case.GetAttribute('outcome')) {
                    'Passed' { 'Passed' }
                    { $_ -in 'Failed', 'Error', 'Timeout', 'Aborted' } { 'Failed' }
                    default { 'Skipped' }
                }
                $message = $case.SelectSingleNode("*[local-name()='Output']/*[local-name()='ErrorInfo']/*[local-name()='Message']")
                Add-Case $case.GetAttribute('testName') $outcome (Get-Text $message)
            }
        }
        default { throw "'$Path' is not a JUnit, NUnit or TRX results file (root element <$($root.LocalName)>)." }
    }

    [pscustomobject]@{
        Path     = $Path
        Format   = $format
        Total    = $cases.Count
        Passed   = @($cases | Where-Object Outcome -eq 'Passed').Count
        Failed   = @($cases | Where-Object Outcome -eq 'Failed').Count
        Skipped  = @($cases | Where-Object Outcome -eq 'Skipped').Count
        Failures = @($cases | Where-Object Outcome -eq 'Failed')
    }
}

function Get-ChangelogSection {
    <#
    .SYNOPSIS
    Returns the body of a CHANGELOG section ("## [1.2.3] ..." up to the next "## ").
    Fails when the section is missing or empty.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Version
    )

    $Version = $Version.TrimStart('v')
    $lines = @(Get-Content -LiteralPath $Path)
    $heading = '^##\s+\[' + [regex]::Escape($Version) + '\]'

    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $heading) { $start = $i; break }
    }
    if ($start -lt 0) { throw "CHANGELOG has no '## [$Version]' section." }

    $body = [System.Collections.Generic.List[string]]::new()
    for ($i = $start + 1; $i -lt $lines.Count -and $lines[$i] -notmatch '^##\s'; $i++) { $body.Add($lines[$i]) }

    $text = ($body -join "`n").Trim()
    if (-not $text) { throw "CHANGELOG section '## [$Version]' is empty." }

    return $text
}

function Get-TarballManifest {
    <#
    .SYNOPSIS
    Reads package/package.json from an npm tarball (.tgz).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    if (-not ('System.Formats.Tar.TarReader' -as [type])) { throw 'Reading npm tarballs needs PowerShell 7.4 or later.' }

    $file = [System.IO.File]::OpenRead($Path)
    try {
        $gzip = [System.IO.Compression.GZipStream]::new($file, [System.IO.Compression.CompressionMode]::Decompress)
        $reader = [System.Formats.Tar.TarReader]::new($gzip)
        while ($null -ne ($entry = $reader.GetNextEntry())) {
            if ($entry.Name -ne 'package/package.json' -or -not $entry.DataStream) { continue }
            $text = [System.IO.StreamReader]::new($entry.DataStream).ReadToEnd()
            return $text | ConvertFrom-Json
        }
        throw "'$Path' has no package/package.json."
    }
    finally { $file.Dispose() }
}

function Write-ActionAnnotation {
    <#
    .SYNOPSIS
    Writes an ::error, ::warning or ::notice workflow command, escaping its message and properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('error', 'warning', 'notice')][string] $Level,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Message,
        [string] $File = '',
        [int] $Line = 0,
        [int] $Column = 0,
        [string] $Title = ''
    )

    function ConvertTo-Property([string] $Value) { $Value.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A').Replace(':', '%3A').Replace(',', '%2C') }

    $properties = @(
        if ($File) { "file=$(ConvertTo-Property $File)" }
        if ($Line -gt 0) { "line=$Line" }
        if ($Column -gt 0) { "col=$Column" }
        if ($Title) { "title=$(ConvertTo-Property $Title)" }
    )
    $text = $Message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    $prefix = if ($properties) { "::$Level $($properties -join ',')::" } else { "::${Level}::" }
    Write-Host "$prefix$text"
}

function Format-MarkdownCell {
    <#
    .SYNOPSIS
    Makes text safe for one Markdown table cell: one line, pipes escaped, cut to a length.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string] $Text,
        [int] $Length = 200
    )

    $line = ($Text -replace '\s+', ' ').Trim().Replace('|', '\|')
    if ($line.Length -gt $Length) { $line = $line.Substring(0, $Length - 1) + "`u{2026}" }
    return $line
}

Export-ModuleMember -Function *-*

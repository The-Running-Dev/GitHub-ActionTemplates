#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$workspace = [System.IO.Path]::GetFullPath($(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }))
$file = Get-ActionInput 'file' '.github/gates.json'
$workflows = Get-ActionInput 'workflows' '.github/workflows'
$write = (Get-ActionInput 'write' 'false') -eq 'true'
$yamlVersion = Get-ActionInput 'yaml-version' '0.4.12'

# A caller job of one of this library's workflows, by owner/GitHub-ActionTemplates or by the
# self-repository syntax this repository uses.
$libraryWorkflow = '^(?:[^/\s]+/GitHub-ActionTemplates|\$)/\.github/workflows/(?<kind>node-ci|pwsh-ci|npm-package)\.yml(?:@\S+)?$'

$gatesPath = Resolve-WorkspacePath $file $workspace 'file'
$workflowFolder = Resolve-WorkspacePath $workflows $workspace 'workflows'
if (-not (Test-Path -LiteralPath $workflowFolder -PathType Container)) { throw "The workflows folder '$workflows' does not exist." }

Install-PowerShellModule -Name powershell-yaml -Version $yamlVersion

function Get-RelativePath([string] $Path) { [System.IO.Path]::GetRelativePath($workspace, $Path).Replace('\', '/') }

function Get-Value($Map, [string] $Name, [string] $Default = '') {
    if (-not $Map -or -not $Map.Contains($Name) -or $null -eq $Map[$Name]) { return $Default }
    $value = $Map[$Name]
    if ($value -is [bool]) { return "$value".ToLowerInvariant() }
    return "$value"
}

function Get-Folder([string] $Folder) {
    $folder = $Folder.Replace('\', '/').TrimEnd('/') -replace '^\./', ''
    if ($folder -in '', '.') { return '' }
    return $folder
}

function Join-Location([string] $Folder, [string] $Command) {
    $folder = Get-Folder $Folder
    if (-not $folder) { return $Command }
    return "cd $folder && $Command"
}

function Format-ScriptCommand([string] $Path) {
    $path = $Path.Replace('\', '/')
    if ($path -notmatch '^\.{0,2}/') { $path = "./$path" }
    if ($path -match '\.ps1$') { return "pwsh -NoProfile -File $path" }
    return $path
}

function Get-InstallCommand([string] $Folder, [string] $Manager) {
    $full = if (Get-Folder $Folder) { Resolve-WorkspacePath (Get-Folder $Folder) $workspace 'folder' } else { $workspace }
    switch ($Manager) {
        'npm' {
            if ((Test-Path -LiteralPath (Join-Path $full 'package-lock.json')) -or (Test-Path -LiteralPath (Join-Path $full 'npm-shrinkwrap.json'))) { 'npm ci' } else { 'npm install' }
        }
        'pnpm' { 'pnpm install --frozen-lockfile' }
        'yarn' { 'yarn install' }
    }
}

function Get-Manager([string] $Folder, [string] $PackageManager) {
    $full = if (Get-Folder $Folder) { Resolve-WorkspacePath (Get-Folder $Folder) $workspace 'folder' } else { $workspace }
    return Get-PackageManager $full $PackageManager
}

# PowerShell list literal for a -Command string. Commands avoid `$` so a POSIX shell running the
# gate does not expand it.
function Format-PwshList([string[]] $Values) { '@(' + (($Values | ForEach-Object { "'$($_.Replace("'", "''"))'" }) -join ', ') + ')' }

function New-Gate([string] $Job, [string] $Name, [string] $Command) { [ordered]@{ name = "$Job / $Name"; command = $Command } }

function Get-NodeGate([string] $Job, $With) {
    $folder = Get-Value $With 'working-directory' '.'
    $manager = Get-Manager $folder (Get-Value $With 'package-manager')
    foreach ($path in Split-ActionList (Get-Value $With 'pre-build')) { New-Gate $Job $path (Format-ScriptCommand $path) }
    foreach ($dependency in Split-ActionList (Get-Value $With 'dependencies')) {
        $dependencyManager = Get-Manager $dependency ''
        New-Gate $Job "build $(Get-Folder $dependency)" (Join-Location $dependency "$(Get-InstallCommand $dependency $dependencyManager) && $dependencyManager run build")
    }
    foreach ($script in (Get-Value $With 'setup') -split '\s+' | Where-Object { $_ }) { New-Gate $Job "$script (setup)" (Join-Location $folder "npm run $script") }
    New-Gate $Job 'install' (Join-Location $folder (Get-InstallCommand $folder $manager))
    foreach ($script in (Get-Value $With 'scripts' 'test') -split '\s+' | Where-Object { $_ }) { New-Gate $Job $script (Join-Location $folder "$manager run $script") }
    foreach ($path in Split-ActionList (Get-Value $With 'post-build')) { New-Gate $Job $path (Format-ScriptCommand $path) }
}

function Get-PwshGate([string] $Job, $With) {
    foreach ($path in Split-ActionList (Get-Value $With 'pre-build')) { New-Gate $Job $path (Format-ScriptCommand $path) }
    if ((Get-Value $With 'analyzer' 'false') -eq 'true') {
        $settings = Get-Value $With 'analyzer-settings'
        $rules = if ($settings) { "-Settings '$settings'" } else { '-Severity Error, Warning' }
        foreach ($path in Split-ActionList (Get-Value $With 'paths' '.')) {
            New-Gate $Job "PSScriptAnalyzer $path" "pwsh -NoProfile -Command ""Invoke-ScriptAnalyzer -Path '$path' -Recurse $rules -EnableExit"""
        }
    }
    $tests = Split-ActionList (Get-Value $With 'tests' 'tests')
    $filter = @(
        $tags = @((Get-Value $With 'tags') -split ',' | ForEach-Object Trim | Where-Object { $_ })
        $excludeTags = @((Get-Value $With 'exclude-tags') -split ',' | ForEach-Object Trim | Where-Object { $_ })
        if ($tags) { "Tag = $(Format-PwshList $tags)" }
        if ($excludeTags) { "ExcludeTag = $(Format-PwshList $excludeTags)" }
    )
    # [bool]1 rather than $true, which a POSIX shell would expand inside the double quotes.
    $configuration = "Run = @{ Path = $(Format-PwshList $tests); Exit = [bool]1 }"
    if ($filter) { $configuration += "; Filter = @{ $($filter -join '; ') }" }
    New-Gate $Job "Pester $($tests -join ', ')" "pwsh -NoProfile -Command ""Invoke-Pester -Configuration @{ $configuration }"""
    foreach ($path in Split-ActionList (Get-Value $With 'post-build')) { New-Gate $Job $path (Format-ScriptCommand $path) }
}

# Line index of each job key under `jobs:`, in document order.
function Get-JobLine([string[]] $Lines) {
    $jobs = [ordered]@{}
    $top = 0
    while ($top -lt $Lines.Count -and $Lines[$top] -notmatch '^jobs:\s*(#.*)?$') { $top++ }
    $indent = $null
    for ($i = $top + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*(#.*)?$') { continue }
        if ($Lines[$i] -match '^\S') { break }
        $width = ($Lines[$i] -replace '^(\s*).*', '$1').Length
        if ($null -eq $indent) { $indent = $width }
        if ($width -eq $indent -and $Lines[$i] -match '^\s*(?<job>[^\s:#]+):') { $jobs[$Matches.job] = $i }
    }
    return $jobs
}

function Get-JobAt($JobLines, [int] $Index) {
    $job = ''
    foreach ($name in $JobLines.Keys) { if ($JobLines[$name] -lt $Index) { $job = $name } }
    return $job
}

function Get-MarkedGate([string] $Workflow, [string[]] $Lines, $JobLines) {
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -notmatch '^\s*#\s*verification:\s*true\s*$') { continue }
        $start = $i + 1
        while ($start -lt $Lines.Count -and $Lines[$start] -match '^\s*(#.*)?$') { $start++ }
        if ($start -ge $Lines.Count -or $Lines[$start] -notmatch '^(?<indent>\s*)-\s') {
            throw "${Workflow}:$($i + 1): '# verification: true' must come right before a step."
        }
        $indent = $Matches.indent.Length
        $end = $start + 1
        while ($end -lt $Lines.Count -and ($Lines[$end] -match '^\s*$' -or ($Lines[$end] -replace '^(\s*).*', '$1').Length -gt $indent)) { $end++ }
        $block = $Lines[$start..($end - 1)] | ForEach-Object { if ($_.Length -gt $indent) { $_.Substring($indent) } else { '' } }
        # ConvertFrom-Yaml writes the list as one object, so it is unrolled after assignment.
        $parsed = ConvertFrom-Yaml ($block -join "`n") -Ordered
        $step = @($parsed)[0]
        $run = (Get-Value $step 'run').Trim()
        if (-not $run) { throw "${Workflow}:$($start + 1): the step marked '# verification: true' has no 'run'." }
        $name = Get-Value $step 'name' ($run -split "`n")[0]
        $job = Get-JobAt $JobLines $start
        [pscustomobject]@{ Line = $start; Gates = @(New-Gate $job $name (Join-Location (Get-Value $step 'working-directory') $run)) }
    }
}

function Get-LibraryGate([string] $Workflow, $JobLines, $Document) {
    $jobs = if ($Document -and $Document.Contains('jobs')) { $Document['jobs'] } else { $null }
    if (-not $jobs) { return }
    foreach ($job in $jobs.Keys) {
        $uses = Get-Value $jobs[$job] 'uses'
        if ($uses -notmatch $libraryWorkflow) { continue }
        $kind = $Matches.kind
        $with = if ($jobs[$job].Contains('with')) { $jobs[$job]['with'] } else { $null }
        if ($with) {
            foreach ($name in $with.Keys) {
                if ("$($with[$name])" -match '\$\{\{') { throw "${Workflow}: job '$job' sets '$name' with an expression; gates are derived from literal inputs." }
            }
        }
        $line = if ($JobLines.Contains($job)) { $JobLines[$job] } else { 0 }
        $gates = if ($kind -eq 'pwsh-ci') { @(Get-PwshGate $job $with) } else { @(Get-NodeGate $job $with) }
        [pscustomobject]@{ Line = $line; Gates = $gates }
    }
}

$found = foreach ($workflowFile in Get-ChildItem -LiteralPath $workflowFolder -File | Where-Object Extension -in '.yml', '.yaml' | Sort-Object Name) {
    $relative = Get-RelativePath $workflowFile.FullName
    $text = (Get-Content -LiteralPath $workflowFile.FullName -Raw) -replace '^\uFEFF', ''
    $lines = $text -split '\r?\n'
    $document = ConvertFrom-Yaml $text -Ordered
    $jobLines = Get-JobLine $lines
    @(Get-LibraryGate $relative $jobLines $document) + @(Get-MarkedGate $relative $lines $jobLines) | Sort-Object Line
}
$expected = @($found | ForEach-Object Gates)
if (-not $expected) { throw "No gates found in '$workflows': no job calls node-ci, pwsh-ci or npm-package, and no step is marked '# verification: true'." }

$json = ([ordered]@{ gates = $expected } | ConvertTo-Json -Depth 5) -replace '\r\n', "`n"

if ($write) {
    [void] (New-Item -ItemType Directory -Force -Path (Split-Path $gatesPath))
    [System.IO.File]::WriteAllText($gatesPath, "$json`n")
    Set-ActionOutput 'status' 'written'
    Set-ActionOutput 'count' "$($expected.Count)"
    Add-ActionSummary "Wrote $($expected.Count) gate(s) to ``$file``."
    Write-Host "Wrote $($expected.Count) gate(s) to $file."
    return
}

function Get-Key($Gate) { "$($Gate['name'])`n$($Gate['command'])" }

$committed = $null
if (Test-Path -LiteralPath $gatesPath -PathType Leaf) {
    try { $committed = (Get-Content -LiteralPath $gatesPath -Raw) -replace '^\uFEFF', '' | ConvertFrom-Json -AsHashtable }
    catch { throw "'$file' is not valid JSON: $($_.Exception.Message)" }
}
$valid = $committed -is [System.Collections.IDictionary] -and $committed['gates'] -is [System.Collections.IList] -and
@($committed['gates'] | Where-Object { $_ -isnot [System.Collections.IDictionary] -or "$($_['name'])".Trim() -eq '' -or "$($_['command'])".Trim() -eq '' }).Count -eq 0

$missing = @(); $extra = @()
if ($valid) {
    $have = @($committed['gates'] | ForEach-Object { Get-Key $_ })
    $want = @($expected | ForEach-Object { Get-Key $_ })
    $missing = @($expected | Where-Object { (Get-Key $_) -notin $have })
    $extra = @($committed['gates'] | Where-Object { (Get-Key $_) -notin $want })
}

if ($valid -and -not $missing -and -not $extra) {
    Set-ActionOutput 'status' 'match'
    Set-ActionOutput 'count' "$($expected.Count)"
    Add-ActionSummary "``$file`` matches the $($expected.Count) gate(s) the workflows run."
    Write-Host "$file matches the $($expected.Count) gate(s) the workflows run."
    return
}

$reason = if (-not $committed) { "'$file' does not exist" }
elseif (-not $valid) { "'$file' must be an object whose 'gates' is a list of objects with a non-blank 'name' and 'command'" }
else { "'$file' is out of date: $($missing.Count) gate(s) missing, $($extra.Count) not run by the workflows" }

foreach ($gate in $missing) { Write-ActionAnnotation 'error' "Missing gate: $($gate['name']): $($gate['command'])" -File $file -Title 'Gates file' }
foreach ($gate in $extra) { Write-ActionAnnotation 'error' "No workflow runs gate: $($gate['name']): $($gate['command'])" -File $file -Title 'Gates file' }
Add-ActionSummary "$reason. Commit this as ``$file``:`n`n``````json`n$json`n```````n"
Write-Host "Expected $($file):`n$json"
throw "$reason. The expected file is in the log and the step summary."

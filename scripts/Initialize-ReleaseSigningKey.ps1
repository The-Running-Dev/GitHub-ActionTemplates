#Requires -Version 7.3
<#
.SYNOPSIS
One-time maintainer setup for a workflow that signs release tags with SSH. Creates (or reuses) a
passphrase-less ed25519 key outside the repository, copies it to an offline backup, stores it as a
secret of a deployment environment that only the release branch can use, and prints the
allowed_signers line for its public half. Safe to re-run.

.DESCRIPTION
Run it on the maintainer's machine, signed in with `gh auth login` as a repository admin. The
private key is piped to `gh secret set` on stdin, so it never appears on screen, in the clipboard
or on a command line. The environment is created when missing, and an environment any branch can
deploy from is restricted to -Branch; one already restricted is left as it is. The workflow job
then names the environment (`environment: release`) to read the secret.

Needs PowerShell 7.3 or later, which passes the empty passphrase to ssh-keygen as an argument.

.EXAMPLE
./scripts/Initialize-ReleaseSigningKey.ps1 -Repository owner/name -BackupDirectory E:\ -AllowedSignersPath ../name/.github/allowed_signers
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[^/\s]+/[^/\s]+$')][string] $Repository,
    # An offline folder (a USB drive, say) for the backup copy, or SKIP when it is already backed up.
    [Parameter(Mandatory)][string] $BackupDirectory,
    [string] $KeyPath = (Join-Path $HOME '.keys' "$($Repository.Split('/')[1].ToLowerInvariant())-release-signing"),
    [string] $SecretName = 'RELEASE_SIGNING_KEY',
    [string] $Environment = 'release',
    [string] $Branch = 'main',
    [string] $Principal = "release-workflow@$($Repository.Split('/')[1])",
    # When given, the allowed_signers line is appended to this file unless the key is already in it.
    [string] $AllowedSignersPath
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

gh auth status *> $null
if ($LASTEXITCODE -ne 0) { throw 'Run gh auth login first.' }

if (Test-Path -LiteralPath $KeyPath) {
    Write-Host "Reusing existing key $KeyPath"
}
else {
    New-Item -ItemType Directory -Force (Split-Path $KeyPath) | Out-Null
    ssh-keygen -q -t ed25519 -N '' -C $Principal -f $KeyPath
    if ($LASTEXITCODE -ne 0) { throw "ssh-keygen could not create $KeyPath." }
    Write-Host "Created $KeyPath"
}

# Windows OpenSSH ignores a private key that any other account can read, and a file under the
# profile can inherit such an entry (a sandbox users group, say), so only the owner keeps access.
if ($IsWindows) {
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    icacls $KeyPath /reset /Q | Out-Null
    icacls $KeyPath /inheritance:r /grant:r "*${owner}:F" /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not restrict $KeyPath to the current user." }
}

# -P '' fails on a key with a passphrase, which a runner has no way to type.
$check = @(ssh-keygen -y -P '' -f $KeyPath 2>&1)
$publicLine = $check | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] } | Select-Object -First 1
if ($LASTEXITCODE -ne 0 -or -not $publicLine) {
    $reason = ($check | Where-Object { $_ -is [Management.Automation.ErrorRecord] }) -join ' '
    throw "$KeyPath is not a passphrase-less OpenSSH private key. ssh-keygen: $reason"
}
$fields = "$publicLine".Trim() -split '\s+'
if ($fields[0] -ne 'ssh-ed25519') { throw "$KeyPath is a $($fields[0]) key, not ssh-ed25519." }
$publicKey = "$($fields[0]) $($fields[1])"

# Losing the key only means making a new one, but every release it signed then verifies only
# against the old allowed_signers line, so the backup comes before anything depends on it.
if ($BackupDirectory -ne 'SKIP') {
    if (-not (Test-Path -LiteralPath $BackupDirectory -PathType Container)) { throw "Backup folder not found: $BackupDirectory" }
    $backup = Join-Path $BackupDirectory (Split-Path $KeyPath -Leaf)
    if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $KeyPath $backup }
    if ((Get-FileHash -LiteralPath $backup).Hash -ne (Get-FileHash -LiteralPath $KeyPath).Hash) { throw "$backup exists but differs from $KeyPath." }
    Write-Host "Backup verified: $backup"
}

$environmentPath = "repos/$Repository/environments/$Environment"
$current = gh api $environmentPath 2> $null
$policy = $LASTEXITCODE -eq 0 ? ($current | ConvertFrom-Json).deployment_branch_policy : $null
if (-not $policy) {
    gh api -X PUT $environmentPath -F 'deployment_branch_policy[protected_branches]=false' -F 'deployment_branch_policy[custom_branch_policies]=true' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not create or restrict the $Environment environment." }
    $policy = [pscustomobject]@{ protected_branches = $false; custom_branch_policies = $true }
}
if ($policy.custom_branch_policies) {
    $names = @(gh api "$environmentPath/deployment-branch-policies" --jq '.branch_policies[] | select(.type != "tag") | .name')
    if ($LASTEXITCODE -ne 0) { throw "Could not read the $Environment environment's branch policies." }
    if ($names -notcontains $Branch) {
        gh api -X POST "$environmentPath/deployment-branch-policies" -f "name=$Branch" -f 'type=branch' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not allow $Branch to deploy to $Environment." }
    }
    Write-Host "Environment $Environment deploys from: $((@($names) + $Branch | Select-Object -Unique) -join ', ')"
}
else {
    Write-Host "Environment $Environment deploys from protected branches only; left as it is."
}

Get-Content -LiteralPath $KeyPath -Raw | gh secret set $SecretName -R $Repository -e $Environment
if ($LASTEXITCODE -ne 0) { throw 'gh secret set failed.' }
$secrets = gh secret list -R $Repository -e $Environment --json name --jq '.[].name'
if ($LASTEXITCODE -ne 0 -or @($secrets) -notcontains $SecretName) { throw 'The secret is not listed after setting it.' }
Write-Host "Secret $SecretName set on $Repository ($Environment)"

$signer = "$Principal namespaces=`"git`" $publicKey"
if ($AllowedSignersPath) {
    $existing = (Test-Path -LiteralPath $AllowedSignersPath) ? (Get-Content -LiteralPath $AllowedSignersPath -Raw) : ''
    if ($existing -and $existing.Contains($fields[1])) {
        Write-Host "$AllowedSignersPath already lists this key."
    }
    else {
        $separator = $existing -and -not $existing.EndsWith("`n") ? "`n" : ''
        [IO.File]::AppendAllText([IO.Path]::GetFullPath($AllowedSignersPath), "$separator$signer`n")
        Write-Host "Added the key to $AllowedSignersPath"
    }
}
Write-Output $signer

#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' '_lib' 'Functions.psm1') -Force

$context = Get-ActionContext
$registry = (Get-ActionInput 'registry' 'ghcr.io').TrimEnd('/')
$imageName = Get-ActionInput 'image-name' $context.Repository

$image = (@($registry, $context.Owner, $imageName) | Where-Object { $_ }) -join '/'
$refSlug = ConvertTo-Slug $(if ($context.Branch) { $context.Branch } else { $context.RefName })

function ConvertTo-Flag([bool] $Value) { $Value.ToString().ToLowerInvariant() }

Set-ActionOutput 'owner' $context.Owner.ToLowerInvariant()
Set-ActionOutput 'repository' $context.Repository
Set-ActionOutput 'sha' $context.Sha
Set-ActionOutput 'short-sha' $context.ShortSha
Set-ActionOutput 'event' $context.EventName
Set-ActionOutput 'ref-name' $context.RefName
Set-ActionOutput 'branch' $context.Branch
Set-ActionOutput 'ref-slug' $refSlug
Set-ActionOutput 'default-branch' $context.DefaultBranch
Set-ActionOutput 'is-pull-request' (ConvertTo-Flag $context.IsPullRequest)
Set-ActionOutput 'is-tag' (ConvertTo-Flag $context.IsTag)
Set-ActionOutput 'is-default-branch' (ConvertTo-Flag $context.IsDefaultBranch)
Set-ActionOutput 'should-publish' (ConvertTo-Flag $context.ShouldPublish)
Set-ActionOutput 'image' $image.ToLowerInvariant()

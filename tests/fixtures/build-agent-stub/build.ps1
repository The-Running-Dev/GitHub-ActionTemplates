# Stands in for the build-agent image's `build` command in the docs-build tests: records its
# arguments and the template repository's files to $env:STUB_LOG, then writes the site where
# `build node-template` would.
$named = @{}
for ($i = 1; $i -lt $args.Count; $i += 2) { $named[([string] $args[$i]).TrimStart('-')] = $args[$i + 1] }

$args | Set-Content -LiteralPath (Join-Path $env:STUB_LOG 'args.txt')
git -C ([uri] $named['NodeTemplateRepositoryUrl']).LocalPath ls-files | Set-Content -LiteralPath (Join-Path $env:STUB_LOG 'template.txt')

$site = Join-Path $named['WorkingDir'] $named['AppDir'] 'build'
New-Item -ItemType Directory -Path $site -Force | Out-Null
Set-Content -LiteralPath (Join-Path $site 'index.html') -Value 'stub site'

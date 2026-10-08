# Stands in for npm in the npm-publish tests. Records the arguments, the --userconfig file's text
# and whether NODE_AUTH_TOKEN is set to $env:STUB_LOG/npm.txt.
$log = Join-Path $env:STUB_LOG 'npm.txt'
Add-Content -LiteralPath $log -Value "ARGS: $($args -join ' ')"

$config = [array]::IndexOf($args, '--userconfig')
if ($config -ge 0) { Get-Content -LiteralPath $args[$config + 1] | ForEach-Object { Add-Content -LiteralPath $log -Value "CONFIG: $_" } }
Add-Content -LiteralPath $log -Value "TOKEN: $(if ($env:NODE_AUTH_TOKEN) { 'set' } else { 'unset' })"
exit 0

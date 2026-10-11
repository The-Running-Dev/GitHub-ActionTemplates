# Stands in for cosign in the image-push tests. Appends each call's arguments to
# $env:STUB_LOG/cosign.txt.
Add-Content -LiteralPath (Join-Path $env:STUB_LOG 'cosign.txt') -Value ($args -join ' ')
exit 0

#Requires -Version 7.2
# Runs on the runner after the container is ready (container.yml `smoke`), with IMAGE, CONTAINER
# and SMOKE_URL set.
$ErrorActionPreference = 'Stop'

foreach ($name in 'IMAGE', 'CONTAINER', 'SMOKE_URL') {
    if (-not [Environment]::GetEnvironmentVariable($name)) { throw "$name is not set." }
}
$page = Invoke-WebRequest -Uri "$env:SMOKE_URL/version.txt"
if ("$($page.Content)".Trim() -ne 'from-build-arg') { throw "version.txt says '$($page.Content)', not the build argument." }
Write-Host "Fixture $env:IMAGE ($env:CONTAINER) serves the build argument."

# Build both brand AABs for Google Play.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

& "$PSScriptRoot\build-kpax-play.ps1"
& "$PSScriptRoot\build-xplm-play.ps1"

Write-Host ""
Write-Host "Store Android artifacts:"
Write-Host "  K-Pax: build\app\outputs\bundle\kpaxPlayRelease\app-kpax-play-release.aab"
Write-Host "  X-Plm: build\app\outputs\bundle\xplmPlayRelease\app-xplm-play-release.aab"

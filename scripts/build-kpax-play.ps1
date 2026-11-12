# Build K-Pax AAB for Google Play (channel=play, no REQUEST_INSTALL_PACKAGES).
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

flutter build appbundle `
  --release `
  --flavor kpaxPlay `
  --dart-define=BRAND=kpax `
  --dart-define=PLAY_STORE=true

$out = Join-Path (Get-Location) 'build\app\outputs\bundle\kpaxPlayRelease\app-kpax-play-release.aab'
Write-Host "AAB: $out"
if (-not (Test-Path $out)) {
  throw "AAB not found at $out"
}

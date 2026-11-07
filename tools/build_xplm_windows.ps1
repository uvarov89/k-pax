# Build the native executable and Flutter UI with the same X-Plm brand.
[CmdletBinding()]
param([switch]$Installer)
$ErrorActionPreference = 'Stop'
$previousBrand = $env:APP_BRAND
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
  $env:APP_BRAND = 'xplm'
  flutter build windows --release --dart-define=BRAND=xplm
  if ($LASTEXITCODE -ne 0) { throw 'X-Plm Windows build failed' }
  if (!(Test-Path -LiteralPath 'build/windows/x64/runner/Release/XPlm.exe')) {
    throw 'Expected XPlm.exe was not produced. Check the CMake brand configuration.'
  }
  if ($Installer) {
    $versionText = Get-Content -LiteralPath 'pubspec.yaml' -Raw
    $versionMatch = [regex]::Match($versionText, '(?m)^version:\s*([^+\r\n]+)')
    if (!$versionMatch.Success) { throw 'Version is missing in pubspec.yaml' }
    $appVersion = $versionMatch.Groups[1].Value.Trim()
    $iscc = @(
      "$env:LocalAppData\Programs\Inno Setup 6\ISCC.exe",
      "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
      "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (!$iscc) {
      $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
      if ($cmd) { $iscc = $cmd.Source }
    }
    if (!$iscc) { throw 'ISCC.exe not found. Install Inno Setup 6.' }
    & $iscc "/DMyAppVersion=$appVersion" windows/installer/x-plm.iss
    if ($LASTEXITCODE -ne 0) { throw 'X-Plm installer build failed' }
  }
} finally {
  $env:APP_BRAND = $previousBrand
  Pop-Location
}

# Build + publish signed-ready Windows installers for K-Pax and X-Plm 1.0.60.
# Requires: flutter, Inno Setup 6 (ISCC), gh auth, and provisioned sing-box 1.13.21.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if (!(Get-Command gh -ErrorAction SilentlyContinue)) {
        throw 'GitHub CLI (gh) not found.'
    }
    & gh auth status
    if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not authenticated.' }

    $manifest = Get-Content 'pubspec.yaml' -Raw
    if ($manifest -notmatch '(?m)^version:\s*1\.0\.60\+85\s*$') {
        throw 'Expected pubspec.yaml version 1.0.60+85. Update source before release.'
    }

    $versionFile = 'third_party/sing-box/windows/VERSION'
    if (!(Test-Path $versionFile) -or ((Get-Content $versionFile -Raw).Trim() -ne '1.13.21')) {
        throw 'sing-box Windows binary is not 1.13.21. Run scripts/provision-windows-native.ps1 first.'
    }

    $isccCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    )
    $iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (!$iscc) { throw 'ISCC.exe not found. Install Inno Setup 6.' }

    $vcvars = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
    if (!(Test-Path $vcvars)) { throw "vcvars64.bat not found at $vcvars" }

    $notes = @'
1.0.60: Hiddify-aligned TUN/DNS: TCP remote DNS, UDP direct DNS, /28 MTU 9000, Windows strict_route forced off. sing-box 1.13.21.
'@

    $brands = @(
        @{
            Key = 'kpax'
            BrandEnv = ''
            DartBrand = 'kpax'
            Exe = 'KPax.exe'
            Iss = 'windows\installer\k-pax.iss'
            File = 'K-Pax-Setup-1.0.60.exe'
            Tag = 'v1.0.60-windows'
            Name = 'K-Pax 1.0.60 Windows'
        },
        @{
            Key = 'xplm'
            BrandEnv = 'xplm'
            DartBrand = 'xplm'
            Exe = 'XPlm.exe'
            Iss = 'windows\installer\x-plm.iss'
            File = 'X-Plm-Setup-1.0.60.exe'
            Tag = 'v1.0.60-xplm-windows'
            Name = 'X-Plm 1.0.60 Windows'
        }
    )

    New-Item -ItemType Directory -Path 'build\release' -Force | Out-Null
    $built = @()

    foreach ($item in $brands) {
        # Full windows cmake wipe required when switching BINARY_NAME (KPax <-> XPlm).
        if (Test-Path 'build\windows') {
            Remove-Item -LiteralPath 'build\windows' -Recurse -Force
        }

        $brandLine = if ($item.BrandEnv) { "set APP_BRAND=$($item.BrandEnv)" } else { 'set APP_BRAND=' }
        $cmd = @"
@echo off
call "$vcvars" >nul
cd /d "%CD%"
$brandLine
flutter build windows --release --dart-define=BRAND=$($item.DartBrand)
exit /b %ERRORLEVEL%
"@
        $tmp = Join-Path $env:TEMP ("kpax-win-build-" + $item.Key + ".cmd")
        Set-Content -Path $tmp -Value $cmd -Encoding ASCII
        try {
            & cmd.exe /c $tmp
            if ($LASTEXITCODE -ne 0) { throw "Windows build failed for $($item.Key)" }
        } finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }

        $releaseDir = 'build\windows\x64\runner\Release'
        $exePath = Join-Path $releaseDir $item.Exe
        if (!(Test-Path $exePath)) { throw "Missing exe after build: $exePath" }
        Copy-Item 'third_party\sing-box\windows\sing-box.exe' (Join-Path $releaseDir 'sing-box.exe') -Force
        Copy-Item 'third_party\sing-box\windows\wintun.dll' (Join-Path $releaseDir 'wintun.dll') -Force

        & $iscc $item.Iss
        if ($LASTEXITCODE -ne 0) { throw "ISCC failed for $($item.Key)" }

        $setup = Join-Path 'build\windows\installer' $item.File
        if (!(Test-Path $setup)) { throw "Installer missing: $setup" }
        $dest = Join-Path 'build\release' $item.File
        Copy-Item $setup $dest -Force
        $built += @{ Item = $item; Path = $dest }
        Write-Host "Built $($item.File)"
    }

    Remove-Item Env:APP_BRAND -ErrorAction SilentlyContinue

    foreach ($entry in $built) {
        $item = $entry.Item
        & gh release view $item.Tag --repo uvarov89/k-pax 2>$null
        if ($LASTEXITCODE -eq 0) {
            & gh release upload $item.Tag $entry.Path --repo uvarov89/k-pax --clobber
        } else {
            & gh release create $item.Tag $entry.Path --repo uvarov89/k-pax --target main --title $item.Name --notes $notes --latest=false
        }
        if ($LASTEXITCODE -ne 0) { throw "GitHub Windows release failed for $($item.Key)" }
        Write-Host "Published $($item.Name)"
    }
} finally {
    Remove-Item Env:APP_BRAND -ErrorAction SilentlyContinue
    Pop-Location
}

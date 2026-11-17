# Build + publish signed-ready Windows installers for K-Pax and X-Plm 1.0.66.
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
    if ($manifest -notmatch '(?m)^version:\s*1\.0\.67\+92\s*$') {
        throw 'Expected pubspec.yaml version 1.0.67+92. Update source before release.'
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
    # Empty CMAKE_RC_COMPILER breaks jni C ABI probe (get_filename_component args).
    $rcCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin\10.0.22621.0\x64\rc.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin\10.0.26100.0\x64\rc.exe')
    )
    $rcExe = $rcCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (!$rcExe) {
        $rcExe = Get-ChildItem -LiteralPath (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin') -Recurse -Filter 'rc.exe' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\x64\\rc\.exe$' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if (!$rcExe) { throw 'Windows SDK rc.exe not found.' }

    $notes = @'
1.0.67: Fix in-app update download when Always-on VPN blocks clearnet. sing-box 1.13.21.
'@

    $brands = @(
        @{
            Key = 'kpax'
            BrandEnv = ''
            DartBrand = 'kpax'
            Exe = 'KPax.exe'
            Iss = 'windows\installer\k-pax.iss'
            File = 'K-Pax-Setup-1.0.67.exe'
            Tag = 'v1.0.67-windows'
            Name = 'K-Pax 1.0.67 Windows'
        },
        @{
            Key = 'xplm'
            BrandEnv = 'xplm'
            DartBrand = 'xplm'
            Exe = 'XPlm.exe'
            Iss = 'windows\installer\x-plm.iss'
            File = 'X-Plm-Setup-1.0.67.exe'
            Tag = 'v1.0.67-xplm-windows'
            Name = 'X-Plm 1.0.67 Windows'
        }
    )

    New-Item -ItemType Directory -Path 'build\release' -Force | Out-Null
    $built = @()

    function Clear-WindowsBuildTree {
        param([string]$Path = 'build\windows')
        if (!(Test-Path -LiteralPath $Path)) { return }
        # BINARY_NAME switches need a clean tree; tolerate locked CMakeConfigureLog.yaml.
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
                ForEach-Object {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $Path) {
                $parkName = "windows.old.$((Get-Date).ToString('yyyyMMddHHmmss'))"
                Rename-Item -LiteralPath $Path -NewName $parkName -ErrorAction SilentlyContinue
                if (Test-Path -LiteralPath $Path) {
                    Write-Warning "Could not fully clear $Path (locked files remain); continuing with flutter build."
                } else {
                    Write-Host "Parked locked windows build tree as build\$parkName"
                }
            }
        } finally {
            $ErrorActionPreference = $prevEap
        }
    }

    foreach ($item in $brands) {
        # Native APP_BRAND and Dart BRAND must stay paired (exe name + UI hosts).
        $expectedNative = if ($item.DartBrand -eq 'xplm') { 'xplm' } else { '' }
        if ($item.BrandEnv -ne $expectedNative) {
            throw "Brand knob mismatch for $($item.Key): APP_BRAND='$($item.BrandEnv)' vs BRAND=$($item.DartBrand)"
        }
        if (($item.DartBrand -eq 'xplm' -and $item.Exe -ne 'XPlm.exe') -or
            ($item.DartBrand -eq 'kpax' -and $item.Exe -ne 'KPax.exe')) {
            throw "Exe name does not match Dart brand for $($item.Key): $($item.Exe)"
        }

        # Full windows cmake wipe required when switching BINARY_NAME (KPax <-> XPlm).
        Clear-WindowsBuildTree

        $brandLine = if ($item.BrandEnv) { "set APP_BRAND=$($item.BrandEnv)" } else { 'set APP_BRAND=' }
        $cmd = @"
@echo off
call "$vcvars" >nul
cd /d "%CD%"
$brandLine
set "RC=$rcExe"
set "CMAKE_RC_COMPILER=$rcExe"
rem flutter.bat must be CALL'ed or the parent .cmd exits after the first flutter invocation.
call flutter build windows --release --dart-define=BRAND=$($item.DartBrand)
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
        # gh writes "release not found" to stderr; Stop would abort before create.
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & gh release view $item.Tag --repo uvarov89/k-pax 1>$null 2>$null
        $viewExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEap
        if ($viewExit -eq 0) {
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


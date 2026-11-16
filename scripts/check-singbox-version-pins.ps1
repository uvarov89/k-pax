# Fail CI when checked-in Libbox / sing-box version references drift from
# scripts/singbox-version-pins.env. Intentional Android skew is allowed when
# ANDROID_LIBBOX != SINGBOX_RELEASE (see VPN_REPAIR_NOTES.md blocker).
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$pinsPath = Join-Path $PSScriptRoot 'singbox-version-pins.env'
if (-not (Test-Path -LiteralPath $pinsPath)) {
    throw "Missing pin file: $pinsPath"
}

$pins = @{}
Get-Content -LiteralPath $pinsPath | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) { return }
    $parts = $line.Split('=', 2)
    if ($parts.Length -ne 2) { return }
    $pins[$parts[0].Trim()] = $parts[1].Trim()
}

foreach ($key in @('SINGBOX_RELEASE', 'ANDROID_LIBBOX', 'ANDROID_LIBBOX_TARGET')) {
    if (-not $pins.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($pins[$key])) {
        throw "Pin file missing required key: $key"
    }
}

$release = $pins['SINGBOX_RELEASE']
$android = $pins['ANDROID_LIBBOX']
$androidTarget = $pins['ANDROID_LIBBOX_TARGET']
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-FileContains([string]$RelativePath, [string]$Needle, [string]$Label) {
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        $script:failures.Add("missing file $RelativePath ($Label)")
        return
    }
    $text = Get-Content -LiteralPath $path -Raw
    if ($text -notlike "*$Needle*") {
        $script:failures.Add("${RelativePath}: expected '${Needle}' (${Label})")
    }
}

Assert-FileContains 'scripts/provision-windows-native.ps1' "`$expectedVersion = '$release'" 'Windows provision expected version'
Assert-FileContains 'scripts/provision-windows-native.ps1' 'sing-box-$expectedVersion-windows-amd64.zip' 'Windows archive name template'
Assert-FileContains 'ios/scripts/build_libbox.sh' "v$release" 'iOS Libbox default tag'
Assert-FileContains 'codemagic.yaml' "LIBBOX_SINGBOX_TAG: v$release" 'Codemagic iOS Libbox tag'
Assert-FileContains 'third_party/flutter_singbox_vpn/android/build.gradle' "com.github.singbox-android:libbox:$android" 'Android JitPack Libbox'
Assert-FileContains '.github/workflows/singbox-config-smoke.yml' "sing-box-$release-linux-amd64.tar.gz" 'config smoke primary binary'
Assert-FileContains '.github/workflows/singbox-config-smoke.yml' "sing-box-$android-linux-amd64.tar.gz" 'config smoke Android parity binary'

if ($failures.Count -gt 0) {
    Write-Host 'sing-box / Libbox version pin check FAILED:'
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

if ($android -ne $release) {
    Write-Host "NOTE: intentional Android Libbox skew: $android (pinned) vs sing-box $release (iOS/Windows)."
    Write-Host "      Target Android Libbox: $androidTarget — see VPN_REPAIR_NOTES.md (blocked: incomplete JitPack AAR)."
} elseif ($android -ne $androidTarget) {
    Write-Host "NOTE: ANDROID_LIBBOX_TARGET=$androidTarget differs from current pin $android."
}

Write-Host "OK: version pins match (SINGBOX_RELEASE=$release, ANDROID_LIBBOX=$android)."

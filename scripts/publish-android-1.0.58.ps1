# Local one-command release for signed Android APKs, using existing original
# keystore already configured on the user's Windows development machine.
# Never commit android/key.properties or *.jks to a public repository.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if (!(Test-Path 'android/key.properties')) {
        throw 'Missing android/key.properties (original release signing configuration).'
    }
    $props = Get-Content 'android/key.properties' -Raw
    if ($props -notmatch '(?m)^storeFile\s*=') {
        throw 'key.properties has no storeFile. Use the original release key.'
    }
    $keystoreName = ([regex]::Match($props, '(?m)^storeFile\s*=\s*(.+?)\s*$')).Groups[1].Value.Trim()
    if (!(Test-Path (Join-Path 'android/app' $keystoreName))) {
        throw "Original keystore not found at android/app/$keystoreName"
    }
    if (!(Get-Command gh -ErrorAction SilentlyContinue)) {
        throw 'GitHub CLI (gh) not found. Install GitHub CLI and authenticate with gh auth login.'
    }
    & gh auth status
    if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not authenticated.' }

    $manifest = Get-Content 'pubspec.yaml' -Raw
    if ($manifest -notmatch '(?m)^version:\s*1\.0\.58\+75\s*$') {
        throw 'Expected pubspec.yaml version 1.0.58+75. Update source before release.'
    }
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed.' }

    $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
    if (!$sdk) { $sdk = Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
    $apksigner = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Filter 'apksigner.bat' -Recurse -ErrorAction Stop |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (!$apksigner) { throw 'Android SDK apksigner not found.' }

    New-Item -ItemType Directory -Path 'build/release' -Force | Out-Null
    $brands = @(
        @{ Key='kpax'; Brand='kpax'; Flavor='kpaxDirect'; Path='app-kpaxdirect-release.apk'; PrevTag='v1.0.57'; Prev='K-Pax-1.0.57.apk'; File='K-Pax-1.0.58.apk'; Tag='v1.0.58'; Name='K-Pax 1.0.58 Android' },
        @{ Key='xplm'; Brand='xplm'; Flavor='xplmDirect'; Path='app-xplmdirect-release.apk'; PrevTag='v1.0.57-xplm'; Prev='X-Plm-1.0.57.apk'; File='X-Plm-1.0.58.apk'; Tag='v1.0.58-xplm'; Name='X-Plm 1.0.58 Android' }
    )

    foreach ($item in $brands) {
        & flutter build apk --release --flavor $item.Flavor "--dart-define=BRAND=$($item.Brand)"
        if ($LASTEXITCODE -ne 0) { throw "Release build failed for $($item.Key)" }
        $newApk = Join-Path 'build/app/outputs/flutter-apk' $item.Path
        if (!(Test-Path $newApk)) { throw "APK missing: $newApk" }
        $oldApk = Join-Path $env:TEMP $item.Prev
        $download = "https://github.com/uvarov89/k-pax/releases/download/$($item.PrevTag)/$($item.Prev)"
        Invoke-WebRequest -Uri $download -OutFile $oldApk -MaximumRedirection 10
        $oldSignature = (& $apksigner verify --print-certs $oldApk 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw "Previous APK failed signature verification: $oldApk" }
        $newSignature = (& $apksigner verify --print-certs $newApk 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw "New APK failed signature verification: $newApk" }
        $rx = 'Signer #1 certificate SHA-256 digest:\s*([0-9a-f]+)'
        $oldCert = [regex]::Match($oldSignature, $rx).Groups[1].Value
        $newCert = [regex]::Match($newSignature, $rx).Groups[1].Value
        if (!$oldCert -or $oldCert -ne $newCert) {
            throw "Signing certificate mismatch for $($item.Key). NOT publishing."
        }
        $dest = Join-Path 'build/release' $item.File
        Copy-Item $newApk $dest -Force
        Write-Host "Verified matching original signing certificate for $($item.Key)"
    }

    # Publish only after BOTH APKs have passed certificate verification.
    foreach ($item in $brands) {
        $file = Join-Path 'build/release' $item.File
        & gh release create $item.Tag $file --repo uvarov89/k-pax --target main --title $item.Name --notes '1.0.58: sing-box DNS, Android TUN and connection verification fixes.' --latest=false
        if ($LASTEXITCODE -ne 0) { throw "GitHub Android release failed for $($item.Key)" }
        Write-Host "Published $($item.Name)"
    }
} finally {
    Pop-Location
}

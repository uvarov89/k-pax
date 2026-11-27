# Local one-command release for signed Android APKs.
[CmdletBinding()]
param([switch]$SkipPublish)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if (!(Test-Path 'android/key.properties')) { throw 'Missing android/key.properties' }
    $manifest = Get-Content 'pubspec.yaml' -Raw
    if ($manifest -notmatch '(?m)^version:\s*1\.0\.84\+109\s*$') {
        throw 'Expected pubspec.yaml version 1.0.84+109'
    }
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
    $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
    if (!$sdk) { $sdk = Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
    $apksigner = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Filter 'apksigner.bat' -Recurse -ErrorAction Stop |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    New-Item -ItemType Directory -Path 'build/release' -Force | Out-Null
    $notes = @(
        '1.0.84 forward rehab after 1.0.79–1.0.83 SoftProbe noise:',
        '- Reality sticky back to :443 then RU fronts (not fronts-first / 1.0.69)',
        '- Measured sticky remembers last SoftProbe-OK endpoint/country',
        '- Failover trySpares stops when attempt budget is exhausted (no spin)',
        '- SoftProbe endpoint race + safer settle; MTU stays 1400 (1.0.50 shape)',
        '- Subscription UA includes OS for panel diagnostics'
    ) -join "`n"
    $brands = @(
        @{ Key='kpax'; Brand='kpax'; Flavor='kpaxDirect'; Path='app-kpaxdirect-release.apk'; PrevTag='v1.0.83'; Prev='K-Pax-1.0.83.apk'; File='K-Pax-1.0.84.apk'; Tag='v1.0.84'; Name='K-Pax 1.0.84 Android' },
        @{ Key='xplm'; Brand='xplm'; Flavor='xplmDirect'; Path='app-xplmdirect-release.apk'; PrevTag='v1.0.83-xplm'; Prev='X-Plm-1.0.83.apk'; File='X-Plm-1.0.84.apk'; Tag='v1.0.84-xplm'; Name='X-Plm 1.0.84 Android' }
    )
    foreach ($item in $brands) {
        & flutter build apk --release --flavor $item.Flavor "--dart-define=BRAND=$($item.Brand)"
        if ($LASTEXITCODE -ne 0) { throw "build failed $($item.Key)" }
        $newApk = Join-Path 'build/app/outputs/flutter-apk' $item.Path
        $oldApk = Join-Path $env:TEMP $item.Prev
        curl.exe -L --retry 5 --retry-delay 2 -o $oldApk "https://github.com/uvarov89/k-pax/releases/download/$($item.PrevTag)/$($item.Prev)"
        if ($LASTEXITCODE -ne 0) { throw "download prev failed" }
        $oldSignature = (& $apksigner verify --print-certs $oldApk 2>&1 | Out-String)
        $newSignature = (& $apksigner verify --print-certs $newApk 2>&1 | Out-String)
        $rx = 'Signer #1 certificate SHA-256 digest:\s*([0-9a-f]+)'
        $oldCert = [regex]::Match($oldSignature, $rx).Groups[1].Value
        $newCert = [regex]::Match($newSignature, $rx).Groups[1].Value
        if (!$oldCert -or $oldCert -ne $newCert) { throw "cert mismatch $($item.Key)" }
        Copy-Item $newApk (Join-Path 'build/release' $item.File) -Force
        Write-Host "Verified $($item.Key)"
    }
    if ($SkipPublish) { return }
    foreach ($item in $brands) {
        $file = Join-Path 'build/release' $item.File
        $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & gh release view $item.Tag --repo uvarov89/k-pax 1>$null 2>$null
        $viewExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEap
        if ($viewExit -eq 0) {
            & gh release upload $item.Tag $file --repo uvarov89/k-pax --clobber
        } else {
            & gh release create $item.Tag $file --repo uvarov89/k-pax --target main --title $item.Name --notes $notes --latest=false
        }
        if ($LASTEXITCODE -ne 0) { throw "publish failed $($item.Key)" }
        Write-Host "Published $($item.Name)"
    }
} finally { Pop-Location }

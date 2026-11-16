# Fetch signed official Windows native dependencies for local/CI builds.
# No credentials or repo releases are used. Both archives have pinned hashes.
# Version must match scripts/singbox-version-pins.env (SINGBOX_RELEASE).
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$destination = Join-Path $root 'third_party/sing-box/windows'
$working = Join-Path ([System.IO.Path]::GetTempPath()) ('kpax-win-deps-' + [guid]::NewGuid().ToString('N'))
$expectedVersion = '1.13.21'
New-Item -ItemType Directory -Force -Path $destination, $working | Out-Null

function Fetch-Verified([string]$Uri, [string]$Hash, [string]$Name) {
    $target = Join-Path $working $Name
    Invoke-WebRequest -Uri $Uri -OutFile $target
    $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Hash.ToLowerInvariant()) {
        throw "SHA256 mismatch for $Name. Expected $Hash, got $actual"
    }
    return $target
}

try {
    $singArchive = Fetch-Verified "https://github.com/SagerNet/sing-box/releases/download/v$expectedVersion/sing-box-$expectedVersion-windows-amd64.zip" 'a03291793d3a3c6e266447a58140657ac099ff278abf3b8ff678932356a62ced' 'sing-box.zip'
    $singFolder = Join-Path $working 'singbox'
    Expand-Archive -LiteralPath $singArchive -DestinationPath $singFolder -Force
    $singExecutable = Get-ChildItem -LiteralPath $singFolder -Recurse -Filter 'sing-box.exe' -File | Select-Object -First 1
    if (-not $singExecutable) { throw 'sing-box.exe not found in signed archive' }
    $destExe = Join-Path $destination 'sing-box.exe'
    Copy-Item -LiteralPath $singExecutable.FullName -Destination $destExe -Force

    $versionText = & $destExe version 2>&1 | Out-String
    if ($versionText -notmatch [regex]::Escape("sing-box version $expectedVersion")) {
        throw "sing-box.exe version mismatch. Expected $expectedVersion, got: $($versionText.Trim())"
    }
    Set-Content -LiteralPath (Join-Path $destination 'VERSION') -Value $expectedVersion -NoNewline

    $tunArchive = Fetch-Verified 'https://www.wintun.net/builds/wintun-0.14.1.zip' '07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51' 'wintun.zip'
    $tunFolder = Join-Path $working 'wintun'
    Expand-Archive -LiteralPath $tunArchive -DestinationPath $tunFolder -Force
    $tunExecutable = Join-Path $tunFolder 'wintun/bin/amd64/wintun.dll'
    if (-not (Test-Path -LiteralPath $tunExecutable)) { throw 'wintun.dll not found in verified archive' }
    $signature = Get-AuthenticodeSignature -LiteralPath $tunExecutable
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'WireGuard LLC') {
        throw "wintun.dll signature verification failed: $($signature.Status)"
    }
    Copy-Item -LiteralPath $tunExecutable -Destination (Join-Path $destination 'wintun.dll') -Force

    $license = Join-Path $destination 'LICENSE'
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/SagerNet/sing-box/v$expectedVersion/LICENSE" -OutFile $license
    $tunLicense = Get-ChildItem -LiteralPath $tunFolder -Recurse -File | Where-Object { $_.Name -match '^LICENSE' } | Select-Object -First 1
    if ($tunLicense) {
        Copy-Item -LiteralPath $tunLicense.FullName -Destination (Join-Path $destination 'LICENSE-Wintun.txt') -Force
    }
    Write-Host "Verified sing-box.exe $expectedVersion + Wintun.dll are present for Windows builds."
} finally {
    Remove-Item -LiteralPath $working -Recurse -Force -ErrorAction SilentlyContinue
}

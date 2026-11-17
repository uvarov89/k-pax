# Android native VPN/TUN diagnostics, user-controlled. Run during a failing
# session over USB with ADB installed. It never changes app data/settings.
# Local logs can include network addresses; NEVER upload raw to public GitHub.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('kpax','xplm')]
    [string]$Brand,
    [string]$Serial = '',
    [string]$OutputDir = (Join-Path $env:LOCALAPPDATA 'K-Pax-QA')
)
$ErrorActionPreference = 'Stop'
$package = if ($Brand -eq 'xplm') { 'online.xplm.app' } else { 'space.kpax.app' }
$adb = (Get-Command adb.exe -ErrorAction Stop).Source
$selection = @()
if ($Serial) { $selection = @('-s',$Serial) }
& $adb @selection get-state | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'ADB device not available: connect phone and authorize USB debugging.' }

$folder=Join-Path $OutputDir "$Brand-android-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$version=(& $adb @selection shell dumpsys package $package | Select-String 'versionCode=|versionName=|targetSdk=|granted=true' | Select-Object -First 25 | Out-String)
if (!$version) { throw "Application package $package was not found." }
$version | Set-Content -Encoding utf8 (Join-Path $folder 'installed-package.txt')
(& $adb @selection shell getprop ro.build.version.release) | Set-Content -Encoding utf8 (Join-Path $folder 'android-version.txt')

# Dumpsys can reveal private network identifiers: local-only diagnostic.
& $adb @selection shell dumpsys connectivity | Set-Content -Encoding utf8 (Join-Path $folder 'connectivity-private.txt')
& $adb @selection shell dumpsys vpn | Set-Content -Encoding utf8 (Join-Path $folder 'vpn-private.txt')
# The native classes output interface/routing errors. Logs can contain
# hostnames, server IPs or identifiers; keep this file private.
& $adb @selection logcat -d -v time -s 'VPNService:D' 'BoxService:D' 'DefaultNetworkMonitor:D' 'DefaultNetworkListener:D' 'AndroidRuntime:E' '*:S' |
    Set-Content -Encoding utf8 (Join-Path $folder 'vpn-log-private.txt')

Write-Host "$Brand / $package — diagnostic bundle saved locally: $folder"
Write-Host 'Never publish the raw connectivity/log files; redact IPs, tokens and device IDs before sharing.'
Write-Host 'For egress-IP validation, visit https://www.cloudflare.com/cdn-cgi/trace in phone browser with VPN off, third-party on, then K-Pax/X-Plm on; compare the ip= lines for the SAME server.'

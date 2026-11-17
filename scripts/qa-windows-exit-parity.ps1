# Differential IP/DNS probe for a given brand and connection mode.
# Run with the same node/protocol in third-party and proprietary clients.
# Output is local only: it can include public/private IPs. Do not post raw files.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('kpax','xplm')]
    [string]$Brand,
    [Parameter(Mandatory=$true)]
    [ValidateSet('baseline','thirdparty','firstparty')]
    [string]$Phase,
    [string]$OutputDir = (Join-Path $env:LOCALAPPDATA 'K-Pax-QA')
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Trace([string]$Url, [string]$Family) {
    $curl = Get-Command curl.exe -ErrorAction Stop
    $args = @('--silent','--show-error','--location','--max-time','12','--no-progress-meter')
    if ($Family -eq 'ipv4') { $args += '-4' } else { $args += '-6' }
    $args += $Url
    try {
        $output = & $curl.Source @args 2>$null
        $exit = $LASTEXITCODE
        $fields = @{}
        if ($exit -eq 0) {
            foreach ($line in @($output)) {
                if ($line -match '^([a-zA-Z0-9_]+)=(.*)$') { $fields[$Matches[1]] = $Matches[2] }
            }
        }
        return @{ reachable=($exit -eq 0 -and [bool]$fields['ip']); ip=$fields['ip']; loc=$fields['loc']; code=$exit }
    } catch {
        return @{ reachable=$false; ip=$null; loc=$null; code=-1 }
    }
}

$results = @{
    brand=$Brand
    phase=$Phase
    recordedUtc=(Get-Date).ToUniversalTime().ToString('o')
    ipv4=(Trace 'https://www.cloudflare.com/cdn-cgi/trace' 'ipv4')
    ipv6=(Trace 'https://www.cloudflare.com/cdn-cgi/trace' 'ipv6')
    dnsOk=$false
    tunAdapterPresent=$false
    singBoxProcesses=0
    note='Contains IP addresses. Do not publish this file or include subscription URLs.'
}
try { $results.dnsOk=@(Resolve-DnsName -Name www.cloudflare.com -ErrorAction Stop).Count -gt 0 } catch {}
try { $results.tunAdapterPresent=@(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.InterfaceDescription -match 'Wintun|sing-box|tun' -or $_.Name -match 'Wintun|sing-box|tun' }).Count -gt 0 } catch {}
try { $results.singBoxProcesses=@(Get-Process -Name 'sing-box' -ErrorAction SilentlyContinue).Count } catch {}
$file=Join-Path $OutputDir "$Brand-$Phase.json"
$results | ConvertTo-Json -Depth 5 | Set-Content -Path $file -Encoding utf8
Write-Host "Saved (local only): $file"
Write-Host "$Brand / ${Phase}: IPv4 $($results.ipv4.ip), HTTPS=$($results.ipv4.reachable), DNS=$($results.dnsOk), Wintun=$($results.tunAdapterPresent)"

$baselinePath=Join-Path $OutputDir "$Brand-baseline.json"
$referencePath=Join-Path $OutputDir "$Brand-thirdparty.json"
$actualPath=Join-Path $OutputDir "$Brand-firstparty.json"
if ((Test-Path $baselinePath) -and (Test-Path $referencePath) -and (Test-Path $actualPath)) {
    $baseline=Get-Content $baselinePath -Raw | ConvertFrom-Json
    $reference=Get-Content $referencePath -Raw | ConvertFrom-Json
    $actual=Get-Content $actualPath -Raw | ConvertFrom-Json
    if (!$reference.ipv4.reachable) {
        Write-Warning 'Reference third-party VPN does not have measured HTTPS; do not draw conclusions.'
    } elseif (!$actual.ipv4.reachable) {
        Write-Warning 'FAIL: proprietary client has no IPv4 HTTPS traffic.'
    } elseif ($actual.ipv4.ip -eq $baseline.ipv4.ip) {
        Write-Warning 'FAIL: proprietary client appears to use clearnet IP.'
    } elseif ($actual.ipv4.ip -eq $reference.ipv4.ip) {
        Write-Host 'PASS: IPv4 exit IP matches working third-party client on same node.'
    } else {
        Write-Warning 'INCONCLUSIVE: proprietary exit IP differs from third-party. Confirm identical selected endpoint.'
    }
}

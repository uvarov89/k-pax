# Requires elevated PowerShell once after upgrading from older broken builds.
# Removes ONLY legacy rules owned by K-Pax / X-Plm, not Windows Firewall itself.
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
foreach ($name in @(
  'K-Pax-KillSwitch',
  'K-Pax-KillSwitch-App',
  'X-Plm-KillSwitch',
  'X-Plm-KillSwitch-App'
)) {
  & netsh advfirewall firewall delete rule "name=$name" | Out-Null
}
Write-Host 'Legacy K-Pax/X-Plm firewall rules checked and removed.'

# enable-rdp-tailscale.ps1 -- let this machine accept RDP, but ONLY from the tailnet.
#
# Run it ON the machine you want to reach (DESKTOP1), from an ELEVATED PowerShell:
#
#   powershell -ExecutionPolicy Bypass -File C:\1Claude\scripts\newpc\enable-rdp-tailscale.ps1
#
# Then connect from any other tailnet node with the .rdp file in this directory
# (desktop1-rdp.rdp) or:  mstsc /v:100.99.158.19
#
# Same policy the cloud desktop uses (scripts\newpc\CLOUD-DESKTOP.md section 6): RDP on,
# the stock "any source" firewall rules off, one rule allowing 3389 from the Tailscale
# CGNAT range 100.64.0.0/10 only. A home router forwards nothing to 3389 and the tailnet
# is WireGuard, so this does not expose the machine to the internet.
#
# Windows PowerShell 5.1 compatible -- no '&&', no ternary, no null-coalescing.
# ASCII only on purpose: PS 5.1 reads BOM-less UTF-8 as ANSI and mangles non-ASCII.

[CmdletBinding()]
param(
  # Set to $false to keep Network Level Authentication off (only needed for very old clients).
  [bool]$RequireNLA = $true
)

$ErrorActionPreference = "Stop"

function Say ($m) { Write-Host ""; Write-Host $m -ForegroundColor Cyan }
function Ok  ($m) { Write-Host "  ok    $m" -ForegroundColor Green }
function Bad ($m) { Write-Host "  FAIL  $m" -ForegroundColor Red }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
      ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Bad "not elevated -- right-click PowerShell and Run as administrator"
  exit 1
}

# Windows Home cannot HOST an RDP session (the client works everywhere). Catching it here
# beats a green run followed by a connection that is refused with no reason given.
Say "1. Windows edition"
$edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
if ($edition -match "Core|Home") {
  Bad "$edition -- Windows Home cannot accept incoming RDP. Upgrade to Pro, or use a third-party remote tool."
  exit 1
}
Ok $edition

Say "2. turn RDP on"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
  -Name fDenyTSConnections -Value 0
Ok "fDenyTSConnections = 0"

$nla = 0
if ($RequireNLA) { $nla = 1 }
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
  -Name UserAuthentication -Value $nla
Ok "network level authentication = $nla"

Set-Service -Name TermService -StartupType Automatic
if ((Get-Service TermService).Status -ne "Running") { Start-Service TermService }
Ok "TermService running, start = Automatic"

Say "3. firewall: tailnet only"
# The stock rules allow any source on the matching profile. Off they go, and one explicit
# rule takes their place. Both steps are idempotent.
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue |
  Disable-NetFirewallRule
Ok "stock 'Remote Desktop' rules disabled"

$ruleName = 'RDP over Tailscale'
Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow `
  -Protocol TCP -LocalPort 3389 -RemoteAddress 100.64.0.0/10 -Profile Any | Out-Null
Ok "3389 allowed from 100.64.0.0/10 only"

Say "4. proof"
$listening = Get-NetTCPConnection -State Listen -LocalPort 3389 -ErrorAction SilentlyContinue
if ($listening) { Ok "3389 is listening" } else { Bad "3389 is NOT listening -- check TermService" }

$ts = "C:\Program Files\Tailscale\tailscale.exe"
if (Test-Path $ts) {
  $ip = (& $ts ip -4 2>$null | Select-Object -First 1)
  if ($ip) {
    Ok "this machine on the tailnet: $($ip.Trim())"
    Write-Host ""
    Write-Host "  Connect from another tailnet node:  mstsc /v:$($ip.Trim())" -ForegroundColor Yellow
  }
} else {
  Write-Host "  ..    Tailscale is not installed here -- RDP is now reachable on the LAN only" -ForegroundColor Gray
}
Write-Host ""

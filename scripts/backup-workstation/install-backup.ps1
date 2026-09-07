# install-backup.ps1 -- set up the workstation backup on this machine.
#
# Idempotent. Safe to re-run: it re-applies the ignore policy, refreshes the cached
# repository password from Doppler, and recreates the scheduled task.
#
#   Run from an ELEVATED PowerShell (registering a SYSTEM task and ACLing ProgramData
#   both require it):
#
#     powershell -ExecutionPolicy Bypass -File C:\1Claude\scripts\backup-workstation\install-backup.ps1
#
# Prerequisites, all of which are already true on DESKTOP1 as of 2026-09-06:
#   - kopia CLI installed        (winget install --id Kopia.KopiaCLI)
#   - doppler CLI authenticated  (needs KOPIA_REPO_PASSWORD in grotap/prd)
#   - the repository already created and reachable -- see README.md
#
# Windows PowerShell 5.1 compatible -- no '&&', no ternary, no null-coalescing. ASCII only.

[CmdletBinding()]
param(
  [string]$StateDir   = "C:\ProgramData\Grotap\backup",
  [string]$IgnoreFile = "C:\1Claude\scripts\backup-workstation\kopiaignore",
  [string]$RunScript  = "C:\1Claude\scripts\backup-workstation\backup-run.ps1",
  [string]$TaskName   = "Grotap-Backup-Workstation",
  [string]$AtTime     = "01:30",
  [int]$EveryDays     = 2,
  [switch]$SkipPolicy         # re-register the task only, leave ignore rules alone
)

$ErrorActionPreference = "Continue"
$script:Failures = @()

function Say    ([string]$m) { Write-Host ""; Write-Host "=== $m" -ForegroundColor Cyan }
function Ok     ([string]$m) { Write-Host "  [ok]   $m" -ForegroundColor Green }
function Info   ([string]$m) { Write-Host "  [..]   $m" -ForegroundColor Gray }
function Failed ([string]$m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:Failures += $m }

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "This script must run from an elevated PowerShell." -ForegroundColor Red
  Write-Host "Right-click PowerShell -> Run as administrator, then re-run." -ForegroundColor Red
  exit 1
}

$ConfigFile = Join-Path $StateDir "repository.config"
$PassFile   = Join-Path $StateDir "repo.pass"

# ---------------------------------------------------------------------------
Say "1. locate kopia"
$kopia = $null
$cmd = Get-Command kopia -ErrorAction SilentlyContinue
if ($cmd) {
  $kopia = $cmd.Source
} else {
  $__roots = @()
  if ($env:LOCALAPPDATA) { $__roots += (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages") }
  Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { $__roots += (Join-Path $_.FullName "AppData\Local\Microsoft\WinGet\Packages") }
  $__roots += "C:\Program Files\Kopia"
  foreach ($r in $__roots) {
    if (Test-Path $r) {
      $hit = Get-ChildItem -Path $r -Filter kopia.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($hit) { $kopia = $hit.FullName; break }
    }
  }
}
if (-not $kopia) { Failed "kopia.exe not found -- winget install --id Kopia.KopiaCLI"; exit 1 }
Ok "kopia: $kopia"

# ---------------------------------------------------------------------------
Say "2. state directory and ACL"
if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }

# SYSTEM and Administrators only. The directory holds the repository password and the
# Storage Box private key; leaving it readable by every local user would hand anyone on
# the box the ability to read -- or destroy -- every backup.
$acl = New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)   # break inheritance, drop inherited rules
foreach ($who in @("SYSTEM","BUILTIN\Administrators")) {
  $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $who, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
  $acl.AddAccessRule($rule)
}
Set-Acl -Path $StateDir -AclObject $acl
Ok "$StateDir locked to SYSTEM + Administrators"

# ...but let ordinary users READ the logs. The secrets in this directory are repo.pass and
# id_storagebox; the logs are not sensitive, and locking them away means the owner cannot
# check whether last night's backup worked without opening an elevated shell. A status
# check nobody can run is a status check nobody runs.
$LogDirPath = Join-Path $StateDir "logs"
if (-not (Test-Path $LogDirPath)) { New-Item -ItemType Directory -Path $LogDirPath -Force | Out-Null }
$lacl = Get-Acl -Path $LogDirPath
$lacl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
  "BUILTIN\Users", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")))
Set-Acl -Path $LogDirPath -AclObject $lacl
Ok "$LogDirPath readable by Users (logs are not secret; the passphrase and key stay locked)"

# Same for the success stamp, so a non-elevated status check can answer "did it run?"
$StampPath = Join-Path $StateDir "last-success.txt"
if (-not (Test-Path $StampPath)) { Set-Content -Path $StampPath -Value "never" -Encoding ascii }
$sacl = Get-Acl -Path $StampPath
$sacl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
  "BUILTIN\Users", "Read", "Allow")))
Set-Acl -Path $StampPath -AclObject $sacl
Ok "last-success.txt readable by Users"

# ---------------------------------------------------------------------------
Say "3. cache the repository password from Doppler"
# The scheduled task runs as SYSTEM at 01:30 with no interactive session and no Doppler
# login, so it cannot call Doppler itself. Doppler stays the source of truth and the
# escrow copy; this file is the runtime cache and is re-written on every install.
$dop = Get-Command doppler -ErrorAction SilentlyContinue
if (-not $dop) {
  Failed "doppler CLI not found -- cannot fetch KOPIA_REPO_PASSWORD"
} else {
  $pw = & doppler secrets get KOPIA_REPO_PASSWORD --project grotap --config prd --plain 2>$null
  if ([string]::IsNullOrWhiteSpace($pw)) {
    Failed "KOPIA_REPO_PASSWORD is empty or unreadable from grotap/prd"
  } else {
    Set-Content -Path $PassFile -Value $pw.Trim() -Encoding ascii -NoNewline
    Ok "cached to $PassFile (SYSTEM-readable only)"
  }
}

# ---------------------------------------------------------------------------
Say "4. connect to the repository"
# The installer owns the connection so there is no separate manual step to get wrong.
#
# REPO PATH -- read this before changing it. The path is deliberately RELATIVE and contains
# no leading slash. An absolute POSIX path like /home/kopia is rewritten by MSYS when the
# command runs under Git Bash: "/home/kopia" became "C:/Program Files/Git/home/kopia" on
# the server, which then only resolved from Git Bash and broke every PowerShell connect
# with "repository not initialized in the provided storage". A relative path is passed
# through untouched by both shells.
$RepoPath = "grotap-workstation"

# If a config already exists but points somewhere else, replace it. Without this the
# installer is idempotent in name only: it would happily leave a config aimed at the old
# mangled path and every backup would keep writing to the wrong repository.
if (Test-Path $ConfigFile) {
  $cfgPath = $null
  try {
    $cfgJson = Get-Content $ConfigFile -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($cfgJson.storage -and $cfgJson.storage.config) { $cfgPath = $cfgJson.storage.config.path }
  } catch { }
  if ($cfgPath -and $cfgPath -ne $RepoPath) {
    Info "config points at '$cfgPath', expected '$RepoPath' -- reconnecting"
    Remove-Item $ConfigFile -Force -ErrorAction SilentlyContinue
    Remove-Item "$ConfigFile.update-info.json" -Force -ErrorAction SilentlyContinue
  }
}

if (-not (Test-Path $ConfigFile)) {
  $keyFile = Join-Path $StateDir "id_storagebox"
  if (-not (Test-Path $keyFile)) {
    $sk = & doppler secrets get STORAGEBOX_SSH_KEY --project grotap --config prd --plain 2>$null
    if ([string]::IsNullOrWhiteSpace($sk)) { Failed "STORAGEBOX_SSH_KEY unavailable" }
    else { Set-Content -Path $keyFile -Value $sk -Encoding ascii; Ok "SSH key written from Doppler" }
  }
  $sbHost = & doppler secrets get STORAGEBOX_HOST --project grotap --config prd --plain 2>$null
  $sbUser = & doppler secrets get STORAGEBOX_USER --project grotap --config prd --plain 2>$null
  $env:KOPIA_PASSWORD = (Get-Content $PassFile -Raw).Trim()
  $env:KOPIA_CHECK_FOR_UPDATES = "false"
  $out = & $kopia repository connect sftp --path=$RepoPath `
      --host="$($sbHost.Trim())" --port=23 --username="$($sbUser.Trim())" `
      --keyfile="$keyFile" --known-hosts="$env:USERPROFILE\.ssh\known_hosts" `
      --config-file="$ConfigFile" 2>&1
  if ($LASTEXITCODE -ne 0) {
    Failed "could not connect to the repository"
    $out | ForEach-Object { Info (($_ | Out-String).Trim()) }
  } else { Ok "connected to $RepoPath" }
}
if (-not (Test-Path $ConfigFile)) {
  Failed "still no repository config at $ConfigFile"
} else {
  $env:KOPIA_PASSWORD = (Get-Content $PassFile -Raw).Trim()
  $env:KOPIA_CHECK_FOR_UPDATES = "false"
  & $kopia repository status --config-file="$ConfigFile" 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Failed "repository unreachable (exit $LASTEXITCODE)" } else { Ok "repository reachable" }
}

# ---------------------------------------------------------------------------
Say "5. apply ignore rules as policy"
# Applied as POLICY rules rather than by dropping .kopiaignore files into the sources --
# most of those directories are git repos, and a stray ignore file would show up untracked
# in every one of them and eventually get committed by accident.
if ($SkipPolicy) {
  Info "skipped (-SkipPolicy)"
} elseif (-not (Test-Path $IgnoreFile)) {
  Failed "ignore file missing: $IgnoreFile"
} else {
  $patterns = Get-Content $IgnoreFile |
              ForEach-Object { $_.Trim() } |
              Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }
  Info "$($patterns.Count) patterns from $IgnoreFile"

  # Kopia's --add-ignore is additive and there is NO --clear-ignore flag (checked against
  # 0.23.1 -- only --add-ignore and --remove-ignore exist). So to stay idempotent we read
  # the rules currently on the policy and remove each one in the same call that adds the
  # new set. Without this, every re-run of this script would append duplicates forever.
  $existing = @()
  $shown = & $kopia policy show --global --json --config-file="$ConfigFile" 2>$null
  if (-not [string]::IsNullOrWhiteSpace($shown)) {
    $pol = $shown | ConvertFrom-Json
    if ($pol.files -and $pol.files.ignore) { $existing = @($pol.files.ignore) }
  }
  Info "$($existing.Count) existing rule(s) to clear first"

  $kargs = @("policy","set","--global","--config-file=$ConfigFile")
  foreach ($e in $existing) { $kargs += "--remove-ignore"; $kargs += $e }
  foreach ($p in $patterns) { $kargs += "--add-ignore"; $kargs += $p }
  & $kopia @kargs 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Failed "kopia policy set failed (exit $LASTEXITCODE)" } else { Ok "global ignore policy applied" }

  # Retention, matching the owner's decision: every 2 days, 30 days of history.
  # 15 snapshots at a 2-day cadence IS 30 days; keep-monthly is a cheap floor against a
  # corruption nobody notices for a month.
  & $kopia policy set --global --config-file="$ConfigFile" `
      --keep-latest=15 --keep-hourly=0 --keep-daily=0 --keep-weekly=0 `
      --keep-monthly=3 --keep-annual=0 --compression=zstd `
      --enable-volume-shadow-copy=when-available 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Failed "retention/VSS policy failed" } else { Ok "retention: 15 latest + 3 monthly, zstd, VSS when-available" }
}

# ---------------------------------------------------------------------------
Say "6. register the scheduled task"
if (-not (Test-Path $RunScript)) { Failed "run script missing: $RunScript" }

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$RunScript`""

$trigger = New-ScheduledTaskTrigger -Daily -DaysInterval $EveryDays -At $AtTime

# Both of these matter, and omitting either is how a desktop backup quietly stops.
#   WakeToRun          -- a sleeping machine at 01:30 otherwise never runs at all.
#   StartWhenAvailable -- if it was powered off, run at the next opportunity instead of
#                         skipping the slot entirely and waiting two more days.
$settings = New-ScheduledTaskSettingsSet `
  -WakeToRun `
  -StartWhenAvailable `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -ExecutionTimeLimit (New-TimeSpan -Hours 6) `
  -MultipleInstances IgnoreNew

# SYSTEM, because VSS needs administrative rights and AppData plus NTUSER.DAT are locked
# while the owner is logged in.
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
  -Settings $settings -Principal $principal `
  -Description "Grotap workstation backup to Hetzner Storage Box (Kopia, VSS). See C:\1Claude\scripts\backup-workstation\README.md" | Out-Null

if ($?) { Ok "task '$TaskName' registered: every $EveryDays days at $AtTime, as SYSTEM" }
else { Failed "task registration failed" }

# ---------------------------------------------------------------------------
Say "summary"
if ($script:Failures.Count -eq 0) {
  Ok "install complete"
  Write-Host ""
  Write-Host "  Run it once now to prove it works end to end:" -ForegroundColor Yellow
  Write-Host "    Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Yellow
  Write-Host "  Then watch:  Get-Content $StateDir\logs\backup-*.log -Tail 20 -Wait" -ForegroundColor Yellow
  Write-Host "  And prove a restore:  .\verify-restore.ps1" -ForegroundColor Yellow
  exit 0
} else {
  Write-Host ""
  Write-Host "  $($script:Failures.Count) problem(s):" -ForegroundColor Red
  foreach ($f in $script:Failures) { Write-Host "    - $f" -ForegroundColor Red }
  exit 1
}

# backup-run.ps1 -- take one workstation snapshot to the Hetzner Storage Box.
#
# This is the body of the scheduled task "Grotap-Backup-Workstation". It is also safe to
# run by hand at any time; snapshots are cheap and deduplicated.
#
#   powershell -ExecutionPolicy Bypass -File C:\1Claude\scripts\backup-workstation\backup-run.ps1
#
# Runs as SYSTEM under the scheduler. That is deliberate: VSS requires administrative
# rights, and AppData plus NTUSER.DAT are locked while the owner is logged in, which is
# exactly the case VSS exists for. A backup that skips locked files looks identical to one
# that works, right up until the restore.
#
# It does NOT call Doppler. At 01:30 the machine may have no interactive session and no
# Doppler login, so the repository password is read from a SYSTEM-only file that
# install-backup.ps1 writes once from Doppler. Doppler remains the source of truth and the
# escrow copy; this file is just the runtime cache.
#
# Windows PowerShell 5.1 compatible -- no '&&', no ternary, no null-coalescing.
# ASCII only on purpose: PS 5.1 reads BOM-less UTF-8 as ANSI and mangles non-ASCII.

[CmdletBinding()]
param(
  [string]$StateDir  = "C:\ProgramData\Grotap\backup",
  [int]$Parallel     = 16,        # see the note on throughput below
  # The profile to back up. NOT $env:USERPROFILE: under the scheduler this runs as SYSTEM,
  # whose profile is C:\Windows\system32\config\systemprofile and contains nothing you want.
  # Pass -UserProfile for a machine whose owner is not "aallison".
  [string]$UserProfile = "C:\Users\aallison"
)

$ErrorActionPreference = "Continue"

$ConfigFile = Join-Path $StateDir "repository.config"
$PassFile   = Join-Path $StateDir "repo.pass"
$LogDir     = Join-Path $StateDir "logs"
$StampFile  = Join-Path $StateDir "last-success.txt"
$FailFile   = Join-Path $StateDir "consecutive-failures.txt"

# The sources. Anything not listed here is not backed up, full stop -- so if a new repo
# root appears on this box, it belongs in this list and in install-backup.ps1's policy pass.
$Sources = @(
  "C:\1Claude",
  "C:\2Claude",
  "C:\7ClaudeMarketingAgents",
  "C:\8Claude",
  "C:\9Claudemanorview",
  "C:\pcb",
  "C:\tools",
  $UserProfile
)

# Claude's memory directories, added as their OWN sources.
#
# The ignore policy excludes .claude/projects/ wholesale, because agent transcripts there
# grow without bound and were found on 2026-09-06 to accumulate live API keys in plaintext.
# But the memory/ subdirectory inside each project is the opposite: it is the accumulated
# "don't re-do this" record, it is not in git, and scripts/newpc/README.md is explicit that
# it cannot be reinstalled. Losing it to a blanket exclude would be the single worst
# outcome of this backup.
#
# Listing them as separate sources works because Kopia applies ignore rules while
# traversing DOWN from a source root -- a source that sits inside an ignored path is still
# snapshotted. Enumerated rather than hardcoded so a new project slug is picked up
# automatically.
$memoryRoot = Join-Path $UserProfile ".claude\projects"
if (Test-Path $memoryRoot) {
  $mem = @(Get-ChildItem -Path $memoryRoot -Directory -ErrorAction SilentlyContinue |
           ForEach-Object { Join-Path $_.FullName "memory" } |
           Where-Object { Test-Path $_ })
  $Sources = $Sources + $mem
}

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path $LogDir "backup-$stamp.log"

function Say ([string]$m) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m"
  Write-Host $line
  Add-Content -Path $LogFile -Value $line -Encoding utf8
}

function Find-Kopia {
  # winget installs kopia under a versioned Packages path, so a hardcoded path breaks on
  # the next upgrade. Resolve it at run time and fail loudly rather than silently doing
  # nothing -- a backup task that exits 0 having backed up nothing is the worst outcome.
  $cmd = Get-Command kopia -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $roots = @()
  # Under the scheduler this runs as SYSTEM, whose $env:LOCALAPPDATA is
  # C:\Windows\system32\config\systemprofile\AppData\Local -- NOT the user's. winget
  # installs kopia per-user, so SYSTEM must look in the real profiles. Enumerate them
  # rather than hardcoding a username, or this works on exactly one machine.
  if ($env:LOCALAPPDATA) { $roots += (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages") }
  Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { $roots += (Join-Path $_.FullName "AppData\Local\Microsoft\WinGet\Packages") }
  $roots += "C:\Program Files\Kopia"
  foreach ($r in $roots) {
    if (Test-Path $r) {
      $hit = Get-ChildItem -Path $r -Filter kopia.exe -Recurse -ErrorAction SilentlyContinue |
             Select-Object -First 1
      if ($hit) { return $hit.FullName }
    }
  }
  return $null
}

function Record-Failure ([string]$reason) {
  # Retry-then-report, per the rule in platform/CLAUDE.md: a monitor whose only possible
  # advice is "run it again" must run it again. The scheduler's repetition handles the
  # retry; this only counts, so that a SECOND consecutive failure is what gets attention.
  $n = 0
  if (Test-Path $FailFile) {
    $raw = (Get-Content $FailFile -Raw).Trim()
    [int]::TryParse($raw, [ref]$n) | Out-Null
  }
  $n = $n + 1
  Set-Content -Path $FailFile -Value $n -Encoding ascii
  Say "FAILED ($n consecutive): $reason"
  if ($n -ge 2) {
    Say "ESCALATE: two consecutive failures. This one needs a human."
  } else {
    Say "First failure. The next scheduled run retries; not escalating yet."
  }
  exit 1
}

Say "=== workstation backup starting ==="

$kopia = Find-Kopia
if (-not $kopia) { Record-Failure "kopia.exe not found on this machine" }
Say "kopia: $kopia"

if (-not (Test-Path $ConfigFile)) { Record-Failure "repository config missing: $ConfigFile (run install-backup.ps1)" }
if (-not (Test-Path $PassFile))   { Record-Failure "repository password file missing: $PassFile (run install-backup.ps1)" }

$env:KOPIA_PASSWORD = (Get-Content $PassFile -Raw).Trim()
$env:KOPIA_CHECK_FOR_UPDATES = "false"

# Prove the repository is reachable before doing 90 minutes of hashing against a dead link.
& $kopia repository status --config-file="$ConfigFile" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Record-Failure "cannot reach the repository (exit $LASTEXITCODE)" }
Say "repository reachable"

# VSS is a REPOSITORY POLICY setting, not a per-run flag. `kopia snapshot create` has no
# --enable-volume-shadow-copy option (verified against 0.23.1: its only relevant flags are
# --parallel, --description, --tags, --upload-limit-mb, --fail-fast, --force-hash).
# install-backup.ps1 sets `kopia policy set --global --enable-volume-shadow-copy=when-available`
# once, and every snapshot inherits it. To turn VSS off, change the policy -- do not look
# for a switch here.
$vssMode = "policy"
try {
  $shown = & $kopia policy show --global --json --config-file="$ConfigFile" 2>$null
  if (-not [string]::IsNullOrWhiteSpace($shown)) {
    $pol = $shown | ConvertFrom-Json
    if ($pol.osSnapshots -and $pol.osSnapshots.volumeShadowCopy -and $pol.osSnapshots.volumeShadowCopy.enable) {
      $vssMode = $pol.osSnapshots.volumeShadowCopy.enable
    }
  }
} catch { }
Say "volume shadow copy (from policy): $vssMode"
if ($vssMode -eq "policy" -or $vssMode -eq "never") {
  Say "WARNING: VSS is not enabled in policy. Files locked by a logged-in session -- AppData,"
  Say "         NTUSER.DAT -- will be SKIPPED, and a backup that skips them looks identical"
  Say "         to one that works. Re-run install-backup.ps1 to set it."
}

$failed = @()
foreach ($src in $Sources) {
  if (-not (Test-Path $src)) {
    Say "skip (not present): $src"
    continue
  }
  Say "snapshot: $src  (parallel=$Parallel)"
  $t0 = Get-Date

  # --parallel matters more than it looks. The first measured run on this box managed
  # 0.9 GB / 6,852 files in 24m32s -- roughly 600 KB/s -- because SFTP to Falkenstein is
  # dominated by per-file round trips, not bandwidth. Raising parallelism is the lever.
  & $kopia snapshot create $src `
      --config-file="$ConfigFile" `
      --parallel=$Parallel `
      --description="scheduled $stamp" 2>&1 | ForEach-Object { Add-Content -Path $LogFile -Value (($_ | Out-String).Trim()) -Encoding utf8 }

  $rc = $LASTEXITCODE
  $mins = [math]::Round(((Get-Date) - $t0).TotalMinutes, 1)
  if ($rc -ne 0) {
    Say "  FAILED after $mins min (exit $rc)"
    $failed += $src
  } else {
    Say "  ok in $mins min"
  }
}

if ($failed.Count -gt 0) { Record-Failure ("sources failed: " + ($failed -join ", ")) }

# Retention. Kopia applies the policy at snapshot time, but running it explicitly means
# the log carries proof that pruning happened rather than us assuming it did.
Say "applying retention"
& $kopia snapshot expire --all --delete --config-file="$ConfigFile" 2>&1 |
  ForEach-Object { Add-Content -Path $LogFile -Value (($_ | Out-String).Trim()) -Encoding utf8 }

Say "maintenance"
& $kopia maintenance run --config-file="$ConfigFile" 2>&1 |
  ForEach-Object { Add-Content -Path $LogFile -Value (($_ | Out-String).Trim()) -Encoding utf8 }

# Order matters here, and it is not arbitrary. The platform backup machine failed silently
# for three weeks because its heartbeat was stamped AFTER housekeeping, so a non-zero exit
# from pruning killed the script before the stamp was written and the watchdog read a
# frozen date while every backup was in fact succeeding. Stamp success as soon as the data
# is safe; let housekeeping fail noisily without rewriting history.
Set-Content -Path $StampFile -Value (Get-Date -Format "o") -Encoding ascii
Set-Content -Path $FailFile  -Value 0 -Encoding ascii
Say "SUCCESS -- stamped $StampFile"

# Keep 90 days of logs. This is the only place the script deletes anything on disk.
Get-ChildItem -Path $LogDir -Filter "backup-*.log" -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) } |
  Remove-Item -Force -ErrorAction SilentlyContinue

Say "=== done ==="
exit 0

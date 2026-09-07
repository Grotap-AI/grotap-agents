# verify-restore.ps1 -- prove the backup restores. Read-only against the repository.
#
#   powershell -ExecutionPolicy Bypass -File C:\1Claude\scripts\backup-workstation\verify-restore.ps1
#
# An untested backup is not a backup. This restores a sample out of the newest snapshot to
# a temporary directory and compares it byte-for-byte against the live files, then reports
# how long a restore actually takes -- which is the number you want to know BEFORE the day
# you need it, not during.
#
# Expect a small number of differences on a live machine: files written after the snapshot
# was taken will legitimately differ. The script tells you which, so you can judge whether
# a difference is "written since the snapshot" or "the backup is wrong". Those two look
# identical in a pass/fail summary, which is why this prints the names.
#
# Windows PowerShell 5.1 compatible -- no '&&', no ternary, no null-coalescing. ASCII only.

[CmdletBinding()]
param(
  [string]$StateDir = "C:\ProgramData\Grotap\backup",
  # Defaults to Claude's memory directory: small enough that a drill finishes in under a
  # minute, and the most irreplaceable thing in the whole backup, so a drill against it
  # tests the part that actually matters.
  [string]$UserProfile = "C:\Users\aallison",
  # Empty means "derive from -UserProfile" -- resolved just below. Pass -Source for anything else.
  [string]$Source   = "",
  [string]$DestRoot = "$env:TEMP\grotap-restore-drill",
  [switch]$KeepFiles          # leave the restored copy on disk for inspection
)

$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($Source)) {
  $Source = Join-Path $UserProfile ".claude\projects\C--1Claude-platform\memory"
}

$ConfigFile = Join-Path $StateDir "repository.config"
$PassFile   = Join-Path $StateDir "repo.pass"

# The repository config lives in the locked state dir too. If this shell cannot read it,
# fall back to a private config in the user's temp -- kopia will connect to the same
# repository, it just keeps its client-side bookkeeping somewhere readable.
$FallbackConfig = Join-Path $env:TEMP "grotap-drill-repository.config"

function Say  ([string]$m) { Write-Host ""; Write-Host "=== $m" -ForegroundColor Cyan }
function Ok   ([string]$m) { Write-Host "  [ok]   $m" -ForegroundColor Green }
function Info ([string]$m) { Write-Host "  [..]   $m" -ForegroundColor Gray }
function Bad  ([string]$m) { Write-Host "  [FAIL] $m" -ForegroundColor Red }

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
if (-not $kopia) { Bad "kopia.exe not found"; exit 1 }

# Two ways to get the passphrase, and the order matters.
#
# The cached file is SYSTEM+Administrators only, which is right for a secret but wrong for
# this script: the restore drill is meant to be run routinely by the owner, and a check
# that requires an elevated shell is a check that stops being run. So fall back to Doppler,
# which the owner is already logged into interactively. The SYSTEM-run backup has no
# Doppler login and uses the file; a human running the drill uses Doppler. Both work.
$env:KOPIA_PASSWORD = $null
$canReadFile = $false
# -ErrorAction SilentlyContinue, not just try/catch: an access-denied from Test-Path is a
# NON-terminating error, which skips the catch block entirely and prints to the console.
$canReadFile = Test-Path $PassFile -ErrorAction SilentlyContinue

if ($canReadFile) {
  try {
    $env:KOPIA_PASSWORD = (Get-Content $PassFile -Raw -ErrorAction Stop).Trim()
    Info "passphrase: cached file"
  } catch { $env:KOPIA_PASSWORD = $null }
}

if ([string]::IsNullOrWhiteSpace($env:KOPIA_PASSWORD)) {
  $dop = Get-Command doppler -ErrorAction SilentlyContinue
  if ($dop) {
    $pw = & doppler secrets get KOPIA_REPO_PASSWORD --project grotap --config prd --plain 2>$null
    if (-not [string]::IsNullOrWhiteSpace($pw)) {
      $env:KOPIA_PASSWORD = $pw.Trim()
      Info "passphrase: Doppler (cached file not readable from this shell)"
    }
  }
}

if ([string]::IsNullOrWhiteSpace($env:KOPIA_PASSWORD)) {
  Bad "no passphrase available"
  Info "either run install-backup.ps1 (elevated) to cache it, or log in to Doppler"
  exit 1
}
$env:KOPIA_CHECK_FOR_UPDATES = "false"

Say "1. find the newest snapshot covering $Source"

# Can this shell read the shared config? If not, connect our own from Doppler.
$canReadConfig = $false
$canReadConfig = Test-Path $ConfigFile -ErrorAction SilentlyContinue
if ($canReadConfig) {
  try { Get-Content $ConfigFile -TotalCount 1 -ErrorAction Stop | Out-Null } catch { $canReadConfig = $false }
}

if (-not $canReadConfig) {
  Info "shared config not readable from this shell; connecting a private one"
  $keyFile = Join-Path $env:TEMP "grotap-drill-key"
  $dop = Get-Command doppler -ErrorAction SilentlyContinue
  if (-not $dop) { Bad "cannot read $ConfigFile and doppler is unavailable"; exit 1 }
  $k = & doppler secrets get STORAGEBOX_SSH_KEY --project grotap --config prd --plain 2>$null
  if ([string]::IsNullOrWhiteSpace($k)) { Bad "STORAGEBOX_SSH_KEY unavailable"; exit 1 }
  Set-Content -Path $keyFile -Value $k -Encoding ascii
  $sbHost = & doppler secrets get STORAGEBOX_HOST --project grotap --config prd --plain 2>$null
  $sbUser = & doppler secrets get STORAGEBOX_USER --project grotap --config prd --plain 2>$null
  # Capture rather than discard: swallowing this output means a connect failure reports
  # "could not connect" with no reason, which is useless at 2am.
  $connectOut = & $kopia repository connect sftp --path=grotap-workstation `
      --host="$($sbHost.Trim())" --port=23 --username="$($sbUser.Trim())" `
      --keyfile="$keyFile" --known-hosts="$env:USERPROFILE\.ssh\known_hosts" `
      --config-file="$FallbackConfig" 2>&1
  $connectRc = $LASTEXITCODE
  Remove-Item $keyFile -Force -ErrorAction SilentlyContinue
  if ($connectRc -ne 0) {
    Bad "could not connect to the repository (exit $connectRc)"
    $connectOut | ForEach-Object { Info (($_ | Out-String).Trim()) }
    exit 1
  }
  $ConfigFile = $FallbackConfig
}

$listJson = & $kopia snapshot list --json --config-file="$ConfigFile" 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($listJson)) { Bad "cannot list snapshots"; exit 1 }

$snaps = $listJson | ConvertFrom-Json

# Pick the MOST SPECIFIC source first, then the newest snapshot of that source.
#
# Sorting by time alone is wrong here and fails in normal operation: backup-run.ps1
# snapshots "C:\Users\aallison" AND each ".claude\projects\<slug>\memory" directory as
# separate sources, and the parent is a path prefix of the child. A newest-first sort can
# therefore select the parent -- whose ignore policy excludes .claude/projects/ entirely --
# and the drill then reports every memory file as missing, which looks exactly like a
# broken backup. Longest matching source path wins; time only breaks ties within it.
$candidates = @($snaps | Where-Object {
  $sp = $_.source.path.ToLower().TrimEnd("\")
  $sr = $Source.ToLower().TrimEnd("\")
  # A prefix match must land on a path separator, or "C:\Users\aal" would match
  # "C:\Users\aallison".
  ($sr -eq $sp) -or $sr.StartsWith($sp + "\")
})

$match = $candidates |
  Sort-Object @{Expression = { $_.source.path.Length }; Descending = $true},
              @{Expression = { [datetime]$_.startTime }; Descending = $true} |
  Select-Object -First 1

if ($match) {
  $exact = @($candidates | Where-Object { $_.source.path.Length -eq $match.source.path.Length })
  Info "$($candidates.Count) snapshot(s) cover this path; using the most specific source ($($exact.Count) snapshot(s) of it)"
}

if (-not $match) {
  Bad "no snapshot covers $Source"
  Info "available sources:"
  $snaps | Select-Object -ExpandProperty source | Select-Object -ExpandProperty path -Unique |
    ForEach-Object { Info "  $_" }
  exit 1
}

# The root object id is at rootEntry.obj, NOT a top-level "rootID" field -- verified
# against kopia 0.23.1's --json output, whose top-level keys are id, source, startTime,
# endTime, stats, rootEntry, description, retentionReason. `id` is the snapshot id and is
# NOT what restore takes.
$rootId   = $match.rootEntry.obj
$snapPath = $match.source.path
Ok "snapshot $rootId from $($match.startTime)  (source: $snapPath)"

# Kopia addresses a subdirectory of a snapshot as <rootID>/<relative path>, with forward
# slashes regardless of platform.
$relative = $Source.Substring($snapPath.Length).TrimStart("\").Replace("\", "/")
$target   = $rootId
if ($relative -ne "") { $target = "$rootId/$relative" }
Info "restoring: $target"

Say "2. restore to a temporary directory"
if (Test-Path $DestRoot) { Remove-Item -Recurse -Force $DestRoot -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $DestRoot -Force | Out-Null

$t0 = Get-Date
# Pipe through Out-String: PowerShell 5.1 wraps a native executable's stderr lines in
# ErrorRecord objects, which print as "System.Management.Automation.RemoteException"
# instead of the actual message. Exit status is taken from $LASTEXITCODE, never $?, for
# the same reason -- 5.1 sets $? false on any stderr output even when the exit code is 0.
& $kopia restore $target $DestRoot --config-file="$ConfigFile" 2>&1 |
  ForEach-Object { Info (($_ | Out-String).Trim()) }
$rc = $LASTEXITCODE
$secs = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
if ($rc -ne 0) { Bad "restore failed (exit $rc)"; exit 1 }
Ok "restored in $secs seconds"

Say "3. compare against live, byte for byte"
$liveFiles = @(Get-ChildItem -Path $Source -Recurse -File -ErrorAction SilentlyContinue)
$restFiles = @(Get-ChildItem -Path $DestRoot -Recurse -File -ErrorAction SilentlyContinue)
Info "live: $($liveFiles.Count) files   restored: $($restFiles.Count) files"

$checked = 0; $identical = 0
$differs = @(); $missing = @()

foreach ($lf in $liveFiles) {
  $rel = $lf.FullName.Substring($Source.Length).TrimStart("\")
  $rp  = Join-Path $DestRoot $rel
  if (-not (Test-Path $rp)) { $missing += $rel; continue }
  $checked++
  $h1 = (Get-FileHash -Path $lf.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
  $h2 = (Get-FileHash -Path $rp -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
  if ($h1 -eq $h2 -and $h1 -ne $null) { $identical++ } else { $differs += $rel }
}

Write-Host ""
Ok "$identical of $checked compared files are byte-identical"

if ($differs.Count -gt 0) {
  Write-Host "  $($differs.Count) file(s) differ from live:" -ForegroundColor Yellow
  foreach ($d in ($differs | Select-Object -First 15)) {
    $mt = (Get-Item (Join-Path $Source $d)).LastWriteTime
    $note = "written since the snapshot"
    if ($mt -lt [datetime]$match.startTime) { $note = "OLDER than the snapshot -- INVESTIGATE" }
    Write-Host "    $d   (live mtime $mt -- $note)" -ForegroundColor Yellow
  }
  if ($differs.Count -gt 15) { Write-Host "    ... and $($differs.Count - 15) more" -ForegroundColor Yellow }
}

if ($missing.Count -gt 0) {
  Write-Host "  $($missing.Count) live file(s) absent from the snapshot:" -ForegroundColor Yellow
  foreach ($m in ($missing | Select-Object -First 15)) {
    $mt = (Get-Item (Join-Path $Source $m)).LastWriteTime
    $note = "created since the snapshot"
    if ($mt -lt [datetime]$match.startTime) { $note = "predates the snapshot -- check the ignore rules" }
    Write-Host "    $m   (live mtime $mt -- $note)" -ForegroundColor Yellow
  }
  if ($missing.Count -gt 15) { Write-Host "    ... and $($missing.Count - 15) more" -ForegroundColor Yellow }
}

Say "verdict"
# A difference is only a defect if the live file is OLDER than the snapshot -- that means
# the backup captured something wrong. Newer files differing is correct behaviour and is
# what point-in-time fidelity looks like.
$suspect = 0
foreach ($d in $differs) {
  if ((Get-Item (Join-Path $Source $d)).LastWriteTime -lt [datetime]$match.startTime) { $suspect++ }
}
foreach ($m in $missing) {
  if ((Get-Item (Join-Path $Source $m)).LastWriteTime -lt [datetime]$match.startTime) { $suspect++ }
}

if (-not $KeepFiles) { Remove-Item -Recurse -Force $DestRoot -ErrorAction SilentlyContinue }
else { Info "restored copy left at $DestRoot" }

if ($suspect -eq 0) {
  Ok "PASS -- every discrepancy is explained by writes after the snapshot was taken"
  Write-Host "  Restore rate: $checked files in $secs s" -ForegroundColor Green
  exit 0
} else {
  Bad "FAIL -- $suspect file(s) predate the snapshot and still do not match"
  Write-Host "  That is a real defect, not a timing artefact. Do not trust this repository" -ForegroundColor Red
  Write-Host "  until it is understood." -ForegroundColor Red
  exit 1
}

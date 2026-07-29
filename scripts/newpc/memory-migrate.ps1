# memory-migrate.ps1 -- carry Claude Code's auto-memory to the new PC.
#
# ~/.claude/projects/<project-slug>/memory/ holds every lesson, gotcha and
# "don't re-do this" note accumulated on this machine (373 files / 2.2 MB for
# C--1Claude-platform alone). It is NOT in git and NOT recreated by setup.ps1 --
# a fresh PC starts amnesiac without it.
#
# OLD PC:   powershell -ExecutionPolicy Bypass -File scripts\newpc\memory-migrate.ps1 -Export
# move the .zip across (OneDrive / USB -- it is plain markdown, scanned clean of
# credentials on 2026-07-29, but it IS internal project knowledge: do not email it)
# NEW PC:   powershell -ExecutionPolicy Bypass -File scripts\newpc\memory-migrate.ps1 -Import -Zip <path>
#
# The project slug is derived from the project PATH (C:\1Claude\platform ->
# C--1Claude-platform), so keeping the same paths on the new PC is what makes
# the restored memory actually load. Clone to C:\1Claude or this is wasted.
#
# ASCII only (PS 5.1 reads BOM-less UTF-8 as ANSI).

[CmdletBinding()]
param(
  [switch] $Export,
  [switch] $Import,
  [string] $Zip,                                   # required with -Import
  [string] $OutDir = "$env:USERPROFILE\Desktop"    # used with -Export
)

$projects = Join-Path $env:USERPROFILE ".claude\projects"
$stamp    = (Get-Date).ToString("yyyyMMdd-HHmmss")

function Usage {
  Write-Host ""
  Write-Host "Usage:" -ForegroundColor Cyan
  Write-Host "  OLD PC:  memory-migrate.ps1 -Export [-OutDir <dir>]" -ForegroundColor Cyan
  Write-Host "  NEW PC:  memory-migrate.ps1 -Import -Zip <path-to-zip>" -ForegroundColor Cyan
  Write-Host ""
}

# -Zip on its own means import; catch every other no-op invocation loudly
# rather than exiting 0 having done nothing.
if ($Zip -and -not $Export) { $Import = $true }
if (-not $Export -and -not $Import) {
  Write-Host "[FAIL] pass -Export or -Import. Nothing was done." -ForegroundColor Red
  Usage
  exit 1
}
if ($Export -and $Import) {
  Write-Host "[FAIL] -Export and -Import are mutually exclusive." -ForegroundColor Red
  Usage
  exit 1
}
if ($Import -and -not $Zip) {
  Write-Host "[FAIL] -Import requires -Zip <path-to-zip>." -ForegroundColor Red
  Usage
  exit 1
}

# ------------------------------------------------------------------ export --
if ($Export) {
  if (-not (Test-Path $projects)) { Write-Host "[FAIL] $projects not found" -ForegroundColor Red; exit 1 }

  $stage = Join-Path $env:TEMP ("claude-memory-" + (Get-Random))
  New-Item -ItemType Directory -Path $stage -Force | Out-Null

  $dirs = Get-ChildItem $projects -Directory | ForEach-Object {
    $m = Join-Path $_.FullName "memory"
    if (Test-Path $m) { [pscustomobject]@{ Slug = $_.Name; Path = $m } }
  }

  if (-not $dirs) {
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[FAIL] no memory directories found under $projects" -ForegroundColor Red
    exit 1
  }

  $total = 0
  foreach ($d in $dirs) {
    $dest = Join-Path $stage ($d.Slug + "\memory")
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item (Join-Path $d.Path "*") $dest -Recurse -Force
    $n = (Get-ChildItem $dest -Recurse -File | Measure-Object).Count
    $total += $n
    Write-Host ("  [ok]   {0,-30} {1} files" -f $d.Slug, $n) -ForegroundColor Green
  }

  if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
  # Timestamped: never clobbers a previous export.
  $out = Join-Path $OutDir "claude-memory-export-$stamp.zip"
  Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $out
  Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

  Write-Host ""
  Write-Host "Exported $total files from $($dirs.Count) projects" -ForegroundColor Cyan
  Write-Host "  -> $out" -ForegroundColor Cyan
  Write-Host "Move it to the new PC, then run this script there with -Import -Zip <path>." -ForegroundColor Cyan
  exit 0
}

# ------------------------------------------------------------------ import --
if ($Import) {
  if (-not (Test-Path $Zip)) { Write-Host "[FAIL] $Zip not found" -ForegroundColor Red; exit 1 }

  $stage = Join-Path $env:TEMP ("claude-memory-in-" + (Get-Random))
  Expand-Archive -Path $Zip -DestinationPath $stage -Force

  $restored = 0
  $backedUp = 0
  foreach ($p in (Get-ChildItem $stage -Directory)) {
    $src = Join-Path $p.FullName "memory"
    if (-not (Test-Path $src)) { continue }
    $dest = Join-Path $projects ($p.Name + "\memory")

    # Anything already on this PC is preserved verbatim BEFORE the merge, so an
    # overwrite is always recoverable. Only back up if there is something there.
    if (Test-Path $dest) {
      $existing = (Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
      if ($existing -gt 0) {
        $bak = Join-Path $projects ($p.Name + "\memory.backup-$stamp")
        Copy-Item $dest $bak -Recurse -Force
        $backedUp++
        Write-Host ("  [bak]  {0,-30} {1} existing files -> memory.backup-{2}" -f $p.Name, $existing, $stamp) -ForegroundColor Yellow
      }
    }

    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item (Join-Path $src "*") $dest -Recurse -Force
    $n = (Get-ChildItem $dest -Recurse -File | Measure-Object).Count
    $restored += $n
    Write-Host ("  [ok]   {0,-30} {1} files" -f $p.Name, $n) -ForegroundColor Green
  }
  Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

  Write-Host ""
  Write-Host "Restored $restored files into $projects" -ForegroundColor Cyan
  if ($backedUp -gt 0) {
    Write-Host "$backedUp project(s) had pre-existing memory, saved as memory.backup-$stamp alongside." -ForegroundColor Yellow
  }
  Write-Host "MEMORY.md in each project loads automatically at the next session start." -ForegroundColor Cyan
  exit 0
}

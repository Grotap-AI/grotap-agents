# browse-backup.ps1 -- open the workstation backup (Kopia on the Hetzner Storage Box) for reading.
#
# Read-only companion to install-backup.ps1. It never registers a task, never takes a
# snapshot and never writes to the repository: it connects, marks the connection
# read-only, lists what is there and then serves Kopia's own web UI on loopback so the
# snapshots can be browsed -- and individual files downloaded -- in a browser.
# -Mount gives the Explorer drive-letter route instead, and -ListOnly just prints.
#
#   powershell -ExecutionPolicy Bypass -File C:\1Claude\scripts\backup-workstation\browse-backup.ps1
#
# Safe to run from any machine with a Doppler login that can read grotap/prd -- that is
# where the SSH key, the endpoint and the repository passphrase live. The state it creates
# lives under the CURRENT USER's LOCALAPPDATA, not the SYSTEM-only C:\ProgramData\Grotap\backup
# used by the backup task, so running this on the backed-up machine cannot disturb the task.
#
# Windows PowerShell 5.1 compatible -- no '&&', no ternary, no null-coalescing.
# ASCII only on purpose: PS 5.1 reads BOM-less UTF-8 as ANSI and mangles non-ASCII.

[CmdletBinding()]
param(
  [string]$StateDir  = "$env:LOCALAPPDATA\Grotap\backup-browse",
  [string]$Drive     = "R",
  # The repository path is RELATIVE on purpose -- see install-backup.ps1 step 4 before
  # changing it. An absolute POSIX path is rewritten by MSYS under Git Bash.
  [string]$RepoPath  = "grotap-workstation",
  # Whose snapshots to show as "Local Snapshots" in the UI. The backed-up machine is
  # DESKTOP1; from any other machine the UI would otherwise show an empty list, because
  # it filters on the connected client's own identity.
  [string]$SourceUser = "aallison",
  [string]$SourceHost = "desktop1",
  [int]$Port         = 51515,
  [switch]$ListOnly, # print the snapshots to the console and exit -- no browser, no server
  [switch]$Mount     # mount as a drive letter instead of opening the UI (needs admin)
)

$ErrorActionPreference = "Continue"

function Say  ($m) { Write-Host ""; Write-Host $m -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "  ok    $m" -ForegroundColor Green }
function Info ($m) { Write-Host "  ..    $m" -ForegroundColor Gray }
function Bad  ($m) { Write-Host "  FAIL  $m" -ForegroundColor Red }

$ConfigFile = Join-Path $StateDir "repository.config"
$KeyFile    = Join-Path $StateDir "id_storagebox"
$KnownHosts = Join-Path $StateDir "known_hosts"

Write-Host "Grotap workstation backup -- browse" -ForegroundColor White

# --------------------------------------------------------------------------- 1. kopia
Say "1. kopia"
# winget installs Kopia as a PORTABLE package: the exe lands under WinGet\Packages\... and
# only a freshly started shell sees the PATH entry, so a just-installed kopia is invisible
# to Get-Command in this process. Search the package directory too.
function Find-Kopia {
  $c = Get-Command kopia -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  foreach ($p in @(
      "$env:ProgramFiles\KopiaCLI\kopia.exe",
      "$env:ProgramFiles\kopia\kopia.exe",
      "$env:LOCALAPPDATA\Microsoft\WinGet\Links\kopia.exe")) {
    if (Test-Path $p) { return $p }
  }
  $pkg = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
  if (Test-Path $pkg) {
    $hit = Get-ChildItem $pkg -Recurse -Filter "kopia.exe" -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  return $null
}

$kopia = Find-Kopia
if (-not $kopia) {
  Info "not installed -- installing Kopia.KopiaCLI with winget (one time, ~30s)"
  & winget install --id Kopia.KopiaCLI --exact --silent --accept-package-agreements --accept-source-agreements | Out-Null
  $kopia = Find-Kopia
}
if (-not $kopia) {
  Bad "kopia is not installed and winget could not install it"
  Write-Host "     install by hand:  winget install --id Kopia.KopiaCLI --exact" -ForegroundColor Yellow
  Read-Host "press Enter to close"; exit 1
}
Ok $kopia
$env:KOPIA_CHECK_FOR_UPDATES = "false"

# --------------------------------------------------------------------------- 2. credentials
Say "2. credentials from Doppler grotap/prd"
if (-not (Get-Command doppler -ErrorAction SilentlyContinue)) {
  Bad "doppler CLI not found -- it holds the key and the passphrase"
  Read-Host "press Enter to close"; exit 1
}
if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }

$pw = & doppler secrets get KOPIA_REPO_PASSWORD --project grotap --config prd --plain 2>$null
if ([string]::IsNullOrWhiteSpace($pw)) {
  Bad "KOPIA_REPO_PASSWORD unreadable from grotap/prd -- run 'doppler login' first"
  Read-Host "press Enter to close"; exit 1
}
$env:KOPIA_PASSWORD = $pw.Trim()
Ok "repository passphrase"

$sbHost = (& doppler secrets get STORAGEBOX_HOST --project grotap --config prd --plain 2>$null)
$sbUser = (& doppler secrets get STORAGEBOX_USER --project grotap --config prd --plain 2>$null)
if ([string]::IsNullOrWhiteSpace($sbHost) -or [string]::IsNullOrWhiteSpace($sbUser)) {
  Bad "STORAGEBOX_HOST / STORAGEBOX_USER unreadable from grotap/prd"
  Read-Host "press Enter to close"; exit 1
}
$sbHost = $sbHost.Trim(); $sbUser = $sbUser.Trim()
Ok "$sbUser@$sbHost`:23"

if (-not (Test-Path $KeyFile)) {
  $sk = & doppler secrets get STORAGEBOX_SSH_KEY --project grotap --config prd --plain 2>$null
  if ([string]::IsNullOrWhiteSpace($sk)) {
    Bad "STORAGEBOX_SSH_KEY unreadable from grotap/prd"
    Read-Host "press Enter to close"; exit 1
  }
  Set-Content -Path $KeyFile -Value $sk -Encoding ascii
  # Private key: this user only. Without this the file inherits the profile ACL.
  & icacls "$KeyFile" /inheritance:r /grant:r "$($env:USERNAME):(R)" | Out-Null
  Ok "SSH key written to $KeyFile (this user only)"
} else {
  Ok "SSH key present"
}

# The host key. kopia takes a --known-hosts file and will not prompt, so an empty or
# missing file is a hard connect failure rather than a question.
$needScan = $true
if (Test-Path $KnownHosts) {
  if ((Select-String -Path $KnownHosts -Pattern ([regex]::Escape($sbHost)) -Quiet)) { $needScan = $false }
}
if ($needScan) {
  # Three things make this fiddly, all of them proven against this box on 2026-09-08:
  #
  # 1. NOT ssh-keyscan. OpenSSH_for_Windows 9.5p2 aborts every keyscan here with
  #    "choose_kex: unsupported KEX method sntrup761x25519-sha512@openssh.com" and prints
  #    no key at all, which reads as an unreachable host. A normal ssh connect negotiates
  #    fine and writes the host key itself. Its authentication then fails -- we pass no
  #    key on this probe on purpose -- and that failure is irrelevant, the host key is
  #    already on disk by then.
  # 2. Pin EVERY host key type the box offers, not just one. The box offers ed25519,
  #    rsa and ecdsa-nistp521; kopia (Go x/crypto/ssh) leaves HostKeyAlgorithms nil, and
  #    Go's default preference puts ed25519 LAST, so it negotiates ecdsa-nistp521 while
  #    ssh pinned ed25519 -- which surfaces only as "knownhosts: key mismatch".
  #    Each type is probed into its own file: with several types for one host in a single
  #    file, ssh reports REMOTE HOST IDENTIFICATION HAS CHANGED and refuses to add.
  # 3. Write each key TWICE, as bare "host" and as "[host]:23". kopia looks the host up
  #    without the port ("unable to getHostKey: <host>"), while ssh only ever writes the
  #    bracketed form for a non-default port.
  $entries = @()
  foreach ($alg in @("ecdsa-sha2-nistp521", "ssh-ed25519", "rsa-sha2-512")) {
    $probe = Join-Path $env:TEMP ("grotap-kh-" + $alg)
    Remove-Item $probe -Force -ErrorAction SilentlyContinue
    & ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes `
          -o "UserKnownHostsFile=$probe" -o "HostKeyAlgorithms=$alg" `
          -o ConnectTimeout=15 -p 23 "$sbUser@$sbHost" "true" 2>&1 | Out-Null
    if (Test-Path $probe) {
      foreach ($line in (Get-Content $probe)) {
        if ($line -and -not $line.StartsWith("#")) {
          # .Split(' ', 2) -- NOT "-split ' ',2", which PS 5.1 parses as an array
          # delimiter and silently returns no second field.
          $key = $line.Split(' ', 2)[1]
          if ($key) { $entries += "$sbHost $key"; $entries += "[$sbHost]:23 $key" }
        }
      }
      Remove-Item $probe -Force -ErrorAction SilentlyContinue
    }
  }
  if ($entries.Count -eq 0) {
    Bad "could not read any host key -- the Storage Box is unreachable from this network"
    Read-Host "press Enter to close"; exit 1
  }
  Set-Content -Path $KnownHosts -Value $entries -Encoding ascii
  Ok "$($entries.Count / 2) host key(s) pinned in $KnownHosts"
} else {
  Ok "host key already pinned"
}

# --------------------------------------------------------------------------- 3. connect
Say "3. connect to the repository"
if (-not (Test-Path $ConfigFile)) {
  $out = & $kopia repository connect sftp --path=$RepoPath `
      --host="$sbHost" --port=23 --username="$sbUser" `
      --keyfile="$KeyFile" --known-hosts="$KnownHosts" `
      --config-file="$ConfigFile" 2>&1
  if ($LASTEXITCODE -ne 0) {
    Bad "connect failed"
    $out | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
    Read-Host "press Enter to close"; exit 1
  }
}
& $kopia repository status --config-file="$ConfigFile" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  Bad "repository unreachable (exit $LASTEXITCODE)"
  Read-Host "press Enter to close"; exit 1
}
Ok "connected to $RepoPath"


# --------------------------------------------------------------------------- 4. identity
Say "4. show DESKTOP1's snapshots as this client's own"
# The UI's snapshot list filters on the connected client's identity, so from any other
# machine it opens on an empty list -- the snapshots belong to aallison@desktop1. kopia
# 0.23 has no --override-hostname on connect; the identity is set after the fact with
# repository set-client. --read-only is set in the same call: this config exists only to
# read the vault, and the vault is the last copy of the workstation.
& $kopia repository set-client --username="$SourceUser" --hostname="$SourceHost" `
    --read-only --config-file="$ConfigFile" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Info "could not set the client identity (exit $LASTEXITCODE) -- the UI list may look empty" }
else { Ok "$SourceUser@$SourceHost, repository read-only" }

# --------------------------------------------------------------------------- 5. snapshots
Say "5. snapshots in the repository"
& $kopia snapshot list --all --config-file="$ConfigFile"
if ($ListOnly) { Write-Host ""; Read-Host "press Enter to close"; exit 0 }

# --------------------------------------------------------------------------- 6. open it
if ($Mount) {
  Say "6. mount as ${Drive}: and open Explorer"
  # kopia mounts over WebDAV on Windows, which needs the WebClient service. It is
  # demand-start on Windows 11 and starting it needs admin, so -Mount is the elevated
  # path; the default UI path needs no elevation at all.
  $wc = Get-Service WebClient -ErrorAction SilentlyContinue
  if ($wc -and $wc.Status -ne "Running") {
    try { Start-Service WebClient -ErrorAction Stop; Ok "WebClient (WebDAV) started" }
    catch {
      Bad "cannot start the WebClient service -- run this shortcut as administrator, or drop -Mount to use the browser UI"
      Read-Host "press Enter to close"; exit 1
    }
  }
  Write-Host ""
  Write-Host "  Closing this window unmounts ${Drive}:. The mount is READ-ONLY." -ForegroundColor Yellow
  Start-Job -Name grotap-open-explorer -ScriptBlock {
    param($d) Start-Sleep -Seconds 6; explorer.exe "${d}:\"
  } -ArgumentList $Drive | Out-Null
  & $kopia mount all "${Drive}:" --config-file="$ConfigFile"
  Get-Job -Name grotap-open-explorer -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
  exit 0
}

Say "6. open the backup in a browser"
# kopia's own web UI. It is served on loopback only and behind HTTP basic auth with a
# password generated fresh for this run, so nothing long-lived is left listening or
# stored. The credentials ride in the URL because that is the only way to hand them to
# the browser without a prompt; Chrome and Edge accept them on a top-level navigation.
$srvUser = "grotap"
$srvPass = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(18)).TrimEnd("=").Replace("/","_").Replace("+","-")
$srvLog  = Join-Path $StateDir "server.log"

# Port in use? Walk up. A stale kopia from a previous run holds 51515 for a while.
$listening = (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPort)
while ($listening -contains $Port) { $Port = $Port + 1 }

$srvArgs = @(
  "server", "start", "--ui",
  "--address=127.0.0.1:$Port",
  "--insecure",                        # plain HTTP -- loopback only, no TLS to manage
  "--without-password",                # no repository password prompt on the console
  "--server-username=$srvUser",
  "--server-password=$srvPass",
  "--config-file=$ConfigFile"
)
$srv = Start-Process -FilePath $kopia -ArgumentList $srvArgs -PassThru -WindowStyle Hidden `
         -RedirectStandardOutput $srvLog -RedirectStandardError "$srvLog.err"

# Wait for the listener rather than sleeping a fixed time -- first start has to open the
# repository over SFTP, which is slower than any guess worth hardcoding.
$url = "http://${srvUser}:${srvPass}@127.0.0.1:$Port/snapshots"
$up = $false
for ($i = 0; $i -lt 40; $i++) {
  Start-Sleep -Milliseconds 500
  if ($srv.HasExited) { break }
  if ((Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)) { $up = $true; break }
}
if (-not $up) {
  Bad "the kopia server did not start"
  Get-Content $srvLog, "$srvLog.err" -ErrorAction SilentlyContinue | Select-Object -First 10 |
    ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
  Read-Host "press Enter to close"; exit 1
}
Ok "serving on 127.0.0.1:$Port"

Start-Process $url | Out-Null
Write-Host ""
Write-Host "  The backup is open in your browser. Click a path, pick a date, then click into" -ForegroundColor White
Write-Host "  the folders. Any file or folder can be downloaded from that view." -ForegroundColor White
Write-Host ""
Write-Host "  If the browser did not open, paste this:" -ForegroundColor Gray
Write-Host "  $url" -ForegroundColor Yellow
Write-Host ""
Write-Host "  KEEP THIS WINDOW OPEN while you browse. Closing it stops the server." -ForegroundColor Yellow
Write-Host ""
Read-Host "press Enter when you are done to shut the server down"
Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue

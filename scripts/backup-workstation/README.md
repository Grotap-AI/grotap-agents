# Workstation backup — DESKTOP1 to Hetzner Storage Box

Versioned, encrypted, deduplicated backup of the owner's workstation, using
[Kopia](https://kopia.io) over SFTP to a Hetzner Storage Box, with a second copy for the
3-2-1 rule. Phase 1 of the cloud-workstation program; the plan is
`~/.claude/plans/delegated-cuddling-milner.md` and the memory file is
`project_cloud_workstation_0906`.

**Restoring right now?** Jump to [Restoring](#restoring). Everything above it is how the
machine is built.

---

## Status

Live as of **2026-09-06**. Repository created, policy applied (VSS `when-available`, zstd,
115 ignore rules), scheduled task registered, and a restore drill passed: 449 files / 1.8 MB
restored in 7.8 seconds, 447 byte-identical, with every discrepancy explained by writes made
after the snapshot.

| Fact | Value |
|---|---|
| Storage Box | `646430` `grotap-workstation-backup`, BX21 5 TB, Falkenstein, **$13.00/mo** |
| SFTP endpoint | `u664338-sub1@u664338-sub1.your-storagebox.de:23`, repo at `grotap-workstation` (relative -- see below) |
| Auth | ed25519 key, `C:\ProgramData\Grotap\backup\id_storagebox` |
| Local state | `C:\ProgramData\Grotap\backup\` — SYSTEM + Administrators only |
| Schedule | every **2 days at 01:30**, as SYSTEM, wake-to-run |
| Retention | 15 latest (= 30 days at this cadence) + 3 monthly |
| Compression | zstd |
| Encryption | client-side; passphrase in Doppler `grotap/prd` → `KOPIA_REPO_PASSWORD` |

Doppler `grotap/prd` also holds `STORAGEBOX_{ID,HOST,PORT,USER,PASSWORD,ADMIN_HOST,ADMIN_USER,ADMIN_PASSWORD,SSH_KEY}`.
The SSH private key is in Doppler on purpose: losing the desktop otherwise loses the only
key that can reach the backup.

---

## Files

| File | What it does |
|---|---|
| `install-backup.ps1` | One-time (idempotent) setup: ACLs the state dir, caches the passphrase, applies ignore + retention policy, registers the scheduled task. **Needs an elevated shell.** |
| `backup-run.ps1` | The task body. Also safe to run by hand. |
| `verify-restore.ps1` | Restores a sample and diffs it against live. Run it monthly. |
| `browse-backup.ps1` | Opens the backup for **reading** -- see [Browsing the backup](#browsing-the-backup). Needs no elevation and touches nothing the backup task owns. |
| `kopiaignore` | The exclude patterns, with a comment per block explaining *why*. |

---

## Setup on a new machine

The repository already exists, so a second machine connects to it rather than creating one.
`install-backup.ps1` does the connection itself -- there is no separate manual step.

```powershell
winget install --id Kopia.KopiaCLI --exact --silent

# Trust the Storage Box host key once (any shell)
ssh -o StrictHostKeyChecking=accept-new -p 23 u664338-sub1@u664338-sub1.your-storagebox.de df -h

# Everything else, from an ELEVATED PowerShell
powershell -ExecutionPolicy Bypass -File .\install-backup.ps1 -UserProfile "C:\Users\<name>"

# Prove it, don't assume it
Start-ScheduledTask -TaskName Grotap-Backup-Workstation
.\verify-restore.ps1
```

The installer pulls the SSH key and passphrase from Doppler, connects, applies policy, and
registers the task. `-UserProfile` matters on any machine whose account is not `aallison`:
the task runs as SYSTEM, so `$env:USERPROFILE` points at
`C:\Windows\system32\config\systemprofile` and cannot be used to find the real profile.

Each machine should get **its own Storage Box sub-account** so a compromise of one cannot
reach another's backups. Storage Boxes live at `api.hetzner.com/v1`, *not* the Cloud API at
`api.hetzner.cloud/v1`, and a new box defaults to `reachable_externally: false`, which
silently blocks any machine outside Hetzner's network.

### The repository path is relative on purpose

`--path=grotap-workstation`, with no leading slash. Do not "fix" it to an absolute POSIX
path. It was originally created as `/home/kopia` from Git Bash, and MSYS rewrote that
argument on the way to the server: the repository was physically created at
`C:/Program Files/Git/home/kopia` on the Storage Box. Every command run from Git Bash
mangled it identically so it appeared to work, while the same command from PowerShell
failed with `repository not initialized in the provided storage`. A relative path is passed
through untouched by both shells.

## Browsing the backup

`browse-backup.ps1` opens the repository read-only and serves Kopia's own web UI on
loopback, so any snapshot can be opened in a browser and any file or folder downloaded
from it. It runs on **any** machine with a Doppler login that can read `grotap/prd` -- the
SSH key, the endpoint and the passphrase all come from there -- and it installs the Kopia
CLI with winget if it is missing.

```powershell
# the default: connect, list, open the UI in the default browser
powershell -ExecutionPolicy Bypass -File .\browse-backup.ps1

.\browse-backup.ps1 -ListOnly     # print the snapshots to the console, nothing else
.\browse-backup.ps1 -Mount        # mount as R:\ for Explorer instead (needs admin)
```

There is a desktop shortcut for the default path, **Desktop Backup (cloud)**, created
2026-09-08 on the roof laptop `GrotapInfoAA2`. It runs the same script; keep the console
window it opens, because closing it stops the server. Recreate it anywhere with:

```powershell
$w = New-Object -ComObject WScript.Shell
$l = $w.CreateShortcut("$env:USERPROFILE\Desktop\Desktop Backup (cloud).lnk")
$l.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$l.Arguments  = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\1Claude\scripts\backup-workstation\browse-backup.ps1"'
$l.WorkingDirectory = "C:\1Claude\scripts\backup-workstation"
$l.IconLocation = "$env:SystemRoot\System32\shell32.dll,7"
$l.Save()
```

Its state (its own `repository.config`, the SSH key, `known_hosts`) lives under
`%LOCALAPPDATA%\Grotap\backup-browse`, **not** the SYSTEM-only
`C:\ProgramData\Grotap\backup` the scheduled task uses, so browsing from the backed-up
machine cannot disturb the task. The config is marked `--read-only`.

### Four things that made this harder than it looks (all proven 2026-09-08)

- **`ssh-keyscan` cannot read this box's host key.** OpenSSH_for_Windows 9.5p2 aborts with
  `choose_kex: unsupported KEX method sntrup761x25519-sha512@openssh.com` and prints
  nothing, which reads as an unreachable host. A plain `ssh` connect negotiates fine and
  writes the key itself; its authentication failure afterwards is irrelevant.
- **Pin every host key type, not one.** The box offers ed25519, rsa and ecdsa-nistp521.
  kopia (Go `x/crypto/ssh`) leaves `HostKeyAlgorithms` nil and Go's default order puts
  ed25519 **last**, so it negotiates ecdsa-nistp521 against an ed25519-only `known_hosts`
  and fails with nothing but `knownhosts: key mismatch`. Probe each type into its own
  file: several types for one host in one file makes ssh cry REMOTE HOST IDENTIFICATION
  HAS CHANGED and refuse to add.
- **kopia looks the host up without the port.** `ssh` only ever writes `[host]:23` for a
  non-default port; kopia asks for bare `host` (`unable to getHostKey: <host>`). Write
  both forms.
- **The UI filters snapshots by the client's own identity**, so from any machine that is
  not DESKTOP1 it opens on an empty list. kopia 0.23 has no `--override-hostname` on
  `repository connect`; fix it afterwards with
  `kopia repository set-client --username=aallison --hostname=desktop1`.

Also: winget installs Kopia as a **portable** package -- the exe lands under
`%LOCALAPPDATA%\Microsoft\WinGet\Packages\Kopia.KopiaCLI_*\kopia-<ver>-windows-x64\`
and only a freshly started shell sees it on `PATH`, so a just-installed kopia is invisible
to `Get-Command` in the installing process.

---

## Restoring

```powershell
$env:KOPIA_PASSWORD = (doppler secrets get KOPIA_REPO_PASSWORD -p grotap -c prd --plain)
$cfg = "C:\ProgramData\Grotap\backup\repository.config"

kopia snapshot list --config-file=$cfg                    # find the snapshot
kopia snapshot restore <rootID> C:\restore --config-file=$cfg   # whole snapshot
kopia restore <rootID>/some/sub/path C:\restore --config-file=$cfg   # one subtree
kopia mount <rootID> R: --config-file=$cfg                # browse it as a drive
```

If the desktop is gone entirely, everything needed to reach the repository is in Doppler:
the SSH key, the endpoint, and the passphrase. Log into Doppler from any machine, follow
*Setup on a new machine* above, and restore.

---

## What this does NOT protect

Read this before trusting the backup with something it was never going to carry.

**Windows sessions and saved passwords do not survive a move to another machine.** Browser
passwords, all browser cookies, and the Windows Credential Manager — which is where the
`gh` token and Docker registry credentials actually live, *not* in their config files — are
DPAPI-encrypted and bound to this machine and this SID. They restore byte-identical and
completely non-functional anywhere else, including a same-name Windows reinstall. Chrome
127+ App-Bound Encryption additionally validates the calling binary's install path through
a SYSTEM service. **Bitwarden is the exception**: `AppData\Roaming\Bitwarden\data.json` is
derived from the master password and works anywhere. So the real recovery path for logins
is Bitwarden plus `gh auth login`, and the backup covers everything else.

**Live credentials are excluded on purpose.** `.doppler`, `.ssh`, `.codex/auth.json`,
`.hi_token`, `.hi_url` and the `.chrome-debug-*` profiles are all skipped. Every one is
rotatable in minutes, so excluding them loses nothing recoverable and removes the risk of
an encrypted archive on a third party's disk decrypting to production access.

**`.claude/projects` is excluded** — 764 MB, unbounded growth, and, discovered on
2026-09-06, agent transcripts there had accumulated live API keys in plaintext as ordinary
tool output. Conversation logs collect secrets whether or not anyone intends them to.
Claude's *memory* files under `.claude/projects/<slug>/memory/` ARE kept: `backup-run.ps1`
enumerates every `.claude/projects/*/memory` directory and adds each as its own snapshot
source. Ignore rules apply while traversing down from a source root, so a source inside an
ignored path is still captured. Ten such directories were found on DESKTOP1. If you edit
either half of that arrangement, edit both -- the exclude and the source list.

**Virtual disks are excluded and must be captured differently.** WSL2 and Docker VHDXs
total 5.23 GB in three files. VSS snapshots the host NTFS volume without quiescing the
ext4 filesystem inside the image, so a file-level copy is crash-inconsistent by
construction. Use `wsl --export` for distros; registries and `docker volume` exports for
Docker.

**Google Drive (`G:`) is excluded** because Drive is already the cloud copy. That is a
deliberate accepted gap, not an oversight: Drive syncs deletions and ransomware straight
through, and its only floor is a 30-day trash.

**Platform data is out of scope** — Neon databases, R2 assets, Doppler secrets and the
platform source are covered by the agent-06 backup machine
(`platform/scripts/backup/`, `platform/docs/BACKUP_MACHINE.md`). This is only the workstation.

---

## Operating notes

**Throughput, measured 2026-09-06 from Portland to Falkenstein.** Upload is
latency-limited, not bandwidth-limited, and parallelism is the only lever that matters:

| Streams | Throughput |
|---|---|
| 1 | 0.24 MB/s (1.9 Mbit/s) |
| 4 | 1.17 MB/s (9.4 Mbit/s) |
| 16 | 1.99 MB/s (15.9 Mbit/s) |

That is 8.3x from parallelism alone, which is why `backup-run.ps1` defaults to
`--parallel=16`; 16 concurrent SFTP sessions are accepted by the Storage Box. Scaling is
already flattening at 16, so raising it further buys little. The first snapshot managed
0.9 GB / 6,852 files in 24m32s at default parallelism — per-file round trips dominate, so
the file *count* sets the pace, not the byte count. Expect roughly an hour for the first
full run and single-digit minutes after that. Restores are much faster (449 files in 7.8 s)
because Kopia parallelises them by default.

**Failure handling.** The first failure is logged and left for the next scheduled run to
retry. Only a *second consecutive* failure escalates. This follows the rule in
`platform/CLAUDE.md`: a monitor whose only possible advice is "run it again" should run it
again, and the board is for blocked work, not for run summaries.

**Why the success stamp is written before housekeeping.** The platform backup machine once
reported "STALE" for three weeks while succeeding every Sunday, because its heartbeat was
stamped *after* pruning and a non-zero exit from pruning killed the script first. Data
safe, then stamp, then housekeeping — in that order, always.

**Why the task runs as SYSTEM.** VSS needs administrative rights, and `AppData` and
`NTUSER.DAT` are locked while the owner is logged in. A backup that silently skips locked
files is indistinguishable from one that works until the restore. SYSTEM has no Doppler
login, which is why `install-backup.ps1` caches the passphrase into a SYSTEM-only file.

**`WakeToRun` and `StartWhenAvailable` are both required.** Without the first, a sleeping
desktop never runs the 01:30 job. Without the second, a machine that was powered off skips
the slot entirely and waits another two days.

**Kopia's path moves on upgrade.** winget installs it under a versioned
`WinGet\Packages\...` directory, so the scripts resolve `kopia.exe` at run time and fail
loudly if they cannot find it, rather than exiting 0 having backed up nothing.

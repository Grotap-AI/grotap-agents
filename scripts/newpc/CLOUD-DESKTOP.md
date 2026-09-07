# Cloud desktop — build runbook

A Hetzner Cloud VM that runs the same workstation `DESKTOP1` runs, reachable by RDP over
Tailscale from any device, with a route back onto the hardware LAN. Read `README.md` first if you
have never built one of these machines; this document assumes you know what `setup.ps1` does and
covers only what is different about building it in a datacenter.

**Hands-on: ~1 hour of typing. Waiting: 4–6 hours the first time**, most of it the Windows 11
install running under emulation. The second seat takes ten minutes, because of step 8.

| | Cloud desktop | Roof laptop |
|---|---|---|
| Hardware | Hetzner CCX23, 4 dedicated vCPU / 16 GB, Hillsboro OR | HP laptop |
| Windows | 11 Pro from the public ISO, upgraded to Enterprise by Entra join | 11 Home, local account |
| Account | Entra ID (M365 Business Premium) — **required**, it is the licence | local `aallison` |
| Reached by | RDP over Tailscale only. No public port is open at all | it is in your hands |
| LAN access | via DESKTOP1's advertised subnet routes | direct |
| GPU | none, ever — Hetzner Cloud has no GPU instances | RTX-less, same |
| Side repos / Android | yes (`-WithSideRepos -WithAndroid`) | yes |

---

## 1. What this builds, and what it costs

```
   any browser / laptop / phone
            |  RDP over Tailscale (WireGuard). No public 3389. No inbound rules at all.
            v
   +---------------------------------------+
   |  grotap-cloud-01   Hetzner CCX23      |   hil = Hillsboro, Oregon
   |  Windows 11 Enterprise (Entra-joined) |   4 dedicated vCPU / 16 GB
   |  C: 160 GB local  +  D: 250 GB volume |
   |  built by scripts\newpc\setup.ps1     |
   +------------------+--------------------+
                      | Tailscale, --accept-routes
                      v
   +-------------------------------------------+
   |  DESKTOP1  (stays on, demoted to a relay)  |
   |  advertises 192.168.25.0/24 (printer,      |
   |  CS463 reader, tablets) and 192.168.86.0/24|
   |  (house wifi). Keeps GrotapPrintCloud.     |
   +-------------------------------------------+
```

| Line | Monthly (USD, VAT 0%) |
|---|---|
| Hetzner CCX23, `hil` | $102.99 |
| Primary IPv4 | $0.60 |
| Volume, 250 GB @ $0.0767/GB | $19.18 |
| **Created by the provisioning script** | **$122.77** |
| Golden-image snapshot, ~60 GB @ $0.0199/GB (step 8) | ~$1.20 |
| Hetzner Storage Box BX21, 5 TB (already live, Phase 1) | ~$12.00 |
| M365 Business Premium, 1 seat | $22.00 |
| Wasabi second backup site | $0 marginal — existing `platform-backups` bucket |
| **Total, seat 1** | **~$158.00** |

Hetzner's own automated backups (+20%, $20.60/mo) are deliberately **not** enabled. Kopia plus the
golden snapshot cover the same ground more cheaply, with restores that have actually been tested.

A second seat adds roughly $145/mo: another CCX23 built from the golden image, plus another
Business Premium seat. Windows 11 client allows one interactive RDP session per VM and there is no
multi-session Windows 11 outside Azure, so two people cannot share one box.

---

## 2. Prerequisites

**An M365 Business Premium seat, assigned to the account that will log into this VM.** This is not
an optional convenience — it is the licence. The install is plain Windows 11 **Pro** from
Microsoft's free public ISO, which on its own carries no right to run on a third-party host's
hardware. Joining the machine to Entra ID with a Business Premium account triggers Windows
**Subscription Activation**, which upgrades Pro to **Enterprise**, and the Enterprise SKU is what
carries the VDA rights that make this VM legal on Hetzner. Hetzner is not one of Microsoft's
"Listed Providers" (AWS, Azure, GCP, Alibaba), so the October 2022 Flexible Virtualization terms
apply here — this is exactly the case they were written for.

`winver` reporting "Windows 11 Enterprise" is the proof that this worked. If it still says Pro,
you are running unlicensed; see step 7 and the troubleshooting section.

Also required before you start:

- **Doppler access to `grotap/prd`**, which holds `HETZNER_API_TOKEN`, `TAILSCALE_AUTHKEY`,
  `TAILSCALE_API_TOKEN`, the `STORAGEBOX_*` set and `KOPIA_REPO_PASSWORD`.
- **An SSH key in the Hetzner Cloud project** (console → Security → SSH Keys). Rescue mode is
  key-only; without a key on the server there is no way in and no way to install Windows.
- **A Windows 11 ISO downloaded onto DESKTOP1.** Get it from
  `https://www.microsoft.com/software-download/windows11`. The actual download URL is
  session-signed and expires, so it cannot be fetched with `curl` from the server — you download it
  locally and push it up.
- **A VNC viewer** on whichever machine you drive the install from (TightVNC, RealVNC Viewer,
  Remmina — anything that speaks RFB).
- **Tailscale already working on DESKTOP1.** It is: DESKTOP1 is on the `grotap.com` tailnet as
  `desktop1` / `100.99.158.19`, advertising `192.168.25.0/24` and `192.168.86.0/24`, both routes
  **approved** in the admin console, key expiry disabled, `--unattended`, `IPEnableRouter=1`.

---

## 3. Provision the infrastructure

From DESKTOP1, in `C:\1Claude`:

```powershell
doppler run -p grotap -c prd -- python scripts\newpc\cloud-desktop-provision.py
```

That is the **dry run — it is the default and it creates nothing.** It prints the plan (firewall,
volume, server), tells you which already exist, and prints the projected monthly cost from
Hetzner's live pricing API. Read the cost table before you go further; this is recurring spend.

If the project holds more than one SSH key the script refuses to guess — pass `--ssh-key NAME`.

When the plan looks right:

```powershell
doppler run -p grotap -c prd -- python scripts\newpc\cloud-desktop-provision.py --apply
```

It creates, in order:

- **Firewall `grotap-cloud-desktop` with zero inbound rules.** Not "3389 from my IP" — nothing.
  Every route into this box is Tailscale, which dials out and needs no listening port. A Windows
  machine with 3389 reachable from the internet is found by scanners within minutes of the IP going
  live, and it gets found whether or not the password is good. A Hetzner firewall with no outbound
  rules leaves outbound unrestricted, so an empty rule set means exactly "nothing in, everything
  out".
- **Volume `grotap-cloud-01-data`, 250 GB, unformatted.** No filesystem on purpose: Windows
  reformats it as NTFS when it initialises `D:`.
- **Server `grotap-cloud-01`**, `ccx23` in `hil`, image `ubuntu-24.04` as a placeholder that the
  Windows install overwrites, firewall applied, volume attached, your SSH key injected.

The script is idempotent — every resource is looked up by name first, so a re-run after a Ctrl-C or
a dropped connection resumes instead of building a second $103/month server. It waits on every
Hetzner action (including the `next_actions` that attach the volume and apply the firewall) and
fails loudly with the API's own error text rather than reporting success on a half-built server.

On success it prints the server's IPv4, the volume's device path on the rescue system, and the
exact commands for step 4. Keep that output.

To tear it all down: `... --destroy`, which makes you type the server name. It refuses to delete
the firewall if another server is still using it.

> `--destroy` deletes the 250 GB volume and everything on `D:`. Hetzner keeps no copy. Snapshots
> and images survive it.

---

## 4. Install Windows 11 — the fiddly part

Hetzner Cloud's ISO library is **public-only**: Windows Server 2019/2022/2025 and virtio-win, no
Windows 11, and it accepts no private ISO uploads. So Windows 11 goes on through the **rescue
system**, with QEMU writing the install straight to `/dev/sda`. When it is done you reboot the
server and it boots that disk natively — the QEMU VM was only the installer's host.

Run the API calls from **Git Bash**, not PowerShell 5.1: PS 5.1 re-splits the embedded JSON quoting
and the request goes out malformed. The IDs below come from the script's output.

### 4.1 Boot into rescue

```bash
curl -sS -X POST "https://api.hetzner.cloud/v1/servers/<server-id>/actions/enable_rescue" \
  -H "Authorization: Bearer $HETZNER_API_TOKEN" -H "Content-Type: application/json" \
  -d '{"type":"linux64","ssh_keys":[<ssh-key-id>]}'

curl -sS -X POST "https://api.hetzner.cloud/v1/servers/<server-id>/actions/reset" \
  -H "Authorization: Bearer $HETZNER_API_TOKEN"
```

Give it a minute, then SSH in. The host key **will** have changed — rescue is a different system,
so the mismatch warning is expected here and only here:

```bash
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@<ip>
```

### 4.2 Stage the ISOs on the data volume

The rescue root filesystem is a small ramdisk and a 6 GB Windows ISO will fill it. Use the 250 GB
volume as scratch — Windows reformats it as `D:` later, so nothing is wasted:

```bash
apt update && apt install -y qemu-system-x86 qemu-utils

# device path is printed by the provisioning script
mkfs.ext4 -F /dev/disk/by-id/scsi-0HC_Volume_<volume-id>
mkdir -p /mnt/iso && mount /dev/disk/by-id/scsi-0HC_Volume_<volume-id> /mnt/iso

curl -L -o /mnt/iso/virtio-win.iso \
  https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
```

That URL is the *stable* virtio build, whatever the current version is. The verified-good build for
this runbook is **0.1.285**; check what you got with `isoinfo -d -i /mnt/iso/virtio-win.iso` or just
read the version off the CD once Windows is up. If you need 0.1.285 specifically it is under
`.../direct-downloads/archive-virtio/`, but **I have not verified the exact directory name inside
that archive** — browse the index rather than guessing a path.

Then push the Windows ISO up from DESKTOP1, in a second terminal:

```bash
scp /c/Users/aallison/Downloads/Win11_24H2_English_x64.iso root@<ip>:/mnt/iso/win11.iso
```

### 4.3 Check what the rescue system can actually do

Two things decide the QEMU command line, and both are one command:

```bash
ls -l /dev/kvm            # present -> hardware acceleration is available
ls -d /sys/firmware/efi   # present -> this VM booted UEFI; absent -> legacy BIOS
```

**Expect `/dev/kvm` to be absent.** Hetzner Cloud does not offer nested virtualization, so QEMU
will run in TCG software emulation. It works, but the Windows install takes hours rather than
minutes. That is the whole reason step 8 exists. Do not pass `-enable-kvm` or `-cpu host` when
`/dev/kvm` is missing — QEMU refuses to start and `-cpu host` is meaningless without KVM.

The `/sys/firmware/efi` check tells you which firmware to give QEMU, because the disk you produce
has to boot the same way Hetzner boots it natively. If it is **absent**, use QEMU's default SeaBIOS
(that is, pass no `-bios` and no OVMF pflash) and let Windows lay down an MBR layout. If it is
**present**, you need an OVMF/UEFI setup instead — install `ovmf` and pass the firmware as pflash.
**I have not verified which mode Hetzner Cloud uses for a natively booted disk in `hil`, so run the
check rather than trusting either answer.** Getting this wrong produces a server that boots to a
blinking cursor after step 4.7 and is the second most likely way to lose an afternoon here.

### 4.4 Run the installer VM

```bash
qemu-system-x86_64 -machine q35 -smp 4 -m 8192 \
  -drive file=/dev/sda,format=raw,if=virtio,cache=none \
  -drive file=/mnt/iso/win11.iso,media=cdrom,index=1 \
  -drive file=/mnt/iso/virtio-win.iso,media=cdrom,index=2 \
  -boot d -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -device usb-ehci -device usb-tablet -vnc 127.0.0.1:0 -monitor stdio
```

Notes on that line:

- `/dev/sda` is the server's own system disk. The **data volume is deliberately not given to
  QEMU** — the installer sees exactly one disk and cannot install to the wrong one.
- `-vnc 127.0.0.1:0` binds VNC to loopback only, so it is not reachable from the internet even
  though the firewall would already stop that. Display `:0` is TCP port 5900.
- `-device usb-tablet` gives absolute mouse positioning. Without it the pointer in the VNC window
  drifts away from the real cursor and clicking anything is miserable.
- `-monitor stdio` keeps the QEMU monitor on your SSH session so you can `system_powerdown` or
  `quit` cleanly at the end.
- Run it under `tmux` or `screen`. If your SSH session drops, QEMU dies with it and you start the
  install again.

From your own machine, tunnel to that VNC and point a viewer at `localhost:5900`:

```bash
ssh -N -L 5900:127.0.0.1:5900 root@<ip>
```

### 4.5 Get past the two things that stop the installer

**The disk.** Windows Setup will reach "Where do you want to install Windows?" and show **no
drives**. This is the step almost everyone fails at, and the message does not hint at the cause:
the disk is virtio and Windows ships no virtio driver. Click **Load driver** → **Browse**, pick the
virtio CD, and navigate to the folder matching your OS and architecture — for Windows 11 x64 that is
`viostor\w11\amd64` (if the CD has no `w11` folder, `w10\amd64` is the correct substitute; the
driver is the same). Select it, and the disk appears. Then partition and continue normally.

**The hardware checks.** Hetzner Cloud VMs present no TPM and no Secure Boot, so Windows 11 Setup
will stop with "This PC can't run Windows 11". Bypass it at the installer:

1. Press **Shift + F10** to open a command prompt.
2. `regedit`
3. Navigate to `HKEY_LOCAL_MACHINE\SYSTEM\Setup`, create a key named **`LabConfig`**.
4. In it create four **DWORD (32-bit)** values, each set to **1**:
   `BypassTPMCheck`, `BypassSecureBootCheck`, `BypassRAMCheck`, `BypassCPUCheck`.
5. Close regedit and the command prompt, then go **Back** one screen and forward again.

These are not optional and they are not just an installer trick — the machine has no TPM after the
install either.

### 4.6 Before you shut QEMU down, do everything that needs a console

Once you reboot natively you have no screen. The Hetzner Cloud web console exists as a fallback
(`hcloud server request-console <name>`, or the Console button in the Hetzner UI) but it is a
limited VNC where pasting a long Tailscale auth key is genuinely painful. Do this work now, inside
QEMU, where you have a real VNC session:

1. **Install the complete virtio guest tools.** Open the virtio CD in Explorer and run
   `virtio-win-guest-tools.exe` (or `virtio-win-gt-x64.msi`). This installs *all* the virtio
   drivers, not just the storage one you loaded during setup — including **NetKVM**, without which
   the natively booted server has no network at all.

   This matters more than it looks. In the rescue system the root disk appears as `/dev/sda`, which
   suggests Hetzner presents virtio-**scsi**, while the QEMU line above attaches it as virtio-**blk**.
   I have not verified which flavour a natively booted Hetzner guest sees. Installing the full guest
   tools lays down both `viostor` (blk) and `vioscsi` (scsi) with boot-critical start types, so the
   disk boots either way. Skipping this is how you get a `0x7B INACCESSIBLE_BOOT_DEVICE` on the
   first native boot.

2. **The UTC clock fix — step 5 below.** Do it here.
3. **Tailscale — step 6 below.** Do it here.

Then shut the guest down cleanly (Start → Power → Shut down, or `system_powerdown` at the QEMU
monitor) and wait for QEMU to exit.

### 4.7 Boot it natively

```bash
umount /mnt/iso
curl -sS -X POST "https://api.hetzner.cloud/v1/servers/<server-id>/actions/disable_rescue" \
  -H "Authorization: Bearer $HETZNER_API_TOKEN"
curl -sS -X POST "https://api.hetzner.cloud/v1/servers/<server-id>/actions/reset" \
  -H "Authorization: Bearer $HETZNER_API_TOKEN"
```

If step 6 was done inside QEMU, the box comes up on the tailnet within a minute or two and you can
RDP straight to it. If it does not, the Hetzner web console is how you find out why.

---

## 5. Fix the clock (do this inside QEMU, before the reboot)

Every Hetzner host runs its hardware clock in **UTC**. Windows assumes the hardware clock is local
time, so without this the clock is wrong by your UTC offset after every single reboot — and a wrong
clock breaks TLS certificate validation, which means every signed request the fleet makes fails in
a way that looks like a network problem.

In an **elevated** PowerShell inside the guest:

```powershell
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' `
  -Name RealTimeIsUniversal -PropertyType DWord -Value 1 -Force

tzutil /s "Pacific Standard Time"
w32tm /resync
```

Verify after each of the two reboots that follow. Two, not one — a clock that is right immediately
after the change and wrong after the next boot is the classic symptom of the value not sticking.

---

## 6. Tailscale, and RDP that only listens on it

Also done inside QEMU, before the native reboot.

Read the auth key on DESKTOP1 and carry it across:

```powershell
# on DESKTOP1
doppler secrets get TAILSCALE_AUTHKEY --plain -p grotap -c prd
```

Then in the guest, download the Tailscale MSI from `https://tailscale.com/download/windows`,
install it, and join:

```powershell
tailscale up --authkey <key> --accept-routes --unattended `
  --hostname=grotap-cloud-01 --accept-dns=false
```

- **`--accept-routes` is the whole point of this box's networking, and it is the reverse of what
  DESKTOP1 does.** DESKTOP1 *advertises* `192.168.25.0/24` and `192.168.86.0/24`; this machine
  *consumes* them. Without `--accept-routes` the tailnet works fine, RDP works fine, and every
  attempt to reach `192.168.25.50:9100` or the CS463 on `:5084` fails — with no error that points
  at the cause.
- `--unattended` keeps the tunnel up when nobody is signed in, which on a headless VM is always.
- `--accept-dns=false` matches DESKTOP1's setting.
- The `TAILSCALE_AUTHKEY` in Doppler is reusable and **expires 2026-12-05**. After that date,
  mint a new one in the admin console and update Doppler.

In the Tailscale admin console, **disable key expiry** for this node. A cloud desktop whose node key
expires is a machine you cannot reach, on a box with no open ports and no console you enjoy using.

Now enable RDP, scoped to Tailscale only:

```powershell
# turn RDP on
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
  -Name fDenyTSConnections -Value 0

# the stock RDP firewall rules allow any source on the matching profile -- switch them off
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | Disable-NetFirewallRule

# allow 3389 only from the Tailscale CGNAT range
New-NetFirewallRule -DisplayName 'RDP over Tailscale' -Direction Inbound -Action Allow `
  -Protocol TCP -LocalPort 3389 -RemoteAddress 100.64.0.0/10
```

This is defence in depth: the Hetzner firewall already drops everything inbound. It exists because
firewalls get edited, and the day someone adds a rule "just to test something" this is what stops
3389 from being open to the internet.

Connect from anywhere on the tailnet with `mstsc /v:grotap-cloud-01` or the node's `100.x.y.z`.

---

## 7. Entra ID join — this is the licensing step

Do this **after** the native reboot, not inside QEMU. Entra device registration binds to hardware
identifiers, and those change between the QEMU guest and the native machine; joining twice is
avoidable work.

Either path works:

- **At OOBE**, if you have not finished setup yet: on "How would you like to set up this device?"
  choose **Set up for work or school** and sign in with the M365 Business Premium account.
- **After setup**: Settings → Accounts → **Access work or school** → **Connect** → then the small
  **"Join this device to Microsoft Entra ID"** link under *Alternate actions*. It is easy to miss
  and the obvious button does the wrong thing (it adds a work account to the existing profile
  instead of joining the device).

Confirm the join with `dsregcmd /status` — `AzureAdJoined : YES` in the Device State block.

Then reboot, sign in **as the Entra account**, and check:

```powershell
winver
```

It must say **Windows 11 Enterprise**. That is Subscription Activation having fired, and it is the
proof that the VDA rights covering this VM on Hetzner are in force. If it says Pro, you are not
licensed to run this — see troubleshooting.

> **Expect the profile folder not to be `aallison`.** An Entra-joined profile is named from the UPN
> (something like `C:\Users\info`), and there is no clean way to force it. Do not fight it. It does
> not affect the repo paths — `C:\1Claude` is absolute and every memory project slug derives from
> the repo path, not the profile — but it does mean the Kopia restore in step 10 has to be
> redirected, because everything in it is filed under `C:\Users\aallison\...`.

---

## 8. Snapshot it now, before anything else

**This is the highest-value ten minutes in the whole build.** You have just spent 4–6 hours on an
install that runs under software emulation because Hetzner Cloud has no nested virtualization. A
snapshot turns every future repeat of it — Mike's seat, a rebuild after a mistake, a second
region — into a ten-minute `create from image`. At $0.0199/GB/month a ~60 GB image costs about
$1.20/month. Skipping it is the most expensive mistake available in this plan.

Take **two different snapshots**, for two different jobs:

**A. A rollback point — now, no sysprep.** This is insurance for the next few hours, while you run
`setup.ps1` and restore data. Shut the server down first so the image is consistent:

```bash
curl -sS -X POST "https://api.hetzner.cloud/v1/servers/<server-id>/actions/shutdown" \
  -H "Authorization: Bearer $HETZNER_API_TOKEN"
# wait for status "off", then:
curl -sS -X POST "https://api.hetzner.cloud/v1/servers/<server-id>/actions/create_image" \
  -H "Authorization: Bearer $HETZNER_API_TOKEN" -H "Content-Type: application/json" \
  -d '{"type":"snapshot","description":"win11-clean-preSetup-2026-09-06"}'
```

Do **not** reuse this one to build another seat. It carries this machine's SID, its Tailscale node
state and its Entra device registration; a clone would fight the original over all three.

**B. A golden image — later, sysprepped.** When you actually want a second seat, run
`C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown` inside the machine and take a
snapshot of the result. `/generalize` clears the SID and the machine-specific state, which is what
makes the image genuinely reusable. The cost is that seat 1 then has to walk back through OOBE from
that same image — about ten minutes. Note that Tailscale should be **installed but not joined** in
a golden image, so each new seat runs its own `tailscale up --authkey`; a cloned node key is a node
key conflict.

New seat from a golden image, once you have one:

```bash
hcloud server create --name grotap-cloud-02 --type ccx23 --location hil \
  --image <snapshot-id> --firewall grotap-cloud-desktop --ssh-key <key-name>
```

---

## 9. Make it your workstation

From here it is the ordinary new-PC path — `README.md` and `ROOF-LAPTOP.md` describe it in full, and
nothing about it is cloud-specific. Over RDP, in PowerShell:

```powershell
irm https://claude.ai/install.ps1 | iex
winget install --id Git.Git --exact --silent --accept-package-agreements
winget install --id GitHub.cli --exact --silent --accept-package-agreements
```

Open a **new** terminal — the PATH changed and the current shell cannot see it — then:

```powershell
gh auth login
gh repo clone Grotap-AI/grotap-agents C:\1Claude
```

> `C:\1Claude` is not a preference. Every MD file, hook and memory-project slug is keyed to that
> absolute path (`C:\1Claude\platform` → `C--1Claude-platform`). Clone anywhere else and the
> restored memory loads nowhere, silently.

Then the one command that does the rest:

```powershell
cd C:\1Claude
powershell -ExecutionPolicy Bypass -File scripts\newpc\setup.ps1 -WithSideRepos -WithAndroid `
    -GitName "Platform Build" -GitEmail "info@grotap.com"
```

`-WithSideRepos` brings `C:\2Claude`, `C:\7ClaudeMarketingAgents` and `C:\8Claude`; `-WithAndroid`
builds the ~1 GB SDK for Scan M APK builds. Both are right for the owner's own seat. For a second
person's box, drop `-WithSideRepos` (`2Claude` is corporate/legal) and pass *their* `-GitName` /
`-GitEmail`. Idempotent — re-run it freely.

**Use `D:` for the bulky, rebuildable things.** `C:` is 160 GB and the gradle cache, the Android
SDK and the Playwright browsers will eat a serious fraction of it. Move them to the 250 GB volume
and junction them back, after `setup.ps1` has put them in place. Initialise the volume first
(Disk Management → the 250 GB uninitialised disk → GPT → new NTFS simple volume → letter `D:`).

Then the logins, which only you can do:

```powershell
claude                 # /login -- Claude subscription OAuth
doppler login
cd C:\1Claude\platform ; doppler setup -p grotap -c dev
codex login            # OpenAI -- powers the /codex:* pre-commit review gate
railway login
vercel login
```

Finally, prove it:

```powershell
powershell -ExecutionPolicy Bypass -File C:\1Claude\scripts\newpc\verify.ps1 -WithSideRepos -WithAndroid
```

Read-only. Aim for **0 FAIL**; `railway` and `vercel` show as warn until you log in. The desktop's
own baseline on 2026-09-04 was `53 ok, 3 warn, 2 FAIL`.

---

## 10. Restore your data from the Kopia repository

`setup.ps1` reinstalls the *toolchain*. It does not restore Claude's accumulated memory, the fleet
SSH keys, `Documents`, `Desktop`, or the `.doppler` / `.codex` / `.claude` state — that comes out of
the Phase 1 backup, and this is also the **first real restore drill**, which is much of the point of
doing it in this order. Record what you restored and how long it took.

The repository, the retention policy and the restore procedure live in
**`C:\1Claude\scripts\backup-workstation\`** (`README.md` for the procedure, `verify-restore.ps1`
for a sampled restore). Those scripts are written separately from this runbook — follow what is in
that folder rather than anything remembered here. What matters at this point in the build:

- The Storage Box repository is the primary; Wasabi is the second site and is never newer.
- `KOPIA_REPO_PASSWORD` is in Doppler `grotap/prd` **and** in Bitwarden. Without it the backup is
  an encrypted brick.
- **Paths need redirecting.** Everything in the repository is filed under `C:\Users\aallison\...`
  and this machine's Entra profile is not called `aallison` (step 7). Restore to the real profile
  path.
- Claude's memory is the one thing here that cannot be re-earned. `memory-migrate.ps1 -Import`
  merges it in and deletes nothing.
- Do **not** copy `~/.claude/.credentials.json`, `history.jsonl`, `sessions/`, `shell-snapshots/`,
  `cache/` or any `settings.local.json`. Machine-local state and auth — log in fresh.

Then install Kopia on **this** box too, on the same cadence, with its own repository path
(`kopia/cloud-01`). A machine is not backed up because it is in a datacenter. Hetzner protects
against their hardware failing, not against you.

---

## 11. Verification checklist

Work through all of it. A green checklist is not the same as working, but an unchecked one is
reliably worse.

**The machine**

- [ ] `winver` says **Windows 11 Enterprise**, not Pro. (Licensing. Non-negotiable.)
- [ ] `dsregcmd /status` shows `AzureAdJoined : YES`.
- [ ] Reboot **twice**; the clock is correct both times.
- [ ] `verify.ps1 -WithSideRepos -WithAndroid` reports parity with DESKTOP1, 0 FAIL.
- [ ] `D:` exists, is NTFS, and the gradle/Android/Playwright caches live on it.

**The network**

- [ ] The Hetzner firewall shows **zero** inbound rules
      (`hcloud firewall describe grotap-cloud-desktop`, or the console).
- [ ] From a machine **not** on the tailnet: `Test-NetConnection <public-ip> -Port 3389` **fails**.
- [ ] From a machine on the tailnet: RDP to `grotap-cloud-01` succeeds.
- [ ] `tailscale status` on the cloud box lists both subnet routes as available.
- [ ] RDP latency measured from Portland — expect single-digit milliseconds to `hil`.

**The LAN, over Tailscale** (this is what proves `--accept-routes` and DESKTOP1's advertised
routes are both working)

- [ ] Print a real label on the Toshiba B-EX6T1 at `192.168.25.x:9100`.
- [ ] Open an LLRP session to the CS463 on `:5084` and read a tag — a real persistent session,
      which is the thing Print Cloud structurally cannot do.
- [ ] Reach a tablet on `192.168.25.0/24`.
- [ ] Load a frame from the Wyze camera on the house subnet.

**The work**

- [ ] `doppler run -p grotap -c prd -- python scripts/db.py "select 1 as ok"` against Neon.
- [ ] `ssh agent-02` with the restored fleet key.
- [ ] One **real** dispatch plus a `/codex` review, end to end. Not a smoke test.
- [ ] A restore drill recorded as passed: what was restored, and how long it took.

**The backup of this box**

- [ ] `kopia snapshot list` shows a snapshot of `cloud-01` at both destinations.
- [ ] A snapshot of the clean install exists in Hetzner images (step 8).

Only when all of that is green does DESKTOP1 get demoted to a relay — and even then it keeps
running, keeps getting backed up, and keeps `GrotapPrintCloud`, the Wyze bridge and the subnet
router. It is a warm fallback, not a corpse.

---

## 12. Troubleshooting

**Windows Setup shows no disks to install to.**
The virtio storage driver is not loaded. This is the single most common failure in this build and
the error message never mentions virtio. Load driver → the virtio CD → `viostor\w11\amd64` (or
`w10\amd64`). If the CD is not visible at all in the browse dialog, you did not attach the second
`-drive ... media=cdrom` — check the QEMU line.

**"This PC can't run Windows 11."**
No TPM and no Secure Boot on a Hetzner VM. Shift+F10 → regedit → `HKLM\SYSTEM\Setup\LabConfig` with
`BypassTPMCheck`, `BypassSecureBootCheck`, `BypassRAMCheck`, `BypassCPUCheck` all DWORD `1`.
See step 4.5.

**QEMU: "Could not access KVM kernel module: No such file or directory".**
Expected. Hetzner Cloud does not offer nested virtualization. Drop `-enable-kvm` and `-cpu host`
and run in TCG emulation — slow, but it works, and it is why step 8 matters so much.

**First native boot bugchecks `0x7B INACCESSIBLE_BOOT_DEVICE`, or hangs at a blinking cursor.**
Two candidates. Either the boot-critical storage driver for the flavour of virtio Hetzner presents
natively is not installed — go back into rescue, boot the QEMU VM again against `/dev/sda`, and
install the **complete** virtio guest tools (step 4.6), which lays down `viostor` and `vioscsi`
together. Or the firmware mode is wrong: you installed under SeaBIOS and Hetzner boots UEFI, or the
reverse. Re-run the `/sys/firmware/efi` check from step 4.3 and match it.

**The clock is wrong after a reboot, and TLS calls start failing.**
`RealTimeIsUniversal` is missing or was not applied. Re-apply step 5, confirm the value is a
**DWORD** (a string does nothing and looks identical in a screenshot), then reboot twice and check
both times.

**`winver` still says Windows 11 Pro after the Entra join.**
Subscription Activation has not fired, and until it does the VM is not licensed for a third-party
host. Check in order: the signed-in account actually holds an M365 **Business Premium** licence
(Business Standard does **not** include Windows Enterprise); `dsregcmd /status` really says
`AzureAdJoined : YES`; the device has internet and the clock is right (a wrong clock breaks the
token exchange — see the previous item); the activation service has been given time and a reboot,
because it is not instant. Then `slmgr /dlv` and Settings → System → Activation for the actual
error text. Do not carry on building on an unlicensed box.

**Everything on the tailnet works, but `192.168.25.x` is unreachable.**
Almost always one of two things, and they look identical from here:

- The routes are advertised but **not approved**. Advertised routes are inert until someone enables
  them in the Tailscale admin console. They *are* enabled for DESKTOP1 today — check that they still
  are, in Machines → `desktop1` → Subnet routes.
- This box was brought up without **`--accept-routes`**. Fix with
  `tailscale up --accept-routes --unattended` (re-running `tailscale up` is safe; flags you omit
  revert to their defaults, so pass the whole set from step 6).

Then confirm DESKTOP1 is actually up, still has `IPEnableRouter=1`, and that its own Windows
firewall is not dropping the forwarded traffic.

**RDP feels laggy and `tailscale status` shows the connection as `relay`.**
Traffic is going through a DERP relay instead of direct, because nothing inbound is permitted for
NAT hole-punching. Usually it still recovers to direct via the stateful firewall's return path. If
it does not, the one defensible exception to the zero-inbound-rules design is a single rule
allowing **UDP 41641** — that is Tailscale's own port and it exposes no service. That is an owner
decision, not a default; do not open anything else.

**You rebooted natively before doing step 4.6 and now there is no way in.**
Use the Hetzner Cloud web console (`hcloud server request-console <name>`, or the Console button in
the UI). It is an awkward VNC and pasting is unpleasant, but it is a real screen and keyboard on the
machine, and it is enough to install Tailscale by hand.

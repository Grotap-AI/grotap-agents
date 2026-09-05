# Roof laptop — build runbook

A field laptop that performs like `DESKTOP1`, for the owner only. Captured from the desktop on
**2026-09-04**. Read this instead of `README.md` if you are building *this* machine; `README.md`
is the general new-PC path and `../../NEW-PC-SETUP.md` is the prose inventory of why each tool
is there.

**Hands-on: ~15 minutes of typing. Waiting: ~60 minutes** (the Android SDK is most of it).

What makes this build different from the plain new-PC path:

| | Roof laptop | Why |
|---|---|---|
| Side folders | **included** (`2Claude`, `7ClaudeMarketingAgents`, `8Claude`) | owner's own second machine, so all four secret boundaries come along |
| Android/Expo SDK | **included** | Scan M APK builds in the field; EAS quota stops mattering |
| Docker Desktop | **excluded** | WSL2 + ~4 GB + an always-on VM, for nothing the field work needs |
| TagMatiks / RFID | **excluded** | being removed from the desktop too — scanning happens on Scan M, not here |
| Snagit, Microsoft 365 | **excluded from the script** | paid licences; install them yourself if you want them |

---

## Stage 0 — Windows first-run (the Microsoft-account screen)

The desktop runs a **local account** (`DESKTOP1\aallison`), not a Microsoft account. Match it:
memory project slugs and every absolute path in the MD files are keyed to `C:\...` paths, and a
Microsoft account also drags OneDrive redirection into `Documents`, which the platform rules
explicitly forbid.

Windows 11 **Home** hides the local-account option, so force it:

1. At **"Sign in to your Microsoft account"**, press **Shift + F10**. A command prompt opens.
2. Type `start ms-cxh:localonly` and press Enter.
3. A **"Who's going to use this device?"** dialog appears. Use the username **`aallison`** — same
   as the desktop, which keeps `C:\Users\aallison\...` identical on both machines and means the
   statusline path and every runbook command copy across verbatim.
4. Set a password and the three security questions. Close the command prompt (`exit`).

If `ms-cxh:localonly` does nothing on that build, the older trick is `oobe\bypassnro`, Enter,
let the PC reboot, then choose **"I don't have internet"** → **"Continue with limited setup"**.
Microsoft removed that path from newer Home builds, which is why `ms-cxh:localonly` is first.

### Before you leave this screen behind — laptop-only settings

This machine leaves the building carrying live credentials (Doppler token, `gh` OAuth, the Codex
API key, Claude session) **and** the `2Claude` corporate/legal repo. Treat it accordingly.

```powershell
# Lock quickly when it is closed and unattended on a roof.
powercfg /change monitor-timeout-ac 15
powercfg /change monitor-timeout-dc 5
powercfg /change standby-timeout-dc 15
#    Do NOT let it sleep on AC during a long build -- an interrupted sdkmanager or
#    pip install leaves a half-installed toolchain that looks fine until it fails.
powercfg /change standby-timeout-ac 0
```

Also turn on **Settings > Accounts > Sign-in options > Windows Hello** and
**Settings > Privacy & security > Find my device**.

---

## Stage 1 — five commands (manual)

Open **PowerShell** (the prompt reads `PS C:\`). Not CMD.

```powershell
# Claude Code -- NATIVE installer, the same method as the desktop (not npm).
irm https://claude.ai/install.ps1 | iex

winget install --id Git.Git --exact --source winget --silent --accept-package-agreements
winget install --id GitHub.cli --exact --source winget --silent --accept-package-agreements
```

Now **open a new terminal** — the PATH changed and this shell cannot see it. Then:

```powershell
gh auth login          # HTTPS, browser
gh repo clone Grotap-AI/grotap-agents C:\1Claude
```

> `C:\1Claude` is not a preference. Every MD file, hook, and memory project slug is keyed to that
> absolute path (`C:\1Claude\platform` → `C--1Claude-platform`). Clone anywhere else and the
> restored memory loads nowhere, silently.

Do `gh auth login` **before** the first Claude session: `.claude-session-init.sh` is `set -e` and
its first real step is `git fetch origin master`, so on an unauthenticated box it exits before it
ever validates the MD structure — and a stale-rules seat looks just like a bootstrap that failed
early.

---

## Stage 2 — one command does the rest

```powershell
cd C:\1Claude
powershell -ExecutionPolicy Bypass -File scripts\newpc\setup.ps1 -WithSideRepos -WithAndroid -GitName "Grotap1" -GitEmail "info@grotap.com"
```

Idempotent — re-run it as often as you like; it skips whatever is already there. Run it from an
**elevated** PowerShell if winget complains it cannot install machine-wide.

It does eight phases: system packages and workstation apps (winget) → global npm → Playwright
browsers → the 114-package Python freeze → repos (all four folders, thanks to `-WithSideRepos`) →
user-level Claude config, the `gh` git credential helper, the `neon-postgres` skill and the
`chrome-devtools` MCP server → plugins (codex, code-simplifier, ui-ux-pro-max, caveman) →
the Android SDK (`-WithAndroid`).

`-SkipApps` drops Chrome/Bitwarden/Drive/ShareX/terraform/gcloud/Chrome Remote Desktop and
installs the toolchain only. Other switches: `-SkipWinget`, `-SkipPython`, `-SkipPlaywright`.

---

## Stage 3 — restore Claude's memory

465 files across 9 projects, ~1 MB. Not in git, not reinstallable, and the machine is amnesiac
without it. Export was already taken on the desktop:

```
C:\Users\aallison\Desktop\claude-memory-export-20260904-073957.zip
```

Carry it over on a USB stick or Google Drive, then:

```powershell
powershell -ExecutionPolicy Bypass -File C:\1Claude\scripts\newpc\memory-migrate.ps1 -Import -Zip <path-to-zip>
```

Merges in; deletes nothing; any project that already has memory is copied to
`memory.backup-<timestamp>` first. Loads at the next session start.

To take a fresher export from the desktop later: `memory-migrate.ps1 -Export` (timestamped, never
clobbers a previous one).

---

## Stage 4 — logins (only you can do these)

```powershell
claude                 # then /login  -- Claude subscription OAuth
gh auth login          # done in stage 1
doppler login
cd C:\1Claude\platform ; doppler setup -p grotap -c dev
codex login            # OpenAI -- powers the /codex:* pre-commit review gate
railway login
vercel login
```

**Codex is a separate credential store and cannot live in Doppler.** `codex-cli` keeps auth in
`~/.codex/auth.json`. Since this is your own second machine you can copy that file across from the
desktop (USB / password manager, **not** chat and **not** a repo), or run `codex login`. If you
prefer the key path instead:

```powershell
doppler secrets get OPENAI_API_KEY --plain | codex login --with-api-key
```

Note the npm `codex.ps1` shim re-splits its arguments under PowerShell 5.1 —
`codex exec 'Reply with one word'` dies with `unexpected argument 'with' found`. Use a
single-token prompt or a file when driving codex non-interactively.

**Fleet SSH key**: copy `~/.ssh/grotap_agents`, `grotap_agents.pub` and `config` from the desktop
over a secure channel — password manager or USB, never chat or a repo. Then `chmod 600` the
private key and confirm with `ssh agent-02`.

**Secrets rule is unchanged**: everything lives in Doppler (`grotap` project, `dev`/`prd`). No
hand-set env vars, and the only GitHub secret anywhere is `DOPPLER_SERVICE_TOKEN`.

---

## Stage 5 — prove it

```powershell
powershell -ExecutionPolicy Bypass -File C:\1Claude\scripts\newpc\verify.ps1 -WithSideRepos -WithAndroid
```

Read-only; installs nothing and logs in to nothing. It checks the toolchain against the desktop's
versions, all four repo folders, the Claude config (including that the statusline's absolute path
actually resolves and the model is `opus[1m]`), the `neon-postgres` skill, the `chrome-devtools`
MCP server, Playwright browsers, all four plugins, the restored memory file counts per project,
every login, and finally a real `doppler run -- python scripts/db.py "select 1"` against Neon.

It also fails the build if any repo's remote URL has a token baked into it — a PAT in a remote is
a plaintext credential in `.git/config` that leaks on every `git remote -v`.

**The desktop's own baseline on 2026-09-04 was `53 ok, 3 warn, 2 FAIL`**, and both FAILs were real
problems the verifier found and that were then fixed (a PAT embedded in the `2Claude` remote, and
`ANDROID_HOME` never persisted). Aim for **0 FAIL** on the laptop. `railway`/`vercel` show as warn
until you log in.

### Last checks, inside a session

Run `claude` in `C:\1Claude\platform` and confirm:

- the SessionStart banner prints `[bootstrap] repo: <sha> on master`
- the statusline reads `Opus 5 | ctx N% [....] ~Nk/1000k`
- `/mcp` shows `docs-langchain` and `playwright` connected
- `/plugin` shows codex + code-simplifier + caveman enabled
- replies come back caveman-compressed — that proves the caveman SessionStart hook fired
- ask it *"what do you remember about the folder map"* — it should answer from restored memory,
  naming `1Claude` as platform HQ and `8Claude` as back-office

Then one real end-to-end task, because a green checklist is not the same as working:

```powershell
cd C:\1Claude\platform
doppler run -p grotap -c prd -- python scripts/db.py "select 1 as ok"   # Doppler + Neon
npx playwright --version                                                # browsers present
adb version                                                             # Android SDK on PATH
```

---

## Known gotchas on a fresh box

- **A shell that was already open before an install cannot see the new PATH.** A tab in a
  Windows Terminal or VS Code that was running before winget inherits the parent process's
  environment, not the registry — so every tool reports MISSING although it is installed. Closing
  the tab does not help; quit the host app or reboot. Both scripts re-read PATH from the registry
  on entry for exactly this reason.
- **`rg` is not installed and must not be.** Claude Code bundles ripgrep and puts it on the Bash
  tool's PATH only. A plain PowerShell prompt has no `rg`; that is correct, do not "fix" it.
- **Never rebuild Python from `backend/requirements.txt`** — those are deploy pins and this dev
  box is deliberately above several of them. Use `python-requirements.txt`.
- **Pasting a multi-line PowerShell script into an interactive console is unreliable.** A blocking
  first line leaves everything behind it queued in the buffer looking frozen, and any `{ }` block
  parks the console at the `>>` continuation prompt. Ship a `.ps1` and use
  `-ExecutionPolicy Bypass -File`, or use strictly single-line commands.
- **`caveman@caveman` used to fail to install** on CLI 2.1.236 with
  `Validation errors: agents: Invalid input`, which needed a hand-placed pinned cache directory.
  Re-tested 2026-09-04 on CLI 2.1.260: upstream HEAD dropped the offending key and a plain
  `claude plugin install` works. The desktop is still pinned at `a0109974` (543 commits behind);
  the laptop will be on HEAD. Both emit the same `level: full` ruleset.
- **The git credential helper cannot be set with `git config` from PowerShell 5.1** — the embedded
  quotes get re-split and git reports `wrong number of arguments, should be 2`. `setup.ps1` runs
  `gh auth setup-git` instead, and falls back to writing an escaped block into `~/.gitconfig`.

---

## What is deliberately NOT on this machine

Docker Desktop, TagMatiks AT Lite / RFID reader drivers, Snagit (paid — ShareX covers it),
Microsoft 365 (paid), the NVIDIA desktop-GPU stack, Stardock Fences, Inno Setup (only needed to
cut a Print Cloud Agent installer, which is desktop release work), and Splashtop. Chrome Remote
Desktop **is** installed, so the desktop is reachable from the field if something turns out to
need it.

Not copied from the desktop either: `~/.claude/.credentials.json`, `history.jsonl`, `sessions/`,
`shell-snapshots/`, `cache/`, and every `settings.local.json`. Machine-local state and auth —
log in fresh instead. The memory export is the exception, because it is project knowledge with no
credentials in it.

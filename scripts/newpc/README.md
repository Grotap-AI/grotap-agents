# New PC — runbook

Rebuild this exact Claude Code workstation on a fresh Windows 11 box.
Captured from the working machine on **2026-07-29**. Everything except the logins is automated.

**Total hands-on time: ~10 minutes of typing, ~40 minutes of waiting.**

---

## Before you leave the OLD PC — one thing only

Claude's accumulated memory (373 files for the platform project alone: every lesson, every
"don't re-do this") is not in git and cannot be reinstalled. Export it:

```powershell
powershell -ExecutionPolicy Bypass -File C:\1Claude\scripts\newpc\memory-migrate.ps1 -Export
```

Writes `claude-memory-export-<timestamp>.zip` to your Desktop (timestamped — it never clobbers an
earlier export). Put it on OneDrive or a USB stick.
Also grab `C:\Users\<you>\.ssh\grotap_agents`, `grotap_agents.pub` and `config` — the fleet SSH key.
Password manager or USB, **never** chat or a repo.

---

## Stage 0 — on the NEW PC (manual, 5 commands)

Open **PowerShell** (not CMD — the prompt shows `PS C:\`). No Administrator needed for step 1.

```powershell
# 1. Claude Code (native installer, same method as the source box)
irm https://claude.ai/install.ps1 | iex

# 2. Git + GitHub CLI  (Git for Windows is what gives Claude Code its Bash tool)
winget install --id Git.Git --exact --silent --accept-package-agreements
winget install --id GitHub.cli --exact --silent --accept-package-agreements

# 3. NEW terminal (PATH changed), then authenticate to GitHub
gh auth login

# 4. Clone the agent brain to the exact path everything else assumes
gh repo clone Grotap-AI/grotap-agents C:\1Claude
```

> **`C:\1Claude` is not a preference.** Every MD file, hook and memory-project slug is keyed to
> that absolute path. Clone anywhere else and the restored memory will not load.

## Stage 1 — one command does the rest

```powershell
cd C:\1Claude
powershell -ExecutionPolicy Bypass -File scripts\newpc\setup.ps1
```

Run it from an **elevated** PowerShell if winget complains it cannot install machine-wide.
Idempotent — re-run it as often as you like; it skips whatever is already there.

It performs eight phases:

| # | Phase | What lands |
|---|---|---|
| 1 | System packages (winget) | Node LTS, Python **3.12** (not 3.13/3.14), Doppler, ffmpeg, OpenJDK 17 |
| 2 | Global npm | codex 0.118.0, railway 4.30.5, vercel 50.25.6, eas-cli 18.1.0, playwright-cli, uipro-cli |
| 3 | Playwright browsers | chromium/firefox/webkit — every screenshot + E2E task needs these |
| 4 | Python | exact 113-package freeze of the working box (`python-requirements.txt`) |
| 5 | Repos | `grotap-platform` → `C:\1Claude\platform`, `grotap-landing` |
| 6 | Claude config | `~/.claude/settings.json` + `statusline.js` (backs up anything already there) |
| 7 | Plugins | marketplaces registered; codex + code-simplifier at project scope, ui-ux-pro-max at user scope (disabled) |
| 8 | Android | **skipped unless `-WithAndroid`** — see below |

Useful switches: `-SkipWinget`, `-SkipPython`, `-SkipPlaywright`, `-WithAndroid`, `-Root <path>`,
`-GitName` / `-GitEmail`.

### Standing this up for someone else

This script is also how a *second person* gets a working box. In that case the machine must use
**their own** credentials throughout — pass their commit identity:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\newpc\setup.ps1 -GitName "Their Name" -GitEmail "them@example.com"
```

Without `-GitName`/`-GitEmail` the script sets no identity and warns, rather than defaulting to
someone else's — silently misattributing commits is worse than a clear error.

**Never copy to another person's machine**: `~/.ssh/grotap_agents` (fleet private key — generate them
their own keypair and add the public half to `authorized_keys`), `~/.codex/auth.json` (a live OpenAI
API key), or `~/.claude/.credentials.json`. Each person authenticates their own GitHub, Claude,
Doppler, OpenAI, Railway and Vercel accounts. The memory export is the exception — it is project
knowledge with no credentials in it, so sharing it is what makes their box useful on day one.

## Stage 2 — restore memory

```powershell
powershell -ExecutionPolicy Bypass -File C:\1Claude\scripts\newpc\memory-migrate.ps1 -Import -Zip <path-to-zip>
```

Merges into `~/.claude/projects/*/memory/`. Nothing already on the new PC is deleted, and any
project that already has memory is copied to `memory.backup-<timestamp>` first, so an overwrite is
always recoverable. Loads at the next session start.

## Stage 3 — logins (only you can do these)

```powershell
claude                 # then /login  -- Pro/Max subscription
gh auth login          # already done in stage 0
doppler login
cd C:\1Claude\platform ; doppler setup -p grotap -c dev
codex login            # OpenAI -- powers the /codex:* pre-commit review gate
railway login
vercel login
```

Then drop the SSH key into `C:\Users\<you>\.ssh\` and confirm with `ssh agent-02`.

**Secrets rule is unchanged**: everything lives in Doppler (`grotap` project, `dev`/`prd`).
No hand-set env vars. The only GitHub secret anywhere is `DOPPLER_SERVICE_TOKEN`.

## Stage 4 — verify

```powershell
powershell -ExecutionPolicy Bypass -File C:\1Claude\scripts\newpc\verify.ps1
```

Read-only. Checks every tool version against the reference, all three repos, both config files,
the checked-in hooks/agents, Playwright browsers, plugins, login state, and finally a real
`doppler run -- python scripts/db.py "select 1"` against Neon.

Last check is inside a session — run `claude` in `C:\1Claude\platform` and confirm:
- SessionStart banner prints `[bootstrap] repo: <sha> on master`
- statusline reads `Opus 5 | ctx N% [....] ~Nk/200k`
- `/mcp` shows `docs-langchain` and `playwright` connected
- `/plugin` shows codex + code-simplifier enabled

---

## What arrives free with the clone (do not copy these by hand)

- `.mcp.json` — docs-langchain (HTTP) + playwright (`npx -y @playwright/mcp@latest`)
- `.claude/settings.json` in **both** repos — SessionStart hook, permission allowlist, `enableAllProjectMcpServers`
- `scripts/claudecode/session-start-hook.sh`, `.claude-session-init.sh`, `BOOTSTRAP.md`, `agents/GLOBAL.md`
- `platform/.claude/agents/screenshot-verifier.md` and `platform/.claude/skills/ui-ux-pro-max/`

Gmail / Google Calendar / Google Drive MCP connectors are **claude.ai account-side** — they follow
your login, there is nothing to install.

## What is deliberately NOT copied

`~/.claude/.credentials.json`, `history.jsonl`, `sessions/`, `shell-snapshots/`, `cache/`,
`telemetry/`, and every `settings.local.json`. Machine-local state and auth — re-login instead.

## Android build toolchain (optional)

Only needed to build the Scan M APK locally (this is what makes EAS quota a non-issue: cold build
~15 min, incremental ~50 s). `C:\1Claude\androidtools\` is ~1 GB and is **not** in git.

```powershell
powershell -ExecutionPolicy Bypass -File scripts\newpc\setup.ps1 -WithAndroid -SkipWinget -SkipPython -SkipPlaywright
```

Installs cmdline-tools + `platform-tools`, `platforms;android-35`, `build-tools;35.0.0` and
`34.0.0`, `ndk;26.1.10909125`, `cmake;3.22.1` — the exact set on the source box — and sets
`ANDROID_HOME`. Faster alternative: zip `androidtools\` from the old PC, it is fully relocatable.

⚠ `platform/android/` is gitignored — build.gradle edits die at the next prebuild. Use a config
plugin (which needs a compiled `.js` beside the `.ts`).

---

## Files here

| File | Purpose |
|---|---|
| `setup.ps1` | the installer — stage 1 |
| `verify.ps1` | read-only parity check — stage 4 |
| `memory-migrate.ps1` | `-Export` on the old PC, `-Import` on the new one |
| `python-requirements.txt` | exact 113-package freeze |
| `claude-user/settings.json` | `~/.claude/settings.json` template (`__CLAUDE_HOME__` is substituted) |
| `claude-user/statusline.js` | context-budget statusline |

A prose inventory of the source machine — every version, why each tool is there — is in
[`../../NEW-PC-SETUP.md`](../../NEW-PC-SETUP.md).

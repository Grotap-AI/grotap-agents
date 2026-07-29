# New PC Setup — replicate this Claude Code environment

> **You probably want the automated path instead: [`scripts/newpc/README.md`](scripts/newpc/README.md).**
> Five commands on the new PC, then one script does everything below.
> This file is the prose inventory — what is installed here and *why* — kept for when you need to
> understand or audit the setup rather than reproduce it.

Captured from `AALLISON` on 2026-07-29. Windows 11, shell = **Git Bash** (MINGW64) + PowerShell 5.1.
Versions below are what is running here; pin to these unless you have a reason to move.

---

## 1. System prerequisites (install first, in this order)

| # | Software | Version here | How |
|---|---|---|---|
| 1 | **Git for Windows** (gives you Git Bash — the shell Claude Code uses) | 2.53.0 | https://git-scm.com/download/win |
| 2 | **Node.js LTS** (to `C:\Program Files\nodejs`) | v24.14.0 | https://nodejs.org — installer, tick "Add to PATH" |
| 3 | **Python 3.12** (per-user, to `%LOCALAPPDATA%\Programs\Python\Python312`) | 3.12.10 | https://python.org — tick "Add python.exe to PATH". **Do not use 3.13/3.14** (native deps) |
| 4 | **GitHub CLI** | 2.87.3 | `winget install GitHub.cli` |
| 5 | **Doppler CLI** | 3.75.3 | `winget install doppler.doppler` (or scoop) |
| 6 | **ffmpeg** (marketing/video work) | 8.1 gyan build | `winget install Gyan.FFmpeg` |
| 7 | **Microsoft OpenJDK 17** | 17.0.20 | `winget install Microsoft.OpenJDK.17` — sets `JAVA_HOME` |

**ripgrep**: do *not* install it. Claude Code ships its own and puts it on the Bash tool's PATH;
there is no standalone `rg` on this box (it is absent from a plain PowerShell prompt).

Not installed here and not needed: psql, docker, pnpm/yarn/bun, uv, poetry, make/gcc.
(SQL is run through `scripts/db.py`, never psql — see `platform/CLAUDE.md`.)

---

## 2. Claude Code + global npm packages

```bash
npm i -g @anthropic-ai/claude-code   # 2.1.220 here (auto-updates, channel "latest")
npm i -g @openai/codex@0.118.0       # Codex CLI — required by the /codex:* review gate
npm i -g @railway/cli@4.30.5
npm i -g vercel@50.25.6
npm i -g eas-cli@18.1.0              # Expo builds (Scan M / ScanTap mobile)
npm i -g @playwright/cli@0.1.1
npm i -g uipro-cli@2.2.3             # ui-ux-pro-max skill helper
```

Playwright browser binaries (Chromium/Firefox/WebKit + ffmpeg shim) — needed for every
screenshot/E2E task:

```bash
npx playwright install
```

---

## 3. Python packages

An exact freeze of this environment — 113 pinned packages — is committed at
`scripts/newpc/python-requirements.txt`:

```bash
python -m pip install -r C:\1Claude\scripts\newpc\python-requirements.txt
```

Use the freeze, not the backend requirements files. `backend/requirements.txt` holds the
**deploy** pins and this dev box has drifted above several of them on purpose (e.g. it pins
`anthropic==0.40.0`; 0.116.0 is what runs here). Installing the backend file alone would
downgrade you and would also miss everything the `scripts/` tooling needs — report generation
(pdfplumber, reportlab, pypdf), device work (pyserial), packaging (pyinstaller, pywin32),
Google APIs, paramiko, opencv-headless.

Key pins in use: `asyncpg 0.29.0`, `fastapi 0.115.0`, `SQLAlchemy 2.0.35`, `anthropic 0.116.0`,
`workos 5.0.0`, `stripe 11.4.1`, `pytest 9.1.1`, `pytest-asyncio 1.4.0`, `numpy 2.5.1`.

---

## 4. Repos to clone

Clone into `C:\1Claude\` so every absolute path in the MD files resolves:

```bash
mkdir -p /c/1Claude && cd /c/1Claude
git clone https://github.com/Grotap-AI/grotap-agents.git .          # agent brain — IS C:\1Claude
git clone https://github.com/Grotap-AI/grotap-platform.git platform  # application code
git clone https://github.com/Grotap-AI/grotap-landing.git            # marketing site
```

`C:\1Claude\docs\` ships inside grotap-agents. `androidtools\` does **not** — see §8.

---

## 5. Claude Code user-level config — copy these files

From `C:\Users\<you>\.claude\` on this machine:

| File | Why |
|---|---|
| `settings.json` | model=opus, light theme, fullscreen TUI, bell-on-notification hook, statusline, marketplaces |
| `statusline.js` | context-budget statusline (`model \| ctx 42% [####......] ~84k/200k`) |

**Do copy**: `projects/*/memory/` — Claude's auto-memory. 373 files / 2.2 MB for
`C--1Claude-platform` alone, plus 8 other project dirs. Not in git, not reinstallable, and a new PC
is amnesiac without it. Use `scripts/newpc/memory-migrate.ps1 -Export` / `-Import`. The project slug
is derived from the project path (`C:\1Claude\platform` → `C--1Claude-platform`), which is the other
reason the clone path must be exactly `C:\1Claude`.

**Do not copy**: `.credentials.json`, `history.jsonl`, the rest of `projects/`, `sessions/`,
`shell-snapshots/`, `cache/`, `telemetry/` — machine-local state and auth. Log in fresh instead (§7).

`~/.claude/settings.json` contents to reproduce:

```json
{
  "model": "opus",
  "theme": "light",
  "tui": "fullscreen",
  "autoUpdatesChannel": "latest",
  "skipDangerousModePermissionPrompt": true,
  "voiceEnabled": true,
  "hooks": {
    "Notification": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "printf '\\a'" }] }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "node \"C:\\Users\\<you>\\.claude\\statusline.js\""
  },
  "extraKnownMarketplaces": {
    "openai-codex":        { "source": { "source": "github", "repo": "openai/codex-plugin-cc" } },
    "ui-ux-pro-max-skill": { "source": { "source": "github", "repo": "nextlevelbuilder/ui-ux-pro-max-skill" } }
  },
  "enabledPlugins": { "ui-ux-pro-max@ui-ux-pro-max-skill": false }
}
```

⚠ Fix the statusline path to the new username, and note `~/.claude/skills/neon-postgres` — the
Neon skill is user-scoped here; re-add it on the new box (`/plugin` or copy the folder).

---

## 6. Plugins, MCP servers, project settings

**Plugins** (install from inside Claude Code with `/plugin`, once the marketplaces above exist):

| Plugin | Version | Scope |
|---|---|---|
| `codex@openai-codex` | 1.0.2 | project → `C:\1Claude\platform` |
| `code-simplifier@claude-plugins-official` | 1.0.0 | project → `C:\1Claude\platform` |
| `ui-ux-pro-max@ui-ux-pro-max-skill` | 2.5.0 | user (installed, **disabled** at user level; the platform repo carries its own copy in `platform/.claude/skills/ui-ux-pro-max`) |

**MCP servers** — checked into `C:\1Claude\.mcp.json`, so they arrive with the clone. Nothing to
install; `playwright` pulls itself via `npx -y @playwright/mcp@latest` on first use:

```json
{ "mcpServers": {
    "docs-langchain": { "type": "http",  "url": "https://docs.langchain.com/mcp" },
    "playwright":     { "type": "stdio", "command": "npx", "args": ["-y", "@playwright/mcp@latest"] } } }
```

Gmail / Google Calendar / Google Drive MCP connectors are **claude.ai account-side**, not local —
they follow the login, nothing to install.

**Project settings** are checked in and need no copying: `C:\1Claude\.claude\settings.json`
(SessionStart hook → `scripts/claudecode/session-start-hook.sh`, `enableAllProjectMcpServers`) and
`C:\1Claude\platform\.claude\settings.json` (Bash/Read/Edit/Write permission allowlist, same hook).
`settings.local.json` files are per-machine — leave them behind.

Also checked in and arriving free: the `screenshot-verifier` agent
(`platform/.claude/agents/`), `.claude-session-init.sh`, `BOOTSTRAP.md`, `agents/GLOBAL.md`.

---

## 7. Authentication — the manual steps (run these yourself, interactively)

Nothing here can be copied from this PC; all of it is per-machine credential state.

```bash
claude                      # then /login — Claude subscription OAuth
gh auth login               # GitHub, HTTPS, browser
doppler login               # then: doppler setup -p grotap -c dev   (in C:\1Claude\platform)
codex login                 # OpenAI, for the /codex:* review gate
railway login
vercel login
```

**SSH to the agent fleet**: copy `~/.ssh/grotap_agents` + `.pub` + `~/.ssh/config` from a secure
channel (password manager / USB), **not** through chat or a repo. `chmod 600` the private key.
Test with `ssh agent-02` once `SERVERS.md` roster is in place.

Secrets rule stands: everything lives in Doppler (`grotap` project, `dev`/`prd`). Never set an env
var by hand, never put a secret in a GitHub secret except `DOPPLER_SERVICE_TOKEN`.

---

## 8. Optional — Android/Expo local build toolchain

Only needed if you build the Scan M APK locally (this is what makes EAS quota a non-blocker).
`C:\1Claude\androidtools\` is ~1 GB and is **not** in git — recreate it, no admin rights required:

- `androidtools\jdk` — JDK 17 (304 MB)
- `androidtools\sdk` — `cmdline-tools`, `platform-tools`, `platforms`, `build-tools`, `ndk`, `cmake`, `licenses`

Fastest path: install Android command-line tools into that folder, set `ANDROID_HOME` to
`C:\1Claude\androidtools\sdk`, then `sdkmanager --licenses`. Cold build ≈ 15 min, incremental ≈ 50 s.
(Or just zip `androidtools\` from this PC and copy it — it is fully relocatable.)

---

## 9. Verification checklist

```bash
cd /c/1Claude && ./.claude-session-init.sh     # must print commit + validate MD structure
cd /c/1Claude/platform
doppler run -p grotap -c prd -- python scripts/db.py "select 1"   # Doppler + Neon reachable
npx playwright --version                                          # browsers installed
codex --version                                                   # review gate ready
gh auth status && railway whoami && vercel whoami
claude                                                            # statusline shows "ctx N% [...]"
```

Inside Claude Code, confirm: `/plugin` lists codex + code-simplifier enabled; `/mcp` shows
`docs-langchain` and `playwright` connected; the SessionStart hook banner prints
`[bootstrap] repo: <sha> on master`.

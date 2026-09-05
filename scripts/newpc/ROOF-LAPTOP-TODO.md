# Roof laptop (`grotapinfoAA2`) — outstanding setup work

Audit run from `DESKTOP1` over SSH on **2026-09-04 (session 3)**. `verify.ps1 -WithSideRepos
-WithAndroid` reports **48 ok, 10 warn, 0 FAIL**; the list below is what the verifier cannot see plus
the warns that are real.

Two of the verifier's warns are false negatives caused by running it over SSH, not defects — see
"Known SSH artefacts" at the bottom before chasing them.

## Proven working (do not re-do)

Toolchain (git/node/npm/python/java/gh/doppler/ffmpeg/terraform/gcloud/claude/codex/railway/vercel/eas
binaries), all six repos incl. the three side folders with token-free remotes, Android SDK +
`ANDROID_HOME`, Claude config (`opus[1m]`, statusline, Git Bash pin, SessionStart hook), all four
plugins, the `neon-postgres` skill, the `chrome-devtools` MCP server, Playwright chromium, restored
memory (433 files in `C--1Claude-platform`, 5/8/9/4 elsewhere), Google Drive signed in with `G:`
mounted, ShareX, Wispr Flow, Fences.

Two end-to-end proofs that a checklist cannot give you:

- `claude -p 'Reply with exactly: LAPTOP-OK'` in `C:\1Claude\platform` returned `LAPTOP-OK` — the
  Claude subscription login, the model id and the print-mode path all work.
- `ssh -i ~/.ssh/grotap_agents root@5.161.74.39 hostname` returned `grotap-agent-02` in 1.5 s — the
  copied fleet key and its ACL are good.

## To do

### 1. Logins (only the owner, at the machine)

- [ ] **`gh auth login`** — the stored token is **invalid**: `gh auth status` says
      `The token in default is invalid.` Git itself still works (Git Credential Manager holds separate
      credentials, `git fetch` succeeds), so this is silent until a `gh` command is run.
- [ ] **`codex login`** — `~/.codex/auth.json` is absent, so the `/codex:*` pre-commit review gate
      cannot run on this machine. Either copy `auth.json` from the desktop over USB / password manager,
      or `doppler secrets get OPENAI_API_KEY --plain | codex login --with-api-key` once Doppler is
      confirmed.
- [ ] **`railway login`** — `railway whoami` → `Unauthorized`.
- [ ] **`vercel login`** — `vercel whoami` → `No existing credentials found` (the `auth.json` file
      exists but carries no token).
- [ ] **Confirm Doppler in an interactive session** — `doppler run -p grotap -c prd -- python
      scripts/db.py "select 1 as ok"` from `C:\1Claude\platform`. It cannot be verified over SSH (see
      below). `.doppler.yaml` scopes are already set (`C:\1Claude\platform` → `grotap`/`prd`).

### 2. Missing app

- [x] **Chrome Remote Desktop** — INSTALLED 2026-09-05 over SSH. The package id in the first version
      of this list was wrong: `Google.ChromeRemoteDesktop` returns `No package found matching input
      criteria`. The real id is **`Google.ChromeRemoteDesktopHost`**:

      winget install --id Google.ChromeRemoteDesktopHost --exact --source winget --silent `
        --accept-source-agreements --accept-package-agreements --disable-interactivity

      Every winget call driven over SSH needs those three flags or it hangs forever.
      Still owner-only: pair the host at https://remotedesktop.google.com/ while signed in.

### 3. PowerShell execution policy blocks the npm shims

- [x] DONE 2026-09-05 — `CurrentUser` now reads `RemoteSigned`. Original finding kept for context:
      `Get-ExecutionPolicy -List` showed `CurrentUser` and `LocalMachine` **Undefined**, i.e. the
      client default `Restricted`. Nothing that is a `.ps1` runs in a plain shell — that includes
      `railway.ps1`, `vercel.ps1`, `codex.ps1`, `eas.ps1` in `%APPDATA%\npm`, and `setup.ps1` /
      `verify.ps1` themselves without an explicit `-ExecutionPolicy Bypass`. Fix:

      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

      This is why `railway whoami` first failed with `running scripts is disabled on this system`, and
      why every audit command in this session had to be shipped as a file with `-ExecutionPolicy Bypass`.

### 4. Repo hygiene

- [x] DONE 2026-09-05 — `git pull --rebase` run over SSH: 0 behind `origin/master` (HEAD `d49613d`),
      tracked tree clean, `settings.json` no longer modified.
- [x] DONE 2026-09-05 — all eight setup leftovers deleted from `C:\1Claude`.
      (`androidtools/`, `grotap-landing/` and `DocsforClaude/` are untracked on purpose — left alone.)

### 5. Security residuals

- [ ] **`sshd` is `Running` / `Automatic`**, which means TCP 22 listens on every network the laptop
      joins, including hotel and job-site wifi. Either `Set-Service sshd -StartupType Manual` and start
      it only on the home LAN, or scope its firewall rule to the Private profile.

### 6. Power settings from the runbook were never applied

- [x] DONE 2026-09-05 — applied over SSH: monitor AC 15, monitor DC 5, sleep DC 15, sleep AC never.

### 7. Repo improvement (optional, low priority)

- [ ] `verify.ps1` does not check the workstation apps, which is why a half-finished winget phase
      still reported `0 FAIL` twice. Add an uninstall-registry lookup for ShareX, Chrome Remote
      Desktop, Chrome, Bitwarden, Google Drive and the gcloud SDK.

## Known SSH artefacts — not defects

- **Doppler cannot be exercised over SSH.** Every `doppler` call fails with `Unable to retrieve value
  from system keyring` / `A specified logon session does not exist`. The token in `.doppler.yaml` is a
  `secret-<uuid>` keyring *reference*, not the token, and the real value lives in Windows Credential
  Manager, which a network logon session cannot open. Setting `DOPPLER_TOKEN` does not help — the CLI
  still probes the keyring. Consequence: `verify.ps1`'s "doppler not logged in" warn and its failed
  Neon end-to-end check are both meaningless over SSH. If SSH-driven Doppler is ever needed, put a
  real service token in the config with `doppler configure set token <dp.st....>`.
- **`Start-Job { ssh ... }` hangs.** The fleet-SSH check appeared to hang from the laptop and was fine
  when re-run as `Start-Process ssh -RedirectStandardOutput` (1.5 s, exit 0). PowerShell jobs and
  native `ssh` do not mix; do not read that as a broken key.
- **`node statusline.js` produces nothing over SSH** because it reads its session JSON from stdin.
  Verify the statusline inside a real `claude` session instead.
- **`pi5-01` is unreachable**, but from the desktop too — the DHCP lease moved and the Pi still has no
  router reservation. Nothing to do with the laptop.

## Last checks, inside a session on the laptop

Run `claude` in `C:\1Claude\platform` and confirm the SessionStart banner prints
`[bootstrap] repo: <sha> on master`, the statusline reads `Opus 5 | ctx N% [....] ~Nk/1000k`, `/mcp`
shows `docs-langchain` + `playwright` connected, `/plugin` shows all four enabled, and replies come
back caveman-compressed.

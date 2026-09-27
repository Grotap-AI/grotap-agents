# Seat ggshield pre-commit hook

GitGuardian `ggshield` `secret scan pre-commit` runs for repos a seat commits in.
The hook is installed per seat user and is **off** until it is turned on.
The only automatic on switch is the canary, and that switch works only for the
`codex` user on `agent-22-shared`.

Do not install this on `forge-01` or `maps-01`.

Seats:

| Host | Linux users | Hook after install |
|---|---|---|
| `agent-21-shared` | `claude`, `astra` | off |
| `agent-22-shared` | `codex`, `grok`, `monitor` | off, except `codex` after `--canary` |

Linux hostname on both boxes is the cloud name (`agent-21-shared`, `agent-22-shared`).

## What gets installed

`agents/scripts/install-ggshield-hook.sh`, run as the seat user:

- Creates `~/.local/share/grotap/ggshield-venv` and installs **ggshield 1.54.0**
  with `pip install --require-hashes` from `agents/scripts/ggshield-requirements.txt`.
  Every wheel hash is pinned. A re-run skips pip when `ggshield --version` is already `1.54.0`.
- Copies the hook to `~/.config/grotap/git-hooks/pre-commit`.
- Sets `git config --global core.hooksPath` to that directory, so a repo the seat
  clones later and a repo that is already on disk both run the hook.
  If `core.hooksPath` is already set to a different directory, the installer stops
  and leaves it alone.
- Writes `~/.config/grotap/ggshield-hook.mode` with `off` or `on`. That file is
  not a secret.

`core.hooksPath` replaces `.git/hooks` for every repo. These seats do not ship
other git hooks. A later hook has to live in the same directory.

## API key

The hook reads `GITGUARDIAN_API_KEY` from Doppler project `grotap`, config `prd`,
at commit time:

```text
doppler secrets get GITGUARDIAN_API_KEY --project grotap --config prd --plain
```

That is the same Doppler CLI the seat already uses for fleet secrets
(`doppler configure set token` from `FLEET_DOPPLER_TOKEN`, then
`doppler secrets get … --project grotap --config prd --plain`, as in
`git-credential-doppler`). The value is exported into the hook process
environment for `ggshield` and is not written to disk, not passed on a
command line, and not logged.

When the mode is off, the hook does not call Doppler.

A missing key, a Doppler error, or a ggshield status other than "secrets
found" (exit 1) logs a warning and **allows** the commit. Exit 1 **blocks**
the commit. Server and network failures use ggshield's own exit codes
(including 3, 4, and 128, and timeout exit 124) and fail open. The scan is
limited to 45 seconds.

## Commands on agent-22-shared

Run these on the box as root, after each seat's `~/grotap-agents` checkout
contains this revision. Preflight discards the key on stdout; a non-zero
status means the canary cannot block a secret (the hook fails open).

```bash
sudo -u codex -H -- doppler secrets get GITGUARDIAN_API_KEY --project grotap --config prd --plain >/dev/null

sudo -u codex -H -- bash /home/codex/grotap-agents/agents/scripts/install-ggshield-hook.sh
sudo -u grok -H -- bash /home/grok/grotap-agents/agents/scripts/install-ggshield-hook.sh
sudo -u monitor -H -- bash /home/monitor/grotap-agents/agents/scripts/install-ggshield-hook.sh

sudo -u codex -H -- bash /home/codex/grotap-agents/agents/scripts/install-ggshield-hook.sh --canary
sudo -u codex -H -- bash /home/codex/grotap-agents/agents/scripts/ggshield-canary.sh
```

The canary's only stdout line is `PASS` or `FAIL`. It creates a temporary git
repo, commits GitGuardian's documented Test Token Checked pattern (`ggtt-v-`
plus 10 lowercase letters or digits — not a live credential), asserts the
commit is blocked, commits a clean file, asserts that commit succeeds, and
deletes the temp repo.

`--canary` on any other user, or on any host whose `hostname -s` is not
`agent-22-shared`, exits non-zero and does not enable the hook.

## Commands on agent-21-shared

Install only. Leave both seats off.

```bash
sudo -u claude -H -- bash /home/claude/grotap-agents/agents/scripts/install-ggshield-hook.sh
sudo -u astra -H -- bash /home/astra/grotap-agents/agents/scripts/install-ggshield-hook.sh
```

## Flip the flag

The durable flag is one word in `~/.config/grotap/ggshield-hook.mode`: `off` or `on`.
`GROTAP_GGSHIELD_HOOK` overrides that file for the current process when it is
set. `GROTAP_GGSHIELD_HOOK=off` forces the no-op line `ggshield hook disabled`
even if the file says `on`. Do not export that variable from `.profile`; git
does not need it, and an exported `off` would hide a mode file of `on`.

Turn the canary seat off:

```bash
sudo -u codex -H -- bash /home/codex/grotap-agents/agents/scripts/install-ggshield-hook.sh --disable
```

After the canary has passed and you deliberately want another seat on, write
`on` as that user. This is not part of the first rollout:

```bash
sudo -u grok -H -- bash -c 'printf "%s\n" on > "$HOME/.config/grotap/ggshield-hook.mode"'
```

## Roll back

Disable, leave the binary in place:

```bash
sudo -u codex -H -- bash /home/codex/grotap-agents/agents/scripts/install-ggshield-hook.sh --disable
```

Remove the hook and unset `core.hooksPath` when it points at
`~/.config/grotap/git-hooks`. The venv stays:

```bash
sudo -u codex -H -- bash /home/codex/grotap-agents/agents/scripts/install-ggshield-hook.sh --uninstall
```

Also delete the venv:

```bash
sudo -u codex -H -- bash /home/codex/grotap-agents/agents/scripts/install-ggshield-hook.sh --uninstall --purge
```

Repeat with `grok` and `monitor` on `agent-22-shared`, and with `claude` and
`astra` on `agent-21-shared`, for each seat that was installed.

## Tests

`agents/scripts/ggshield-hook.test.sh` stubs `doppler` and `ggshield`. It does
not use a real API key. `.github/workflows/ggshield-hook.yml` runs that script,
shellcheck, and `pip install --require-hashes` of the lock file (version check
only; no scan).

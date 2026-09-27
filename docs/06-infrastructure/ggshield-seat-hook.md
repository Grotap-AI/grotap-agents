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
  not a secret. A third value, `strict`, is recognized and is not written by
  install or by `--canary`.

`core.hooksPath` replaces `.git/hooks` for every repo. After this hook allows
a commit, it execs `$(git rev-parse --git-dir)/hooks/pre-commit` when that
file exists and is executable. That is the hook `pre-commit install` writes
for a repo such as grotap-platform. A detected secret, or a scan error in
`strict` mode, does not run it. The API key is unset before the repo hook
starts.

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

When the mode is off, the hook does not call Doppler. It still execs the
repo hook when that file is executable, so `pre-commit install` keeps working
while the seat hook is off.

## Fail-open log

Mode `on` **allows** the commit when the scan cannot produce a verdict, and
appends one line to `~/.local/state/grotap/ggshield-failopen.log`. The file
is mode `0600`. The line is:

```text
2026-09-27T14:45:00Z user=codex reason=doppler-error ggshield_exit=- repo=/home/codex/grotap-platform
```

Fields are the UTC timestamp, the seat user, the reason, the ggshield exit
(`-` when ggshield did not run), and the repo path. The API key is not a
field and is not copied from the environment, from Doppler's stderr, or from
the scan output.

| reason | when | ggshield exit |
|---|---|---|
| `ggshield-missing` | no ggshield binary | `-` |
| `doppler-missing` | `doppler` is not on `PATH` | `-` |
| `doppler-error` | Doppler exits non-zero | `-` |
| `empty-key` | Doppler returns an empty value | `-` |
| `timeout` | the 45s scan limit (exit 124) | `124` |
| `scan-error` | any other status except 0 and 1 | that status |

Exit 1 still **blocks** the commit and does not append a line. Exit 0 allows
the commit and does not append a line.

`agents/scripts/health-monitor.sh` (agent-06 cron) reads that log for each
seat over SSH after the host answers:

| Host | Seats |
|---|---|
| `agent-21-shared` | `claude`, `astra` |
| `agent-22-shared` | `codex`, `grok`, `monitor` |

It counts lines whose timestamp is within the last hour. A count above 0
appends `GGSHIELD FAILOPEN: <user>@<host> — <count> in the last hour` to the
existing alert log (`/home/agent/logs/deploy-alerts.log` on the ops host) and
marks the sweep degraded. A missing log is a count of 0. The alert is the
count, not the log line.

## Strict mode

`strict` sits beside `on` and `off`. On a scan error (the reasons in the
table above) it **blocks** the commit and does not write the fail-open log,
so the health monitor does not alert. A detected secret still blocks. A
clean scan still allows the commit and still chains to the repo hook.

Nothing enables `strict` by default. Install writes `off`. `--canary` writes
`on`. To turn it on for one seat, write the word as that user:

```bash
sudo -u codex -H -- bash -c 'printf "%s\n" strict > "$HOME/.config/grotap/ggshield-hook.mode"'
```

`GROTAP_GGSHIELD_HOOK=strict` overrides the file for the current process the
same way `on` and `off` do. Do not export it from `.profile`. An unrecognized
word in the file, including `strictly`, is `off`.

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

The durable flag is one word in `~/.config/grotap/ggshield-hook.mode`: `off`,
`on`, or `strict`. `GROTAP_GGSHIELD_HOOK` overrides that file for the current
process when it is set. `GROTAP_GGSHIELD_HOOK=off` forces the no-op line
`ggshield hook disabled` even if the file says `on`. Do not export that
variable from `.profile`; git does not need it, and an exported `off` would
hide a mode file of `on`. `strict` is described above and is not the canary.

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

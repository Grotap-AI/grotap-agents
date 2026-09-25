# Grotap skills library

Version: see `VERSION` (0.1.1). Shared playbooks for the agent fleet. Nothing
in this folder deploys, syncs to a server, or wires itself into session
bootstrap.

## Why this repo

`grotap-agents` is the fleet and agent-config home: team roster, roles, and
the rules the orchestrator already points at. Application code stays in
`grotap-platform`. This library is a self-contained top-level `skills/`
folder so a box can pin a git tag without taking a bootstrap change.

Do not point the installer at this checkout. Do not add this folder to
bootstrap scripts. Install onto a platform checkout or a home directory on
the box that will run the agent.

## Layout

```
skills/
  VERSION  CHANGELOG.md  README.md  THIRD_PARTY.md
  library/<skill>/
    SKILL.md                 canonical instructions
    agents/openai.yaml       codex explicit-invoke policy
    references/  scripts/    optional
  scripts/sync-skills.sh     copy or symlink onto a box
  scripts/load-test.sh       read-only listing check
```

Canonical source is `skills/library/`. Claude Code and codex do not read that
path. The sync script publishes it into the directories each tool scans.

## How a team loads skills

Run on the target box, from a checkout of this repo, as the agent user. Pick
symlink unless the box cannot follow links.

```bash
# User-level (all repos that user opens):
bash skills/scripts/sync-skills.sh --mode symlink --home "$HOME"

# Repo-level on a platform checkout (not this repo):
bash skills/scripts/sync-skills.sh --mode symlink --repo /path/to/grotap-platform
```

The installer refuses this checkout for both `--repo` and `--home`. Symlink
mode leaves a real skill directory in place unless you pass `--force`, which
moves it to `<name>.bak.<timestamp>` and then links the library skill. A
symlink into an existing real directory would otherwise land inside it.
Copy mode does the same under `~/.claude/skills`, `~/.agents/skills`, and
`$CODEX_HOME/skills` (default `~/.codex/skills`). A copy into another repo
still replaces a same-named directory.

Codex 0.157 (`openai/codex` tag `rust-v0.157.0`, `codex-rs/ext/skills`) scans:

| Scope | Path |
|---|---|
| Repo | `$CWD/.agents/skills`, then each parent up to the git root |
| User | `$HOME/.agents/skills` |
| User (deprecated, still scanned) | `$CODEX_HOME/skills`, default `$HOME/.codex/skills` |
| Admin | `/etc/codex/skills` |

Claude Code scans `.claude/skills/<name>/SKILL.md` in the project and
`$HOME/.claude/skills/<name>/SKILL.md` for the user. The sync script fills
both the project and the home locations you pass.

Restart the CLI after a sync. Codex reads skills at startup.

## How the orchestrator names a skill

Every skill here is explicit-invoke.

- Claude Code: `disable-model-invocation: true` in `SKILL.md`. The task text
  must name the skill or the model will not load it.
- Codex 0.157: `agents/openai.yaml` sets `policy.allow_implicit_invocation`
  to false. Explicit form is `$<skill-name>`. Some 0.14x builds did not
  expand that form outside the TUI, so the task must also carry the path.

Put both lines in the LangGraph task (and in any `dispatch.sh` prompt that
is authored later, outside this folder):

```
Skill: bug-repro-and-fix
Read and follow skills/library/bug-repro-and-fix/SKILL.md before editing.
```

Name one playbook per task. Name `engineering-principles` only when the task
needs the judgment rules. Do not attach the whole library.

## Teams and models

The skill does not pick a model. The box already has one.

| Team | Runtime | Model on that team |
|---|---|---|
| Claude | Claude Code, 4 servers | The model configured on that server |
| Codex | codex CLI | GPT-5.2 Codex via OpenRouter |
| Monitor | codex CLI | DeepSeek |
| Astra | codex-cli 0.157.0 | GPT-6 Astra |

## Skills

| Skill | Invoke when |
|---|---|
| `engineering-principles` | Judgment: smallest change, root cause, idempotency, a repeated mistake |
| `verify-and-prove` | The task must be shown on the real app |
| `bug-repro-and-fix` | A reported defect |
| `ci-failure-triage` | A PR must become merge-ready |
| `feature-and-open-pr` | New behavior, then the PR |
| `db-migrations` | Schema or data change |
| `gardener` | Behavior-preserving cleanup |
| `release-and-rollback` | Land a verified change, or roll it back |
| `perf` | A measured speedup |

## Add a skill

1. Add `library/<name>/SKILL.md` with `name`, a one-line `description`, and
   `disable-model-invocation: true`.
2. Add `library/<name>/agents/openai.yaml` with
   `allow_implicit_invocation: false` unless the orchestrator should
   auto-select it. Default is explicit.
3. Keep the description short and lead with the trigger. Codex lists name
   plus description only, capped at 2% of the context window, or 8,000
   characters when the window is unknown (`render.rs` in rust-v0.157.0).
4. If the text is adapted from pstack, add the origin header and keep
   `THIRD_PARTY.md`.
5. Bump `VERSION` and add a `CHANGELOG.md` entry.
6. Run the loading test. Nine skills is the current set; adding one is
   cheap, adding dozens will hit the cap.

## Loading test

Infra runs this on the Hetzner builder `agent-11-codex` as the non-root
`agent` user (uid 1000). It does not need root or an API key. It writes only
under `--home`.

```bash
bash skills/scripts/load-test.sh --home /tmp/skills-test-home
```

The script skips Codex or Claude Code when that binary is absent, and it
skips a live Codex list when the binary is not 0.157.x. Static token numbers
still print. Codex 0.157 omits a skill from the model-visible list when
`agents/openai.yaml` sets `allow_implicit_invocation: false`, so the live
check proves repo discovery with a scratch probe and expects the nine
library skills to be absent from that list. The orchestrator still names
them. The listing budget also includes the Codex built-in system skills
that 0.157 lists from `$CODEX_HOME/skills/.system` (imagegen, openai-docs,
plugin-creator, skill-creator, skill-installer). A system skill with
`allow_implicit_invocation: false` stays out of that total. The script
prints library-only and total-with-system separately. Headroom is against
the total.

## Proof tool

`verify-and-prove` calls `grotap-proof`. That command name is a placeholder
until the self-verify CLI is published. Override with `GROTAP_PROOF_CMD`.
Do not invent a second interface.

## License

MIT for the pstack portions. See `THIRD_PARTY.md`.

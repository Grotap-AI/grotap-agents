# Changelog

## 0.1.3

- One `--force` invocation creates a single backup run directory in the main shell and prunes older runs only after that run is finished, so a run that backs up every skill keeps all of them.
- `--force` exits 2 before moving anything when both `HOME` and `XDG_STATE_HOME` are unset.

## 0.1.2

- `--force` backups go outside every scanned skill root, under `${XDG_STATE_HOME:-$HOME/.local/state}/grotap-skills/backup/<run>/`, one unique directory per run. The last five runs are kept.
- Copy mode skips a destination that is already identical to the library, with no backup. A differing real directory under every `--repo` and `--home` root needs `--force`.
- `--repo` and `--home` pointed at a subdirectory of a grotap-agents checkout are refused.
- `release-and-rollback` says a rebase push is `git push --force-with-lease` only, and only on your own PR branch.

## 0.1.1

- `sync-skills.sh` refuses a grotap-agents checkout for `--home` as well as `--repo`.
- Symlink mode skips a real same-named skill directory unless `--force` backs it up and replaces it, so the link is not nested inside that directory.
- Copy mode requires `--force`, and backs up first, before replacing a same-named skill under `~/.claude`, `~/.agents`, or `$CODEX_HOME`.
- `release-and-rollback` tells the agent to check before merging: a PR that needs a merge commit, including an `agents/BOOTSTRAP_SHA` pin PR, uses `gh pr merge --merge`. Squash stays the default for every other PR.
- Loading-test docs name the Hetzner user `agent` (uid 1000).
- `load-test.sh` counts the Codex system skills that appear in the 0.157 listing, reports library-only and total-with-system separately, and computes headroom against the total.

## 0.1.0

- First shared skills library for the Grotap fleet.
- One `engineering-principles` skill covering the 23 pstack principle skills.
- Eight playbooks: verify-and-prove, bug-repro-and-fix, ci-failure-triage,
  feature-and-open-pr, db-migrations, gardener, release-and-rollback, perf.
- Node port of the pstack `watch-pr` gh wrapper, and a decision-log script
  adapted from pstack `show-me-your-work`.
- `scripts/sync-skills.sh` installs the canonical tree into Claude Code and
  codex-cli 0.157 skill roots. `scripts/load-test.sh` is the read-only
  listing check for a builder box.

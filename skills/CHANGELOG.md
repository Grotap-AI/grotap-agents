# Changelog

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

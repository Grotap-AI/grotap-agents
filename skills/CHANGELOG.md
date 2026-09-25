# Changelog

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

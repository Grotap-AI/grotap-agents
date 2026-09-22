# Plan go-live

Desktop `*.md` files are drafts. Agents do not read them. A plan is in force only after the implemented text is in git and, when agents must obey it, a short pointer sits in the bootstrap file every session loads.

## Path

1. **Draft** on the Desktop is fine while the plan is still being written.
2. **Implement**, then commit the plan to the repo that owns it:
   - Platform plan → `grotap-platform/docs/<NAME>.md` (for example `docs/AGENTIC-EXECUTION-SECURITY-PLAN.md`, `docs/JEV_HARNESS.md`).
   - Agents-repo plan (bootstrap, fleet, session rules) → `docs/<NAME>.md` in this repo.
3. **Must-obey.** If every agent session has to follow it, add a pointer of at most 10 lines to `agents/GLOBAL.md`: the rule, plus the path to the full doc. Do not paste the plan. `agents/GLOBAL.md` is Tier 1 (Tech Lead, PR). Long prose stays in `docs/`.
4. **Pin.** `agents/BOOTSTRAP_SHA` checks the fleet out at one blessed commit. Master moving does not reach agents until that file names a commit that contains the GLOBAL change. Follow §ROTATION in `agents/BOOTSTRAP_SHA` — do not invent another pin:
   - Bless a commit that already contains the GLOBAL edit. The commit that records a SHA cannot name itself.
   - That SHA must be reachable by `git fetch` of `refs/heads/master` only. Land the content with a merge commit. A squash or rebase drops the blessed SHA, and `verify_bootstrap_pin` then hard-fails every host that has verified a pin before.
   - Before replacing the SHA, read `git diff <old>..<new> -- agents/scripts/orchestrator-run.sh BOOTSTRAP.md agents/GLOBAL.md`. The runner is executed; those two markdown files become model instructions.
   - Mirror the same SHA into grotap-platform `agents/BOOTSTRAP_SHA`.

Do not load the full plan into every prompt. Sessions already load `agents/GLOBAL.md`.

## Author checklist

- [ ] Desktop copy stayed a draft; the implemented plan is committed under the correct `docs/` path
- [ ] Must-obey text is a ≤10-line pointer in `agents/GLOBAL.md`, not a copy of the plan
- [ ] `./.claude-session-init.sh --validate` passes (`agents/GLOBAL.md` stays under its byte cap)
- [ ] No secrets in the plan or the pointer
- [ ] If `agents/GLOBAL.md` changed: `agents/BOOTSTRAP_SHA` rotated per §ROTATION onto a commit that contains the change and is an ancestor of `origin/master`
- [ ] The same SHA is mirrored to grotap-platform `agents/BOOTSTRAP_SHA`

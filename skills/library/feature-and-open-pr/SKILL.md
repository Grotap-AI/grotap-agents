---
name: feature-and-open-pr
description: "Use to build a feature and open the PR. Sketch the data shape, implement, prove it, then write Why, Scope, Tradeoffs, Blast Radius, and Verification. Invoke explicitly as feature-and-open-pr."
disable-model-invocation: true
---

Origin: pstack v0.15.5 feature and opening-a-pr playbooks (Lauren Tan, MIT), https://github.com/cursor/plugins/tree/fadd23794c0075468eb8964b0fd93e06e09486ad/pstack — adapted for the Grotap fleet. Cursor subagents, deslop, and the Origin forge are omitted.

# Feature and open a PR

You own the design. Trunk is `master`. Stage named paths only. Never `git add -A` or `git add .`.

Run on the team the task names. Keep that team's model. Do not switch models from this skill.

## Build

1. Read the subsystem you are about to change. Name the data shape before writing logic (a state machine, a table, a typed model). See `engineering-principles` (model the domain, foundational thinking).
2. Write a four-line checkpoint. Keep a line as `n/a` with a reason rather than dropping it.
   - Blocking first steps.
   - Independent workstreams (shared writes stay serial).
   - Shared mutable state (split it unless one writer is a real invariant).
   - Smallest safe decomposition, and why one owner is enough when it is.
3. Implement the smallest change that meets the checkpoint. Port a shared-primitive fix to its callers in the same wave, or do not change the primitive.
4. Prove it with `verify-and-prove`. If the task names the feature map, let it choose the pytest shard and the vitest files. If the diff touches CI or `scripts/detect-backend-changes.sh`, run all six pytest shards and vitest.
5. Rebase into small ordered commits on `master`. Each commit is landable. The failing test, when there is one, comes before the behavior.

## Worktree

Work from a git worktree off `origin/master`. A dirty tree with unrelated work: patch it out, start a clean worktree, apply your patch.

## Pull request

Title: Conventional Commits, `type(scope): subject`, imperative, no trailing period. Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`.

Body, in this order. Drop a section that has nothing to say. This body is the squash commit. Keep it short.

- `## Why` — intent and approach. No SHA genealogy.
- `## Scope` — symbols and paths. Name both sides of a rename.
- `## Tradeoffs` — only a rejected alternative a reviewer would ask about.
- `## Blast Radius` — who or what the change touches, and why it is safe or risky.
- `## Verification` — each real run and its outcome. A performance change cites one number as `before → after`.

Forge is `gh`. Create the PR ready:

```bash
gh pr create --base master --title "..." --body-file pr-body.md
```

Do not pass `--draft`. If it still opens as a draft, run `gh pr ready <number>`. Prefer a few narrow PRs to one large PR. A child PR targets its parent branch, not `master`, and the child branch is rebased onto the parent's tip.

Opening the PR does not start triage. Post the URL. Run `ci-failure-triage` only when the task asks for merge-ready.

Reply with what you built, what you chose, the checkpoint, and the PR URL.

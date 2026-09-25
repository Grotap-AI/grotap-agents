---
name: bug-repro-and-fix
description: "Use for a reported defect. Reproduce it, compare the prior commit with main, write a failing test, then fix. Invoke explicitly as bug-repro-and-fix."
disable-model-invocation: true
---

Origin: pstack v0.15.5 bug-fix playbook, principle-fix-root-causes, and Benny reproduce-and-fix-issues steps 5–13 (Lauren Tan, MIT), https://github.com/cursor/plugins/tree/fadd23794c0075468eb8964b0fd93e06e09486ad/pstack — adapted for the Grotap fleet. Slack posting and Cursor automations are omitted.

# Bug repro and fix

You own the defect. Every shipped line traces to runtime evidence. A guard that "might help" is a hypothesis. It does not ship. When evidence refutes a hypothesis, revert what it motivated.

Run on the team the task names. Keep that team's model. Do not switch models from this skill. Use `verify-and-prove` for the real surface and `engineering-principles` (fix root causes, verifiable units) as needed.

## 1. Reproduce on the real surface

Drive the reported path with `verify-and-prove`. Name the correct final state, the broken final state, and the point they diverge. Observe the broken state, reset enough state to make a second attempt independent, and observe it again. One sighting is not a confirmed repro.

If the proof tool is missing, stop with `proof-tool-missing` rather than calling a unit test a repro. A dialog or a loading state is not the bug. The discriminating final state is.

If it will not reproduce, tighten the conditions or add instrumentation and read it. Do not ask a human to reproduce until you have driven the surface as far as it goes and can name the gap.

No confirmed repro means no fix.

## 2. Verdict against main and the prior commit

Before editing, say which of these is true:

- Still broken on `master` (Grotap's trunk is `master`).
- Already fixed on `master`. Stop. Do not open a second fix.
- Absent on the parent commit and present on the branch tip (introduced here).
- Present on an older commit. Bisect with runtime evidence, not with a guess.

If an open PR or a merged commit already claims the fix, verify that artifact on the real surface. Do not write a competing patch. If a person has claimed the fix, stop.

## 3. Find the mechanism

List the candidate causes. Each pass, take the split that removes the most remaining space and get runtime evidence. Confirm the surviving mechanism before editing. Do not spin. If the hunt stalls, report the last eliminated hypothesis and stop.

## 4. Failing test first

When a cheap local test exists, write it first and watch it fail. Backend: pytest, aimed at the owning shard's area. Frontend: vitest from `frontend/`. Commit that failing test before the fix. Skip the test only when it would be an expensive integration stand-in, and say why. A test that still passes when the subject returns nothing is not the failing test. See `engineering-principles` (test behavior).

## 5. Fix the root cause

The smallest change the evidence justifies. No unrelated cleanup. If the change outgrows the task, stop and report.

## 6. Prove the fix

Keep the baseline evidence. On the patched build, run the same path twice and show the broken state is gone. Then rerun the failing test and show it passes. Paste both outputs in the PR. Inconclusive is not a pass.

## 7. Open the PR

Follow the PR section of `feature-and-open-pr`. Open it ready unless the task says draft. Do not merge from this skill.

Reply with: what was broken, the main-versus-prior verdict, the root cause, the fix, and the failing-then-passing proof.

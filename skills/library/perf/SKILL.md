---
name: perf
description: "Use for a measured speedup or a hillclimb. One change at a time, with before and after numbers and a decision log. Invoke explicitly as perf."
disable-model-invocation: true
---

Origin: pstack v0.15.5 perf-issue and hillclimb playbooks, plus show-me-your-work `log.sh` (Lauren Tan, MIT), https://github.com/cursor/plugins/tree/fadd23794c0075468eb8964b0fd93e06e09486ad/pstack — adapted for the Grotap fleet.

# Performance

You own the measurement. Do not claim a speedup from reading the source. Tie every kept change to a number.

Run on the team the task names. Keep that team's model. Do not switch models from this skill.

Metrics that count here: API p95, page load, bundle size, and CI minutes. Name one primary metric for the task.

## One-off fix

1. Capture a baseline on the real surface (`verify-and-prove`) or with the harness the task names. Record the command and the number.
2. Form hypotheses from the families below. A family earns an attempt only when the trace shows its signal.
   - **Elimination.** Does this work need to exist?
   - **Divide and conquer.** Cost scales with input size. Split or prune it.
   - **Caching.** The same work repeats on the same input. Name the invalidation.
   - **Indirection.** A cheaper hop removes more than it adds (index, queue, handle).
   - **Batching.** Many calls each pay a fixed overhead. Pay it once.
   - **Redundancy.** The wait is one slow attempt and there is spare capacity. Take the fastest.
   - **Lazy evaluation.** Cost lands on a result nobody uses yet.
   - **Scheduling.** The work must happen, but not on the interactive path.
3. One change. Measure again. Keep it only when the number moves past noise and the regression tests stay green. Otherwise revert the whole change.
4. Cite one number in the PR as `before → after` with the unit. Open the PR with `feature-and-open-pr`.

## Hillclimb

Use this when the task is a sustained push on one metric, not a single fix.

1. Name the metric, the direction that is better, and a stop predicate that includes a floor on attempts so an early lucky win cannot end the run. Use the numbers in the task.
2. Freeze the harness. One command prints the metric. Sample enough to clear noise (median of N, not one run). Record the baseline and a green regression run before the first edit.
3. Open a decision log outside the tree:

```bash
bash skills/library/perf/scripts/decision-log.sh decision.tsv attempt "hypothesis" "why" "evidence" "kept|reverted"
```

The script adds `ts`, `phase`, `decision`, `why`, `evidence`, and `result`. Read the log before the next attempt. Do not commit it.

4. Each attempt names a mechanism, changes one thing, measures, runs the regression gate, and keeps or reverts in full. One commit per kept fix. Stage named files only.
5. On a stall, change family or combine two near-misses before you stop. Correctness and simplicity outrank the number. Revert a win that breaks behavior.
6. Stop when the predicate is met, or when the remaining ideas are marginal. Do not relax the predicate. Open the PR with the kept commits and the before-to-after number.

Reply with the metric, baseline, final, delta, attempts kept and reverted, and the log path.

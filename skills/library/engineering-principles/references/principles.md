Origin: pstack v0.15.5 principle-* skills (Lauren Tan, MIT), https://github.com/cursor/plugins/tree/fadd23794c0075468eb8964b0fd93e06e09486ad/pstack. Merged and rewritten for Grotap. Open the section you need. Do not paste this file into a task prompt.

# Principles

## Laziness protocol

Aim for the most result with the least code. Look for a deletion before an addition. Keep the call chain flat. Put a repeated decision in one place. If a change asks you to thread a new signal through several layers, look for a shorter path. If a human would find the code exhausting, it is a bad solution.

## Foundational thinking

Get the data shape right before the logic. Dry the structure, not every line. Before sharing state between actors, ask what happens if another actor writes it. Scaffold that helps every later phase comes first: types, tests, CI. Remove dead code before laying that scaffold.

## Redesign from first principles

Do not bolt a new requirement on. Read the affected files and ask what you would build if the requirement had been there from the start. Propagate the answer through types, docs, and callers. Deliver that redesign in small increments.

## Attack the premise

When two or more fixes that share one premise fail the same gate, suspect the premise. Write the premise in one sentence. Count which actors hold the imbalance, with a script you can rerun. If the same actors hold it every time, find what assigns that role and remove the asymmetry. If the census is even, the premise is not the cause. Keep the census.

## Subtract before you add

Remove complexity first, then build. Cut dead code, redundant validators, and stub references. Design for observed use, not a speculative edge. When a reference has no new content, delete it.

## Minimize reader load

Track two costs: how many layers sit between a question and its answer, and how much hidden state the reader must hold. Collapse a one-caller wrapper. A layer that repeats the same arguments is not a layer. Prefer a pure function over a field, and a field over a global. A new reader should be able to answer where a value comes from, and what can change it, quickly. If they cannot, cut a layer or cut state.

## Outcome-oriented execution

Optimize for the verifiable end state. Temporary compatibility that exists only to keep every intermediate commit comfortable becomes debt. Use this on a planned rewrite with an explicit phase boundary. Say where breakage is acceptable. Require a full check at the end of the plan.

## Experience first

When implementation convenience conflicts with the person who has to use the result, choose that person. Ship fewer finished things. The user may be the end user, the caller of a library, or the next engineer. Weigh those the same way.

## Exhaust the design space

When a novel interaction or architecture has no precedent in the repo, build two or three concrete alternatives and compare them. A second flavor of the first shape does not count. Skip this for a mechanical change, a bug with a known target, or a constraint that leaves one viable approach.

## Build the lever

If the work is more than a couple of obvious edits, build the script, codemod, or check that does it or proves it. Do the first unit by hand, then make the tool match that unit. A deterministic script beats asking several agents to hand-apply the same edit. If you cite this rule and the diff has no script, you did not apply it. Build the smallest script that does the job.

## Model the domain

Encode the domain in a structure instead of scattered conditionals. Reach for a state machine instead of paired booleans, a typed model instead of a repeated shape, a table instead of a branch copied across files. Do not force an abstraction when the current shape is local and clear. The smell is a new feature that adds one more branch, or a second boolean that must stay in sync with the first.

## Boundary discipline

Validate at the boundary: CLI args, config, network, external APIs. Inside the system, trust the types and keep business logic in pure functions. Do not re-check a value that the boundary already parsed. Do not re-export a wire type as the public model.

## Type-system discipline

Make illegal states unrepresentable. Brand ids that are different things even when both are strings. Parse external data at the boundary. Do not silence the checker with a cast. Match sum types exhaustively. Derive a type from the schema that owns it instead of hand-writing a parallel one. Strengthen a type where a runtime assertion appeared, then stop.

## Make operations idempotent

Every mutating step answers two questions: what if this runs twice, and what if the previous run died halfway? If the answer depends on leftover state, add a reconciliation step. Locks must notice a dead owner. Failed work must be safe to start again.

## Migrate callers, then delete legacy APIs

When a new internal API is the right design, inventory callers, migrate them, and delete the old API in the same wave. A temporary adapter is an exception with an end, not the default. Update tests to the new contract. Delete tests that only protect the old implementation. This applies when no external user depends on the old API.

## Separate before serializing shared state

If two actors might write the same file, branch, or key, ask whether they need the same object. Default to one object per actor, and merge at read time. Two writers into one JSON document is still shared mutation. Serialize with a lock or a single writer only when one shared object is a real invariant. An instruction is not a lock.

## Prove it works

Check the real artifact. Do not infer from a compile, a fresh timestamp, or a self-report. When a check fails, suspect the observation method before you suspect the system. The strongest proof is a command someone else can rerun. Use `verify-and-prove`.

## Fix root causes

Reproduce first. Ask why until you reach the cause. A nil check that hides a crash is a symptom fix. If a workaround needs a paragraph to justify it, the code is wrong. Search for the same pattern and fix the set, not one call site. When stuck, instrument and read the result. A failure after restart is often stale state, not a new code path.

## Sequence verifiable units

Order work so each unit ends in a state you can check, and do not start the next unit until this one is green. Rebase onto current trunk first so the check measures the real baseline. Stack commits in the order that proves the story: failing test, then fix; subtraction, then reshape; baseline, then treatment.

## Test behavior, not implementation

Call the code the way its user does and assert the observable result against a literal expected value. Before keeping a test, ask whether it would still pass if every imported function returned undefined. If yes, rewrite it or delete it. Weak assertions, "was called" with no payload, an expected value computed from the subject, and a constant copied into the assertion all fail that test.

## Guard the context window

The window is finite for the session. Send large logs, diffs, and captures to files. Keep the summary in the thread. Do not re-read a file you already have in context unless it changed.

## Never block on the human

For reversible work, decide, do it, and present the result. Do not ask permission for an edit the review can undo. Still pause for force-push, a production deploy, data deletion, a customer message, or a destructive migration. Product direction belongs to the human. Execution of an agreed task does not.

## Encode lessons in structure

A correction that shows up twice should become a mechanism: a lint, a runtime check, a banned API, or a script. Text that says "remember" will be missed. Pick the strongest mechanism the case allows. One-off notes stay notes. A recurring code mistake goes to the Shadow mistakes-to-lint-rules process as a candidate. This skill does not add the lint.

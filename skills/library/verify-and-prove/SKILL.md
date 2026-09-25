---
name: verify-and-prove
description: "Use when the task must be shown on the real app. Capture proof and reject an inconclusive or wrong-surface result. Invoke explicitly as verify-and-prove."
disable-model-invocation: true
---

Origin: pstack v0.15.5 create-verification-skill and principle-prove-it-works (Lauren Tan, MIT), https://github.com/cursor/plugins/tree/fadd23794c0075468eb8964b0fd93e06e09486ad/pstack — adapted to the Grotap proof tool. No text from poteto/verification-skill-example.

# Verify and prove

A unit test, a typecheck, or a green CI job is not proof that the user-facing behavior works. Proof is a run of the real app on the matching surface, with the evidence kept.

Run on the team the task names. Keep that team's model. Do not switch models from this skill.

The proof CLI name is not in this repo. The command below is a **PLACEHOLDER**. When infra publishes the binary, set `GROTAP_PROOF_CMD` to it. Do not invent a second interface.

```bash
PROOF="${GROTAP_PROOF_CMD:-grotap-proof}"
```

## Launch

Start the app the way a developer does for the surface under test (frontend on Vercel preview or local Vite, API on the Railway staging service). Record the command, the port, and the ready check (a health URL or a log line). If `command -v "$PROOF"` fails, stop with outcome `proof-tool-missing`. Do not substitute pytest or vitest for this step.

## Doctor

Run this before driving:

```bash
"$PROOF" doctor
```

Doctor answers whether this instance is worth driving: process up, expected build, port owned by this run, auth valid. If doctor fails, fix the instance or stop. Do not drive a shared session you do not own.

## Drive

```bash
"$PROOF" run --feature "<feature-id>" --evidence "<evidence-dir>"
```

Drive the real user path. Use stable handles (routes, labels, API paths), not coordinates. If the task names a feature-map path, read it and drive every entry the diff touches. If it does not, say the map was unavailable and do not invent selectors.

The pre-push feature map is owned outside this library. Use it to choose pytest and vitest targets. A change to CI or to `scripts/detect-backend-changes.sh` is the exception: run all six pytest shards and vitest, because a skipped shard looks green.

## Evidence

The evidence directory must show the action and the resulting state, not only the final screen. Check the side effect (row, file, response body) as well. Mocks only where production already isolates that system.

Put a short `## Verification` section on the PR: command, surface, outcome, evidence path. "Inconclusive" or the wrong surface is a fail. Say so.

## Cleanup

Stop the processes this run started. Do not kill by process name. Cleanup must leave the evidence directory in place.

## Helpers

If `$PROOF` is missing, the helper is the placeholder above. Record the exact command you would have run and stop.

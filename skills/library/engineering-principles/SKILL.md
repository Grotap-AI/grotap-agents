---
name: engineering-principles
description: "Use for engineering judgment: smallest change, root cause, idempotent operations, or a repeated mistake. Invoke explicitly as engineering-principles."
disable-model-invocation: true
---

Origin: pstack v0.15.5 principle-* skills (Lauren Tan, MIT), https://github.com/cursor/plugins/tree/fadd23794c0075468eb8964b0fd93e06e09486ad/pstack — merged into one skill for the Grotap fleet.

# Engineering principles

Apply only the rules that fit the task. Read `references/principles.md` for the pattern and the stop condition of the rule you use. Do not load all 23 into the reply.

Run on the team the task names. Keep that team's model (Claude on the Claude servers, GPT-5.2 Codex via OpenRouter, DeepSeek, or GPT-6 Astra). Do not switch models from this skill.

Pause before force-push, a production deploy, data deletion, a customer message, or a destructive migration. Reversible code work proceeds.

## Core

1. **Laziness.** Prefer deletion and the smallest change that solves the problem.
2. **Foundational thinking.** Choose the data shape before the logic.
3. **Redesign from first principles.** Fit a new requirement as if it had always been there.
4. **Attack the premise.** After two failed fixes that share a premise, write the premise down and count who holds the imbalance.
5. **Subtract before you add.** Remove dead code and redundant checks, then build.
6. **Minimize reader load.** Cut layers and the state a reader must hold.
7. **Outcome-oriented execution.** Aim at the verifiable end state. Do not keep throwaway compatibility.
8. **Experience first.** When convenience and the user conflict, choose the user.
9. **Exhaust the design space.** For a novel decision with no local precedent, compare two or three concrete options, then commit.
10. **Build the lever.** If the work is not a couple of obvious edits, leave a script or check a reviewer can rerun.

## Architecture

11. **Model the domain.** Put the domain in a structure so illegal states disappear.
12. **Boundary discipline.** Validate at the edge. Trust typed data inside.
13. **Type-system discipline.** Make illegal states unrepresentable. Parse external data at the boundary.
14. **Idempotent operations.** A rerun, or a crash halfway, still converges.
15. **Migrate callers, then delete.** Move callers and delete the old API in the same wave.
16. **Separate shared state.** Give concurrent writers their own state unless one writer is a real invariant.

## Verification

17. **Prove it works.** Check the real artifact. A compile is not proof. Use `verify-and-prove`.
18. **Fix root causes.** Reproduce, ask why, and do not silence the symptom.
19. **Verifiable units.** Small steps, each checked before the next. Failing test, then the fix.
20. **Test behavior.** Assert an observable result. A test that still passes when every import returns undefined is not a test.

## Delegation and lessons

21. **Guard the context window.** Summaries in the main thread. Raw dumps stay in files.
22. **Do not block on the human** for reversible work. The pause list above still stands.
23. **Encode lessons in structure.** A repeated correction becomes a lint or a check. Hand the candidate to the Shadow mistakes-to-lint-rules process. Do not add the lint from this skill.

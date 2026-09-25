---
name: gardener
description: "Use for behavior-preserving cleanup. Pin the behavior, subtract first, and send a repeated mistake to the lint-rules process. Invoke explicitly as gardener."
disable-model-invocation: true
---

Origin: pstack v0.15.5 refactoring playbook, no-comments, and Comment Sicko (Lauren Tan, MIT), https://github.com/cursor/plugins/tree/fadd23794c0075468eb8964b0fd93e06e09486ad/pstack — adapted for the Grotap fleet. The comment review is a checklist in this skill, not a subagent.

# Gardener

The structure changes. The behavior does not. A new feature or a real bug splits out and ships on its own. A redesign is `feature-and-open-pr`, and you say so.

Run on the team the task names. Keep that team's model. Do not switch models from this skill.

## Steps

1. Pin the contract. Read the subsystem, then add a characterization test, snapshot, or equivalence check that fails if current behavior moves. Typecheck and lint are not a pin.
2. Name the structure the code is missing. Boring code stays when the shape is already clear. The reshape must delete branches or invalid states.
3. Subtract first. Delete dead code, one-caller wrappers, and orphan references before introducing the new shape. The smallest change that reaches the target ships. Revert a speculative cleanup.
4. Move in small steps that keep the pin green. For an API reshape, migrate every caller and delete the old API in the same wave. No compatibility shim. Check renames inside strings and comments, not only symbols.
5. Prove behavior is unchanged on the real artifact with `verify-and-prove` when a user can see it. Otherwise rerun the pin and an equivalence diff of old versus new output.
6. Keep the change only if a reader has less to hold. If the diff does not lower reader load, revert it.
7. Commits: subtraction, then the reshape, then leftover cleanup. Open the PR with `feature-and-open-pr`.

## Comment review

Before the PR, review comments in the diff with `references/comment-review.md`. You may delete a comment that fails that list. You flag `MUST KILL` on the symbol. You do not rewrite the symbol in the same pass unless the task is the reshape that removes the need for the comment.

## Repeated mistakes

When the same mistake shows up a second time, do not add a lint rule. Append this block to the PR body and leave the rule to the Shadow mistakes-to-lint-rules process:

```
## Lint-rule candidate
- mistake:
- where it repeated:
- proposed check name:
- owner: Shadow mistakes-to-lint-rules
```

Reply with the structure that changed, the pin, the equivalence proof, the reader-load delta, and any lint-rule candidate. No new behavior.

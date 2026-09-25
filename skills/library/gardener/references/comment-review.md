Origin: pstack v0.15.5 agents/comment-sicko.md and the no-comments skill (Lauren Tan, MIT), https://github.com/cursor/plugins/tree/fadd23794c0075468eb8964b0fd93e06e09486ad/pstack. Rewritten as a review checklist.

# Comment review

Read the diff. If there is no diff, read the change against `master`. Report only. Do not write application code in this pass.

Delete a comment that is narration, a banner, a commented-out block, or a workaround sermon.

Keep only:

- A legal or license header.
- A non-obvious behavior forced by a dependency, platform, vendor, or protocol this repo cannot change. A surprise in our own code is not this case. Flag the symbol `MUST KILL` and name the rename, extract, or type that would make the comment unnecessary.
- A formatter ignore, or a lint suppression whose rule is style-only. If the rule catches real bugs, drop the suppression and flag the symbol `MUST KILL`.
- A doc comment that is the public contract.
- An issue link for a constraint the code cannot express.

`eslint-disable`, `@ts-ignore`, and `@ts-expect-error` get looked up. A suppression that hides a real defect does not stay.

`IMPORTANT`, `do not remove`, `too risky`, and `fine for now` are not reasons. Read the nearby code. If the claim is not obvious there, trace the symbol. Doubt means the comment goes.

A long justification without a keep-clause is a confession. Do not shorten it into a cleaner excuse. Flag the symbol and stop.

The report names files, how many comments you would delete, each `MUST KILL` on one line, and each keep with its clause.

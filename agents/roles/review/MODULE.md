# agents/roles/review/MODULE.md
# Review module — Layer 2 domain context.
# Covers: all post-build code review roles on Agent-03.

## Module Scope
The review module contains the four specialized reviewers that evaluate code
quality, correctness, policy compliance, and performance. All four are part of
the mandatory 4-reviewer sign-off pipeline (Rule 8).

## Reviewer Responsibilities
| Role | What It Checks |
|---|---|
| Fix Reviewer | Correctness of a bug fix — does it actually solve the problem? |
| Policy Reviewer | Adherence to platform rules 1–9 and architectural patterns |
| Logic Reviewer | Implementation correctness, edge cases, business logic accuracy |
| Perf Reviewer | N+1 queries, unbounded loops, render bottlenecks, token waste |

## Shared Review Standards
- Every finding must cite file:line
- Verdicts are binary: PASS or FAIL (WARN is advisory, does not block)
- A FAIL verdict immediately blocks the branch — no partial merges
- Reviewers work from the merge-base diff, not the full file
- Agents on old branches (far behind master) need cherry-pick to fresh branch

## Output Standard (all reviewers)
```
{ROLE} REVIEW — ticket #{ticket_id}
Branch: {branch}
Verdict: PASS | FAIL

Findings:
- [FAIL] {file}:{line} — {description}
- [WARN] {file}:{line} — {description}
```

## Key References
- Review scripts: `agents/review-pipeline.sh`, `agents/collect-reviews.sh`
- Never-do rules: `docs/05-agents/langgraph-never-do.md`

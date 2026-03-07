# agents/roles/pipeline/MODULE.md
# Pipeline module — Layer 2 domain context.
# Covers: code review pipeline execution and audit filter review.

## Module Scope
The pipeline module manages the multi-reviewer code review pipeline that every
branch must pass before merge. It coordinates the 4-reviewer sign-off process
and handles audit filter reviews.

## The 4-Reviewer Pipeline
Every feature branch must receive PASS from all four reviewers:
| Reviewer | Server | Checks |
|---|---|---|
| Security Reviewer | Agent-02 | Secrets, tenant isolation, auth bypass |
| Logic Reviewer | Agent-03 | Correctness, edge cases, business logic |
| Perf Reviewer | Agent-03 | N+1s, unbounded queries, render bottlenecks |
| Build Validator | Agent-04 | Zero compile errors, zero lint errors |

Run: `./agents/review-pipeline.sh <branch>`
Collect: `./agents/collect-reviews.sh --wait <branch>`

## Pipeline States
- `pending` — branch submitted, reviews not yet started
- `in-review` — one or more reviewers active
- `blocked` — one or more FAIL verdicts received
- `approved` — all 4 reviewers returned PASS
- `merged` — branch merged to master

## Audit Filter Scope
Audit filters apply when a task requires compliance or data-access review:
- Verify DB queries have correct tenant scoping
- Check INNGEST job payloads contain no cross-tenant data
- Validate JSONB field access uses correct operators (`->>` not `->` for text)

## Key References
- Review scripts: `agents/review-pipeline.sh`, `agents/collect-reviews.sh`
- Build validation: `agents/roles/enforcement/build-validator/ROLE.md`

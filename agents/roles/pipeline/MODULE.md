# agents/roles/pipeline/MODULE.md
# Pipeline module — Layer 2 domain context.
# Covers: code review pipeline execution and audit filter review.

## Module Scope
The pipeline module manages the multi-reviewer code review pipeline that every
branch must pass before merge. It coordinates the 4-reviewer sign-off process
and handles audit filter reviews.

## The 4-Reviewer Pipeline
Reviewer set, commands, and blocking semantics: `agents/GLOBAL.md` Rule 7.
Server/role placement: `agents/SERVERS.md`.

## Pipeline States
- `pending` — branch submitted, reviews not yet started
- `in-review` — one or more reviewers active
- `blocked` — one or more FAIL verdicts received
- `approved` — all 4 reviewers returned PASS
- `merged` — branch merged to master

## Audit Filter Scope
Audit filters apply when a task requires compliance or data-access review:
- Check INNGEST job payloads contain no PII or cross-tenant data
- Verify GLOBAL Rules 1–8 + ⚠ FAIL causes apply to the diff (tenant scoping, JSONB operators)

## Key References
- Review scripts: `agents/review-pipeline.sh`, `agents/collect-reviews.sh`
- Build validation: `agents/roles/enforcement/build-validator/ROLE.md`

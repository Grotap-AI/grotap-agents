# agents/roles/enforcement/build-validator/ROLE.md
# Role: Build Validator | Server: Agent-04 | Module: enforcement
# Trigger: task.type == 'build' OR task.stage == 'build-validation'

## Role Purpose
Confirm the branch compiles and lints with zero errors before merge.
This is the final gate before a branch is approved for deployment.

## Validation Checklist
1. Run TypeScript compile: confirm zero type errors
2. Run lint: confirm zero `noUnusedLocals` violations (unused imports = FAIL)
3. Confirm no `// @ts-ignore` or `// eslint-disable` added without justification
4. Run backend: confirm FastAPI starts without import errors
5. Confirm Railway health check routes exist:
   `@router.get("")` AND `@router.get("/")` on health router
6. Confirm OPTIONS requests bypass auth middleware (CORS preflight)
7. Check agent-worker Dockerfile uses `npm install` not `npm ci`
   (no package-lock.json present)

## Output Format
```
BUILD VALIDATION — ticket #{ticket_id}
Branch: {branch}
Verdict: PASS | FAIL

Errors:
- [TS] {file}:{line} — {error}
- [LINT] {file}:{line} — {error}
- [RUNTIME] {description}
```

## Handoff
PASS → none (terminal — branch approved for merge and deploy)
FAIL → agent-04 / execute (fix build errors)
next_server: [per verdict]
next_role: [per verdict]
priority: normal

## Handoff Template
---
generated_at_commit: {SESSION_COMMIT}
generated_at_timestamp: {SESSION_TIMESTAMP}
generated_by_role: build-validator
generated_by_server: agent-04
ticket_id: {ticketId}

## Staleness Declaration
# Receiving agent MUST compare generated_at_commit to SESSION_COMMIT.
# If they differ: prepend '⚠️ STALE HANDOFF' and re-read MODULE.md + ROLE.md.

## Task Context
module: enforcement
task_type: build
ticket_description: {description}

## Outputs
verdict: PASS | FAIL
ts_errors: {count}
lint_errors: {count}
fastapi_starts: YES | NO
health_routes_present: YES | NO

## Next Role
next_role: none | execute
next_server: none | agent-04
priority: normal

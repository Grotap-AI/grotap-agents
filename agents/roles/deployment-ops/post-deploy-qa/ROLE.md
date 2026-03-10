# agents/roles/deployment-ops/post-deploy-qa/ROLE.md
# Role: Post-Deploy QA | Server: Agent-06 | Module: deployment-ops
# Trigger: deploy-verifier verdict == PASS OR task.type == 'post-deploy-qa'

## Role Purpose
Run automated smoke tests against live production endpoints after every deployment.
Catches regressions that pass build validation but break in production — wrong env vars,
missing DB migrations, auth middleware errors, broken routes.

## Failure Patterns This Role Catches
1. FastAPI starts but request.state.organization_id throws AttributeError (wrong middleware var)
2. Frontend loads but routes return blank page (missing component import)
3. API returns 200 but response body is empty or error JSON
4. Auth callback fails (WorkOS staging vs production key mismatch)
5. Database queries fail (missing migration, wrong connection string)
6. CORS preflight fails (OPTIONS not bypassing auth middleware)

## Smoke Test Routes

### Backend API (api.grotap.com)
| Route | Method | Auth | Expected |
|---|---|---|---|
| /health | GET | None | 200 + JSON body |
| /health/ | GET | None | 200 + JSON body |
| /apps | GET | Bearer | 200 + array |
| /brands/by-domain?hostname=apps.grotap.com | GET | None | 200 + brand object |
| /apps | OPTIONS | None | 200 (CORS preflight) |

### Frontend (apps.grotap.com)
| Route | Expected |
|---|---|
| / | 200 + HTML with React root |
| /apps/buy | 200 + HTML |
| /billing | 200 + HTML |
| /support | 200 + HTML |

## Validation Criteria
- Response status code == 200
- Response body length > 20 characters (catches empty responses)
- Response body does NOT contain "error", "exception", "traceback" (case-insensitive)
- Response time < 5 seconds
- CORS headers present on OPTIONS responses

## Output Format
```
POST-DEPLOY QA — ticket #{ticket_id}
Commit: {commit_sha}
Timestamp: {timestamp}

Backend:
- GET /health: {status} ({response_time}ms) — {body_length} chars
- GET /health/: {status} ({response_time}ms) — {body_length} chars
- GET /apps: {status} ({response_time}ms) — {body_length} chars
- GET /brands/by-domain: {status} ({response_time}ms) — {body_length} chars
- OPTIONS /apps: {status} — CORS: {present|missing}

Frontend:
- GET /: {status} ({response_time}ms) — {body_length} chars
- GET /apps/buy: {status} ({response_time}ms) — {body_length} chars

Errors Detected:
- {list of any error/exception strings found in responses}

Verdict: PASS | FAIL
```

## Handoff
PASS → none (terminal — deployment confirmed live and working)
FAIL → deploy-executor (rollback or hotfix)
next_server: agent-06
next_role: deploy-executor
priority: critical

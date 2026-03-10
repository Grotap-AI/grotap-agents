# agents/roles/deployment-ops/env-validator/ROLE.md
# Role: Env Validator | Server: Agent-06 | Module: deployment-ops
# Trigger: task.type == 'env-validate' OR before any deploy-execute

## Role Purpose
Validate that all required secrets and environment variables exist in Doppler
across both dev and prd configs. Catches the failure pattern where 9 secrets
were missing from prd, blocking all production deployments.

## Failure Patterns This Role Catches
1. Secret exists in dev but missing from prd (production deploy fails)
2. Secret exists in prd but missing from dev (local dev works, CI fails)
3. Secret value is empty or placeholder
4. New service added but its secrets not added to Doppler
5. WorkOS staging vs production key mismatch
6. HETZNER_API_TOKEN or HETZNER_API_TOKEN_2 expired/invalid

## Required Secrets Checklist
All of these MUST exist in BOTH dev and prd configs:

### Core Platform
- WORKOS_API_KEY
- WORKOS_CLIENT_ID
- DATABASE_URL (control plane Neon)
- TENANT_DATABASE_URL (grotap tenant Neon)

### Deployment
- VERCEL_TOKEN
- RAILWAY_TOKEN

### AI / Agents
- ANTHROPIC_API_KEY
- LANGCHAIN_API_KEY (same as LANGSMITH_API_KEY)
- LANGSMITH_API_KEY
- INNGEST_EVENT_KEY
- INNGEST_SIGNING_KEY

### Infrastructure
- HETZNER_API_TOKEN
- HETZNER_API_TOKEN_2
- DOPPLER_TOKEN

### Security
- GITGUARDIAN_API_KEY
- PAGEINDEX_API_KEY

## Validation Steps
1. List all secrets in dev: `doppler secrets --project grotap --config dev`
2. List all secrets in prd: `doppler secrets --project grotap --config prd`
3. Diff the two lists — any key in one but not the other = FAIL
4. Check for empty values = FAIL
5. Validate Hetzner tokens: `curl -s -H "Authorization: Bearer $TOKEN" https://api.hetzner.cloud/v1/servers` → not "unauthorized"
6. Validate WorkOS: confirm CLIENT_ID matches expected environment (staging vs production)

## Output Format
```
ENV VALIDATION — ticket #{ticket_id}
Timestamp: {timestamp}

Config Parity:
- dev secrets count: {n}
- prd secrets count: {n}
- Missing from prd: {list}
- Missing from dev: {list}
- Empty values: {list}

Token Validity:
- HETZNER_API_TOKEN: VALID | INVALID
- HETZNER_API_TOKEN_2: VALID | INVALID
- VERCEL_TOKEN: VALID | INVALID

Verdict: PASS | FAIL
```

## Handoff
PASS → deploy-executor (cleared to deploy)
FAIL → human escalation (fix secrets before deploying)
next_server: agent-06
next_role: deploy-executor
priority: high

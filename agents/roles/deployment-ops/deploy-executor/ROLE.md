# agents/roles/deployment-ops/deploy-executor/ROLE.md
# Role: Deploy Executor | Server: Agent-06 | Module: deployment-ops
# Trigger: deploy-verifier verdict == FAIL OR task.type == 'deploy-execute'

## Role Purpose
Execute deployments that didn't happen automatically or failed.
This is the role that actually runs the Vercel CLI deploy command and
triggers Railway redeployments when auto-deploy fails.

## Failure Patterns This Role Fixes
1. Vercel frontend never deployed (manual step forgotten) → run Vercel CLI
2. Railway auto-deploy failed with "no associated build" → trigger manual redeploy via API
3. Railway deploy stuck in BUILDING → cancel and redeploy
4. Individual Railway service failed → redeploy only that service

## Pre-Flight Checks (MUST pass before deploying)
1. Confirm env-validator has run and passed (secrets are in sync)
2. Confirm build-validator passed on the branch/commit being deployed
3. Confirm the commit being deployed matches master HEAD

## Deployment Commands

### Vercel Frontend
```bash
VTOKEN=$(doppler secrets get VERCEL_TOKEN --project grotap --config prd --plain)
cd platform/frontend && npx vercel --token "$VTOKEN" --prod --yes
```

### Railway Backend (manual redeploy when auto-deploy fails)
```bash
# Use Railway CLI
cd platform/backend && doppler run --project grotap --config dev -- railway up --detach --service grotap-backend

# Or Railway API for specific service
railway deployment list --service grotap-backend
```

### Railway Agent-Worker
```bash
# Must use service ID — name lookup fails
railway up --detach --service 18c95d3f-c41a-43e8-a552-c358491856af
```

## Post-Deploy Verification
After executing deploy, MUST hand off to deploy-verifier to confirm success.
Do NOT assume the deploy worked — verify it.

## Output Format
```
DEPLOY EXECUTION — ticket #{ticket_id}
Commit: {commit_sha}
Action: {vercel-deploy | railway-redeploy | railway-cancel-redeploy}
Service: {service_name}
Result: SUCCESS | FAILED
Error: {error_message if failed}
```

## Handoff
SUCCESS → deploy-verifier (re-verify everything is live)
FAILED → escalate to human (deployment infrastructure issue)
next_server: agent-06
next_role: deploy-verifier
priority: critical

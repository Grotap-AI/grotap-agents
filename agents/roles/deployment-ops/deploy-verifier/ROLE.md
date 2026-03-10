# agents/roles/deployment-ops/deploy-verifier/ROLE.md
# Role: Deploy Verifier | Server: Agent-06 | Module: deployment-ops
# Trigger: event == 'merge-to-master' OR task.type == 'deploy-verify'

## Role Purpose
Confirm that code merged to master actually deployed successfully to production.
This role exists because merging code does NOT guarantee it is live — Vercel requires
manual deploy, Railway auto-deploy can fail silently, and nobody was checking.

## Failure Patterns This Role Catches
1. Vercel frontend not deployed after merge (manual deploy forgotten)
2. Railway backend deploy stuck in BUILDING or FAILED status
3. Railway deploy succeeds but health check fails (app crash on startup)
4. Agent-worker deploy fails due to npm install issues (no package-lock.json)
5. Ingestion-worker deploy fails silently

## Verification Checklist
1. Check Railway deployment status for ALL 3 services:
   - grotap-backend (6cad7f74-9329-406e-b733-719a33c53ac3)
   - grotap-ingestion-worker (179c40ce-cd06-4c66-a10b-35b347f1ac67)
   - grotap-agent-worker (18c95d3f-c41a-43e8-a552-c358491856af)
   - Confirm status == SUCCESS, not BUILDING or FAILED
2. Check Vercel deployment status:
   - Compare latest Vercel deploy commit to master HEAD
   - If mismatch → FAIL (frontend not deployed)
3. Check health endpoints respond:
   - GET https://api.grotap.com/health → 200
   - GET https://apps.grotap.com → 200
4. Check response times are within acceptable range (< 5s)

## Output Format
```
DEPLOY VERIFICATION — ticket #{ticket_id}
Commit: {commit_sha}
Timestamp: {timestamp}

Railway:
- grotap-backend: SUCCESS | BUILDING | FAILED
- grotap-ingestion-worker: SUCCESS | BUILDING | FAILED
- grotap-agent-worker: SUCCESS | BUILDING | FAILED

Vercel:
- Latest deploy commit: {vercel_commit} vs master HEAD: {master_commit}
- Match: YES | NO

Health:
- api.grotap.com/health: {status_code} ({response_time}ms)
- apps.grotap.com: {status_code} ({response_time}ms)

Verdict: PASS | FAIL
Failures: {list of failures}
```

## Handoff
PASS → post-deploy-qa (smoke test live endpoints)
FAIL → deploy-executor (trigger redeployment)
next_server: agent-06
next_role: post-deploy-qa | deploy-executor
priority: high

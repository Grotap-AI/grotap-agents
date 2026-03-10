# agents/roles/deployment-ops/MODULE.md
# Deployment Operations module — Layer 2 domain context.
# Covers: deploy verification, execution, env validation, health monitoring, DNS, post-deploy QA.

## Module Scope
The deployment-ops module ensures that every merge to master actually reaches
production — Railway, Vercel, and all infrastructure. It catches the gap between
"code merged" and "code live" that has caused repeated silent failures.

## Why This Module Exists
Documented failure patterns that prompted this module:
1. Vercel does NOT auto-deploy — every frontend change requires manual CLI deploy
2. Railway auto-deploy sometimes fails silently ("no associated build")
3. Doppler secrets missing from prd config blocked all production deploys
4. DNS wildcard misconfiguration routed API traffic to Vercel instead of Railway
5. Agents complete code work, push, and assume it's live — nobody verifies
6. Health check routes missing or misconfigured cause Railway deploy to hang
7. WorkOS staging vs production key mismatch caused auth failures

## Role Summary
| Role | When It Runs | What It Checks |
|---|---|---|
| Deploy Verifier | After every merge to master | Railway + Vercel deploy status = SUCCESS |
| Deploy Executor | After build-validator PASS | Runs manual Vercel deploy + confirms Railway auto-deploy |
| Env Validator | Before deploy OR on schedule | Doppler dev/prd secret parity, required env vars present |
| Health Monitor | Continuous / on schedule | Polls api.grotap.com/health, apps.grotap.com, agents.grotap.com |
| DNS Watchdog | On schedule / after infra changes | DNS records match expected targets, no wildcard drift |
| Post-Deploy QA | After deploy-verifier confirms live | Smoke tests against live endpoints, catches regressions |

## Authority
- Deploy Verifier FAIL → blocks next task dispatch (code is merged but not live)
- Health Monitor FAIL → escalates to deploy-executor for redeployment
- Env Validator FAIL → blocks deploy-executor from proceeding
- Any role can escalate to agent-04/execute for hotfix if live is broken

## Server Assignment
All deployment-ops roles run on Agent-06 (cpx31 / 4 vCPU / 8 GB / Hillsboro).
Agent-06 is the ops/monitoring server — it does not run dev tasks.

## Key References
- Vercel manual deploy: `doppler secrets get VERCEL_TOKEN` + `npx vercel --prod --yes`
- Railway verify: `railway deployment list --service grotap-backend` → confirm SUCCESS
- Railway services: backend=6cad7f74, ingestion=179c40ce, agent-worker=18c95d3f
- Doppler: project=grotap, configs=dev+prd
- DNS: apps.grotap.com → Vercel, api.grotap.com → Railway, agents.grotap.com → Vercel
- Health endpoint: GET api.grotap.com/health

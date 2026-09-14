# agents/roles/deployment-ops/MODULE.md
# Deployment Operations module — Layer 2 domain context.
# Covers: deploy verification, execution, env validation, health monitoring, DNS, post-deploy QA.

## Module Scope
The deployment-ops module ensures that every merge to master actually reaches
production — Railway, Vercel, and all infrastructure. It catches the gap between
"code merged" and "code live" that has caused repeated silent failures.

## Why This Module Exists
Documented failure patterns that prompted this module:
1. Frontend deploys via CI (`deploy-frontend.yml`, paths `frontend/**`) — merges touching only other paths don't redeploy it, and a failed CI run silently leaves prod stale
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
| Deploy Executor | Deploy-verifier FAIL | Manual Vercel/Railway (re)deploy when CI/auto-deploy failed |
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

## Railway Service IDs (canonical copy — ROLE files reference this table)
| Service | ID |
|---|---|
| grotap-backend | 6cad7f74-9329-406e-b733-719a33c53ac3 |
| grotap-ingestion-worker | 179c40ce-cd06-4c66-a10b-35b347f1ac67 |
| grotap-agent-worker | 18c95d3f-c41a-43e8-a552-c358491856af |

## Expected DNS (canonical copy — ROLE files reference this table)
| Record | Type | Target | Notes |
|---|---|---|---|
| apps.grotap.com | CNAME (DNS-only, TTL 300) | ec9a3efc9f58a0b1.vercel-dns-016.com | Vercel frontend — explicit record `c7d600d7c8a008bf095b0d4de1b6e28d` created 2026-09-14 |
| app.grotap.com | CNAME (DNS-only, TTL 300) | ec9a3efc9f58a0b1.vercel-dns-016.com | Vercel alias (308 → apps) — explicit record `060e898ace536cfed0926185b90dce10` created 2026-09-14 |
| agents.grotap.com | CNAME (DNS-only, TTL 300) | ec9a3efc9f58a0b1.vercel-dns-016.com | Agents brand frontend — explicit record `7570e19998438f37ff5993fd0f8b5b4b` created 2026-09-14 |
| api.grotap.com | CNAME (proxied) | grotap-backend-production.up.railway.app | Backend API |
| www.grotap.com | CNAME | cname.vercel-dns.com | grotap-landing (apex is A 76.76.21.21) |
| agents.grotap.ai | CNAME | cname.vercel-dns.com | Agents brand (.ai TLD, separate zone) |
| *.grotap.com | — | MUST NOT EXIST | Wildcard (→ vercel-dns-016, created 2026-07-19) REMOVED 2026-09-14 — apps/app/agents had been resolving only through it; rollback JSON `agents/logs/dns-wildcard-removed-20260914.json`. Never re-add; a new brand host needs its own explicit Cloudflare CNAME (provisioner fix filed 2026-09-14). |

## Key References
- Vercel manual deploy: `doppler secrets get VERCEL_TOKEN` + `npx vercel --prod --yes`
- Railway verify: `railway deployment list --service grotap-backend` → confirm SUCCESS
- Doppler: project=grotap, configs=dev+prd
- Health endpoint: GET api.grotap.com/health

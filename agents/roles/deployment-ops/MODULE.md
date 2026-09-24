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
- Any role can escalate to agent-04-claude/execute for hotfix if live is broken

## Server Assignment
All deployment-ops roles run on agent-06-claude (cpx31 / 4 vCPU / 8 GB / Ashburn, `5.161.53.103`).
agent-06-claude is the ops/monitoring server — it does not run dev tasks. The old Hillsboro address `5.78.178.81` is released.

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


### Who writes these records, and what silently does not get written (CASE-20260914-7D138E)
Per-brand/app hosts are created by `brand_provisioner.py` calling `cloudflare_dns_provider.py`,
one explicit `<app-slug>.grotap.com CNAME <vercel-target>` per provisioned tenant app. There is no
wildcard to fall back on (see the last table row), so an unprovisioned or mistyped subdomain
returns NXDOMAIN — the safe default, and the reason a missing record shows up as a dead host
rather than as traffic reaching the wrong app. Each explicit CNAME resolves to Vercel edge IPs.
That is the whole argument against ever re-adding the wildcard: it would forward EVERY subdomain
to Vercel regardless of provisioning state, which both masks provisioning errors and creates an
open-redirect risk, where a host nobody provisioned still answers.

Two secrets gate that write, both on `grotap-backend` and both in `REQUIRED_VARS` in
`scripts/railway_secret_audit.py`:

| Var | Purpose | Absent behaviour |
|---|---|---|
| `CLOUDFLARE_EDGE_TOKEN` | DNS write token scoped to the grotap.com zone | provisioner logs a warning, SKIPS the DNS step, and reports success — the tenant subdomain is simply never created |
| `CLOUDFLARE_ZONE_ID_GROTAP_COM` | Zone ID, avoids a Zones API lookup | extra round trip; fails outright if the edge token lacks Zones:Read |

The edge token's silent skip is the failure worth knowing: provisioning "succeeds" and the host
does not resolve. NXDOMAIN on a host that should exist means provisioning was incomplete or the
CNAME was deleted — re-run the provisioner rather than hand-adding a record, so the table above
stays the only source of truth. Token scopes and rotation history live in
`docs/06-infrastructure/cloudflare-access-forge.md`.

## Key References
- Vercel manual deploy: `doppler secrets get VERCEL_TOKEN` + `npx vercel --prod --yes`
- Railway verify: `railway deployment list --service grotap-backend` → confirm SUCCESS
- Doppler: project=grotap, configs=dev+prd
- Health endpoint: GET api.grotap.com/health

# Platform Build — Project Status
*Last updated: 2026-07-05 (keep this file to ~25 lines; details live in the Reports app + docs/)*

## What We're Building
Multi-tenant AI-powered ERP/SaaS platform. Every feature is a discrete app; tenants subscribe to apps.
- Tenancy: Neon Postgres, pooled shards + FORCE RLS by default; dedicated project = premium placement
- An agent fleet (Claude Code on Hetzner + LangGraph orchestrator on Railway) builds the platform itself:
  pipeline cases → continuous dispatch → 4-reviewer gate → merge to prod
- Enterprise auth (WorkOS), billing (Stripe), jobs (Inngest), storage (R2), mobile (Expo), cobrowse (Cobrowse.IO)

**Code:** `C:\1Claude\platform\` · **Agent brain:** `C:\1Claude\agents\GLOBAL.md` · **Docs:** `C:\1Claude\docs\00-INDEX.md`

## Live Services
| Service | URL |
|---|---|
| Frontend (React + Vercel) | apps.grotap.com / agents.grotap.ai |
| Backend (FastAPI + Railway) | api.grotap.com |
| Marketing site (Vercel, grotap-landing repo) | grotap.com |
| Control plane DB (Neon) | `green-rice-76766370` |
| Reports (GitHub Pages) | grotap1.github.io/Reports |

## Current State (2026-07-05)
- Two brands live (Grotap Apps, Grotap AI Agents); app catalog with voting/building/beta/live lifecycle
- Pipeline runs CONTINUOUSLY (3-min assign loop + webhook refill); review gate every 4h on agent-06
- Fleet: agent-02…06 executing (roster: `agents/SERVERS.md`); staging SUSPENDED (ships master → prod)
- Scale program (pooled tenancy, RLS, migration runner) executed; ScanTap + Manor View Farm onboarded
- Secrets: Doppler only. DR backup to Wasabi nightly from agent-06.

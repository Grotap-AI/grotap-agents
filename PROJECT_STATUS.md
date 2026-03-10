# Platform Build — Project Status
*Last updated: 2026-03-09*

---

## What We're Building
Multi-tenant AI-powered ERP/SaaS platform.
- Every tenant gets an isolated Neon Postgres database
- AI agents (Claude Code + LangGraph) handle build, automation, and orchestration
- Knowledge lives in Neon + PageIndex, queryable by agents at runtime
- Enterprise auth (WorkOS), billing (Stripe), mobile (Expo), screen sharing (Cobrowse)

**Code:** `C:\Grotap\platform\`
**Master docs:** `C:\1Claude\docs\CLAUDE.md`
**Full doc index:** `C:\1Claude\docs\00-INDEX.md`

---

## Live Services

| Service | URL |
|---|---|
| Frontend (React + Vercel) | apps.grotap.com / agents.grotap.ai |
| Backend (FastAPI + Railway) | api.grotap.com |
| Control Plane DB (Neon) | green-rice-76766370 |

---

## Doppler Secrets — ALL SET

Project: `grotap`, config: `prd`
All secrets populated including STRIPE_WEBHOOK_SECRET, COBROWSE_API_KEY, EXPO_TOKEN.

---

## Current State (as of 2026-03-09)

### Multi-Brand Platform — LIVE
- 2 brands: Grotap Apps (apps.grotap.com), Grotap AI Agents (agents.grotap.ai)
- 22 apps total. Grotap Apps: 19 assigned. Grotap AI Agents: 11 assigned.
- Brand resolution via hostname. BrandContext injects CSS vars.
- WorkOS redirect URIs configured for both brands.

### Platform Framework — LIVE
- TopNav: platform tabs only (My Apps, Add Apps, Beta Apps, Suggest a New App). No hardcoded admin links.
- All apps use AppSidebar (dark left nav with Help Menu, Back to Apps, user email)
- Brand Management: AppSidebar, grid with Brand Name/Origin Site/# Apps/# Subscribers/3-dot menu
- App Manager: AppSidebar, split views (App Status + Brands & Price)
- App statuses: New Idea, Approved in Queue, In Progress, In Beta, Live

### Pipeline App — Feature Branches (968-973)
- Agent teams, status simplification, rich description, cobrowse forwarding, approvals gate, beta link

### Agentic Workflow — Feature Branches (974-980)
- Co-plan gate, trust scores, knowledge curation, SOP ingestion, automation levels, agent registry, eval pipeline

### Agent Infrastructure
- 6 Hetzner servers (agent-01 through agent-06), 3 concurrent task slots per server via git worktrees
- **Primary executors**: Agent-01, Agent-04 — always first choice for execution tasks
- **Overflow executors**: Agent-02, Agent-03, Agent-05 — execute when slots available, primary roles take priority
- **Total capacity**: 15 concurrent tasks (5 task servers x 3 slots) + Agent-06 (deploy ops)
- `dispatch.sh` — worktree-isolated task dispatch (each task gets `/home/agent/worktrees/<session>/`)
- `dispatch-execute.sh` — auto-routes to server with most free slots (primary first, then overflow)
- `server-status.sh` — shows slots used/available, CPU, memory, load across all servers
- Task lifecycle folders (pending/active/done/archive) are gitignored
- ~280 tasks dispatched across sessions (669-933, 968-980)

---

## Build Phases

### Phase 1 — Foundation — LIVE
WorkOS auth, Neon control plane, FastAPI on Railway, Doppler secrets

### Phase 2 — Knowledge Layer — LIVE
Cloudflare R2, PageIndex, Neon + PageIndex trees, INNGEST ingestion pipeline

### Phase 3 — Agent Layer — LIVE
LangGraph + LangSmith, Central Event Bus, GitGuardian MCP, Terraform + Hetzner

### Phase 4 — Product Layer — LIVE
React frontend, Stripe billing, Cobrowse.IO, Expo mobile

### Wave 2 — App Platform + RFID Pipe — LIVE
Universal AppSidebar, Help Menu, Support screens, RFID Pipe (22 endpoints, 4 pages)

### Wave 3 — Multi-Brand + Cleanup — LIVE
Multi-brand schema, brand resolution, 22 apps, platform cleanup, framework cleanup

### Wave 4 — Pipeline + Agentic (feature branches, not yet merged)
Pipeline enhancements (968-973), Agentic workflow (974-980)

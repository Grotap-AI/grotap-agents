# CLAUDE.md — Platform Agent Context
> Rules are in `agents/GLOBAL.md`. Do not duplicate them here.

## Secrets — Doppler Only
```
Project: grotap | Configs: dev (local) / prd (Railway + Vercel auto-sync)
Add secret: doppler secrets set KEY="val" --project grotap --config dev  (repeat for prd)
Never add secrets any other way.
```

## Stack
| Layer | Tech | URL / Location |
|---|---|---|
| Frontend | React + Vercel | grotapfrontend.vercel.app → `platform/frontend/` |
| Backend | FastAPI + Railway | grotap-backend-production.up.railway.app → `platform/backend/` |
| Auth | WorkOS | Enterprise SSO, multi-tenant JWT |
| Database | Neon (db-per-tenant) | control: `green-rice-76766370` |
| Knowledge | PageIndex | reasoning-based retrieval |
| Jobs | INNGEST | durable background workflows |
| Agents | LangSmith + LangGraph | TypeScript only |
| Storage | Cloudflare R2 | hot → PageIndex ingestion |
| Backup | Wasabi | cold long-term |
| Infra | Terraform + Hetzner | Linux agent farm |
| Billing | Stripe | per-tenant metering |
| Mobile | Expo MCP | React Native |
| Cobrowse | Cobrowse.IO | AI-agent co-browsing |
| Secret Scan | GitGuardian MCP | pre-commit compliance |

## Key Patterns
- **Multi-tenant**: WorkOS JWT → FastAPI middleware → `organization_id` → Neon per request
- **Vendor Wrapper**: All 3rd-party SDKs in `app/providers/` — never call SDKs directly
- **Doc flow**: Upload → R2 → INNGEST → PageIndex → tree in tenant Neon → agent queries

## App Platform
Every feature = discrete app in `apps` control-plane table.
- **New app**: clone `platform/app-template/`, build in `src/features/`, POST `/app-registry/register`
- **Access**: WorkOS Feature per app slug — enable/disable on subscribe/cancel
- **Revenue**: Grotap 20%, creator 80% → `app_earnings` table
- **Internal**: `is_internal=true` → visible only to `@grotap.com` users
- **All apps**: must use `AppShell` (Rule 9 in GLOBAL.md)

## Docs Index
`docs/00-INDEX.md` → `01-platform` `02-auth` `03-database` `04-knowledge` `05-agents` `06-infrastructure` `07-jobs` `08-storage` `09-frontend` `10-billing` `11-devops` `12-app-platform`

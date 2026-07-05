# CLAUDE.md — Platform Agent Context
> Rules + stack table are in `agents/GLOBAL.md`. Do not duplicate them here.

## Secrets — Doppler Only
Project: `grotap` | Configs: `dev` (local) / `prd` (Railway + Vercel auto-sync)
`doppler secrets set KEY="val" --project grotap --config dev` (repeat for prd). Never add secrets any other way.

## Live URLs
Frontend apps.grotap.com (Vercel) · Backend api.grotap.com (Railway) · Marketing grotap.com (Vercel, grotap-landing repo)

## Key Patterns
- **Multi-tenant**: WorkOS JWT → FastAPI middleware → `organization_id` → tenant DB (pooled shard + FORCE RLS, or dedicated Neon)
- **Vendor Wrapper**: All 3rd-party SDKs in `app/providers/` — never call SDKs directly
- **Doc flow**: Upload → R2 → Inngest ingestion → tenant Neon

## App Platform
Every feature = discrete app in `apps` control-plane table.
- **New app**: clone `platform/app-template/`, build in `src/features/`, POST `/app-registry/register`
- **Access**: WorkOS Feature per app slug — enable/disable on subscribe/cancel
- **Revenue**: Grotap 20%, creator 80% → `app_earnings` table
- **Internal**: `is_internal=true` → visible only to `@grotap.com` users
- **All apps**: must use `AppShell` (Rule 8 in GLOBAL.md)

## Docs Index
`docs/00-INDEX.md` → `01-platform` `02-auth` `03-database` `04-knowledge` `05-agents` `06-infrastructure` `07-jobs` `08-storage` `09-frontend` `10-billing` `11-devops` `12-app-platform`

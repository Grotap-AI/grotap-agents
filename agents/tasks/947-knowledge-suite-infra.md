---
title: "feat: AI Knowledge Agents suite — infrastructure + DB setup (#947)"
branch: task/947-knowledge-suite-infra
complexity: complex
---

# Task 947 — AI Knowledge Agents Suite Infrastructure

## Context
We are building a suite of 3 AI Knowledge Agent apps (knowledge-manager, agent-manager, agent-teams) that share a per-tenant knowledge database. This task sets up the infrastructure: control plane migrations, app seeding, and the `suite_slug` concept.

## What Already Exists
- Phase 5 migration SQL files at `backend/migrations/phase5_app_schema_migrations.sql` and `phase5_suite_slug.sql`
- Control plane DB: `green-rice-76766370` (Neon MCP)
- Tenant DB: `proud-union-74070434` (Neon MCP)
- `apps` table and `tenant_app_subscriptions` table already exist
- Inngest `appKnowledgeQuery` function exists in ingestion-worker

## Requirements

### 1. Run Phase 5 Migrations on Control Plane
Run these on Neon project `green-rice-76766370`:
```sql
-- Add columns to apps table
ALTER TABLE apps ADD COLUMN IF NOT EXISTS db_schema TEXT;
ALTER TABLE apps ADD COLUMN IF NOT EXISTS migrations TEXT[];
ALTER TABLE apps ADD COLUMN IF NOT EXISTS business_rules_docs TEXT[];
ALTER TABLE apps ADD COLUMN IF NOT EXISTS suite_slug TEXT;
```

### 2. Add knowledge_project_id to organizations table
Per architecture decision: knowledge_project_id belongs on organizations, NOT apps.
```sql
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS knowledge_project_id TEXT;
```
Do NOT add knowledge_project_id to apps table.

### 3. Seed the 3 Knowledge Agent Apps
Insert into `apps` table on control plane (`green-rice-76766370`):

| slug | name | category | suite_slug | status |
|---|---|---|---|---|
| knowledge-manager | Knowledge Manager | ai-knowledge | ai-knowledge | beta |
| agent-manager | Agent Manager | ai-knowledge | ai-knowledge | beta |
| agent-teams | Agent Teams | ai-knowledge | ai-knowledge | beta |

All three should have: `is_free = false`, `is_internal = false`, `has_mobile = false`

### 4. Seed Tenant Subscriptions
Insert into `tenant_app_subscriptions` for the default Grotap tenant (query organizations table to get tenant_id):
- Subscribe default tenant to all 3 apps with status = 'active'

### 5. Cleanup: Remove rfid-pipe knowledge references
- In `phase5_suite_slug.sql`, the line setting `knowledge_project_id = 'falling-brook-32044564'` for rfid-pipe is WRONG. Do NOT run that line.
- rfid-pipe is a regular app, NOT part of the AI Knowledge suite.

## Backend Changes

### Update control_plane.py seeding
File: `backend/app/database/control_plane.py`
Add the 3 new apps to the seed list so they get created on fresh installs.

## Verification
- Query `SELECT slug, suite_slug FROM apps WHERE suite_slug = 'ai-knowledge'` — should return 3 rows
- Query `SELECT * FROM tenant_app_subscriptions WHERE app_id IN (SELECT app_id FROM apps WHERE suite_slug = 'ai-knowledge')` — should return 3 active rows
- Verify `organizations` table has `knowledge_project_id` column

## Important Rules
- Use `request.state.organization_id` NOT `request.state.tenant_id` in any backend code
- Run all SQL via Neon MCP, never tell user to run SQL manually
- Do NOT create standalone Vite apps — all code lives in main frontend/backend

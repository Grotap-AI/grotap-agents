---
title: "feat: per-tenant knowledge DB provisioning + cleanup (#951)"
branch: task/951-knowledge-provisioning
complexity: medium
---

# Task 951 — Per-Tenant Knowledge DB Provisioning + Cleanup

## Context
When a tenant subscribes to the AI Knowledge Agents suite, they need a dedicated Neon knowledge project provisioned. This task builds the provisioning flow and cleans up the wrong rfid-pipe-knowledge project reference.

## What Already Exists
- Inngest `app/knowledge.query-requested` function in `ingestion-worker/src/functions/appKnowledgeQuery.ts`
- Inngest `app/schema.provision-requested` in `ingestion-worker/src/functions/appSchemaProvision.ts`
- Organizations table in control plane with new `knowledge_project_id` column (added by task #947)
- Knowledge schema: documents, knowledge_trees, agent_learnings tables in tenant template

## Requirements

### 1. Inngest Function: Provision Knowledge DB
Create `ingestion-worker/src/functions/knowledgeProvision.ts`:

Trigger: `knowledge/provision-requested`
Input: `{ organization_id: string }`

Steps:
1. Check if organization already has `knowledge_project_id` set → skip if yes
2. Create new Neon project via Neon API (name: `knowledge-{org_id_short}`)
3. Run knowledge schema migration on new project:
   - Enable pgvector extension
   - Create `documents`, `knowledge_trees`, `agent_learnings` tables (use tenant_template.sql schema)
4. Update organizations table: SET `knowledge_project_id = '{new_project_id}'`
5. Return success with project_id

### 2. Inngest Function: Suspend Knowledge DB
Create `ingestion-worker/src/functions/knowledgeSuspend.ts`:

Trigger: `knowledge/suspend-requested`
Input: `{ organization_id: string }`

Steps:
1. Look up `knowledge_project_id` from organizations table
2. Suspend the Neon project (don't delete — data retention)
3. Log suspension event

### 3. Update appKnowledgeQuery to be tenant-scoped
File: `ingestion-worker/src/functions/appKnowledgeQuery.ts`

Current: looks up `knowledge_project_id` from `apps` table by app_slug
Change to: look up `knowledge_project_id` from `organizations` table by organization_id

This is the key architectural change — knowledge DB is per-tenant, not per-app.

### 4. Backend: Suite Subscribe/Unsubscribe Hooks
Add to `backend/app/routers/app_registry.py` (or create new router):

When subscribing to any app with `suite_slug = 'ai-knowledge'`:
- Check if tenant already has `knowledge_project_id`
- If not, emit Inngest event `knowledge/provision-requested` with `organization_id`
- Subscribe to all 3 suite apps at once (not just the one clicked)

When unsubscribing from last app in suite:
- Emit Inngest event `knowledge/suspend-requested` with `organization_id`

### 5. Cleanup
- Delete the Neon project `falling-brook-32044564` (rfid-pipe-knowledge) — this was created in error
- Remove `ingestion-worker/migrations/knowledge/rfid-pipe/` directory (v001_schema.sql, v002_seed.sql)
- Remove any references to `falling-brook-32044564` in codebase
- Do NOT remove the rfid-pipe app itself — only its wrong knowledge DB reference

## Verification
- After provisioning: organizations row should have knowledge_project_id set
- appKnowledgeQuery should use organizations.knowledge_project_id, not apps.knowledge_project_id
- rfid-pipe app should still work (it doesn't use knowledge DB)

## Important Rules
- Use `request.state.organization_id` NOT `request.state.tenant_id`
- All SQL via Neon MCP — never tell user to run manually
- No unused imports
- Neon project deletion is irreversible — confirm project ID before deleting

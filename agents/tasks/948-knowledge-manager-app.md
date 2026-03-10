---
title: "feat: Knowledge Manager app — upload/manage documents + PageIndex trees (#948)"
branch: task/948-knowledge-manager
complexity: complex
---

# Task 948 — Knowledge Manager App

## Context
Knowledge Manager is 1 of 3 apps in the AI Knowledge Agents suite (`suite_slug = 'ai-knowledge'`). It lets tenants upload, manage, and browse documents that feed the AI knowledge base. Documents are stored in Cloudflare R2, indexed via PageIndex, and searchable via Neon pgvector.

## What Already Exists
- `backend/app/routers/documents.py` — existing document upload router with R2 integration
- Tenant DB (`proud-union-74070434`) already has: `documents`, `knowledge_trees`, `agent_learnings` tables
- `frontend/src/pages/UploadPage.tsx` — existing basic upload page
- `frontend/src/pages/DashboardPage.tsx` — existing document dashboard
- Inngest `appKnowledgeQuery` function for querying knowledge
- App row in control plane DB (seeded by task #947)

## Requirements

### Frontend — KnowledgeManagerPage.tsx
Create `frontend/src/pages/KnowledgeManagerPage.tsx` with these sections:

**Tab 1: Documents**
- Table listing all documents for the tenant (from `documents` table)
- Columns: filename, content_type, status, department, tags, uploaded_by, created_at
- Upload button → opens file picker (PDF, Excel, Word, images)
- Upload calls existing document upload endpoint
- Status badges: uploaded (gray), processing (yellow), indexed (green), failed (red)
- Click row → expand to show PageIndex tree (from `knowledge_trees` table)

**Tab 2: Knowledge Trees**
- Visual tree browser showing PageIndex decision trees per document
- Expand/collapse tree nodes from `tree_json` JSONB field
- Search across trees by keyword

**Tab 3: Agent Learnings**
- Table of agent learnings from `agent_learnings` table
- Columns: work_area, content (truncated), confidence, source_session_id, indexed_at
- Filter by work_area
- Mark learnings as verified/rejected

### Backend — knowledge_manager.py
Create `backend/app/routers/knowledge_manager.py`:

```
GET  /knowledge-manager/documents          — list documents for tenant
POST /knowledge-manager/documents/upload    — upload document (delegate to existing documents.py logic)
GET  /knowledge-manager/documents/{id}      — get document detail
DELETE /knowledge-manager/documents/{id}    — soft-delete document

GET  /knowledge-manager/trees               — list knowledge trees
GET  /knowledge-manager/trees/{id}          — get tree detail with full tree_json

GET  /knowledge-manager/learnings           — list agent learnings
PATCH /knowledge-manager/learnings/{id}     — update learning (verify/reject)
```

All queries run against tenant DB (`proud-union-74070434`). Use `request.state.organization_id` for tenant scoping.

### Wiring
1. Add route to `App.tsx`: `/knowledge-manager` → `<PrivateRoute><><TopNav /><KnowledgeManagerPage /></></PrivateRoute>`
2. Add to `WorkspaceContext.tsx` APP_ROUTES: `'knowledge-manager': '/knowledge-manager'`
3. Add tile to `AppLibraryPage.tsx` MODULES array:
   - name: "Knowledge Manager", slug: "knowledge-manager", icon: appropriate icon, category: "AI Knowledge"
4. Add "AI Knowledge" to CATEGORIES array if not present
5. Register router in `backend/app/main.py`

## Important Rules
- Use `request.state.organization_id` NOT `request.state.tenant_id`
- All SQL via Neon MCP — never tell user to run manually
- No unused imports (tsconfig has `noUnusedLocals: true`)
- Follow `<PrivateRoute><><TopNav />...</>` pattern for routes
- App code lives in `frontend/src/pages/` — NOT in `platform/apps/`

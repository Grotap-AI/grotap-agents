---
title: "App Lifecycle — States, Transitions & Agent Build Process"
updated: 2026-03-05
doc_type: reference
category: architecture
tags: [app-lifecycle, agents, build-process, states]
status: active
---

# App Lifecycle

## Status States

```
idea_submitted → (admin accepts) → building → beta → active → deprecated
                 (admin rejects) → rejected
```

### `app_suggestions.status` (idea phase)
| Status | Meaning |
|---|---|
| `submitted` | Just submitted, awaiting community attention |
| `voting` | Admin opened for community voting |
| `accepted` | Admin accepted — triggers agent build pipeline |
| `rejected` | Admin rejected (with reason) |
| `building` | Agents actively building the app |
| `launched` | App is live — `linked_app_id` set |

### `apps.status` (app phase)
| Status | Meaning |
|---|---|
| `building` | Agents building — not visible in store |
| `beta` | Visible in Beta Apps tab — free to try |
| `active` | Visible in Buy Apps — paid subscription |
| `deprecated` | Hidden from store — existing subscribers still see it |

---

## Agent Build Pipeline

When an idea is accepted (`PATCH /app-suggestions/{id}/status` → `accepted`), Inngest fires `app/suggestion.accepted`.

### Inngest Function: `app/suggestion.accepted`
```
Step 1: Create GitHub branch: feature/app-{suggestion-id}
Step 2: Clone base template into platform/apps/{slug}/
Step 3: Write app.manifest.json from suggestion metadata
        → Must include: db_schema, migrations[], knowledge_project_id, business_rules_docs[]
Step 4: Agent creates platform/migrations/apps/{slug}/v001_initial.sql
        → Schema CREATE + all app tables with tenant_id + RLS on every table
        → Schema name = slug in snake_case (rfid-pipe → rfid_pipe)
Step 5: Dispatch to agent farm:
        - Agents receive: idea description, use_case, industry context
        - Agents build src/features/ (unique app functionality)
        - Agents must NOT modify AppShell, lib/cobrowse.ts, lib/api.ts
Step 6: Agent calls POST /app-registry/register with manifest
        → apps table row created with status='building'
Step 7: Agent runs Cobrowse snapshot tests (see cobrowse-snapshot-testing.md)
        → Test uses Neon branch snapshot (includes rfid_pipe schema)
Step 8: On test pass: status → 'beta'
Step 9: Notify submitter + grotap admin
```

### Optional: Customer Collaboration
Admin can invite the original idea submitter to a Cobrowse session with the agent during build.
- Agent shares screen (Agent Present Mode)
- Customer gives real-time feedback
- Feedback stored as `app_suggestion_votes.notes`

---

## Base App Template

Location: `platform/app-template/`

```
platform/app-template/
├── app.manifest.json          ← agents fill this in
├── src/
│   ├── App.tsx               ← routing scaffold (agents add routes here)
│   ├── features/             ← AGENTS BUILD HERE (empty, with README)
│   │   └── README.md
│   ├── lib/
│   │   ├── api.ts            ← JWT Axios client (pre-wired, DO NOT MODIFY)
│   │   └── cobrowse.ts       ← Cobrowse vendor wrapper (DO NOT MODIFY)
│   └── components/
│       └── AppShell.tsx      ← TopNav + Cobrowse overlays (DO NOT MODIFY)
├── package.json              ← same deps as main frontend
└── README.md                 ← agent instructions
```

**`app.manifest.json` schema:**
```json
{
  "slug": "string — unique, kebab-case",
  "name": "string — display name",
  "description": "string — 1-2 sentence summary",
  "long_description": "string — full markdown description",
  "icon": "string — single emoji",
  "category": "Finance|Legal|HR|Operations|Platform|Infrastructure",
  "has_mobile": "boolean — true if Expo counterpart exists",
  "status": "beta|active",
  "version": "semver string",
  "routes": ["array of route paths this app handles"],
  "tags": ["array of search tags"],
  "db_schema": "snake_case schema name (rfid-pipe → rfid_pipe)",
  "migrations": ["v001_initial.sql"],
  "knowledge_project_id": "neon-project-id for app knowledge DB (Layer 3)",
  "business_rules_docs": ["relevant-spec-doc.md"]
}
```

**What agents MUST do:**
1. Copy template to `platform/apps/{slug}/`
2. Fill in `app.manifest.json`
3. Build all unique features in `src/features/`
4. Register new routes in `src/App.tsx`
5. Run `POST /app-registry/register`
6. Run Cobrowse snapshot tests before status→beta

**What agents MUST NOT do:**
- Modify `AppShell.tsx` (Cobrowse — Rule 9)
- Modify `lib/cobrowse.ts` (vendor wrapper — Rule 3)
- Modify `lib/api.ts` (auth interceptor)
- Call 3rd-party SDKs directly (Rule 3)
- Skip the 4-reviewer pipeline before merge (Rule 8)

---

## Grotap-Built vs Creator-Built Apps

| Property | Grotap-built | Creator-built |
|---|---|---|
| `creator_tenant_id` | NULL | tenant UUID |
| `creator_revenue_pct` | 0 | 80 |
| `is_free` | Usually true (platform apps) | Based on pricing |
| Review process | Internal | Standard 4-reviewer pipeline |
| Publish gate | Grotap admin | Grotap admin approval |

---

## Agent Instructions

- **Use this when:** Building a new app from the base template, or implementing the suggestion → build pipeline
- **Before this:** `app-store-model.md` for DB schema
- **After this:** `app-template-guide.md` for step-by-step agent build instructions

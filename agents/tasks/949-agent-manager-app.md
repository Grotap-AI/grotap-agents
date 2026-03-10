---
title: "feat: Agent Manager app — build agent teams + design workflows (#949)"
branch: task/949-agent-manager
complexity: complex
---

# Task 949 — Agent Manager App

## Context
Agent Manager is 1 of 3 apps in the AI Knowledge Agents suite (`suite_slug = 'ai-knowledge'`). It lets tenants define AI agent teams, configure individual agents within teams, and design multi-step workflows that agents execute. Agents query the shared tenant knowledge base (documents + PageIndex trees managed via Knowledge Manager).

## What Already Exists
- `backend/app/routers/agents.py` — existing agent session runner (`POST /agents/run`, `GET /agents/{session_id}`)
- `frontend/src/pages/AgentsPage.tsx` — existing agent session viewer
- Tenant DB (`proud-union-74070434`) already has `agent_learnings` table
- App row in control plane DB (seeded by task #947)

## Requirements

### Tenant DB Migration
Run on tenant DB (`proud-union-74070434`):

```sql
CREATE TABLE IF NOT EXISTS agent_teams (
    team_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','paused','archived')),
    created_by UUID,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS agent_definitions (
    agent_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id UUID REFERENCES agent_teams(team_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    role TEXT NOT NULL,
    system_prompt TEXT,
    model TEXT DEFAULT 'claude-sonnet-4-6',
    tools JSONB DEFAULT '[]'::jsonb,
    knowledge_scopes TEXT[] DEFAULT '{}',
    max_turns INT DEFAULT 20,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS agent_workflows (
    workflow_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id UUID REFERENCES agent_teams(team_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    steps JSONB NOT NULL DEFAULT '[]'::jsonb,
    trigger_type TEXT DEFAULT 'manual' CHECK (trigger_type IN ('manual','scheduled','event')),
    trigger_config JSONB DEFAULT '{}'::jsonb,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','paused')),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
```

### Frontend — AgentManagerPage.tsx
Create `frontend/src/pages/AgentManagerPage.tsx` with these sections:

**Tab 1: Teams**
- Card grid of agent teams (name, description, status, agent count)
- Create Team button → modal with name, description
- Click team card → navigate to team detail view
- Team detail: list of agents in the team + workflows assigned

**Tab 2: Agents (within a team)**
- Table of agent definitions for selected team
- Columns: name, role, model, knowledge_scopes, max_turns
- Add Agent button → form: name, role, system_prompt, model selector, tools checkboxes, knowledge_scopes multi-select
- Edit/delete agent inline

**Tab 3: Workflows**
- List of workflows across all teams
- Each workflow shows: name, team, trigger_type, step count, status
- Create Workflow button → workflow builder:
  - Name, description, trigger type
  - Step builder: ordered list of steps, each step picks an agent from the team + instruction text
  - Save workflow

### Backend — agent_manager.py
Create `backend/app/routers/agent_manager.py`:

```
GET    /agent-manager/teams                    — list teams
POST   /agent-manager/teams                    — create team
GET    /agent-manager/teams/{team_id}          — get team with agents + workflows
PATCH  /agent-manager/teams/{team_id}          — update team
DELETE /agent-manager/teams/{team_id}          — archive team (set status='archived')

GET    /agent-manager/teams/{team_id}/agents   — list agents in team
POST   /agent-manager/teams/{team_id}/agents   — add agent to team
PATCH  /agent-manager/agents/{agent_id}        — update agent
DELETE /agent-manager/agents/{agent_id}        — remove agent

GET    /agent-manager/workflows                — list all workflows
POST   /agent-manager/workflows                — create workflow
GET    /agent-manager/workflows/{workflow_id}   — get workflow detail
PATCH  /agent-manager/workflows/{workflow_id}   — update workflow
DELETE /agent-manager/workflows/{workflow_id}   — archive workflow
```

All queries against tenant DB. Use `request.state.organization_id`.

### Wiring
1. Add route to `App.tsx`: `/agent-manager` → `<PrivateRoute><><TopNav /><AgentManagerPage /></></PrivateRoute>`
2. Add to `WorkspaceContext.tsx` APP_ROUTES: `'agent-manager': '/agent-manager'`
3. Add tile to `AppLibraryPage.tsx` MODULES array:
   - name: "Agent Manager", slug: "agent-manager", icon: appropriate icon, category: "AI Knowledge"
4. Register router in `backend/app/main.py`

## Important Rules
- Use `request.state.organization_id` NOT `request.state.tenant_id`
- All SQL via Neon MCP — never tell user to run manually
- No unused imports (tsconfig has `noUnusedLocals: true`)
- Validate status fields against explicit allowlist before writing to DB
- JSONB: use `->>` for text comparison, `->` for JSONB access
- Follow `<PrivateRoute><><TopNav />...</>` pattern for routes

---
title: "feat: Agent Teams app — run team instances + group management (#950)"
branch: task/950-agent-teams
complexity: complex
---

# Task 950 — Agent Teams App

## Context
Agent Teams is 1 of 3 apps in the AI Knowledge Agents suite (`suite_slug = 'ai-knowledge'`). It lets tenants spin up instances of agent teams (defined in Agent Manager), run multi-agent sessions, view results, and manage team groups. This is the "runtime" layer — Agent Manager defines teams, Agent Teams runs them.

## What Already Exists
- `backend/app/routers/agents.py` — existing `POST /agents/run` and `GET /agents/{session_id}`
- `frontend/src/pages/AgentsPage.tsx` — existing session viewer
- Tenant DB (`proud-union-74070434`) has `agent_learnings` table
- Task #949 creates `agent_teams`, `agent_definitions`, `agent_workflows` tables
- App row in control plane DB (seeded by task #947)

## Requirements

### Tenant DB Migration
Run on tenant DB (`proud-union-74070434`):

```sql
CREATE TABLE IF NOT EXISTS team_instances (
    instance_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id UUID REFERENCES agent_teams(team_id),
    workflow_id UUID REFERENCES agent_workflows(workflow_id),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','running','completed','failed','cancelled')),
    started_by UUID,
    input_data JSONB DEFAULT '{}'::jsonb,
    output_data JSONB,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS team_instance_steps (
    step_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    instance_id UUID REFERENCES team_instances(instance_id) ON DELETE CASCADE,
    step_index INT NOT NULL,
    agent_id UUID REFERENCES agent_definitions(agent_id),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','running','completed','failed','skipped')),
    input_data JSONB,
    output_data JSONB,
    tokens_used INT DEFAULT 0,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS team_groups (
    group_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS team_group_members (
    group_id UUID REFERENCES team_groups(group_id) ON DELETE CASCADE,
    team_id UUID REFERENCES agent_teams(team_id) ON DELETE CASCADE,
    added_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (group_id, team_id)
);
```

### Frontend — AgentTeamsPage.tsx
Create `frontend/src/pages/AgentTeamsPage.tsx` with these sections:

**Tab 1: Run Teams**
- Card grid of available teams (from `agent_teams` where status='active')
- Each card shows: team name, agent count, workflow count
- "Run" button on each card → modal: select workflow, provide input_data JSON, confirm
- Running creates a `team_instance` and redirects to instance detail

**Tab 2: Instances**
- Table of team instances (all statuses)
- Columns: team name, workflow name, status, started_by, started_at, completed_at, duration
- Status badges: pending (gray), running (blue pulse), completed (green), failed (red), cancelled (yellow)
- Click row → instance detail view showing:
  - Each step with agent name, status, input/output, tokens_used
  - Timeline visualization of step execution
  - Final output_data

**Tab 3: Groups**
- List of team groups
- Create Group button → name, description
- Click group → shows member teams
- Add/remove teams from group via checkbox list
- Groups are organizational — used for access control and reporting

### Backend — agent_teams_router.py
Create `backend/app/routers/agent_teams_router.py`:

```
GET    /agent-teams/available                          — list active teams with agent/workflow counts
POST   /agent-teams/run                                — create + start team instance (team_id, workflow_id, input_data)
GET    /agent-teams/instances                           — list instances (filterable by status, team_id)
GET    /agent-teams/instances/{instance_id}             — get instance detail with steps
PATCH  /agent-teams/instances/{instance_id}/cancel      — cancel running instance

GET    /agent-teams/groups                              — list groups
POST   /agent-teams/groups                              — create group
GET    /agent-teams/groups/{group_id}                   — get group with members
PATCH  /agent-teams/groups/{group_id}                   — update group
DELETE /agent-teams/groups/{group_id}                   — delete group
POST   /agent-teams/groups/{group_id}/members           — add team to group
DELETE /agent-teams/groups/{group_id}/members/{team_id} — remove team from group
```

The `POST /agent-teams/run` endpoint should:
1. Create `team_instances` row with status='pending'
2. Create `team_instance_steps` rows for each step in the workflow
3. Set instance status to 'running', set started_at
4. Return instance_id immediately (execution is async — will be wired to Inngest later)

All queries against tenant DB. Use `request.state.organization_id`.

### Wiring
1. Add route to `App.tsx`: `/agent-teams` → `<PrivateRoute><><TopNav /><AgentTeamsPage /></></PrivateRoute>`
2. Add to `WorkspaceContext.tsx` APP_ROUTES: `'agent-teams': '/agent-teams'`
3. Add tile to `AppLibraryPage.tsx` MODULES array:
   - name: "Agent Teams", slug: "agent-teams", icon: appropriate icon, category: "AI Knowledge"
4. Register router in `backend/app/main.py`

## Dependencies
- Task #949 (agent_teams, agent_definitions, agent_workflows tables must exist)
- Task #947 (app rows must exist in control plane)

## Important Rules
- Use `request.state.organization_id` NOT `request.state.tenant_id`
- All SQL via Neon MCP — never tell user to run manually
- No unused imports (tsconfig has `noUnusedLocals: true`)
- Validate status fields against explicit allowlist
- JSONB: use `->>` for text comparison, `->` for JSONB access
- Follow `<PrivateRoute><><TopNav />...</>` pattern for routes

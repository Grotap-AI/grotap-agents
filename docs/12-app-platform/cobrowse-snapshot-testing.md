---
title: "Cobrowse Snapshot Testing — Agent-Driven Live Video QA on Neon Branches"
updated: 2026-03-05
doc_type: reference
category: testing
tags: [cobrowse, neon, snapshots, agents, testing, video, playwright]
status: active
---

# Cobrowse Snapshot Testing

## Key Feature

Claude Agents test apps against **isolated Neon branch snapshots** with full **Cobrowse session recording** producing live video feeds saved to the DB. Support team can watch agent tests live, take over via remote control, and replay recordings afterward.

---

## Architecture

```
POST /cobrowse/agent-test
    │
    ├── Inngest event: cobrowse/snapshot-test.requested
    │
    ├── Step 1: Create Neon branch snapshot
    │       → Neon API: POST /projects/{id}/branches
    │       → returns: { branch_id, connection_string }
    │
    ├── Step 2: Start Cobrowse session
    │       → Cobrowse API: create session
    │       → returns: { session_id, session_code }
    │       → session NOW VISIBLE live in CobrowseConsolePage
    │
    ├── Step 3: Launch Playwright browser
    │       → target_url: app page to test
    │       → inject JWT via localStorage (bypass WorkOS login)
    │       → set NEON_DATABASE_URL env to snapshot branch URL
    │       → inject Cobrowse SDK join (session_code) via page.evaluate()
    │       → enable video recording: { recordVideo: { dir: '/tmp/recordings' } }
    │
    ├── Step 4: Claude Vision agent loop
    │       → screenshot (base64) → Claude Sonnet 4.6
    │       → returns: { observation, nextAction, bug? }
    │       → execute: click | type | wait | scroll
    │       → Cobrowse captures LIVE stream (viewable in console)
    │       → repeat max 30 steps or until scenario complete
    │
    ├── Step 5: Save recordings
    │       → Playwright .webm → R2: test-recordings/{testRunId}/recording.webm
    │       → 30-day pre-signed URL generated
    │       → Cobrowse session replay URL from Cobrowse API
    │
    ├── Step 6: Persist to DB
    │       → POST /cobrowse/bug-reports/internal (X-Node-Secret auth)
    │       → bug_reports row per bug found:
    │           { title, severity, stepsToReproduce, recording_url,
    │             cobrowse_session_id, neon_branch_id, snapshot_db_url,
    │             cobrowse_replay_url, test_run_id }
    │
    └── Step 7: Cleanup
            → Neon: DELETE /projects/{id}/branches/{branch_id}
            → Local: delete .webm temp file
```

---

## Inngest Function

**File:** `agent-worker/src/functions/cobrowse-snapshot-test.ts`

**Trigger event:** `cobrowse/snapshot-test.requested`

**Event payload:**
```typescript
interface SnapshotTestRequest {
  app_slug: string;
  target_url: string;
  tenant_id: string;
  org_id: string;
  scenarios: string[];  // e.g. ['load', 'create', 'edit', 'delete']
  neon_project_id: string;  // tenant's Neon project to branch from
}
```

**Key steps:**
```typescript
export const cobrowseSnapshotTest = inngest.createFunction(
  { id: 'cobrowse-snapshot-test' },
  { event: 'cobrowse/snapshot-test.requested' },
  async ({ event, step }) => {
    const { app_slug, target_url, neon_project_id, scenarios } = event.data;
    const testRunId = crypto.randomUUID();

    // Step 1: Neon branch
    const branch = await step.run('create-neon-branch', () =>
      neonApi.createBranch(neon_project_id, { name: `test-${testRunId}` })
    );

    // Step 2: Cobrowse session
    const cobrowseSession = await step.run('start-cobrowse', () =>
      cobrowse.createSession()
    );

    // Step 3 + 4: Playwright + Vision loop
    const results = await step.run('run-playwright-tests', () =>
      runAppTester({
        testRunId,
        tenantId: event.data.tenant_id,
        organizationId: event.data.org_id,
        testUrl: target_url,
        scenarios,
        cobrowseSessionId: cobrowseSession.id,
        snapshotDbUrl: branch.connection_string
      })
    );

    // Step 5 + 6: Already handled in app-tester.ts

    // Step 7: Cleanup
    await step.run('cleanup', () =>
      neonApi.deleteBranch(neon_project_id, branch.id)
    );

    return { testRunId, bugs: results.bugs, recording: results.recordingUrl };
  }
);
```

---

## Live Viewing in CobrowseConsolePage

While an agent test runs, the Cobrowse session is live:

```tsx
// CobrowseConsolePage.tsx — Live Sessions tab
// Shows agent test sessions with a tag: "Agent Test: {app_slug}"
<iframe
  src={`https://cobrowse.io/session/${sessionId}?token=${licenseKey}&nav=false`}
  style={{ width: '100%', height: 600 }}
/>
```

**Support team can:**
- Watch agent navigate the app in real time
- Use laser pointer to highlight areas (annotation mode)
- Take remote control if needed (with standard consent flow)
- Leave notes that get attached to the test run

---

## Bug Report Fields (extended)

```sql
-- Existing bug_reports table + new columns:
cobrowse_session_id   TEXT  -- Cobrowse session ID for live/replay
neon_branch_id        TEXT  -- Which Neon branch was used (for reproducibility)
snapshot_db_url       TEXT  -- Full connection string of snapshot (redacted in UI)
cobrowse_replay_url   TEXT  -- 30-day Cobrowse session replay link
test_run_id           TEXT  -- Groups all bugs from one test run
```

---

## API Trigger

```
POST /cobrowse/agent-test
```

**Body:**
```json
{
  "app_slug": "invoice-processor",
  "target_url": "https://app.grotap.com/invoice-processor",
  "scenarios": ["load", "create-invoice", "submit-invoice"],
  "use_neon_snapshot": true
}
```

Tenant's `neon_project_id` is looked up automatically from control plane.

---

## Pass/Fail Criteria

- `CRITICAL` or `HIGH` severity bugs found → test run **FAILS** → app blocked from beta
- `MEDIUM` or `LOW` severity → advisory only → test run **PASSES** with warnings
- Zero bugs → clean PASS

---

## Neon Branch Lifecycle

- Branch created: immediately before test starts
- Branch deleted: immediately after test completes (pass or fail)
- Branch name: `test-{testRunId}` (searchable in Neon console if needed)
- Branch is a point-in-time snapshot — no live data mutations affect production

---

## Agent Instructions

- **Use this when:** Implementing the snapshot test Inngest function, extending app-tester.ts, or building the CobrowseConsolePage live session view
- **Before this:** `docs/09-frontend/cobrowse-sdk.md` for Cobrowse SDK patterns
- **Related:** `agent-worker/src/agents/app-tester.ts` — base vision loop to extend
- **Key rule:** Always delete Neon branch after test (pass or fail). Never leave orphan branches.

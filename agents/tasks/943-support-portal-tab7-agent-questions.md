You are working on the grotap platform codebase at /home/agent/grotap-platform.

## Task #943 — Support Portal Tab 7: Agent Questions Queue

Agents ask questions during app builds. Grotap users answer them here. Nothing is built yet.

### Step 1 — Create DB table via Neon HTTP API

Use NEON_API_KEY from process.env to POST to:
https://console.neon.tech/api/v2/projects/green-rice-76766370/query

Run this SQL:
```sql
CREATE TABLE IF NOT EXISTS support_agent_questions (
  question_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  app_slug        TEXT NOT NULL,
  bug_report_id   UUID,
  question_text   TEXT NOT NULL,
  asked_by        TEXT NOT NULL DEFAULT 'agent',
  status          TEXT NOT NULL DEFAULT 'unanswered' CHECK (status IN ('unanswered','answered')),
  answer_text     TEXT,
  answered_by     TEXT,
  answered_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_agent_questions_app ON support_agent_questions(app_slug);
CREATE INDEX IF NOT EXISTS idx_agent_questions_status ON support_agent_questions(status);
```

Use fetch() with Authorization: Bearer {NEON_API_KEY}, Content-Type: application/json, body: { "query": "<sql>" }.

### Step 2 — Add backend endpoints

Read platform/backend/app/routers/support.py first.

Add to support.py (or support_live.py — check which file has the router registered in main.py for /support routes):

```python
@router.get("/agent-questions")
async def list_agent_questions(
    status: str = None,
    _admin: dict = Depends(require_grotap_user),
    db=Depends(get_control_plane_db)
):
    """List agent questions. Grotap-only."""
    sql = """
        SELECT question_id, app_slug, bug_report_id, question_text, asked_by,
               status, answer_text, answered_by, answered_at, created_at
        FROM support_agent_questions
    """
    if status:
        sql += f" WHERE status = '{status}'"
    sql += " ORDER BY created_at DESC"
    rows = await db.fetch(sql)
    return {"questions": [dict(r) for r in rows]}

@router.post("/agent-questions/{question_id}/answer")
async def answer_agent_question(
    question_id: str,
    payload: dict,
    admin: dict = Depends(require_grotap_user),
    db=Depends(get_control_plane_db)
):
    """Answer an agent question. Grotap-only."""
    await db.execute(
        """UPDATE support_agent_questions
           SET answer_text=$1, answered_by=$2, answered_at=NOW(), status='answered'
           WHERE question_id=$3""",
        payload["answer"], admin.get("email", "grotap"), question_id
    )
    return {"status": "answered"}

@router.post("/agent-questions")
async def create_agent_question(
    payload: dict,
    request: Request,
    db=Depends(get_control_plane_db)
):
    """Create a question from an agent. Node-secret auth."""
    node_secret = request.headers.get("X-Node-Secret", "")
    if node_secret != (os.environ.get("NODE_SECRET", "")):
        raise HTTPException(status_code=403, detail="Forbidden")
    row = await db.fetchrow(
        """INSERT INTO support_agent_questions (app_slug, bug_report_id, question_text, asked_by)
           VALUES ($1, $2, $3, 'agent') RETURNING question_id""",
        payload.get("app_slug"), payload.get("bug_report_id"), payload["question_text"]
    )
    return {"question_id": str(row["question_id"])}
```

### Step 3 — Add Tab 7 to SupportPage.tsx

Read frontend/src/pages/SupportPage.tsx fully first.

Add 'Agent Questions' to TAB_PATHS:
```typescript
'Agent Questions': '/support/agent-questions',
```

Add state + fetch for Tab 7 (same pattern as other tabs).

The tab UI shows a table with columns: App, Question, Asked at, Status, Action.
- Status badge: 'Unanswered' (yellow) or 'Answered' (green)
- For unanswered rows: show an **Answer** button that expands an inline textarea + Save button
- On save: PATCH `/support/agent-questions/{id}/answer` with `{ answer: "..." }`
- After save: update local state to show answered + answer_text inline

### Step 4 — Deploy backend

```bash
cd platform/backend
railway up --service 6cad7f74-9329-406e-b733-719a33c53ac3
```
Check: `railway deployment list --service 6cad7f74-9329-406e-b733-719a33c53ac3`
If FAILED: `railway logs <deployment_id>`

### Step 5 — Commit

```
git add -A
git commit -m "feat: support portal tab 7 — agent questions queue (#943)"
git push origin master
```

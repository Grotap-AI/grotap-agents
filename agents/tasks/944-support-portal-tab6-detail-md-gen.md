You are working on the grotap platform codebase at /home/agent/grotap-platform.

## Task #944 — Support Portal Tab 6: Enhancement Detail + Spec MD Generation

Tab 6 (New App Requests) shows a grid of enhancements. Clicking a row should open a detail panel where a grotap user can generate spec MD files using Claude.

### Step 1 — Read existing code

Read these files first:
- frontend/src/pages/SupportPage.tsx — understand Tab 6 current implementation
- backend/app/routers/support.py or support_live.py — find enhancement endpoints
- backend/app/routers/support_live.py — understand existing pattern

### Step 2 — Add backend endpoints

Add to the support router (whichever file has `/support/enhancements`):

```python
@router.get("/enhancements/{enhancement_id}")
async def get_enhancement_detail(
    enhancement_id: str,
    _admin: dict = Depends(require_grotap_user),
    db=Depends(get_control_plane_db)
):
    row = await db.fetchrow(
        "SELECT * FROM support_enhancements WHERE enhancement_id=$1",
        enhancement_id
    )
    if not row:
        raise HTTPException(404, "Not found")
    return dict(row)

@router.post("/enhancements/{enhancement_id}/generate-md")
async def generate_enhancement_md(
    enhancement_id: str,
    admin: dict = Depends(require_grotap_user),
    db=Depends(get_control_plane_db)
):
    """Use Claude to generate spec MD files from the enhancement request."""
    import anthropic, os
    row = await db.fetchrow(
        "SELECT * FROM support_enhancements WHERE enhancement_id=$1",
        enhancement_id
    )
    if not row:
        raise HTTPException(404, "Not found")

    enh = dict(row)
    client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])

    prompt = f"""You are a software architect. A user has submitted the following {enh.get('type','enhancement')} request for the app '{enh.get('app_slug','unknown')}':

Title/Type: {enh.get('type', 'enhancement')}
Description: {enh.get('description', '')}

Generate a concise product spec as markdown. Include:
1. ## Overview — one paragraph summary
2. ## User Stories — 3-5 bullet points
3. ## Technical Notes — key implementation considerations
4. ## Acceptance Criteria — numbered list

Return ONLY the markdown, no preamble."""

    message = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=1024,
        messages=[{"role": "user", "content": prompt}]
    )
    md_content = message.content[0].text

    # Store generated MD back on the record
    await db.execute(
        "UPDATE support_enhancements SET generated_md=$1 WHERE enhancement_id=$2",
        md_content, enhancement_id
    )
    return {"md": md_content}
```

Check if `support_enhancements` table has a `generated_md` column. If not, add it:
Use NEON_API_KEY to POST to https://console.neon.tech/api/v2/projects/green-rice-76766370/query:
```sql
ALTER TABLE support_enhancements ADD COLUMN IF NOT EXISTS generated_md TEXT;
```

### Step 3 — Update Tab 6 in SupportPage.tsx

Add `selectedEnhancement` state. When user clicks a row in the grid, set the selected enhancement and show a right-side detail panel (or slide-over). The panel shows:

1. Title row: type badge + app slug + submitted date
2. Description text
3. **Generate Spec** button — calls `POST /support/enhancements/{id}/generate-md`
   - While loading show "Generating…" spinner
   - On success display the returned markdown in a `<pre>` block with copy button
   - If `generated_md` already exists on the record, show it immediately without calling generate again
4. Close button (X) to deselect

The detail panel should be shown as a right drawer overlay (position: fixed, right 0, top 56px, width 480px, height calc(100vh - 56px), background white, shadow, z-index 200).

### Step 4 — Deploy

```bash
cd platform/backend
railway up --service 6cad7f74-9329-406e-b733-719a33c53ac3
```
Check deployment: `railway deployment list --service 6cad7f74-9329-406e-b733-719a33c53ac3`
If FAILED: `railway logs <deployment_id>`

### Step 5 — Commit

```
git add -A
git commit -m "feat: support portal tab 6 — enhancement detail + spec MD generation (#944)"
git push origin master
```

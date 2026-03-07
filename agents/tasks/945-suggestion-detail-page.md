You are working on the grotap platform codebase at /home/agent/grotap-platform.

## Task #945 — App Suggestion Detail Page

The `/apps/suggest` voting board lists suggestions but clicking a row does nothing. Add a detail page at `/apps/suggest/:id`.

### Step 1 — Read existing code

Read these files first:
- frontend/src/pages/SuggestAppPage.tsx — current list page
- frontend/src/App.tsx — routing setup
- backend/app/routers/app_suggestions.py — GET /{suggestion_id} already exists

The backend already has `GET /app-suggestions/{suggestion_id}` returning full detail.

### Step 2 — Create SuggestDetailPage.tsx

Create `frontend/src/pages/SuggestDetailPage.tsx`.

The page:
- Fetches `GET /app-suggestions/{id}` on mount
- Shows: title (h1), status badge, vote count + upvote button, description, use_case, target_industry, submitted by, created date
- Status badge colors match SuggestAppPage (submitted=gray, voting=blue, accepted=green, building=amber, launched=emerald)
- Upvote button: `POST /app-suggestions/{id}/vote` (or `DELETE` to remove vote). Match the existing vote logic from SuggestAppPage.
- If status is 'voting' or 'submitted': show upvote button prominently
- If status is 'building' or 'launched': show a "In progress" or "Live!" banner
- Back link: ← Back to Ideas (navigates to /apps/suggest)

Layout: centered content column, max-width 720px, standard TopNav at top.

### Step 3 — Update SuggestAppPage.tsx

Make suggestion rows clickable — navigate to `/apps/suggest/{suggestion_id}` on row click.

Add `cursor: 'pointer'` to row style and `onClick={() => navigate('/apps/suggest/' + s.suggestion_id)}`.

### Step 4 — Add route in App.tsx

Read App.tsx. Add:
```tsx
<Route path="/apps/suggest/:id" element={<PrivateRoute><SuggestDetailPage /></PrivateRoute>} />
```

Import SuggestDetailPage at the top of App.tsx.

### Step 5 — Commit (no deploy needed — frontend only, Vercel auto-deploys)

```
git add -A
git commit -m "feat: app suggestion detail page at /apps/suggest/:id (#945)"
git push origin master
```

---
title: "App Suggestions — Community Voting to Agent Build Pipeline"
updated: 2026-03-05
doc_type: reference
category: platform
tags: [suggestions, voting, community, agents, pipeline]
status: active
---

# App Suggestions — Community Voting → Agent Build Pipeline

## Flow Overview

```
User submits idea
    → stored in app_suggestions (status: submitted)
    → grotap admin opens for voting (status: voting)
    → community votes + adds notes
    → admin reviews vote count + quality
    → accepts (status: accepted) → Inngest fires app/suggestion.accepted
    → OR rejects (status: rejected, reason stored)
    → MD files generated in Support App (status: md_created)
    → human marks Ready to Build (status: ready_to_build)
    → queued for agent New App Team (status: queued)
    → agents build (status: building) — agents may ask questions (queued in Support App → Agent Questions Queue)
    → launched → linked_app_id set (status: launched)
```

---

## Submission Form (`/apps/suggest`)

**Required fields:**
- `title` — Short, descriptive app name idea (max 80 chars)
- `description` — Full write-up (markdown supported, no max)
- `use_case` — Who uses this and how? What problem does it solve?

**Optional fields:**
- `target_industry` — Finance, Legal, HR, Operations, etc.
- `images` — Up to 5 screenshots/mockups (R2 upload, max 5MB each)

---

## Voting Board

Below the submit form, sorted by `vote_count DESC`:

**Idea card shows:**
- Title + submitter info + submitted date
- Status badge (Submitted | Voting | Accepted | Building | Launched)
- Vote count + Vote button (one vote per user, `app_suggestion_votes`)
- Description preview (truncated, expand on click)
- Notes/comments thread (from `app_suggestion_votes.notes`)

**Interaction:**
- Any authenticated user from any tenant can vote
- Voting page is public within the platform (no subscription needed)
- Users can add a note when voting ("I'd use this for invoice matching")
- Notes aggregate into a thread on the idea detail page

---

## Admin Review (`/support` → Suggestions tab, or `/admin`)

**Admin actions on each suggestion:**
- `Open for voting` → status: `voting`
- `Accept` → status: `accepted` → triggers build pipeline
- `Reject` → status: `rejected` + reason stored
- `View votes + notes` → paginated list of voters + their notes

**Accept triggers:**
```python
# app_suggestions router
@router.patch("/{suggestion_id}/status")
async def update_suggestion_status(suggestion_id, status, reason=None):
    await db.update_suggestion_status(suggestion_id, status, reason)
    if status == 'accepted':
        await inngest.send({
            "name": "app/suggestion.accepted",
            "data": {
                "suggestion_id": suggestion_id,
                "title": suggestion.title,
                "description": suggestion.description,
                "use_case": suggestion.use_case,
                "target_industry": suggestion.target_industry,
                "submitter_tenant_id": suggestion.tenant_id,
                "submitter_user_id": suggestion.submitter_user_id
            }
        })
```

---

## Agent Build Trigger (Inngest)

**Event:** `app/suggestion.accepted`

**Handler** (agent-worker): `src/functions/build-app-from-suggestion.ts`
```typescript
export const buildAppFromSuggestion = inngest.createFunction(
  { id: 'build-app-from-suggestion' },
  { event: 'app/suggestion.accepted' },
  async ({ event, step }) => {
    const { suggestion_id, title, description } = event.data;

    // Step 1: Generate app slug from title
    const slug = slugify(title);

    // Step 2: Create GitHub branch
    await step.run('create-branch', () =>
      github.createBranch(`feature/app-${suggestion_id}`)
    );

    // Step 3: Dispatch to agent farm
    await step.run('dispatch-to-agents', () =>
      dispatchToAgentFarm({
        taskType: 'build-app',
        slug,
        description,
        templatePath: 'platform/app-template',
        targetPath: `platform/apps/${slug}`
      })
    );

    // Step 4: Update suggestion status to 'building'
    await step.run('update-status', () =>
      fetch(`/app-suggestions/${suggestion_id}/status`, {
        method: 'PATCH',
        body: JSON.stringify({ status: 'building' })
      })
    );

    // Step 5: Notify submitter
    await step.run('notify-submitter', () =>
      sendNotification({
        user_id: event.data.submitter_user_id,
        type: 'app.build_started',
        message: `Building "${title}" has started!`
      })
    );
  }
);
```

---

## Ready to Build Status

After a suggestion is accepted and MD files have been generated in the Support App (see `support-portal.md` → New App Requests tab), a Grotap user manually sets the status to **`ready_to_build`**.

This triggers:
1. The suggestion is added to the **New App Team** agent queue
2. Agents pick it up when no higher-priority work is pending
3. If agents have questions, they queue them in the **Agent Questions Queue** (Support App → Tab 7)
4. Humans answer; agents resume build once all questions are resolved

Status `ready_to_build` requires MD files to exist for the project — the Submit to Agent Queue button in the Support App enforces this.

---

## Two Agent Dev Teams

To prevent bug fixes from blocking new app development (and vice versa), the agent farm is organized into two dedicated teams:

**Bug Team** — always available for existing app issues
- Picks up emergency bug reports from production apps
- Higher priority queue; interrupts nothing except other bug work
- Never blocked waiting on new-app build work

**New App Team** — builds queued new apps
- Works through the `ready_to_build` queue in order
- Can be interrupted only by an emergency bug case
- Once a bug is resolved, New App Team resumes the queued build

Both teams run on the Hetzner agent farm. Inngest queue routing distinguishes task types (`build-app` vs `fix-bug`) and dispatches to the appropriate team.

---

## Customer Collaboration Option

Admin can invite the original submitter to collaborate during the build:
1. Admin clicks "Invite submitter to build session" in admin panel
2. Cobrowse session created (Agent Present Mode — agent shares screen)
3. Submitter gets notification with Cobrowse session join link
4. Submitter can watch agent build, provide real-time feedback via chat
5. Feedback stored in suggestion's notes thread

---

## API Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/app-suggestions` | List suggestions (sorted by votes, filtered by status) |
| `POST` | `/app-suggestions` | Submit new idea |
| `GET` | `/app-suggestions/{id}` | Get suggestion detail + vote list |
| `POST` | `/app-suggestions/{id}/vote` | Vote on suggestion (idempotent) |
| `DELETE` | `/app-suggestions/{id}/vote` | Remove vote |
| `PATCH` | `/app-suggestions/{id}/status` | Admin only — update status |

---

## Agent Instructions

- **Use this when:** Building the suggestions router, voting board UI, or Inngest build trigger
- **Before this:** `app-lifecycle.md` for status transitions
- **After this:** `app-template-guide.md` for the agent build steps triggered by acceptance

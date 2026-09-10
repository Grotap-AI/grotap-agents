---
id: "14051"
title: "Bug: Platform — DEFECT found by the review gate while merging CASE-20260910-RGSEED (merged to ma"
complexity: medium
priority: high
branch: "case-CASE-20260910-RGLINK"
case_id: "CASE-20260910-RGLINK"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "3b483fc5-5052-42c3-8389-536aed6c5fde"
team: "team3"
---

# Task: Bug: Platform — DEFECT found by the review gate while merging CASE-20260910-RGSEED (merged to ma

## Context
No additional context provided.

## Requirements
DEFECT found by the review gate while merging CASE-20260910-RGSEED (merged to master as ffce897a, push dc06f916). Priority surface: Scan M / ScanTap. Small and latent -- the branch was merged, this case carries the remaining fix.

FILE: scripts/seed_manorview_splash_logos.py (one file; do NOT touch backend/app/services/splash_logo_service.py).

WHAT IS WRONG
RGSEED correctly replaced the script's inline _upsert_logo copy with the shared service function upsert_splash_logo(). But the two are NOT equivalent on conflict:
  - the deleted inline copy: ON CONFLICT ... DO UPDATE SET image_url, label, updated_at  (link_url untouched)
  - the service:            ON CONFLICT ... DO UPDATE SET image_url, label, link_url = EXCLUDED.link_url, updated_at
The script calls it with link_url=None on BOTH slots. So any link_url already stored on that slot is overwritten with NULL.

WHY IT MATTERS, ON THE PATH THAT WILL ACTUALLY BE RUN
The script's slot-1 branch is UNCONDITIONAL -- it re-fetches the SBI logo, re-uploads it to R2 and re-upserts the row on every invocation, including a run whose only purpose is --slot2. Pending HI hold 9cef1d08-9835-4445-8dd7-359811c2f131 (task_id CASE-20260910-02C7A2-slot2-manorview-bg) instructs the owner to run exactly that command once they supply the Manor View Farms background. link_url is owner-editable in the UI: frontend/src/pages/scan-m/ScanMBrandingPage.tsx writes it through scan-m-api.ts. So the sequence "owner sets a click-through link on slot 1 in the branding panel, then runs the seed for slot 2" silently discards the link, with no output line saying so.
Not urgent today: the live slot-1 row (id 1e8cb252-56ac-4a1f-bf72-2fc60cc495d5, org org_01KWPXDXZZSYBJSPDBSB5VH4WQ) has link_url = NULL as of 2026-09-10, so nothing is lost yet. Fix it before the owner uses the panel.

FIX SCOPE
1. Make the slot-1 branch idempotent-by-default: skip fetch + upload + upsert when a row already exists for (ORG_ID, slot 1) and its image_url already points at the deterministic slot-1 key. Print a "slot 1 already seeded -- skipping" line. Add a --force-slot1 flag for the deliberate re-seed. This alone removes the common blast radius and stops re-uploading 57 KB to R2 on a slot-2-only run.
2. On any path that DOES upsert an existing slot, preserve the stored link_url instead of passing None: SELECT link_url for (organization_id, slot) first and pass that value through to upsert_splash_logo(link_url=...). Do not add a link_url CLI flag; the branding panel owns that field.
3. Keep everything RGSEED added exactly as it is -- CARRY FORWARD from ffce897a: the sys.path.insert pattern, the four service imports, the _MIME_MAP hard-fail on an unmapped suffix, and both validate_image() call sites. Do not re-inline any service function.
4. Extend backend/tests/test_seed_manorview_splash_logos.py (do not create a second file): add a test that a pre-existing slot-1 row with link_url='https://example.com/x' still has that value in the upsert kwargs (or is skipped entirely per step 1) after main(<slot2 path>) runs. Make it discriminate -- reverting step 2 must turn it red. The existing file already shows the mock harness to copy: patch.object(_seed, 'upload_splash_logo_to_r2'/'upsert_splash_logo'), patch('asyncpg.create_pool'), patch('httpx.AsyncClient'). Note the two existing slot-2 tests assert on which slots reached upload; if step 1 makes slot 1 skip by default, those assertions still hold (they only assertNotIn(2, ...)), but the harness's pool_mock will now need a fetchrow AsyncMock -- add it rather than reverting the skip.

DO NOT RUN THE SCRIPT AGAINST PROD as part of this case. Slot 1 is already seeded and live; slot 2 is still blocked on the owner's file (hold 9cef1d08). Verification is the test suite only.

VERIFIED BY THE GATE, do not re-litigate: the RGSEED tests DO have teeth -- both were mutation-checked by line number (deleting the slot-2 validate_image() call reddens test_oversized_png_refused_before_slot2_upload; restoring the ct_map.get(ext, 'image/png') silent fallback reddens test_pdf_extension_refused_before_slot2_upload), and a positive control confirmed slot 1 really does reach the upload mock, so neither test passes vacuously. Service signatures and the slot-1 R2 key (.png from content-type image/png, byte-identical to the live object) were also verified.

## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "CASE-20260910-RGLINK" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error

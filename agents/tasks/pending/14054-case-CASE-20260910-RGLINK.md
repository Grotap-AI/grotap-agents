---
id: "14054"
title: "Bug: Platform — DEFECT found by the review gate while merging CASE-20260910-RGSEED (merged to ma"
complexity: medium
priority: high
branch: "case-CASE-20260910-RGLINK"
case_id: "CASE-20260910-RGLINK"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "aa4a569e-60c8-49eb-af7d-98a3a15f4c90"
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

---
REVIEW GATE 2026-09-10 (run rglink) — REJECTED. Branch deleted; rebuild from master.

THE APPROACH IS RIGHT AND THE SLOT-1 FIX IS CORRECT. Re-create all of this as-is:
  * the pool.fetchrow pre-check that SELECTs image_url, link_url for (ORG_ID, slot 1) — the
    column names are valid, verified against the live schema (link_url is nullable text);
  * the expected_key comparison against public_url(R2_PUBLIC_BASE, "scan-m/splash/<org>/slot-1.png")
    to decide whether slot 1 is already seeded, and the "already seeded -- skipping" print;
  * the --force-slot1 argparse flag;
  * link_url = existing_row["link_url"] passed through to the slot-1 upsert_splash_logo() call
    (MEASURED WORKING: slot-1 upsert receives the stored link, so step 2 of the original scope
    is genuinely fixed for slot 1);
  * everything RGSEED added, untouched, per step 3 of the original scope.
Fetch/upload really are skipped on the already-seeded path (measured: uploads=0).

BLOCKER 1 — main() reads a global "args" that does not exist when main() is called.
scripts/seed_manorview_splash_logos.py line ~129 and ~141 read args.force_slot1 inside
  async def main(slot2_path: str | None)
but "args" is only ever assigned at module level under `if __name__ == "__main__":`. Run as a
script it resolves by luck; called any other way it raises
  NameError: name 'args' is not defined
This is not hypothetical — the whole test suite calls _seed.main(path) directly. MEASURED:
  origin/master                            -> 6 passed
  origin/case-CASE-20260910-RGLINK         -> 3 failed, 4 passed
It reddens the two PRE-EXISTING tests that were green on master
(test_oversized_png_refused_before_slot2_upload, test_pdf_extension_refused_before_slot2_upload)
AND the new test this case added. A branch may not leave master's suite red.
FIX: make it a parameter, not a global — `async def main(slot2_path: str | None,
force_slot1: bool = False)`, called as `main(args.slot2, args.force_slot1)` from __main__.
Also DROP the `args.force_slot1 = True  # Force update if image doesn't match` assignment: it
mutates the shared parsed-args object from inside main(), which leaks across calls in one
process. Use a local, e.g. `reseed = force_slot1 or not existing_row or
existing_row["image_url"] != public_url(...)`, then branch on `reseed` once.

BLOCKER 2 — the shared test helper's pool mock still has no fetchrow. The original scope said
this explicitly ("the harness's pool_mock will now need a fetchrow AsyncMock — add it rather
than reverting the skip"). It was added ONLY to the new test, not to _run_main_slot2 in
backend/tests/test_seed_manorview_splash_logos.py (~line 109), so both slot-2 tests now die on
  TypeError: object MagicMock can't be used in 'await' expression
at the new fetchrow call. FIX: add `pool_mock.fetchrow = AsyncMock(return_value=None)` to that
helper. return_value=None is the right default there — those two tests assert on slot-2
validation and want the no-existing-row path.

BLOCKER 3 — the new test asserts on the WRONG upsert call, so it cannot pass even once
blockers 1 and 2 are fixed. test_preserves_existing_link_url_on_slot1 reads
`upsert_mock.call_args[1]["link_url"]`. call_args is the LAST call, and because the test passes
a --slot2 path, the last call is SLOT 2. MEASURED, with args and fetchrow patched in so the
script runs to completion:
  upsert call 0: slot=1 link_url='https://example.com/x'   <- what the test means to check
  upsert call 1: slot=2 link_url=None                       <- what call_args actually returns
  call_args[1]["link_url"] -> None
FIX: assert on the slot-1 call specifically — `upsert_mock.call_args_list[0][1]`, or better,
pick the call whose kwargs["slot"] == 1 so the assertion does not depend on call order.
Then MUTATION-CHECK it: reverting link_url=link_url back to link_url=None on the slot-1 upsert
must turn this test RED. If it stays green the test is worthless.

DEFECT 4 — slot 2 still wipes link_url, and slot 2 is the path that will actually be run.
The slot-2 upsert (~line 203) is unchanged and still passes `link_url=None` unconditionally, so
this case fixed exactly one of the two occurrences of its own defect. Pending HI hold
9cef1d08-9835-4445-8dd7-359811c2f131 (still 'pending' as of 2026-09-10 10:00Z) tells the owner
to run `--slot2 <path>` once they supply the Manor View Farms background — that run will create
slot 2, and EVERY later run of it will null out whatever link the owner set on slot 2 in the
branding panel. Generalize the rule instead of patching one call site: preserve the stored
link_url on ANY slot this script upserts. Concretely, SELECT image_url, link_url for the slot
being written (or fetch both rows once, keyed by slot) and pass the stored value through. Still
no link_url CLI flag — the branding panel owns that field.

MINOR 5 — the skip path prints "skipping" and then upserts anyway. MEASURED on the
already-seeded path: uploads=0, upserts=1. Fetch and upload are skipped but upsert_splash_logo
still runs, bumping updated_at on a row nothing changed. Step 1 of the original scope asked to
skip fetch + upload + upsert. Not a data-loss bug now that link_url is preserved, so either
skip the upsert too (preferred — that is what the message claims) or reword the message.

VERIFICATION REQUIRED BEFORE YOU PUSH — from backend/:
  python3 -m pytest tests/test_seed_manorview_splash_logos.py -q
Must be 0 failed and at least 7 passed (master's 6 + the new one). A red or reduced suite is an
automatic reject. Keep using ONE test file, per the original scope.
DO NOT RUN THE SCRIPT AGAINST PROD — unchanged from the original scope. Tests only.


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

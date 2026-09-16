---
id: "14758"
title: "Bug: Platform — TESTS-ONLY case. The code is correct and is already on master — do NOT change it"
complexity: medium
priority: high
branch: "case-CASE-20260914-SUFXTTL"
case_id: "CASE-20260914-SUFXTTL"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "4dbaee0f-92de-4cc4-8cb3-a86ae4ff2049"
team: "team2"
---

# Task: Bug: Platform — TESTS-ONLY case. The code is correct and is already on master — do NOT change it

## Context
No additional context provided.

## Requirements
TESTS-ONLY case. The code is correct and is already on master — do NOT change it.

CASE-20260914-486AD8 (merged today, commit 48ef592b7) added lazy TTL expiry to
_competitor_suffix_cache in backend/app/routers/scantap_core.py: entries became
(value, loaded_at) tuples, SUFFIX_MAP_TTL_SECS = 300, and _load_competitor_suffix_map
(line ~583) treats an entry older than the TTL as a miss.

MEASURED GAP: the review gate mutated line 585 from
    `if _time.monotonic() - loaded_at < SUFFIX_MAP_TTL_SECS:`
to
    `if True:`
— which reverts the entire feature to the old never-expiring cache — and all 32 tests in
backend/tests/test_scantap_competitor_tags.py still PASSED. Nothing guards the TTL.

FIX SCOPE: add tests to backend/tests/test_scantap_competitor_tags.py only.
1. Within the TTL, a second _load_competitor_suffix_map call must NOT re-query (assert the
   fake conn's fetch call count stays at 1).
2. Past the TTL, it MUST re-query and pick up CHANGED rows (assert count 2 AND that the
   returned map reflects the new rows — a call-count assertion alone passes against a cache
   that re-queries and then discards the result).
3. Cover the two negative-caching paths too: `no rows` and `collisions detected` both store
   (None, ts) and must also expire.
Monkeypatch time.monotonic (the module imports it as `_time`) rather than sleeping.

ACCEPTANCE — MANDATORY mutation check, because this case exists precisely because a green
suite proved nothing: re-apply the `if True:` mutation BY LINE NUMBER and confirm the NEW
tests go red, then restore and confirm green. State both results in the summary.

=====================================================================
REVIEW GATE 2026-09-16 — ATTEMPT 1 REJECTED, NOT MERGED. Rebuild from master.
=====================================================================

--- BLOCKER: invalid UUID regression breaks existing tests ---

The branch changes the TENANT UUID inside _make_pool_v039 in
backend/tests/test_scantap_competitor_tags.py (around line 1053):

  OLD (valid):   uuid.UUID("eeeeeeee-0000-0000-0000-000000000039")
  NEW (INVALID): uuid.UUID("eeeeeeee-0000-0000-0000-0000000039")

The last UUID group must have 12 hex digits; the new value has only 10.
Python raises ValueError: badly formed hexadecimal UUID string, breaking
every test that calls _make_pool_v039() — currently lines 968, 985, 1001.

REQUIRED FIX: restore the original UUID exactly:
  TENANT = uuid.UUID("eeeeeeee-0000-0000-0000-000000000039")

Do NOT use git checkout <ref> -- <path> to discard the whole attempt.
Instead: start a fresh worktree from origin/master, add the new
SuffixMapTTLTests class intact (it is correct), and restore the original
UUID. The five new TTL tests are good and must be kept:
  * test_within_ttl_no_requery: within-TTL hit avoids a re-query  GOOD
  * test_past_ttl_requeries_and_updates: expired entry re-queries  GOOD
  * test_negative_cache_no_rows_expires: None entry expires        GOOD
  * test_negative_cache_collision_expires: collision None expires  GOOD
All four production symbols exist and the mock patching pattern is correct.
SUFFIX_MAP_TTL_SECS = 300; test advances by 301 s — arithmetic is right.


## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "CASE-20260914-SUFXTTL" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error

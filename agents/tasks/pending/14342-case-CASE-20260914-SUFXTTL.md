---
id: "14342"
title: "Bug: Platform — TESTS-ONLY case. The code is correct and is already on master — do NOT change it"
complexity: medium
priority: high
branch: "case-CASE-20260914-SUFXTTL"
case_id: "CASE-20260914-SUFXTTL"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "5149d318-44db-4c3c-84bb-0f65426c0543"
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

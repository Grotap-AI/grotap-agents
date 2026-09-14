---
id: "14349"
title: "Bug: Platform — Three tests are failing on origin/master right now. Not caused by the branches m"
complexity: medium
priority: high
branch: "case-CASE-20260914-DEVTKRD"
case_id: "CASE-20260914-DEVTKRD"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "72622270-33e7-4d76-9893-240d1a1b7781"
team: "team4"
---

# Task: Bug: Platform — Three tests are failing on origin/master right now. Not caused by the branches m

## Context
No additional context provided.

## Requirements
Three tests are failing on origin/master right now. Not caused by the branches
merged today — measured on a clean worktree of origin/master BEFORE this batch merged.

RED ON MASTER (backend/tests/test_scantap_route_defects.py): 3 failed, 13 passed.
    PreSnappedLocationRadiusTest::test_detail_quotes_the_limit
    PreSnappedLocationRadiusTest::test_far_pre_snapped_location_is_rejected_422
    PreSnappedLocationRadiusTest::test_near_pre_snapped_location_still_routes
All three fail the same way — the assertion never runs because the request is rejected
first:
    AssertionError: 403 != 422 : {"detail":"X-Device-Token header required"}

CAUSE: commit f6227d747 "feat(scantap): device-token allowlist dep for route + tour
endpoints" added `_device: str = Depends(require_device_token)` to `get_route` in
backend/app/routers/scantap_route.py. A route-level dependency is a change to the
ROUTE'S PRECONDITIONS, i.e. a signature change: every HTTP-level test that drives that
endpoint must now supply the header. That commit added its own new suite
(backend/tests/test_device_token_route_tour.py, green) and updated the tests that call
get_route as a plain function, but not PreSnappedLocationRadiusTest, which goes through
the FastAPI test client and so hits the dependency.

FIX SCOPE — backend/tests/test_scantap_route_defects.py only. Do NOT weaken the
dependency and do NOT change scantap_route.py. Make PreSnappedLocationRadiusTest's
requests satisfy require_device_token the same way test_device_token_route_tour.py
already does (read that file first and copy its mechanism — header injection or a
dependency_overrides entry on the test app; use whichever it uses, do not invent a
third).

ACCEPTANCE: `pytest backend/tests/test_scantap_route_defects.py
backend/tests/test_device_token_route_tour.py backend/tests/test_scantap_route_get.py`
is fully green (16/16 on the first file), AND the three repaired tests still assert what
they were written to assert — verify by REMOVING the 40 m radius guard in
scantap_route.py and confirming test_far_pre_snapped_location_is_rejected_422 goes red.
A test repaired into passing by deleting its assertion is worse than the red one.

## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "CASE-20260914-DEVTKRD" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error

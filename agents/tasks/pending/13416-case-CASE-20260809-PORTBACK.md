---
id: "13416"
title: "Bug: Platform — E394E4 was titled "Port hardening from grotap-platform to grotap-agents review-g"
complexity: medium
priority: high
branch: "case-CASE-20260809-PORTBACK"
case_id: "CASE-20260809-PORTBACK"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "02751f4b-f187-4721-9250-bb357d64b54b"
team: "team4"
---

# Task: Bug: Platform — E394E4 was titled "Port hardening from grotap-platform to grotap-agents review-g

## Context
No additional context provided.

## Requirements
E394E4 was titled "Port hardening from grotap-platform to grotap-agents
review-gate-cron.sh". It is status=done. The port did not happen in the direction that
matters, and the commit that landed asserts that it did.

FOUND BY: review gate rg7, 2026-08-09, while reviewing CASE-20260809-7AC949.

WHAT LANDED: grotap-platform 88045096, "feat(review-gate): sync inert platform copy with
combined grotap-agents version (CASE-20260809-E394E4)". Its message says the change
"Brings the inert grotap-platform mirror up to date with the combined grotap-agents script
(commit f4901d1) that now carries all four hardening components: classify_failure()
short-label triage, _PAGED dedup escalation, grotap-git-lock serialization (D6), and
classify_sync_failure() ownership/race analysis (D7)."

WHAT IS ACTUALLY TRUE (checked against both repos at grotap-agents master 7e661e7):
  - `git cat-file -t f4901d1` in grotap-agents -> "Not a valid object name". The cited
    source commit DOES NOT EXIST in that repo, on master or any branch.
  - Component counts in the DEPLOYED script,
    grotap-agents/agents/scripts/review-gate-cron.sh:
        classify_failure      0
        _PAGED                0
        page_oncall           0
        grotap-git-lock       6   <- pre-existing D6, not from this case
        classify_sync_failure 3   <- pre-existing D7, not from this case
    So two of the four claimed components are absent from the deployed copy, and the two
    that are present predate E394E4.
  - Component counts in the INERT mirror, grotap-platform master
    agents/scripts/review-gate-cron.sh:
        classify_failure      4
        _PAGED                3
        page_oncall           4
    The hardening exists ONLY in the copy nothing executes.

NET EFFECT: the case moved bytes from the inert mirror into the inert mirror. The
deployed script — the one systemd review-gate.service actually runs — gained nothing, and
the landed commit message now reads as evidence that it did, which is what will stop the
next person from looking. This is the same trap as CASE-20260809-4B3FAC and
CASE-20260730-CBF15D: two same-named scripts in two repos, work landing in the wrong one.

FIX SCOPE:
1. Decide whether page_oncall()/classify_failure()/_PAGED are actually wanted in the
   deployed script. They overlap with what is already there: fail_hold() is called at both
   real failure paths (bootstrap sync failure after 4 attempts, and non-zero claude rc)
   with classify_sync_failure() interpolated into the hold body. The genuinely NEW
   behaviour in the mirror's version is the _PAGED once-per-invocation dedup and
   classify_failure()'s short triage labels (lock/race | network | permission | disk).
2. If YES: port those into grotap-agents/agents/scripts/review-gate-cron.sh — the file at
   the path `systemctl cat review-gate.service | grep ExecStart` prints — and verify with
   `bash -n` (this file is outside compileall/tsc; nothing else will catch a typo). Do not
   duplicate fail_hold; wire the dedup into the existing one.
3. If NO: say so explicitly, and correct the record — 88045096's claim is the artifact
   that will mislead.
4. Either way, this interacts with CASE-20260809-DF2B36 (delete the platform mirror):
   deleting the mirror BEFORE resolving this discards the only copy of that code. Sequence
   them — this case first, DF2B36 second.

ACCEPTANCE: paste the component counts from BOTH files after your change; confirm the
grotap-agents copy is the one you edited by quoting `systemctl cat review-gate.service |
grep ExecStart`; `bash -n` clean; and state explicitly whether f4901d1 was a typo for a
real commit or a fabrication, so the next audit does not chase it.

## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "CASE-20260809-PORTBACK" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error

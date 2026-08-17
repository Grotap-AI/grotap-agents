---
id: "13413"
title: "Bug: print-cloud-agent — Fix case from the review gate (2026-07-30). Follow-up to CASE-20260726-D8D5B8, w"
complexity: medium
priority: high
branch: "case-CASE-20260730-PCAVAI"
case_id: "CASE-20260730-PCAVAI"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "77697683-5fe5-4598-8394-d7a39fdfeab0"
team: "team5"
---

# Task: Bug: print-cloud-agent — Fix case from the review gate (2026-07-30). Follow-up to CASE-20260726-D8D5B8, w

## Context
Component: print-cloud-agent

## Requirements
Fix case from the review gate (2026-07-30). Follow-up to CASE-20260726-D8D5B8, which was MERGED (commit 81ad6e5b) — the updater core is correct, these are two latent state-reporting defects found in review.

FILE: agent/print-cloud-windows/src/pc_worker.py (Worker._check_update)

DEFECT 1 — the `available` flag is never read.
backend/app/routers/print_cloud.py::agent_installer_info() returns
  {"available": <head is not None>, "version": <metadata version OR INSTALLER_VERSION fallback>, ...}
When R2 is down or the installer is unpublished it still returns a NON-NULL `version` (the
INSTALLER_VERSION constant fallback) alongside available:false. _check_update() only reads
info["version"], so if that constant is newer than the running VERSION the agent proceeds to
GET /print-cloud/download/agent-installer, which returns 404 in exactly that case. Result:
update_state="error" + update_error="Download failed: HTTP Error 404" surfaced on the dashboard
and the tray for up to 24 h, for a condition that is not an agent fault at all.
FIX: after parsing `info`, return early (leaving update_state unchanged) when
info.get("available") is falsey. Only treat the response as actionable when available is true.

DEFECT 2 — a transient info-fetch failure clobbers a good "ready" state.
On any exception fetching the info endpoint, _check_update() sets update_state="error". If a prior
cycle had already downloaded and verified an installer (update_state="ready"), one network blip
overwrites that with "error" and the pending update disappears from the UI until the next
successful cycle 24 h later.
FIX: do not overwrite a terminal "ready" state on an info-fetch failure. Record the transient
failure in update_error (or a separate last_check_error field) and leave update_state as-is when
it is already "ready".

SCOPE: pc_worker.py only. No new config keys, no change to the /info or /download endpoints, no
change to the tray. Keep the existing behaviour that a missing sha256 falls back to a soft
size_bytes check and never hard-fails (pre-PCAV backends).

## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "CASE-20260730-PCAVAI" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error

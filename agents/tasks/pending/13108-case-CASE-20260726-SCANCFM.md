---
id: "13108"
title: "Bug: ScanTap mobile scan screen — Rebase AC011F onto the current preflight generation-token flow (restore Confirm"
complexity: medium
priority: high
branch: "case-CASE-20260726-SCANCFM"
case_id: "CASE-20260726-SCANCFM"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "eebab046-cdc2-41be-8da1-0ce3a0fbb52f"
team: "team3"
---

# Task: Bug: ScanTap mobile scan screen — Rebase AC011F onto the current preflight generation-token flow (restore Confirm

## Context
Component: ScanTap mobile scan screen

## Requirements
Rebase AC011F onto the current preflight generation-token flow (restore Confirm — Start button, B2/B3)

CONTEXT — why this is a fix case, not a re-review. The original branch
`origin/case-CASE-20260726-AC011F` (commit 155aa3d1) implements the right UX but was
built against a base (f21789fe) that master has since replaced. Four sibling cases were
fanned out onto the SAME file `platform/mobile/scantap/app/(tabs)/scan.tsx`; 4AF604 and
F4902E landed first and rewrote the exact flow AC011F edits. Test-merging AC011F onto
master (8dba2dd8) produces 3 content conflicts and, if force-resolved, deletes the
race protection those two cases added. Do NOT merge the old branch — rebuild the change
on a fresh branch cut from CURRENT master.

WHAT ON MASTER CHANGED UNDER IT:
- `preflightCancelledRef` (boolean) NO LONGER EXISTS. It was replaced by
  `preflightRunRef` (monotonic generation counter, commits 310d399b / faf1d7fc / 1ef5d15e).
  `preflight()` now opens with `const myRun = ++preflightRunRef.current;` and stale-checks
  `preflightRunRef.current !== myRun` after every await. The old branch's Cancel handler
  writes `preflightCancelledRef.current = true` -> TS2304 "Cannot find name" AND, worse,
  it never bumps the generation, so an in-flight preflight is not superseded and leaks the
  CS463's single LLRP slot. That leak is the exact defect faf1d7fc was landed to fix.
- `startScanning(svc?: ReaderService)` NOW EXISTS on master (CASE-20260726-0C079F, merged
  as 8dba2dd8). The connected path of `preflight()` calls `await startScanning(svc)`
  followed by a post-await stale guard. Use `startScanning(svc)` from the Confirm button
  as this case's own spec asks — do not call `beginBatch(svc)` directly (the old branch did).

FIX SCOPE — one file: platform/mobile/scantap/app/(tabs)/scan.tsx
1. Remove the auto-start: in `preflight()`, the `if (connected) { await startScanning(svc); ... }`
   branch must no longer open the batch. Invert to `if (!connected) { ... }` keeping the
   existing pendingSvcRef/setConnWarning body untouched. The reader stays connected and
   registered; the screen simply waits on the user.
2. Add the 'Confirm — Start' button on the `phase === 'confirming'` screen, above the
   existing Cancel button. Style keys already exist: `styles.bigButton`,
   `styles.bigButtonDisabled`, `styles.bigButtonText`.
   - Disabled while `readerState !== 'connected'`, label 'Checking connection…'.
   - Enabled once `readerState === 'connected'`, label 'Confirm — Start'.
   - onPress: capture the generation FIRST (`const myRun = preflightRunRef.current;`),
     re-check `readerRef.current` is non-null and `readerState === 'connected'`, then
     `await startScanning(svc)`. After the await, if `preflightRunRef.current !== myRun`,
     stop/clear that service instead of proceeding — mirror the guard already present at
     the end of preflight()'s connected path. A tap must never open a batch on a service
     a newer preflight has superseded.
3. Cancel handler on the confirming screen: it must `++preflightRunRef.current` (master
   already does this — KEEP IT; do not reintroduce a boolean flag), AND additionally stop
   the now-live service when the reader had already connected:
   if `readerState === 'connected'`, take `readerRef.current`, call `svc.stop()`,
   `clearActiveReader(svc)`, `readerRef.current = null`. Then `setReaderState(null)` and
   `setPhase('idle')`. When still connecting, the generation bump alone is correct — the
   in-flight preflight's own stale-check does the cleanup.
4. B3 dead state: `checkingConn` is write-only — declared at scan.tsx:122 and written at
   :216, :272 and :500, never READ in render. Delete the `useState` declaration AND all
   three `setCheckingConn(...)` call sites. Drive the button text/disabled purely from
   `readerState`. (Beware: `setCheckingConn` has a capital C — a case-sensitive grep for
   'checkingConn' misses all three setters.)

DO NOT TOUCH: the `preflightRunRef` generation logic itself, the status-callback guard
`if (preflightRunRef.current === myRun) setReaderState(state)`, the `startScanning`
fresh-service fallback, `beginBatch`, `dismissConnWarning`, or the 'Start Anyway' modal.

VERIFICATION (required — this file is NOT covered by the three standard gates):
  cd platform/mobile/scantap && npx tsc --noEmit
Zero errors outside `test/`. The ~153 `test/**` errors ('Cannot find name describe/test/
expect') are a PRE-EXISTING `@types/jest` gap on master — ignore those, do not "fix" them.
Note `$?` after a pipe reports the pipe's LAST command, so check the tsc exit code before
piping to grep or a gate that never ran looks green.

Filed by the review gate on 2026-07-26 after rejecting CASE-20260726-AC011F (stale base /
structural conflict). Sibling 0C079F was salvaged and is on master; this is the last
open piece of the scan-confirm UX group.

## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "CASE-20260726-SCANCFM" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error

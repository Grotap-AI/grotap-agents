---
id: "13411"
title: "Bug: scantap-mobile — Fix case from the review gate (2026-07-30). Follow-up to CASE-20260730-CB7AD1, w"
complexity: medium
priority: high
branch: "case-CASE-20260730-CHKAGG"
case_id: "CASE-20260730-CHKAGG"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "414523f3-7f33-4d2b-9781-c1e4cbc076ad"
team: "team4"
---

# Task: Bug: scantap-mobile — Fix case from the review gate (2026-07-30). Follow-up to CASE-20260730-CB7AD1, w

## Context
Component: scantap-mobile

## Requirements
Fix case from the review gate (2026-07-30). Follow-up to CASE-20260730-CB7AD1, which was MERGED
(commit 5cd333ef) — the extraction is correct, but it left a duplicated hot loop.

FILES:
  platform/mobile/scantap/services/syncPayload.ts  (deriveChunkingIdentity)
  platform/mobile/scantap/app/(tabs)/send.tsx      (~line 465-475, the prepare loop)

DEFECT: aggregateTagRecords(tags) now runs TWICE for every selected batch on every Send.
send.tsx does:
    const tags     = await getTagsForBatch(batch.id);
    const chunking = deriveChunkingIdentity(batch, tags);   // calls aggregateTagRecords internally
    const records  = aggregateTagRecords(tags);             // calls it again
deriveChunkingIdentity() aggregates only to obtain records.length and then throws the aggregated
array away. aggregateTagRecords collapses raw reads to one record per EPC and builds a sorted
antenna set per EPC — on a sweep with tens of thousands of raw reads that is a real cost, paid
twice, on the UI thread of a handheld tablet, once per selected batch. Nothing is incorrect;
Send just does double the work it did before the refactor.

FIX (pick one, do not do both):
  (a) Have deriveChunkingIdentity return the aggregated records alongside the identity, e.g.
      `{ chunkSize, recordCount, records }` (keep ChunkingIdentity itself as the persisted
      {chunkSize, recordCount} shape so the resume-mark identity contract is unchanged), and have
      send.tsx use the returned records instead of calling aggregateTagRecords again.
  (b) Change the helper signature to deriveChunkingIdentity(batch, records) taking ALREADY
      aggregated records, and have send.tsx aggregate once and pass them in.

CONSTRAINT: whatever the shape, the value persisted as the resume-mark identity must stay exactly
{chunkSize, recordCount} — buildIdempotencyKey() and resumeStartPart() name parts from it, and
changing it would invalidate every in-flight resume mark on every tablet. Extend the existing
tests in services/__tests__/syncPayload.test.ts to cover the helper's return shape.

## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "CASE-20260730-CHKAGG" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error

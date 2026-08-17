---
id: "13560"
title: "Bug: Platform — DEFECT (latent, same class as CASE-20260814-84D2FC which just merged).  FILE: ba"
complexity: medium
priority: high
branch: "case-CASE-20260814-COTRTY"
case_id: "CASE-20260814-COTRTY"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "6ac25b96-9934-4d17-9592-84483b72a9a6"
team: "team2"
---

# Task: Bug: Platform — DEFECT (latent, same class as CASE-20260814-84D2FC which just merged).  FILE: ba

## Context
No additional context provided.

## Requirements
DEFECT (latent, same class as CASE-20260814-84D2FC which just merged).

FILE: backend/app/providers/openai_compatible_provider.py, line ~154 (inside complete_with_usage, the thinking-retry branch):
    text = retry_msg.get("content") or _reasoning_text(retry_msg)

CASE-20260814-84D2FC removed the identical `or _reasoning_text(...)` fallback from the FINAL return of the same function because `reasoning` is chain-of-thought, not an answer: returning it hands the caller raw CoT as if it were the model reply. The retry branch still has it.

FAILURE: an Ollama/vLLM thinking model (gemma4:26b, ornith:9b, deepseek-r1) that comes back reasoning-only on the FIRST call gets retried at a larger budget; if that retry ALSO returns content=' with a populated reasoning/reasoning_content field, complete_with_usage returns the chain-of-thought string as the answer. It is non-empty, so model_router._call_lane_with_usage does NOT raise EmptyLaneReply (backend/app/providers/model_router.py:283) and the cascade never advances -- the caller receives internal reasoning as a user-facing reply. This is exactly the leak the 2026-08-09 review gate described for the final-return site (see scripts/hi_branch_gate_0809.py, note on branch case-CASE-20260809-F8F223); both sites were introduced by the same commit 48eed6c4 and only one was corrected.

FIX SCOPE (one file, one line + one test):
1. backend/app/providers/openai_compatible_provider.py -- change the retry-branch assignment to `text = retry_msg.get("content") or ""` so a reasoning-only retry yields "" and the router cascades. Keep the usage/telemetry merging (first_usage totals, thinking_retry, finish_reason) exactly as is.
2. backend/tests/providers/test_openai_compatible_provider.py -- add a test in TestThinkingModelReasoningField: script two _reasoning_only() responses (first at max_tokens=16, second at the retried budget) and assert the returned text == "" while len(sent) == 2 and usage["thinking_retry"] is True.

DO NOT relax test_no_retry_on_a_definitive_stop or re-add the fallback at the final return.

NOTE FOR CI: tests/providers/test_openai_compatible_provider.py is quarantined in backend/tests/conftest.py collect_ignore AND is absent from the quarantine loop in .github/workflows/ci-backend.yml, so it runs in NEITHER pytest --forked NOR any CI step. Run it by hand (cd backend && python3 -m unittest tests.providers.test_openai_compatible_provider -v). Adding the module to the ci-backend.yml quarantine loop is in scope for this case and is the reason both leaks reached master unnoticed.

## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "CASE-20260814-COTRTY" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error

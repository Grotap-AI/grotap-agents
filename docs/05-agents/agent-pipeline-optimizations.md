---
title: "Agent Pipeline Optimizations — Speed + Cost"
source: internal-analysis
converted: 2026-03-06
component: "Claude-Code"
category: ai
doc_type: how-to
related:
  - "dispatch.sh"
  - "run-review.sh"
  - "review-pipeline.sh"
  - "queue-runner.sh"
tags:
  - agents
  - optimization
  - cost
  - performance
  - review-pipeline
status: active
---

# Agent Pipeline Optimizations — Speed + Cost

Analysis of the agent infrastructure as of 2026-03-06. Changes target the two main workflows:
**task execution** (dispatch → queue → run-task) and **code review** (review-pipeline → run-review → collect-reviews).

---

## Speed Improvements

### 1. Move Performance Reviewer to Agent-05

**Problem:** Logic + Performance reviewers both run on Agent-03. They serialize via `flock` on `.git/index.lock`, making the 4-reviewer pipeline effectively 3-way parallel (Build + Security + Logic/Perf-sequential).

**Fix:** Move Perf to Agent-05 (`5.161.73.195`), which is currently underutilized for reviews.

Files to change:
- `platform/agents/review-pipeline.sh` — `PERF_IP="5.161.73.195"`
- `platform/agents/collect-reviews.sh` — `[perf]="5.161.73.195"`

Expected gain: review wall time drops by ~30-40% for medium/large diffs.

### 2. Reduce Review Wait Polling Interval

**Problem:** `collect-reviews.sh --wait` polls every 15 seconds. Reviews finish in 2-4 minutes; wasted wall time per cycle is 0-14 seconds.

**Fix:** Change `sleep 15` → `sleep 5` in `collect-reviews.sh`.

### 3. Dynamic `--max-turns` by Task Complexity

**Problem:** All tasks run with `--max-turns 80`. A 10-line config change does not need 80 turns. Unused turns don't cost money but the model may spin when it should stop.

**Fix:** Add optional `complexity:` field to task YAML frontmatter. `run-task.sh` reads it:
- `complexity: simple` → `--max-turns 20`
- `complexity: medium` → `--max-turns 40`
- `complexity: complex` → `--max-turns 80` (default if field absent)

Update `TASK_TEMPLATE.md` to include the field.

### 4. Cap Review `--max-turns`

**Problem:** Review sessions (`run-review.sh`) run with no `--max-turns` cap. A reviewer reads a diff and outputs a verdict — it doesn't need 80 turns.

**Fix:** Add `--max-turns 15` to the claude invocation in `run-review.sh`. Build Validator runs tsc/eslint (needs a few tool calls); 15 is comfortable headroom.

### 5. Task Priority Queue

**Problem:** Queue runner processes tasks in filename order (= task number order). A critical bug fix waits behind a batch of feature tasks queued before it.

**Fix:** Add `priority: critical|high|normal` field to task YAML frontmatter. `queue-runner.sh` reads priority and picks `critical` tasks first, then `high`, then `normal`. Default = `normal`. Implement via temp file rename with prefix `1-`, `2-`, `3-` before sorting.

---

## Cost Reductions

### 1. Remove Static CI Snapshots from run-review.sh (biggest win)

**Problem:** `run-review.sh` injects ~30 hardcoded code snapshots (~200 lines, ~8,000 tokens) into every review prompt — regardless of whether those code sections changed. These were added during the 933-task batch to suppress false positives on known-good code patterns. Now that master is stable, they are dead weight sent to all 4 reviewers on every branch.

**Fix:** Remove the entire static `SNAP_*` extraction block and `CODE_SNAPSHOTS` variable (approximately lines 86–381). Replace with a **dynamic context block** that extracts only the files actually changed in the current diff:

```bash
# Dynamic: extract content of changed files for reviewer context
CHANGED_FILES=$(git diff master..HEAD --name-only 2>/dev/null \
  | grep -v 'package-lock.json\|\.lock$' || true)

DYNAMIC_CONTEXT=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if [[ -f "$REPO/$f" ]]; then
    LINE_COUNT=$(wc -l < "$REPO/$f" 2>/dev/null || echo 0)
    if [[ $LINE_COUNT -le 500 ]]; then
      CONTENT=$(cat "$REPO/$f" 2>/dev/null | head -c 20000 || true)
    else
      # Large file: show only changed hunks with context
      CONTENT=$(git diff master..HEAD -- "$f" 2>/dev/null | head -c 20000 || true)
    fi
    DYNAMIC_CONTEXT="${DYNAMIC_CONTEXT}
### $f
\`\`\`
$CONTENT
\`\`\`
"
  fi
done <<< "$CHANGED_FILES"

CODE_SNAPSHOTS="## Changed File Contents (for reviewer context)
Review the diff below. The full content of changed files is provided here for reference.

${DYNAMIC_CONTEXT}"
```

Also update `reviews/logic-reviewer.md` and `reviews/performance-reviewer.md` to remove the "IMPORTANT: CI pre-verified sections" note (now irrelevant).

Token impact: ~8,000 tokens removed per reviewer × 4 reviewers = **~32,000 tokens saved per review cycle**.

### 2. Model Tiering — Haiku for Reviewers

**Problem:** All review sessions use the default (Sonnet) model. Reviews are pattern-matching + structured output tasks that don't require deep reasoning.

**Fix (phase 2):** In `run-review.sh`, add `--model claude-haiku-4-5-20251001` to the claude invocation. If the result is FAIL, optionally escalate to Sonnet to confirm (prevents false FAILs blocking merges).

```bash
RESULT=$(doppler run -- claude --model claude-haiku-4-5-20251001 \
  --dangerously-skip-permissions --max-turns 15 --print < "$PROMPT_FILE")

# Escalate on FAIL to confirm with Sonnet (prevents false blocks)
if ! echo "$RESULT" | grep -q "^## VERDICT: PASS"; then
  RESULT=$(doppler run -- claude --dangerously-skip-permissions \
    --max-turns 15 --print < "$PROMPT_FILE")
fi
```

Cost impact: ~5-8× reduction on review sessions (Haiku is much cheaper than Sonnet). Escalation on FAIL ensures correctness.

### 3. Diff-Aware Reviewer Skipping

**Problem:** All 4 reviewers run for every branch, even when the diff is trivially small or limited to a specific layer.

**Fix (phase 2):** Add a pre-check to `review-pipeline.sh` that inspects changed file types before dispatching:

| Condition | Action |
|---|---|
| Diff < 30 lines total | Run Build + Security only; auto-pass Logic + Perf |
| No `.py` files changed | Skip Security reviewer's SQL injection scope |
| No `frontend/` files changed | Skip Performance reviewer's React checks |
| Only `*.md` or docs files | Skip all 4 reviewers; auto-pass |

This requires a lightweight pre-check (Haiku or `git diff --stat` analysis) before dispatch.

### 4. Diff Routing Per Reviewer Role

**Problem:** All 4 reviewers receive the full diff (up to 400KB). Each reviewer only cares about a subset of file types.

**Fix (phase 2):** In `run-review.sh`, build role-specific diff slices before building `FULL_PROMPT`:

| Reviewer | Files included |
|---|---|
| Build Validator | Full diff (needs everything for compile errors) |
| Security Reviewer | `*.py`, auth files, SQL, env-touching, routes |
| Logic Reviewer | Full diff minus `*.lock`, migrations, SQL-only files |
| Performance Reviewer | `frontend/**`, `**/routers/*.py`, any DB query file |

Implement via `git diff master..HEAD -- <glob-patterns>` per reviewer role.

---

## Implementation Order

| Priority | Change | File(s) | Effort |
|---|---|---|---|
| **1 — Now** | Move Perf to Agent-05 | `review-pipeline.sh`, `collect-reviews.sh` | 5 min |
| **1 — Now** | Add `--max-turns 15` to reviews | `run-review.sh` | 2 min |
| **1 — Now** | Reduce poll interval 15s → 5s | `collect-reviews.sh` | 1 min |
| **2 — Now** | Remove static CI snapshots, add dynamic context | `run-review.sh` | 30 min |
| **2 — Now** | Remove stale CI note from reviewer prompts | `logic-reviewer.md`, `performance-reviewer.md` | 5 min |
| **3 — Now** | Dynamic max-turns from `complexity:` frontmatter | `run-task.sh`, `dispatch.sh`, `TASK_TEMPLATE.md` | 30 min |
| **4 — Phase 2** | Haiku for reviewers + Sonnet escalation | `run-review.sh` | 1 hour |
| **5 — Phase 2** | Diff-aware reviewer skipping | `review-pipeline.sh` | 2 hours |
| **6 — Phase 2** | Diff routing per reviewer role | `run-review.sh` | 2 hours |

---

## Agent Instructions

- **Use this when:** Optimizing agent pipeline speed or reducing Claude API costs
- **Before this:** Confirm no active review pipeline is running — changes to `run-review.sh` affect in-flight reviews
- **After this:** Test with a small branch: `./agents/review-pipeline.sh <test-branch>` + `./agents/collect-reviews.sh --wait <test-branch>`
- **Implemented via:** Task `#934` in `platform/agents/tasks/`

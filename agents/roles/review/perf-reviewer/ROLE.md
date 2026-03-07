# agents/roles/review/perf-reviewer/ROLE.md
# Role: Perf Reviewer | Server: Agent-03 | Module: review
# Trigger: task.type == 'perf-review' OR task.flags contains 'performance'

## Role Purpose
Identify performance regressions: database query inefficiency, frontend
render bottlenecks, and agent token waste.

## Checklist
1. **N+1 queries** — flag any query inside a loop; batch or JOIN instead
2. **Unbounded queries** — flag SELECT without LIMIT on tables that grow
3. **Missing indexes** — flag WHERE clauses on unindexed columns (large tables)
4. **React render bottlenecks** — unnecessary re-renders, missing memoization
   on expensive components, large lists without virtualization
5. **Agent token waste** — oversized prompts, loading full files when diff suffices,
   no `head_limit` on large Grep results
6. **INNGEST job sizing** — jobs that should be parallelized running serially
7. **PageIndex over-fetching** — loading full tree when partial query suffices

## Handoff
PASS → agent-04 / build-validator
FAIL → agent-03 / planner (perf rework required)
next_server: [per verdict]
next_role: [per verdict]
priority: normal (urgent if flag contains `performance`)

## Handoff Template
---
generated_at_commit: {SESSION_COMMIT}
generated_at_timestamp: {SESSION_TIMESTAMP}
generated_by_role: perf-reviewer
generated_by_server: agent-03
ticket_id: {ticketId}

## Staleness Declaration
# Receiving agent MUST compare generated_at_commit to SESSION_COMMIT.
# If they differ: prepend '⚠️ STALE HANDOFF' and re-read MODULE.md + ROLE.md.

## Task Context
module: review
task_type: perf-review
ticket_description: {description}

## Outputs
verdict: PASS | FAIL
n_plus_one_found: YES | NO
unbounded_queries_found: YES | NO
render_bottlenecks_found: YES | NO
token_waste_found: YES | NO

## Next Role
next_role: build-validator | planner
next_server: agent-04 | agent-03
priority: normal | urgent

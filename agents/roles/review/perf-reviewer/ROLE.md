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

## Handoff
Routes: PASS → build-validator | FAIL → planner (perf rework)
Output fields: see `agents/roles/shared/handoff-schema.md` → perf-reviewer

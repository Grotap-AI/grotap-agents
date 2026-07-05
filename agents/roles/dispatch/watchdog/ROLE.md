# Role: Task Watchdog (automation)
# Implemented today by agent-06 crons: `pipeline_failure_monitor.py` (10m), `deploy_freshness_watchdog.py`
# (5m), and `reconcile_dispatch.py` (30m, flock) — there is no `grotap-watchdog` systemd service.

## Responsibility
Monitor running tasks for failures. Detect crashed, stuck, or error'd tasks and recover them for
re-dispatch — infra-caused failures are relabeled `failed_infra` (no case strike, per GLOBAL).

## What It Watches
1. **Crashed sessions** — task in active/ but no matching tmux session
2. **API errors** — rate limits, auth failures, overloaded errors in logs
3. **Stuck tasks** — no log activity for >4 hours
4. **Stale dispatch rows** — active rows with no live run (they starve MAX_INFLIGHT)

## Recovery Protocol
1. Kill zombie tmux session (if any); clean worktree (`git worktree remove --force`)
2. Archive failed log to `task-{id}.failed.{timestamp}.log`
3. Move task back to pending/ (or relabel row `failed_infra` + reset case to `plan_approved`)
4. Rate limits: wait 5 minutes before recovery — never rapid re-dispatch into the same limit

## Never Do
- Kill a task that is actively producing log output
- Move a completed task back to pending/ (check for "TASK DONE" in log)
- Ignore API errors — always log and recover

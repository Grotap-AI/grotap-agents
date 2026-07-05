# Dispatch Module
# Assignment is owned by the backend continuous loop (every 3 min + completion-webhook refill)
# and the LangGraph orchestrator on Railway, which SSHes dispatches to the fleet.
# Agent-06 hosts the supporting monitor/reconciler crons — there is no dispatcher daemon on it.

## Purpose
Keep every agent server at capacity. No task waits while a slot is open.
Failed tasks get recovered automatically (reconciler + failure monitor, not left orphaned).

## Components
| Component | Where | Purpose |
|---|---|---|
| `pipeline_automation` loop | backend (Railway) | Assigns cases every 3 min; completion webhook refills freed slots |
| LangGraph orchestrator | Railway | Owns run lifecycle; SSHes `dispatch.sh` to fleet servers |
| `reconcile_dispatch.py` | agent-06 cron 30m | Closes stale dispatch rows, relabels infra failures (`failed_infra`, no strike) |
| `pipeline_failure_monitor.py` / `deploy_freshness_watchdog.py` | agent-06 cron 10m/5m | Detect failed runs + stale deploys |

## Task Lifecycle
`pending/ → active/ → done/` — reconciler recovers failed tasks back to pending; API rate-limit
errors get a 5-min cooldown before re-dispatch. Any auto-retry needs backoff/circuit breaker (GLOBAL).

## Tools (platform repo root)
- `bash agents/dispatch.sh <task.md> <server-ip> <session-name>` — manual dispatch
- `bash agents/dispatch-execute.sh <task.md> <session-name>` — auto-route to most free slots
- `bash agents/server-status.sh` — check slot availability

## Key Rules
- Concurrent tasks are git-worktree isolated, max 3 per server
- Executor pool: agent-04 primary (3 slots); overflow agent-02/03/05 (3 each); agent-06 (2). Roster: `agents/SERVERS.md`.
- Tasks move pending → active on dispatch, active → done on completion

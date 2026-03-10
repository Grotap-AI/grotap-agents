# Dispatch Module
# Priority: #1 — dispatch takes precedence over ALL other roles.
# Assigned to: Agent-08 (77.42.42.213) — two systemd services, never stop.

## Purpose
Keep every agent server at maximum capacity 24/7. No server sits idle.
No task waits in queue while a slot is open. Failed tasks get recovered automatically.
Agent-08 owns this module permanently.

## Roles
| Role | Service | Script | Purpose |
|---|---|---|---|
| Coordinator | `grotap-dispatch` | `/home/agent/self-dispatch.sh` | Pick up tasks, create worktrees, launch in tmux |
| Watchdog | `grotap-watchdog` | `/home/agent/task-watchdog.sh` | Detect failures, recover tasks back to pending/ |

Both services run 24/7 via systemd with `Restart=always`. They survive reboots.

## Task Lifecycle
```
pending/  →  active/  →  done/
   ↑            |
   └── watchdog recovers failed tasks
```

## Dispatch Order
1. `agents/tasks/pending/` — lowest ID first
2. `agents/tasks/active/` — backlog tasks not currently running, lowest ID first

## Tools
- `bash agents/dispatch.sh <task.md> <server-ip> <session-name>` — manual dispatch
- `bash agents/dispatch-execute.sh <task.md> <session-name>` — auto-route
- `bash agents/install-dispatcher.sh` — install self-dispatch on all servers
- `bash agents/server-status.sh` — check slot availability

## Key Rules
- Every server supports 3 concurrent tasks (git worktree isolated)
- Primary executors: agent-01, 04, 07, 08
- Overflow executors: agent-02, 03, 05 (dispatch when idle)
- agent-06: deploy ops only, never dispatch execution tasks
- Watchdog checks every 30s — crashed/stuck/errored tasks auto-recover
- API rate limit errors trigger 5-min cooldown before re-dispatch
- Tasks move pending → active on dispatch, active → done on completion

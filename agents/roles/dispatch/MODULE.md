# Dispatch Module
# Priority: #1 — dispatch takes precedence over ALL other roles.
# If a server has idle slots, dispatch fills them before any other work.

## Purpose
Keep every agent server at maximum capacity 24/7. No server sits idle.
No task waits in queue while a slot is open.

## Dispatch Order
1. `agents/tasks/pending/` — newest tasks, lowest ID first
2. `agents/tasks/active/` — backlog tasks not currently running, lowest ID first

## Tools
- `bash agents/dispatch.sh <task.md> <server-ip> <session-name>` — manual dispatch
- `bash agents/dispatch-execute.sh <task.md> <session-name>` — auto-route
- `bash agents/continuous-dispatch.sh` — 24/7 auto-refill loop (run in tmux)
- `bash agents/server-status.sh` — check slot availability

## Key Rules
- Every server supports 3 concurrent tasks (git worktree isolated)
- Primary executors: agent-01, 04, 07, 08
- Overflow executors: agent-02, 03, 05 (dispatch when idle)
- agent-06: deploy ops only, never dispatch execution tasks
- After dispatching, ALWAYS verify tmux session started on target server
- If dispatch fails (missing API key, stale worktree): fix and re-dispatch immediately
- Check cluster every 60 seconds when running continuous-dispatch.sh

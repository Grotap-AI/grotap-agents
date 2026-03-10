# Role: Task Watchdog
# Priority: #1 — runs alongside Dispatch Coordinator, never stops
# Trigger: ALWAYS RUNNING — systemd service `grotap-watchdog`

## Responsibility
Monitor all running tasks for failures. Detect crashed, stuck, or error'd tasks
and recover them by moving back to pending/ for re-dispatch.

## What It Watches
1. **Crashed sessions** — task in active/ but no matching tmux session
2. **API errors** — rate limits, auth failures, overloaded errors in logs
3. **Stuck tasks** — no log activity for >4 hours

## Recovery Protocol
1. Kill zombie tmux session (if any)
2. Clean up worktree (`git worktree remove --force`)
3. Archive failed log to `task-{id}.failed.{timestamp}.log`
4. Move task file from active/ back to pending/
5. Self-dispatch picks it up on next cycle

## Rate Limit Handling
When API usage limits are hit, the watchdog waits 5 minutes before recovering
the task — this prevents rapid re-dispatch into the same limit.

## Systemd Service
```bash
systemctl status grotap-watchdog    # check
systemctl restart grotap-watchdog   # restart
journalctl -u grotap-watchdog -f    # live logs
```

## Never Do
- Kill a task that is actively producing log output
- Move a completed task back to pending/ (check for "TASK DONE" in log)
- Ignore API errors — always log and recover

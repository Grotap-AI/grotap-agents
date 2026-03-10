# Role: Dispatch Coordinator
# Priority: #1 — this role overrides all other roles
# Trigger: ALWAYS RUNNING — systemd service `grotap-dispatch`
# Server: Agent-08 (77.42.42.213) — permanent assignment

## Responsibility
You are the dispatch coordinator. Your only job is ensuring every agent server
is running at maximum capacity 24/7. You never stop. You are a systemd service.

## How It Works (systemd — fully autonomous)
The dispatch coordinator runs as `/home/agent/self-dispatch.sh` via systemd.
It does NOT require a Claude session to operate. It is a bash loop that:
1. Checks local tmux sessions to count used slots
2. Picks next task from `pending/` (lowest ID first), then `active/`
3. Moves task from `pending/` → `active/` before dispatching (prevents re-dispatch)
4. Creates a git worktree, writes a runner script, launches in tmux
5. On completion, runner moves task to `done/` and cleans up worktree
6. Loops forever — sleeps 10s when full, 30s when no tasks

## Paired Service: Task Watchdog
The watchdog (`grotap-watchdog.service`) runs alongside dispatch and handles:
- Crashed tmux sessions → recovers task back to `pending/`
- API rate limit errors → waits 5 min, then recovers
- Stuck tasks (>4h no log activity) → kills and recovers
See `roles/dispatch/watchdog/ROLE.md` for details.

## Systemd Commands
```bash
systemctl status grotap-dispatch     # check dispatch
systemctl status grotap-watchdog     # check watchdog
systemctl restart grotap-dispatch    # restart dispatch
systemctl restart grotap-watchdog    # restart watchdog
journalctl -u grotap-dispatch -f     # live dispatch logs
journalctl -u grotap-watchdog -f     # live watchdog logs
```

## Task File Lifecycle
```
pending/  →  active/  →  done/
   ↑            |
   └── (watchdog recovers failed tasks)
```

## Common Failures
- "API usage limits" → key rate-limited; watchdog waits 5 min then retries
- "Doppler Error: you must provide a token" → API key not in .env/.profile
  Fix: `echo 'export ANTHROPIC_API_KEY=...' > /home/agent/.env`
- Stale worktree → `git worktree remove <path> --force`
- SSH timeout → server may be rebooting, retry in 60s

## Never Do
- Leave a server idle when tasks exist in pending/ or active/
- Dispatch to agent-06 (deploy ops only)
- Dispatch more than 3 tasks to one server
- Skip verification after dispatch
- Stop the systemd services — they must run 24/7

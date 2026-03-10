# agents/servers/agent-08.md
# Server: Agent-08 | IP: 77.42.42.213
# Type: Dispatch Coordinator (PRIMARY) + Execute (secondary)
# DC: Helsinki (hel1)
# Hetzner Project: Secondary (HETZNER_API_TOKEN_2)

## Role Assignments

### Dispatch Coordinator (PRIMARY — #1 PRIORITY)
trigger:    ALWAYS RUNNING — systemd service `grotap-dispatch`, never stops
priority:   #1 — this role overrides all other work on this server
load_order: GLOBAL.md → roles/dispatch/MODULE.md → roles/dispatch/coordinator/ROLE.md

Runs `self-dispatch.sh` as systemd service. Picks tasks from pending/, creates
worktrees, launches Claude in tmux. Moves tasks pending → active → done.
- Survives reboots (systemd Restart=always)
- 2 of 3 worktree slots reserved for dispatched execution tasks
- 1 slot always available for dispatch overhead

### Task Watchdog (PRIMARY — #1 PRIORITY, paired with Coordinator)
trigger:    ALWAYS RUNNING — systemd service `grotap-watchdog`, never stops
priority:   #1 — runs alongside dispatch coordinator
load_order: GLOBAL.md → roles/dispatch/MODULE.md → roles/dispatch/watchdog/ROLE.md

Runs `task-watchdog.sh` as systemd service. Monitors every 30s for:
- Crashed tmux sessions (task in active/ but session dead)
- API errors (rate limits, auth failures) in task logs
- Stuck tasks (no log activity >4 hours)
Recovery: moves failed tasks back to pending/ for re-dispatch.

### Execute (secondary)
trigger:    task.stage == 'execution' (only when dispatch has filled other servers first)
priority:   secondary — dispatch takes precedence
load_order: GLOBAL.md → roles/execution/MODULE.md → roles/execution/execute/ROLE.md → handoff (if exists)
max_slots:  2 (1 slot reserved for dispatch coordination)

## Dispatch Commands
```bash
# This server's self-dispatch (systemd — auto-starts on boot)
systemctl status grotap-dispatch
systemctl restart grotap-dispatch
journalctl -u grotap-dispatch -f

# Manual override (if systemd service is stopped)
bash /home/agent/self-dispatch.sh
```

## Inbound Routes (this server receives from)
- self-dispatch.sh — auto-assigns tasks to itself when other servers are full
- dispatch-execute.sh — auto-routed execution tasks (primary tier)

## Outbound Routes (this server sends to)
- ALL servers — dispatch coordinator sends tasks to every server
- agent-03 / perf-reviewer — after build, for performance review
- agent-04 / rule-enforcer — rule violation flagged mid-execution
- agent-02 / security-reviewer — security flag raised

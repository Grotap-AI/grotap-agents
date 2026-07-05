# Role: Dispatch Coordinator (automation — not a Claude session)
# Owned by: backend `pipeline_automation` loop (3-min assign + completion-webhook refill) and the
# LangGraph orchestrator on Railway, which SSHes `dispatch.sh` to fleet servers.
# Agent-06 hosts the supporting crons (reconciler, failure monitor) — no dispatcher daemon runs there.

## Responsibility
Keep every execute server at capacity: no case waits while a slot is open, and nothing double-claims
a slot. Assignment picks `plan_approved` cases; the orchestrator creates the worktree, launches the
run in tmux on the target server, and tracks lifecycle in `pipeline_dispatch_log`.

## Mechanics per dispatch
1. Task moves `pending/` → `active/` before launch (prevents re-dispatch)
2. Git worktree per session on the target server (max 3/server; roster in `agents/SERVERS.md`)
3. On completion, runner moves task to `done/`, cleans up the worktree, completion webhook refills the slot

## Common Failures
- "API usage limits" → key rate-limited; 5-min cooldown then retry
- "Doppler Error: you must provide a token" → check `doppler me` as the `agent` user.
  Git auth uses `credential.helper = /home/agent/bin/git-credential-doppler` (per GLOBAL) —
  NEVER write a static token to `~/.env`.
- Stale worktree → `git worktree remove <path> --force`
- SSH timeout → server may be rebooting, retry in 60s; never open unbounded concurrent SSH (GLOBAL)
- Stale active dispatch rows starve MAX_INFLIGHT → close rows via reconciler, then REDEPLOY the
  orchestrator (its slot map is boot-only)

## Never Do
- Leave a server idle when approved cases exist
- Dispatch more than 3 tasks to one server (agent-06: max 2)
- Dispatch to hosts outside the pool (cobrowse, LLM engines, retired boxes — see SERVERS.md)
- Instant re-assign on failure without backoff/circuit breaker (GLOBAL — retry massacre)

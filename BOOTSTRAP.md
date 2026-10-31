# BOOTSTRAP.md — Fleet / jumpbox session init. No exceptions. No quick sessions.
Workstation sessions use `CLAUDE.md` instead. Canonical load order: `AGENTS.md`. Headless fleet builders get platform `agents/FLEET_HEADER.md` by default.

## Steps (do all, in order)
1. Jumpbox: `git pull --ff-only origin master`. Fleet host: skip (the runner syncs and pins this tree). Then `git rev-parse HEAD` → SESSION_COMMIT.
2. `./.claude-session-init.sh` → STOP if it fails, report the error.
3. `/codex:setup` → verify Codex CLI ready. WARN if unavailable (non-blocking).
4. Load `agents/GLOBAL.md`; for role work, `agents/roles/{module}/MODULE.md` → `agents/roles/{module}/{role}/ROLE.md`. Everything else on demand per `AGENTS.md` (`agents/SERVERS.md` only for fleet/SSH/host work). Implemented-plan must-obey pointers live in `agents/GLOBAL.md`; do not load full plan novels.
5. Output: `BOOTSTRAP COMPLETE | Commit: {SESSION_COMMIT} | Role: {role} | Server: {server} | Codex: {ready|unavailable}`

Identify your server by hostname/IP (`hostname -I`) against the roster in `agents/SERVERS.md`.
Fleet names: `docs/GROTAP-SERVER-RENAME-PLAN.md` (status: `docs/GROTAP-SERVER-RENAME-STATUS.md`).
Overflow executor: load `roles/execution/MODULE.md` + `roles/execution/execute/ROLE.md`.

## Server Setup Checklist (new server or after reset — full list in agents/SERVERS.md)
- Swap: `bash agents/ensure-swap.sh` (this repo; idempotent 4 GiB swap + swappiness). Re-run after ANY hard reset/rebuild — OOM has wedged two boxes. Also runs automatically in grotap-platform `agents/setup-server.sh`.
- API key in **both**: `/home/agent/.env` AND `/home/agent/.profile` (`export ANTHROPIC_API_KEY=...`)
- Git safe.directory if root/agent mismatch: `git config --global --add safe.directory /home/agent/grotap-platform`
- SCP task files (not in git): `scp -r agents/tasks/pending agents/tasks/active agent-06-claude:/home/agent/grotap-platform/agents/tasks/` — `agent-06-claude` is the live ops host (see `agents/SERVERS.md`).
- Status server: `node agents/status-server.js` running on localhost:7654

## Post-Task
Auto-dispatch permanently frozen 2026-10-30 (code-enforced): no automatic slot refill, ever. Build in Claude CLI sessions; still file/answer pipeline cases; agents work only human-dispatched `agent_eligible` cases. Manual ops (platform repo root):
`bash agents/server-status.sh` then `bash agents/dispatch-execute.sh <task.md> <session>`.

## Never Do
- SSH by raw IP — use the Hetzner Cloud name from `agents/SERVERS.md` (e.g. `ssh agent-06-claude`). Aliases of deleted hosts are dead: never re-point one at a recycled IP. Keys: `agents/scripts/ssh-key-for.sh`.
- `git add -A` or `git add .`
- Leave agents idle or skip bootstrap
- Load `docs/CLAUDE.md` as agent context — use `agents/GLOBAL.md`
- Assume task files are in git (pending/active are local-only, must SCP)

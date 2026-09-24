# agents/roles/deployment-ops/health-monitor/ROLE.md
# Role: Health Monitor | Server: agent-05-claude (Hillsboro, OFF) | Module: deployment-ops
# Trigger: scheduled (every 5 min) OR task.type == 'health-check'

## Role Purpose
Continuously monitor all production endpoints and catch outages before users do.
Detects 502s, 500s, timeouts, and DNS resolution failures that have caused
prolonged undetected downtime in the past.

## Failure Patterns This Role Catches
1. Railway backend crashed — /health returns 502 or timeout
2. Vercel frontend down — apps.grotap.com returns 500 or Vercel error page
3. DNS misconfiguration — api.grotap.com resolving to wrong target
4. Database connection failure — /health returns 200 but API calls return 500
5. Auth system down — WorkOS callback failures
6. Agent servers unreachable — SSH connection refused

## Endpoints to Monitor

### HTTP Health Checks
| Endpoint | Expected | Timeout |
|---|---|---|
| https://api.grotap.com/health | 200 OK | 5s |
| https://apps.grotap.com | 200 OK | 10s |
| https://agents.grotap.com | 200 OK | 10s |
| https://agents.grotap.ai | 200 OK | 10s |

### Agent Server SSH Checks (roster: `agents/SERVERS.md`)
| Server | IP | Check |
|---|---|---|
| agent-01-claude | 5.161.74.39 | SSH port 22 open |
| agent-02-claude | 5.161.81.193 | SSH port 22 open |
| agent-03-claude | 178.156.222.220 | SSH port 22 open |
| agent-04-claude | 5.161.73.195 | SSH port 22 open. Running |
| agent-05-claude | 5.78.178.81 | Hillsboro ops box. OFF / unreachable |
| agent-06-claude | 5.161.53.103 | Ashburn. Linux hostname still grotap-agent-06-ash |

### DNS Resolution Checks
Resolve each domain and compare to MODULE.md "Expected DNS" (canonical table).

## Alert Escalation
- 1 failed check → retry in 30s
- 2 consecutive failures → log to health-alerts.log
- 3 consecutive failures → escalate to deploy-executor for redeployment
- DNS failure → escalate to human (infrastructure change required)

## Output Format
```
HEALTH CHECK — {timestamp}

HTTP:
- api.grotap.com/health: {status} ({response_time}ms)
- apps.grotap.com: {status} ({response_time}ms)
- agents.grotap.com: {status} ({response_time}ms)
- agents.grotap.ai: {status} ({response_time}ms)

Agents:
- agent-01-claude (5.161.74.39): REACHABLE | UNREACHABLE
- agent-02-claude (5.161.81.193): REACHABLE | UNREACHABLE
- agent-03-claude (178.156.222.220): REACHABLE | UNREACHABLE
- agent-04-claude (5.161.73.195): REACHABLE | UNREACHABLE
- agent-05-claude (5.78.178.81): REACHABLE | UNREACHABLE
- agent-06-claude (5.161.53.103): REACHABLE | UNREACHABLE

DNS:
- api.grotap.com → {resolved_target} (CORRECT | WRONG)
- apps.grotap.com → {resolved_target} (CORRECT | WRONG)

Status: ALL OK | DEGRADED | DOWN
```

## Handoff
ALL OK → none (terminal)
DEGRADED → deploy-executor (attempt recovery)
DOWN → human escalation + deploy-executor
next_server: agent-05-claude
next_role: deploy-executor
priority: critical

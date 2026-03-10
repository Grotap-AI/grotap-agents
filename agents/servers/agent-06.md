# agents/servers/agent-06.md
# Server: Agent-06 | IP: 5.78.178.81
# Type: cpx31 (4 vCPU / 8 GB) | DC: Hillsboro, OR (hil-dc1)
# Roles: Deploy Verifier | Deploy Executor | Env Validator | Health Monitor | DNS Watchdog | Post-Deploy QA
# Hetzner Project: Secondary (HETZNER_API_TOKEN_2)

## Role Assignments

### Deploy Verifier
trigger:    event == 'merge-to-master' OR task.type == 'deploy-verify'
load_order: GLOBAL.md → roles/deployment-ops/MODULE.md → roles/deployment-ops/deploy-verifier/ROLE.md → handoff (if exists)

### Deploy Executor
trigger:    deploy-verifier verdict == FAIL OR task.type == 'deploy-execute'
load_order: GLOBAL.md → roles/deployment-ops/MODULE.md → roles/deployment-ops/deploy-executor/ROLE.md → handoff (if exists)

### Env Validator
trigger:    task.type == 'env-validate' OR before any deploy-execute
load_order: GLOBAL.md → roles/deployment-ops/MODULE.md → roles/deployment-ops/env-validator/ROLE.md → handoff (if exists)

### Health Monitor
trigger:    scheduled (every 5 min) OR task.type == 'health-check'
load_order: GLOBAL.md → roles/deployment-ops/MODULE.md → roles/deployment-ops/health-monitor/ROLE.md → handoff (if exists)

### DNS Watchdog
trigger:    scheduled (daily) OR task.type == 'dns-check' OR after infra changes
load_order: GLOBAL.md → roles/deployment-ops/MODULE.md → roles/deployment-ops/dns-watchdog/ROLE.md → handoff (if exists)

### Post-Deploy QA
trigger:    deploy-verifier verdict == PASS OR task.type == 'post-deploy-qa'
load_order: GLOBAL.md → roles/deployment-ops/MODULE.md → roles/deployment-ops/post-deploy-qa/ROLE.md → handoff (if exists)

## Dispatch
bash agents/dispatch.sh agents/tasks/{ticket}.md 5.78.178.81 {session-name}

## Inbound Routes (this server receives from)
- agent-04 / build-validator PASS → triggers deploy-verifier
- Any merge to master → triggers deploy-verifier
- Scheduled cron → triggers health-monitor, dns-watchdog
- deploy-verifier FAIL → triggers deploy-executor
- deploy-verifier PASS → triggers post-deploy-qa

## Outbound Routes (this server sends to)
- Human escalation — when deployment infrastructure is broken
- agent-04 / execute — when hotfix is needed for production regression

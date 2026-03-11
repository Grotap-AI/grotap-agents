# agents/OWNERS.md
# Ownership contract — every file in /agents listed with owner and tier.
# Tier 1: Tech Lead only (PR + 2 senior reviews + 48hr window)
# Tier 2: Domain/Infra Lead (PR + 1 senior + 1 peer + 24hr window)
# Tier 3: Role Owner (PR + 1 peer review, same-day merge allowed)
# Tier 4: Agent auto-generated (no review, auto-committed to agent-state branch)
#
# Format: file_path | owner | tier | backup_owner
# Owner: @Grotap1 (sole operator — expand as team grows)

## Tier 1 — Protected
agents/GLOBAL.md                                        | @Grotap1      | 1 | @Grotap1
agents/registry.md                                      | @Grotap1      | 1 | @Grotap1
agents/OWNERS.md                                        | @Grotap1      | 1 | @Grotap1
BOOTSTRAP.md                                            | @Grotap1      | 1 | @Grotap1
.claude-session-init.sh                                 | @Grotap1     | 1 | @Grotap1

## Tier 2 — Server Manifests
agents/servers/agent-01.md                              | @Grotap1     | 2 | @Grotap1
agents/servers/agent-02.md                              | @Grotap1     | 2 | @Grotap1
agents/servers/agent-03.md                              | @Grotap1     | 2 | @Grotap1
agents/servers/agent-04.md                              | @Grotap1     | 2 | @Grotap1
agents/servers/agent-05.md                              | @Grotap1     | 2 | @Grotap1
agents/servers/agent-06.md                              | @Grotap1     | 2 | @Grotap1
agents/servers/agent-07.md                              | @Grotap1     | 2 | @Grotap1
agents/servers/agent-08.md                              | @Grotap1     | 2 | @Grotap1

## Tier 2 — Module Files
agents/roles/intake/MODULE.md                           | @Grotap1    | 2 | @Grotap1
agents/roles/security/MODULE.md                         | @Grotap1    | 2 | @Grotap1
agents/roles/pipeline/MODULE.md                         | @Grotap1    | 2 | @Grotap1
agents/roles/approvals/MODULE.md                        | @Grotap1    | 2 | @Grotap1
agents/roles/planning/MODULE.md                         | @Grotap1    | 2 | @Grotap1
agents/roles/review/MODULE.md                           | @Grotap1    | 2 | @Grotap1
agents/roles/execution/MODULE.md                        | @Grotap1    | 2 | @Grotap1
agents/roles/enforcement/MODULE.md                      | @Grotap1    | 2 | @Grotap1
agents/roles/dispatch/MODULE.md                         | @Grotap1    | 2 | @Grotap1
agents/roles/deployment-ops/MODULE.md                   | @Grotap1    | 2 | @Grotap1

## Tier 3 — Role Files
agents/roles/intake/intake/ROLE.md                      | @Grotap1     | 3 | @Grotap1
agents/roles/intake/triage/ROLE.md                      | @Grotap1     | 3 | @Grotap1
agents/roles/security/security-reviewer/ROLE.md         | @Grotap1     | 3 | @Grotap1
agents/roles/pipeline/pipeline-detail/ROLE.md           | @Grotap1     | 3 | @Grotap1
agents/roles/pipeline/audit-filters/ROLE.md             | @Grotap1     | 3 | @Grotap1
agents/roles/approvals/mobile-approvals/ROLE.md         | @Grotap1     | 3 | @Grotap1
agents/roles/planning/planner/ROLE.md                   | @Grotap1     | 3 | @Grotap1
agents/roles/review/fix-reviewer/ROLE.md                | @Grotap1     | 3 | @Grotap1
agents/roles/review/policy-reviewer/ROLE.md             | @Grotap1     | 3 | @Grotap1
agents/roles/review/logic-reviewer/ROLE.md              | @Grotap1     | 3 | @Grotap1
agents/roles/review/perf-reviewer/ROLE.md               | @Grotap1     | 3 | @Grotap1
agents/roles/execution/execute/ROLE.md                  | @Grotap1     | 3 | @Grotap1
agents/roles/enforcement/change-reviewer/ROLE.md        | @Grotap1     | 3 | @Grotap1
agents/roles/enforcement/rule-enforcer/ROLE.md          | @Grotap1     | 3 | @Grotap1
agents/roles/enforcement/build-validator/ROLE.md        | @Grotap1     | 3 | @Grotap1
agents/roles/deployment-ops/deploy-verifier/ROLE.md      | @Grotap1     | 3 | @Grotap1
agents/roles/deployment-ops/deploy-executor/ROLE.md     | @Grotap1     | 3 | @Grotap1
agents/roles/deployment-ops/env-validator/ROLE.md       | @Grotap1     | 3 | @Grotap1
agents/roles/deployment-ops/health-monitor/ROLE.md      | @Grotap1     | 3 | @Grotap1
agents/roles/deployment-ops/dns-watchdog/ROLE.md        | @Grotap1     | 3 | @Grotap1
agents/roles/deployment-ops/post-deploy-qa/ROLE.md      | @Grotap1     | 3 | @Grotap1
agents/roles/dispatch/coordinator/ROLE.md               | @Grotap1     | 3 | @Grotap1
agents/roles/dispatch/watchdog/ROLE.md                  | @Grotap1     | 3 | @Grotap1
agents/roles/shared/conventions.md                      | @Grotap1    | 3 | @Grotap1

## Tier 4 — Agent-Generated (no review required)
state/handoffs/handoff-*.md                             | agent-auto      | 4 | none

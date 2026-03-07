# agents/OWNERS.md
# Ownership contract — every file in /agents listed with owner and tier.
# Tier 1: Tech Lead only (PR + 2 senior reviews + 48hr window)
# Tier 2: Domain/Infra Lead (PR + 1 senior + 1 peer + 24hr window)
# Tier 3: Role Owner (PR + 1 peer review, same-day merge allowed)
# Tier 4: Agent auto-generated (no review, auto-committed to agent-state branch)
#
# Format: file_path | owner | tier | backup_owner
# ⚠️  Owner handles below are PLACEHOLDERS — fill in real GitHub handles.

## Tier 1 — Protected
agents/GLOBAL.md                                        | @tech-lead      | 1 | @architect
agents/registry.md                                      | @tech-lead      | 1 | @architect
agents/OWNERS.md                                        | @tech-lead      | 1 | @architect
BOOTSTRAP.md                                            | @tech-lead      | 1 | @architect
.claude-session-init.sh                                 | @infra-lead     | 1 | @tech-lead

## Tier 2 — Server Manifests
agents/servers/agent-02.md                              | @infra-lead     | 2 | @tech-lead
agents/servers/agent-03.md                              | @infra-lead     | 2 | @tech-lead
agents/servers/agent-04.md                              | @infra-lead     | 2 | @tech-lead
agents/servers/agent-05.md                              | @infra-lead     | 2 | @tech-lead

## Tier 2 — Module Files
agents/roles/intake/MODULE.md                           | @domain-lead    | 2 | @tech-lead
agents/roles/security/MODULE.md                         | @domain-lead    | 2 | @tech-lead
agents/roles/pipeline/MODULE.md                         | @domain-lead    | 2 | @tech-lead
agents/roles/approvals/MODULE.md                        | @domain-lead    | 2 | @tech-lead
agents/roles/planning/MODULE.md                         | @domain-lead    | 2 | @tech-lead
agents/roles/review/MODULE.md                           | @domain-lead    | 2 | @tech-lead
agents/roles/execution/MODULE.md                        | @domain-lead    | 2 | @tech-lead
agents/roles/enforcement/MODULE.md                      | @domain-lead    | 2 | @tech-lead

## Tier 3 — Role Files
agents/roles/intake/intake/ROLE.md                      | @role-owner     | 3 | @domain-lead
agents/roles/intake/triage/ROLE.md                      | @role-owner     | 3 | @domain-lead
agents/roles/security/security-reviewer/ROLE.md         | @role-owner     | 3 | @domain-lead
agents/roles/pipeline/pipeline-detail/ROLE.md           | @role-owner     | 3 | @domain-lead
agents/roles/pipeline/audit-filters/ROLE.md             | @role-owner     | 3 | @domain-lead
agents/roles/approvals/mobile-approvals/ROLE.md         | @role-owner     | 3 | @domain-lead
agents/roles/planning/planner/ROLE.md                   | @role-owner     | 3 | @domain-lead
agents/roles/review/fix-reviewer/ROLE.md                | @role-owner     | 3 | @domain-lead
agents/roles/review/policy-reviewer/ROLE.md             | @role-owner     | 3 | @domain-lead
agents/roles/review/logic-reviewer/ROLE.md              | @role-owner     | 3 | @domain-lead
agents/roles/review/perf-reviewer/ROLE.md               | @role-owner     | 3 | @domain-lead
agents/roles/execution/execute/ROLE.md                  | @role-owner     | 3 | @domain-lead
agents/roles/enforcement/change-reviewer/ROLE.md        | @role-owner     | 3 | @domain-lead
agents/roles/enforcement/rule-enforcer/ROLE.md          | @role-owner     | 3 | @domain-lead
agents/roles/enforcement/build-validator/ROLE.md        | @role-owner     | 3 | @domain-lead
agents/roles/shared/conventions.md                      | @domain-lead    | 3 | @tech-lead

## Tier 4 — Agent-Generated (no review required)
state/handoffs/handoff-*.md                             | agent-auto      | 4 | none

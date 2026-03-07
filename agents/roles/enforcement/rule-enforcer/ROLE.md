# agents/roles/enforcement/rule-enforcer/ROLE.md
# Role: Rule Enforcer | Server: Agent-04 | Module: enforcement
# Trigger: task.type == 'rule-enforcement' OR task.flags contains 'rule-violation'

## Role Purpose
Investigate a flagged rule violation, confirm whether it occurred,
and enforce the appropriate consequence (block, escalate, or clear).

## Enforcement Checklist
1. Identify which rule is flagged (1–9) from the task context
2. Read the relevant code — confirm violation is real, not a false positive
3. For Rules 1–6 (security/arch): escalate to agent-02 / security-reviewer
4. For Rules 7–9 (pattern/UX): document violation and route back to planner
5. Confirm no `--no-verify` was used to bypass hooks
6. Confirm no force-push to main/master occurred

## Escalation Paths
| Rule | Action |
|---|---|
| 1 (secrets) | Immediately escalate → agent-02 / security-reviewer |
| 2 (Python agents) | Block + route → agent-03 / planner to rewrite in TypeScript |
| 3 (direct SDK) | Block + route → agent-03 / planner to add vendor wrapper |
| 4 (cross-tenant) | Block + escalate → agent-02 / security-reviewer |
| 5 (shared schema) | Block + route → agent-03 / planner |
| 6 (skip compliance) | Block + escalate → agent-02 / security-reviewer |
| 7 (vector search) | Block + route → agent-03 / planner |
| 8 (merge without review) | Block — do not merge under any circumstances |
| 9 (missing AppShell) | Block + route → agent-04 / execute to add AppShell |

## Handoff
cleared   → agent-04 / build-validator
escalated → agent-02 / security-reviewer
rework    → agent-03 / planner
next_server: [per outcome]
next_role: [per outcome]
priority: urgent

## Handoff Template
---
generated_at_commit: {SESSION_COMMIT}
generated_at_timestamp: {SESSION_TIMESTAMP}
generated_by_role: rule-enforcer
generated_by_server: agent-04
ticket_id: {ticketId}

## Staleness Declaration
# Receiving agent MUST compare generated_at_commit to SESSION_COMMIT.
# If they differ: prepend '⚠️ STALE HANDOFF' and re-read MODULE.md + ROLE.md.

## Task Context
module: enforcement
task_type: rule-enforcement
ticket_description: {description}

## Outputs
rule_violated: {rule number or NONE}
violation_confirmed: YES | NO | FALSE-POSITIVE
action_taken: escalated | blocked | cleared

## Next Role
next_role: build-validator | security-reviewer | planner
next_server: agent-04 | agent-02 | agent-03
priority: urgent

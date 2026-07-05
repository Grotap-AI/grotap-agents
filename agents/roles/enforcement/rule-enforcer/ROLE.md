# agents/roles/enforcement/rule-enforcer/ROLE.md
# Role: Rule Enforcer | Server: Agent-04 | Module: enforcement
# Trigger: task.type == 'rule-enforcement' OR task.flags contains 'rule-violation'

## Role Purpose
Investigate a flagged rule violation, confirm whether it occurred,
and enforce the appropriate consequence (block, escalate, or clear).

## Enforcement Checklist
1. Identify which rule is flagged (1–8) from the task context
2. Read the relevant code — confirm violation is real, not a false positive
3. For Rules 1–6 (security/arch): escalate to agent-02 / security-reviewer
4. For Rules 7–8: enforce per the escalation matrix below
5. Confirm no `--no-verify` was used to bypass hooks
6. Confirm no force-push to main/master occurred

## Escalation Paths
| Rule | Action |
|---|---|
| 1 (secrets) | Immediately escalate → agent-02 / security-reviewer |
| 2 (Python agents) | Block + route → agent-03 / planner to rewrite in TypeScript |
| 3 (direct SDK) | Block + route → agent-03 / planner to add vendor wrapper |
| 4 (cross-tenant) | Block + escalate → agent-02 / security-reviewer |
| 5 (RLS bypass / weakened policy) | Block + escalate → agent-02 / security-reviewer |
| 6 (skip compliance) | Block + escalate → agent-02 / security-reviewer |
| 7 (merge without review) | Block — do not merge under any circumstances |
| 8 (missing AppShell / Cobrowse) | Block + route → agent-04 / execute to add AppShell |

## Handoff
Routes: cleared → agent-04 / build-validator | escalated → agent-02 / security-reviewer
rework → agent-03 / planner — priority: urgent
Output fields: see `agents/roles/shared/handoff-schema.md` → rule-enforcer

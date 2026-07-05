# agents/roles/security/security-reviewer/ROLE.md
# Role: Security Reviewer | Server: Agent-02 | Module: security
# Trigger: task.type == 'security-review' OR task.flags contains 'security'

## Role Purpose
Audit a code branch for security violations before it is allowed to merge.
Return a structured PASS/FAIL verdict with specific file:line citations.

## Review Checklist — Run All Items
1. **Secrets scan** — run GitGuardian MCP compliance node; fail on any finding
2. **Vendor wrapper compliance** — grep for direct SDK imports (stripe, workos,
   r2) outside `app/providers/` — each is a Rule 3 violation
3. **Tenant isolation** — verify every DB query includes `tenant_id` or
   `organization_id` scope; flag any unscoped SELECT/UPDATE/DELETE; RLS
   policies never weakened (Rule 5)
4. **Auth bypass** — check no route skips WorkOS JWT middleware
5. **Commit hygiene** — confirm no `--no-verify` flags in recent commits
6. **Hardcoded values** — grep for UUIDs, API keys, passwords in source files
7. **Input sanitization** — spot-check user-facing inputs for XSS surface
8. Verify GLOBAL Rules 1–8 + ⚠ FAIL causes apply to the diff

## Output Format
```
SECURITY REVIEW — ticket #{ticket_id}
Branch: {branch}
Verdict: PASS | FAIL | WARN

Findings:
- [FAIL] {file}:{line} — {description}
- [WARN] {file}:{line} — {description}

Rules violated: {list rule numbers or NONE}
```

## Handoff
Routes: PASS → agent-03 / planner (or return to original route from triage)
FAIL → agent-02 / triage (re-triage with security flag escalated, priority urgent)
Output fields: see `agents/roles/shared/handoff-schema.md` → security-reviewer

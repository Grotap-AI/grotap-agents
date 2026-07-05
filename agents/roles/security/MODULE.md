# agents/roles/security/MODULE.md
# Security module — Layer 2 domain context.
# Covers: security review of all code changes before merge.

## Module Scope
The security module enforces the platform's security posture on every code change.
It has one role: Security Reviewer, which runs as part of the 4-reviewer pipeline.

A branch flagged with `security` by triage, or any branch submitted for merge,
must pass this module before proceeding.

## What Security Reviewer Checks
- Verify GLOBAL Rules 1–8 + ⚠ FAIL causes apply to the diff (secrets, wrappers,
  cross-tenant access, compliance node)
- Tenant isolation via FORCE RLS + `app.current_tenant_id` GUC; RLS policies never weakened (Rule 5)
- No `--no-verify` on commits
- No hardcoded tenant IDs, org IDs, or user IDs
- SQL injection surface: all queries parameterized
- XSS surface: all user input sanitized before render

## Verdict Options
- `PASS` — no security issues found
- `FAIL` — one or more violations found (list each with file:line)
- `WARN` — advisory only, does not block merge

## Key References
- Rule violations → `agents/GLOBAL.md` Rules 1–8
- GitGuardian MCP: `docs/11-devops/gitguardian-mcp.md`
- Vendor wrapper pattern: `docs/01-platform/vendor-wrapper-pattern.md`

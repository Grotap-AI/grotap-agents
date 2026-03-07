# agents/roles/security/MODULE.md
# Security module — Layer 2 domain context.
# Covers: security review of all code changes before merge.

## Module Scope
The security module enforces the platform's security posture on every code change.
It has one role: Security Reviewer, which runs as part of the 4-reviewer pipeline.

A branch flagged with `security` by triage, or any branch submitted for merge,
must pass this module before proceeding.

## What Security Reviewer Checks
- No secrets, tokens, or credentials in code or comments
- No direct 3rd-party SDK calls bypassing vendor wrappers (Rule 3)
- No cross-tenant data access (Rule 4)
- No shared database schemas (Rule 5)
- GitGuardian MCP compliance node not bypassed (Rule 6)
- No `--no-verify` on commits
- No hardcoded tenant IDs, org IDs, or user IDs
- SQL injection surface: all queries parameterized
- XSS surface: all user input sanitized before render

## Verdict Options
- `PASS` — no security issues found
- `FAIL` — one or more violations found (list each with file:line)
- `WARN` — advisory only, does not block merge

## Key References
- Rule violations → `agents/GLOBAL.md` rules 1–9
- GitGuardian MCP: `docs/11-devops/gitguardian-mcp.md`
- Vendor wrapper pattern: `docs/01-platform/vendor-wrapper-pattern.md`

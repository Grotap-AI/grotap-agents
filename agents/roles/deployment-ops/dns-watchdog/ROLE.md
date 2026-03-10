# agents/roles/deployment-ops/dns-watchdog/ROLE.md
# Role: DNS Watchdog | Server: Agent-06 | Module: deployment-ops
# Trigger: scheduled (daily) OR task.type == 'dns-check' OR after infra changes

## Role Purpose
Validate that DNS records haven't drifted from expected configuration.
Catches the incident where a wildcard *.grotap.com was routing API traffic
to Vercel instead of Railway, causing all backend calls to fail.

## Failure Patterns This Role Catches
1. Wildcard *.grotap.com re-created (routes API to Vercel)
2. api.grotap.com CNAME changed (breaks backend)
3. agents.grotap.ai CNAME removed or changed
4. New subdomain added without corresponding DNS record
5. SSL certificate expiration on any domain

## Expected DNS Configuration
| Record | Type | Target | Notes |
|---|---|---|---|
| apps.grotap.com | CNAME | cname.vercel-dns.com | Vercel frontend |
| api.grotap.com | CNAME | Railway target | Backend API |
| agents.grotap.com | CNAME | cname.vercel-dns.com | Agents brand frontend |
| agents.grotap.ai | CNAME | cname.vercel-dns.com | Agents brand (.ai TLD) |
| *.grotap.com | — | MUST NOT EXIST | Wildcard was removed — never re-add |

## Validation Steps
1. Resolve each domain via DNS lookup
2. Confirm targets match expected values
3. Confirm NO wildcard record exists for *.grotap.com
4. Check SSL certificate validity and expiration date
5. Verify Squarespace nameserver configuration unchanged

## Anti-Pattern Detection
- If `*.grotap.com` resolves to anything → CRITICAL FAIL
- If `api.grotap.com` resolves to Vercel → CRITICAL FAIL (repeat of March incident)
- If any domain returns NXDOMAIN → FAIL

## Output Format
```
DNS WATCHDOG — {timestamp}

Records:
- apps.grotap.com → {target} (CORRECT | WRONG | MISSING)
- api.grotap.com → {target} (CORRECT | WRONG | MISSING)
- agents.grotap.com → {target} (CORRECT | WRONG | MISSING)
- agents.grotap.ai → {target} (CORRECT | WRONG | MISSING)
- *.grotap.com → {target} (ABSENT ✓ | PRESENT ✗ — CRITICAL)

SSL Expiry:
- apps.grotap.com: {expiry_date} ({days_remaining} days)
- api.grotap.com: {expiry_date} ({days_remaining} days)

Verdict: PASS | FAIL | CRITICAL
```

## Handoff
PASS → none (terminal)
FAIL → human escalation (DNS changes require registrar access)
CRITICAL → human escalation + immediate alert
next_server: none
next_role: none
priority: critical

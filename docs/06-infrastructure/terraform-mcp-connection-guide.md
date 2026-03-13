---
title: "Terraform MCP Connection Guide"
component: "Terraform-MCP"
category: devops
doc_type: setup-guide
related: ["Claude-Code", "Hetzner"]
tags: [terraform, mcp, connection, sse, ssh]
status: active
---

# Terraform MCP Connection Guide

The Terraform MCP server runs on your Hetzner Linux cluster and connects back to Claude Desktop via one of two methods.

## Option 1: SSH Tunnel (Recommended for single user)
Simplest setup — no SSL certificate needed. Claude logs into the cluster and runs Terraform directly.

```json
{
  "mcpServers": {
    "linux-cluster-terraform": {
      "command": "ssh",
      "args": ["user@your-cluster-ip", "npx -y @modelcontextprotocol/server-terraform"]
    }
  }
}
```
Uses your existing SSH keys. No inbound ports required on the cluster.

## Option 2: Remote SSE (For shared/persistent agent teams)
Host the MCP server as an HTTPS/SSE endpoint for 24/7 availability or multiple users.

```json
{
  "mcpServers": {
    "cluster-terraform": {
      "url": "https://your-cluster-domain.com/mcp",
      "headers": { "Authorization": "Bearer your_secret_token" }
    }
  }
}
```
Requires: SSL certificate + bearer token auth on the cluster.

## Option 3: Kubernetes
Deploy the HashiCorp Terraform MCP image as a Pod, expose via `kubectl port-forward` or Ingress.

---

## What the Terraform MCP Can Control (Single Server → All Providers)

One Terraform MCP server can coordinate a full multi-provider plan:

| Provider | What it manages |
|---|---|
| Hetzner (`hcloud`) | Boot Linux nodes, networks, firewalls |
| Cloudflare | R2 buckets, DNS, storage policies |
| Neon (`kislerdm/neon`) | Postgres projects, branches, endpoints |
| Doppler | Secret syncing across environments |
| Vercel | Project deployments, env vars, domains |
| Stripe | Webhook + product configuration |
| Railway | Services and environments |
| Auth0 | Tenants, clients, rules |
| GitGuardian | Secret scanning policies |

**Example flow:** Hetzner boots node → Cloudflare points domain → Neon creates DB → Doppler saves connection string → Vercel deploys frontend

---
**Before this:** Terraform MCP server installed on Hetzner node — see `terraform-mcp-install.md`
**After this:** Agents can provision full tenant infrastructure via Claude Code

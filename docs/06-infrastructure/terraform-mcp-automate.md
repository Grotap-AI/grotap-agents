---
title: "Terraform MCP - Automate Neon-Linux-"
source: google-drive-docx
converted: 2026-03-01
component: "Terraform-MCP"
category: devops
doc_type: how-to
related:
  - "Neon"
  - "Hetzner"
  - "Claude-Code"
tags:
  - terraform
  - mcp
  - automation
  - neon
  - linux
  - hetzner
status: active
---


# Terraform MCP - Automate Neon-Linux-

The Terraform MCP server itself is free to download and use. However, you may incur costs from the underlying Terraform Cloud (HCP Terraform) service and the infrastructure Claude provisions.

1. MCP Server Cost
- Software: The actual MCP server (available on GitHub or AWS Marketplace) is provided free of charge under open-source licenses (like MIT).
   Infrastructure for the Server: If you run the MCP server as a managed instance (e.g., on AWS), you pay standard cloud compute rates for that instance.

   Amazon Web Services (AWS) +2

2. HCP Terraform Service Costs
If Claude uses the MCP to manage your infrastructure via HCP Terraform, you are billed based on a "Managed Resource" (Resources Under Management / RUM) model:

## Tier
Price per Resource / Month
Key Features
Enhanced Free
$0 (up to 500 resources)
Core workflows, SSO, policy as code
Essentials
$0.10
VCS integration, private module registry
Standard
$0.47
Drift detection, audit logs, unlimited policies
Premium
$0.99
Advanced security, private run tasks
Note: The "Legacy Free" plan ends March 31, 2026.

3. Third-Party Infrastructure Costs
Claude's actions through the MCP will trigger real-world charges on the platforms you are automating:
- Hetzner: Standard hourly/monthly rates for VPS or dedicated servers.
- Vercel/Cloudflare: Usage-based billing for bandwidth, serverless functions, or R2 storage.
- Neon/Stripe: Database storage and transaction fees.
4. Claude API Costs
If you are using Claude through an API (rather than a fixed monthly subscription), every time Claude uses an MCP tool to "think" or write Terraform code, it consumes tokens

---

## Agent Instructions

- **Use this when:** Automating Neon and Linux server provisioning via Terraform MCP
- **Before this:** Terraform MCP Server installed and connected
- **After this:** Linux clusters ready for Claude Code agent deployment

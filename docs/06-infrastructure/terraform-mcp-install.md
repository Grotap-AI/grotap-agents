---
title: "Terraforma MCP Server Install"
source: google-drive-docx
converted: 2026-03-01
component: "Terraform-MCP"
category: devops
doc_type: setup-guide
related:
  - "Hetzner"
  - "Doppler"
tags:
  - terraform
  - mcp
  - install
  - setup
status: active
---


# Terraforma MCP Server Install

Terraforma MCP Server Install

## Remote Installation (On your Linux Boxes)
You can install the MCP server directly on one of your Linux nodes to act as a "command center" for the rest of the cluster.

## HashiCorp
- How it works:
     Docker: Run the HashiCorp Terraform MCP Docker image  on a Linux node.
     Direct Binary: Install the compiled binary or use go install on the Linux box.
- Connecting back to Claude: Since Claude Desktop primarily uses stdio (local pipes), you typically bridge the connection using an SSH tunnel. This tells Claude: "When I use this tool, run this command over SSH on my Linux box".
   Best for: "Bare metal" or local cluster tasks where the agent needs direct access to the internal network or files on those specific Linux boxes.

   HashiCorp

Where should you put it?
- For your specific list (Stripe, Auth0, Vercel, Neon), installing locally on your laptop is much simpler because these are all web-based APIs.
- For the "Linux servers on Hetzner" part, you only need it on a Linux box if you want Claude to run local shell scripts inside those servers rather than just managing them via the Hetzner API.
Next Steps
- Do you want the SSH command to bridge Claude on your laptop to an MCP server on your Linux box?
- Should I help you set up Docker on one of your Linux nodes to host the server?
- Would you like to see how to secure the connection if you choose to host it remotely?

---

## Agent Instructions

- **Use this when:** Installing the Terraform MCP Server from scratch
- **Before this:** Doppler secrets configured with Hetzner and cloud credentials
- **After this:** Proceed to Core Deployment guide

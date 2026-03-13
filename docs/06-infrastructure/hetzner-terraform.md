---
title: "Hetzner Cloud and Terraform"
source: google-drive-docx
converted: 2026-03-01
component: "Terraform-MCP"
category: devops
doc_type: setup-guide
related:
  - "Terraform-MCP"
  - "Claude-Code"
tags:
  - hetzner
  - cloud
  - terraform
  - linux
  - infrastructure
  - servers
status: active
---


# Hetzner Cloud and Terraform

To automatically create Linux clusters on Hetzner Cloud using Terraform, you can leverage the official Hetzner Cloud (hcloud) provider  to provision infrastructure and use cloud-init or specialized modules to install and join agents to a cluster.
1. Prerequisites & Initial Setup
Before provisioning, you must obtain a Read-Write API Token from the Hetzner Cloud Console under Security > API Tokens.

## Francesco
- Provider Configuration: Define the hcloud provider in your Terraform files to authenticate with your token.
   SSH Keys: Register your public SSH key within Hetzner via Terraform using the hcloud_ssh_key resource to ensure secure access to the provisioned nodes.

   Terraform

2. Provisioning the Cluster Infrastructure
You can define your cluster nodes using the hcloud_server resource. To automate the installation of agents (such as Kubernetes, K3s, or Rancher agents), use the user_data field to pass a cloud-init script.

- Server Definition: Specify the server type (e.g., cx21), image (e.g., ubuntu-22.04), and location.
- Networking: For security, place your cluster nodes in a hcloud_network  with private subnets.
   Firewalls: Use hcloud_firewall to restrict traffic, only exposing necessary ports like 443 for API access or 6443 for Kubernetes.

   Terraform

3. Using Specialized Modules for Automation
Instead of manual scripts, highly automated modules can deploy full clusters with agents pre-configured:
  kube-hetzner: A popular module that deploys a fully declarative K3s cluster  with automated agent scaling.
  hcloud-k8s (Talos Linux): Deploys a production-grade Kubernetes cluster using Talos Linux , which is an immutable, minimal OS that operates entirely without SSH and uses its own agent-based API for management.
   Rancher Quickstart: Provides Terraform templates to quickly spin up Hetzner nodes and join them to a Rancher-managed cluster.

4. Terraform Cloud Agents (Alternative Intent)
If your goal is to manage private Hetzner infrastructure from Terraform Cloud, you can deploy Terraform Cloud Agents as Docker containers or binaries on your Hetzner servers. These agents poll Terraform Cloud for jobs, allowing you to provision resources in private Hetzner networks without opening inbound firewall ports.

---

## Agent Instructions

- **Use this when:** Provisioning Linux agent servers on Hetzner Cloud
- **Before this:** Terraform MCP Server must be installed and connected
- **After this:** Deploy Claude Code agent clusters onto provisioned servers

# Documentation Index

> Start here: `CLAUDE.md` — stack, rules (9 absolute rules), key patterns. Then `01-platform/platform-summary.md` for platform UX model.

---

## 01 — Platform Architecture
| File | Topic |
|---|---|
| [platform-summary](./01-platform/platform-summary.md) | **App store launcher model — nav, apps, lifecycle, Cobrowse** |
| [architecture-overview](./01-platform/architecture-overview.md) | Full AI + multi-tenant + distributed stack deployment |
| [deployment-guide](./01-platform/deployment-guide.md) | Step-by-step deployment |
| [central-event-bus](./01-platform/central-event-bus.md) | ERP module routing — post office pattern |
| [vendor-wrapper-pattern](./01-platform/vendor-wrapper-pattern.md) | How to wrap all 3rd-party SDKs |
| [multi-tenant-switching](./01-platform/multi-tenant-switching.md) | Tenant context switching |
| [database-strategy](./01-platform/database-strategy.md) | Multi-tenant database strategy — points to neon-app-schema-architecture |
| [security-stack](./01-platform/security-stack.md) | Security & connection stack |
| [business-registration](./01-platform/business-registration.md) | Business registration |

## 02 — Auth (WorkOS)
| File | Topic |
|---|---|
| [workos-auth](./02-auth/workos-auth.md) | WorkOS auth overview |
| [workos-setup](./02-auth/workos-setup.md) | WorkOS setup steps |
| [workos-multitenant](./02-auth/workos-multitenant.md) | Multi-tenant context via WorkOS |
| [auth0-neon-integration](./02-auth/auth0-neon-integration.md) | Auth0 + Neon JWT / RLS integration |

## 03 — Database (Neon)
| File | Topic |
|---|---|
| [**neon-app-schema-architecture**](./03-database/neon-app-schema-architecture.md) | **4-layer Neon design — schema-per-app, app knowledge, platform rules — SOURCE OF TRUTH** |
| [neon-basics](./03-database/neon-basics.md) | Neon + PageIndex basics overview |
| [neon-vs-mongo](./03-database/neon-vs-mongo.md) | Why Neon over MongoDB for AI ERP |
| [neon-vector-data](./03-database/neon-vector-data.md) | pgvector + pgrag — document pipeline, where vectors live |
| [neon-billing](./03-database/neon-billing.md) | **Per-tenant provisioning + consumption API + billing** |
| [neon-backup](./03-database/neon-backup.md) | Backup logic + read replicas |
| [neon-sample-schema](./03-database/neon-sample-schema.md) | Reference SQL — app schema + tenant_knowledge schema |
| [neon-pageindex-architecture](./03-database/neon-pageindex-architecture.md) | PageIndex tree placement + multi-doc search patterns |

## 04 — Knowledge Layer (PageIndex + LangChain)
| File | Topic |
|---|---|
| [pageindex-install-setup](./04-knowledge/pageindex-install-setup.md) | PageIndex install, hardware, costs, deployment options |
| [neon-pageindex-integration](./04-knowledge/neon-pageindex-integration.md) | Neon + PageIndex integration implementation |
| [neon-pageindex-ingestion](./04-knowledge/neon-pageindex-ingestion.md) | Ingestion with auto-summarization |
| [neon-pageindex-tree-storage](./04-knowledge/neon-pageindex-tree-storage.md) | Multi-document JSONB tree storage |
| [neon-pageindex-search](./04-knowledge/neon-pageindex-search.md) | All 3 search strategies: metadata, description, reasoning |
| [neon-pageindex-async-queue](./04-knowledge/neon-pageindex-async-queue.md) | Inngest async ingestion queue |
| [langchain-vectoring](./04-knowledge/langchain-vectoring.md) | LangChain document vectoring |
| [langgraph-vector-design](./04-knowledge/langgraph-vector-design.md) | LangGraph + vector data design |
| [hybrid-rag](./04-knowledge/hybrid-rag.md) | Hybrid RAG with Neon + PageIndex + LangGraph |
| [knowledge-base-app](./04-knowledge/knowledge-base-app.md) | Knowledge base app — ingestion & agent control |
| [langgraph-neon-pageindex-loading](./04-knowledge/langgraph-neon-pageindex-loading.md) | Loading docs into LangGraph knowledge app |
| [langgraph-neon-pageindex-design](./04-knowledge/langgraph-neon-pageindex-design.md) | LangGraph + Neon + PageIndex architecture |

## 05 — Agents (LangGraph + LangSmith)
| File | Topic |
|---|---|
| [langgraph-plan-execute-verify](./05-agents/langgraph-plan-execute-verify.md) | Plan-Execute-Verify graph — single source of truth |
| [langgraph-never-do](./05-agents/langgraph-never-do.md) | AgentState never-do rules + constraint loader |
| [never-do-python-compliance](./05-agents/never-do-python-compliance.md) | Compliance checker node implementation |
| [langsmith-agent-management](./05-agents/langsmith-agent-management.md) | LangSmith Studio agent management |
| [langsmith-builder-library](./05-agents/langsmith-builder-library.md) | Agent builder template library |
| [langsmith-summarization](./05-agents/langsmith-summarization.md) | Recursive summarization |
| [agent-install-types](./05-agents/agent-install-types.md) | Claude Code agent install & types |
| [agent-management-cli](./05-agents/agent-management-cli.md) | Claude Code CLI management |
| [agent-development-teams](./05-agents/agent-development-teams.md) | Agent development teams — how to |
| [agent-architecture-reliability](./05-agents/agent-architecture-reliability.md) | Agent architecture for reliability |
| [agent-pipeline-optimizations](./05-agents/agent-pipeline-optimizations.md) | **Speed + cost optimizations — review parallelism, dynamic turns, token reduction** |

## 06 — Infrastructure (Terraform + Hetzner)
| File | Topic |
|---|---|
| [hetzner-terraform](./06-infrastructure/hetzner-terraform.md) | Hetzner Cloud + Terraform provisioning |
| [terraform-mcp-automate](./06-infrastructure/terraform-mcp-automate.md) | Automate Neon + Linux with Terraform MCP |
| [terraform-mcp-deployment](./06-infrastructure/terraform-mcp-deployment.md) | Terraform MCP core deployment architecture |
| [terraform-mcp-connection-guide](./06-infrastructure/terraform-mcp-connection-guide.md) | SSH tunnel + SSE + all provider connections |
| [terraform-mcp-install](./06-infrastructure/terraform-mcp-install.md) | Terraform MCP server install on Hetzner |

## 07 — Background Jobs (INNGEST)
| File | Topic |
|---|---|
| [inngest-tier-prioritization](./07-jobs/inngest-tier-prioritization.md) | Tier-based job prioritization (Gold/Silver) |
| [inngest-cost-tracking](./07-jobs/inngest-cost-tracking.md) | Per-tenant AI token + compute cost tracking |
| [inngest-per-tenant-throttling](./07-jobs/inngest-per-tenant-throttling.md) | Per-tenant concurrency throttling |
| [inngest-background-jobs](./07-jobs/inngest-background-jobs.md) | PageIndex + Neon background jobs |
| [inngest-realtime](./07-jobs/inngest-realtime.md) | Realtime progress updates (React + Vue) |
| [inngest-resource](./07-jobs/inngest-resource.md) | INNGEST resource reference |

## 08 — Storage
| File | Topic |
|---|---|
| [cloudflare-r2-neon](./08-storage/cloudflare-r2-neon.md) | Cloudflare R2 + Neon metadata-first architecture |
| [wasabi-backups](./08-storage/wasabi-backups.md) | Wasabi cold backup strategy |

## 09 — Frontend (React + FastAPI + Cobrowse + Expo)
| File | Topic |
|---|---|
| [react-fastapi-vercel](./09-frontend/react-fastapi-vercel.md) | React + FastAPI + Vercel deployment |
| [fastapi-architecture](./09-frontend/fastapi-architecture.md) | FastAPI as ERP orchestration layer |
| [fastapi-middleware-rls](./09-frontend/fastapi-middleware-rls.md) | FastAPI middleware + RLS context injection |
| [cobrowse-features](./09-frontend/cobrowse-features.md) | Cobrowse reusable component features |
| [cobrowse-sdk](./09-frontend/cobrowse-sdk.md) | Cobrowse SDK implementation |
| [expo-mcp](./09-frontend/expo-mcp.md) | Expo MCP mobile app setup |

## 10 — Billing (Stripe)
| File | Topic |
|---|---|
| [stripe-subscriptions](./10-billing/stripe-subscriptions.md) | Stripe subscription + Inngest webhook fan-out |

## 11 — DevOps
| File | Topic |
|---|---|
| [git](./11-devops/git.md) | Git + MCP + Inngest webhook triggers |
| [doppler](./11-devops/doppler.md) | Doppler secrets across all services |
| [gitguardian-mcp](./11-devops/gitguardian-mcp.md) | GitGuardian MCP — agent secret scanning |

## 12 — App Platform (App Store Model)
| File | Topic |
|---|---|
| [app-store-model](./12-app-platform/app-store-model.md) | **Full DB schema, API spec, WorkOS Features integration** |
| [app-lifecycle](./12-app-platform/app-lifecycle.md) | App states: building → beta → active → deprecated |
| [app-template-guide](./12-app-platform/app-template-guide.md) | **Step-by-step agent build instructions** |
| [app-ux-patterns](./12-app-platform/app-ux-patterns.md) | **Universal app UX: left sidebar, Back to Apps, Help menu** |
| [app-revenue-model](./12-app-platform/app-revenue-model.md) | 80/20 creator split, WorkOS Features, Stripe per-app |
| [app-suggestions](./12-app-platform/app-suggestions.md) | Community voting → ready-to-build → two-team agent pipeline |
| [support-portal](./12-app-platform/support-portal.md) | grotap support: data views, live help, agent questions, new app requests |
| [cobrowse-snapshot-testing](./12-app-platform/cobrowse-snapshot-testing.md) | **Agent-driven live video QA on Neon branch snapshots** |

### 12 — App Specs
| File | Topic |
|---|---|
| [apps/rfid-pipe](./12-app-platform/apps/rfid-pipe.md) | RFID Pipe app spec: batch templates, scan review, dashboard, setup |

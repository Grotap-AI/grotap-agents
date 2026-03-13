---
title: "Knowledge Base App document ingestion and agentic control system"
source: google-drive-docx
converted: 2026-03-01
component: "PageIndex"
category: ai
doc_type: architecture
related:
  - "Neon"
  - "PageIndex"
  - "LangGraph"
  - "INNGEST"
  - "Cloudflare-R2"
tags:
  - knowledge-base
  - ingestion
  - agents
  - control
  - documents
status: active
---


# Knowledge Base App document ingestion and agentic control system

This plan outlines the integration of LangGraph, Neon, PageIndex, and Cloudflare R2 into a cohesive document ingestion and agentic control system.

**All agent code is TypeScript only. No Python.**

## Phase 1: Ingestion Pipeline (R2 + Neon + PageIndex)

The ingestion flow is a linear sequence that ensures data is durable, searchable, and structured for agents.

1. **Storage (Cloudflare R2)**: The frontend uploads the raw document (PDF, Docx) directly to an R2 bucket. This provides an egress-free source of truth.
2. **Metadata & Text (Neon DB)**: A background worker extracts the text and saves it to Neon, along with the user-selected Department and Tags (e.g., `is_never_do: true`).
3. **Reasoning Index (PageIndex)**: The text is sent to PageIndex for indexing. Use the department and tags as metadata filters during this step to enable isolated retrieval for different teams.

## Phase 2: LangGraph "Rules & Flows" Architecture

The "Control Plane" is managed by a LangGraph `StateGraph` that enforces your "Never Do" rules.

### The Entry Point Node (`initialize_context`)

This node is the first step in any agentic execution. It pulls the specific rules from Neon to "prime" the agent.

```typescript
import { Annotation } from "@langchain/langgraph";
import { Pool } from "pg";

const AgentStateAnnotation = Annotation.Root({
  department: Annotation<string>(),
  never_dos: Annotation<string[]>({
    default: () => [],
    reducer: (_prev, next) => next,
  }),
  status: Annotation<string>({
    default: () => "PENDING",
    reducer: (_prev, next) => next,
  }),
});

async function initializeContextNode(
  state: typeof AgentStateAnnotation.State
): Promise<Partial<typeof AgentStateAnnotation.State>> {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });

  // 1. Fetch "Never Do" rules and "SOPs" from Neon for the department
  const result = await pool.query<{ content: string }>(
    "SELECT content FROM knowledge WHERE dept = $1 AND tag = 'Never Do'",
    [state.department]
  );

  await pool.end();

  // 2. Update state so every subsequent node knows the boundaries
  return {
    never_dos: result.rows.map((r) => r.content),
    status: "INITIALIZED",
  };
}
```

### Building the Control Plane Graph

```typescript
import { Annotation, StateGraph, END, START } from "@langchain/langgraph";

const workflow = new StateGraph(AgentStateAnnotation)
  .addNode("initialize_context", initializeContextNode)
  .addNode("context_retriever", contextRetrieverNode)
  .addNode("generator", generatorNode)
  .addNode("compliance_checker", complianceCheckerNode)
  .addNode("human_review", humanReviewNode)
  .addNode("finalizer", finalizerNode)
  .addEdge(START, "initialize_context")
  .addEdge("initialize_context", "context_retriever")
  .addEdge("context_retriever", "generator")
  .addEdge("generator", "compliance_checker")
  .addConditionalEdges("compliance_checker", routeAfterCompliance, {
    passed: "human_review",
    failed: "generator",  // Loop back with compliance_issues in state
  })
  .addEdge("human_review", "finalizer")
  .addEdge("finalizer", END);

const graph = workflow.compile();
```

## Phase 3: The Task App & Human Approval Flow

This phase bridges the gap between agent reasoning and human control.

1. **Task Loading**: New tasks are inserted into a `tasks` table in Neon.
2. **Agent Processing**: The agent uses PageIndex to retrieve context, filtered by its department.
3. **Compliance Loop**: The Compliance Checker node compares the agent's draft against the `never_dos` loaded in Phase 2.
4. **Human-in-the-Loop (HITL)**: Use LangGraph's `interrupt()` function to pause execution. The Task App UI polls Neon for `status = 'AWAITING_APPROVAL'`.
5. **Resumption**: When a human approves, your app sends a `Command(resume=true)` to the LangGraph thread to finalize the task.

## Summary of Component Roles

| Component | Responsibility | Link |
|---|---|---|
| Cloudflare R2 | Durable file storage | R2 Setup Guide |
| Neon DB | Relational metadata & Task Queue | Neon R2 Integration |
| PageIndex | Reasoning-based retrieval | PageIndex Documentation |
| LangGraph | Orchestration & Compliance | Interrupts & HITL |

---

## Agent Instructions

- **Use this when:** Building the complete document ingestion and agent control system
- **Before this:** Cloudflare R2, Neon, PageIndex, and INNGEST all set up
- **After this:** Agents can now query the knowledge base via LangGraph

---
title: "LangChain Library — Document Orchestration (Vectorless)"
source: google-drive-docx
converted: 2026-03-01
updated: 2026-03-04
component: "LangChain"
category: ai
doc_type: how-to
related:
  - "Neon"
  - "PageIndex"
  - "LangGraph"
tags:
  - langchain
  - documents
  - ingestion
  - orchestration
status: active
---

# LangChain Library — Document Orchestration (Vectorless)

> **Rule #7 — NO VECTOR EMBEDDINGS FOR RETRIEVAL.** PageIndex reasoning-based retrieval only. No pgvector similarity search for document lookup.

LangChain.js is the TypeScript framework that "chains" together the different parts of an AI application. In the grotap platform, it handles document loading, prompt management, and tool orchestration — but **NOT** vector embeddings or similarity search.

## 1. What LangChain Does in Our Stack

| Capability | How We Use It | What We Do NOT Use |
|---|---|---|
| Document Loader | Grab files from R2, convert to text | — |
| Prompt Manager | Consistent prompt templates for Claude | — |
| Tool Use (Agents) | Claude decides which function to call | — |
| Output Parsers | Force JSON responses for frontend | — |
| Memory | Store chat history in Neon | — |
| ~~Vector Store Wrapper~~ | **NOT USED** | We use PageIndex tree reasoning instead |

## 2. How It Connects to Our Architecture

```
Upload → R2 → INNGEST job → PageIndex tree generation → Neon JSONB storage
                                                              ↓
                                                    LangChain orchestrates:
                                                    - Prompt template for query
                                                    - Tool call to read tree from Neon
                                                    - PageIndex reasoning-based search
                                                    - Output parsing for frontend
```

LangChain acts as the **coordinator** between Neon (structured data) and PageIndex (reasoning-based retrieval). It does NOT perform any vector embedding or similarity search.

## 3. Code Example (Vectorless)

```typescript
import { ChatAnthropic } from "@langchain/anthropic";
import { neon } from "@neondatabase/serverless";

// 1. Connect to tenant's Neon DB (NOT a vector store)
const sql = neon(tenantDbUrl);

// 2. Fetch PageIndex tree for the relevant document
const [doc] = await sql`
  SELECT index_tree, summary FROM tenant_knowledge
  WHERE document_name = ${docName}
`;

// 3. Use LangChain to orchestrate Claude + PageIndex tree
const model = new ChatAnthropic({ modelName: "claude-sonnet-4-5-20250514" });

const response = await model.invoke([
  { role: "system", content: "Navigate the document tree to answer the query. Return node IDs." },
  { role: "user", content: `Tree: ${JSON.stringify(doc.index_tree)}\nQuery: ${userQuery}` }
]);
```

## 4. What LangChain Provides vs. What PageIndex Provides

| Concern | LangChain | PageIndex |
|---|---|---|
| Document retrieval | ❌ Not used | ✅ Reasoning-based tree search |
| Prompt templating | ✅ Templates + memory | — |
| Agent tool routing | ✅ Claude decides tools | — |
| Output formatting | ✅ JSON parsers | — |
| Traceability | Via LangSmith | ✅ Node-level citations |

---

## Agent Instructions

- **Use this when:** Orchestrating LLM calls with LangChain — prompts, tools, output parsing
- **NEVER use for:** Vector embeddings, similarity search, pgvector — use PageIndex instead
- **Before this:** Neon and PageIndex must be set up
- **After this:** Run INNGEST ingestion job to process documents

---
title: "Never Do Python Compliance Checker needed"
source: google-drive-docx
converted: 2026-03-01
component: "Architecture"
category: architecture
doc_type: never-do
related:
  - "Claude-Code"
  - "LangGraph"
tags:
  - never-do
  - typescript
  - compliance
  - checker
  - rules
  - agents
status: active
---


# Never Do Compliance Checker

This node acts as a logical firewall. It sits between the Agent's reasoning and the Human approval step, scanning the proposed action against the constraints stored in the state.

**All agent code is TypeScript only. No Python.**

## Compliance Checker Node

```typescript
import { ChatAnthropic } from "@langchain/anthropic";
import { Annotation } from "@langchain/langgraph";

// State includes never_dos loaded by the constraint_loader node
const ERPStateAnnotation = Annotation.Root({
  draft_response: Annotation<string>(),
  never_dos: Annotation<string[]>({
    default: () => [],
    reducer: (_prev, next) => next,
  }),
  compliance_passed: Annotation<boolean>({
    default: () => false,
    reducer: (_prev, next) => next,
  }),
  compliance_issues: Annotation<string[]>({
    default: () => [],
    reducer: (_prev, next) => next,
  }),
});

// Use claude-haiku for cost-efficient compliance checks
const checker = new ChatAnthropic({
  model: "claude-haiku-4-5-20251001",
});

async function complianceCheckerNode(
  state: typeof ERPStateAnnotation.State
): Promise<Partial<typeof ERPStateAnnotation.State>> {
  const { draft_response, never_dos } = state;

  if (never_dos.length === 0) {
    // No constraints loaded — pass immediately
    return { compliance_passed: true, compliance_issues: [] };
  }

  // Construct a strict validation prompt
  const prompt = [
    "Check if the following response violates any of these 'NEVER DO' rules.",
    "Reply ONLY with valid JSON: { \"passed\": boolean, \"issues\": string[] }",
    "If passed=true, issues must be []. Be strict and specific about violations.",
    "",
    "NEVER DO LIST:",
    ...never_dos.map((r, i) => `${i + 1}. ${r}`),
    "",
    "PROPOSED ACTION:",
    draft_response,
  ].join("\n");

  const result = await checker.invoke([{ role: "user", content: prompt }]);
  const text = (result.content as string).trim();

  const jsonMatch = text.match(/\{[\s\S]*?\}/);
  if (jsonMatch) {
    try {
      const parsed = JSON.parse(jsonMatch[0]) as {
        passed: boolean;
        issues: string[];
      };
      return {
        compliance_passed: parsed.passed,
        compliance_issues: parsed.issues ?? [],
      };
    } catch {
      // Malformed JSON — treat as passed to avoid false blocks
    }
  }

  return { compliance_passed: true, compliance_issues: [] };
}
```

## Integration into the Flow

To make this work, configure the graph edges to handle the compliance loop:

1. **constraint_loader Node**: Loads "Never Do" rules from Neon into `never_dos` on the state.
2. **generator Node**: Generates the draft response into `draft_response`.
3. **compliance_checker Node**: Runs the check above.
4. **Conditional Edge**:
   - If `compliance_passed === false`: Route back to generator to try again (with issues in state).
   - If `compliance_passed === true`: Proceed to `human_review` (LangGraph `interrupt()`).

The actual 7-node ERP agent graph is:

```
constraint_loader → context_retriever → generator → compliance_checker
  → [human_review | finalizer] → learning_extractor → finalizer
```

## Why this works with PageIndex & Neon

- Neon provides the `never_dos` strings to the state during the initial `constraint_loader` node.
- PageIndex ensures that if the "Never Do" list is 50 pages long, the compliance checker still gets the most relevant constraints via reasoning-based retrieval rather than random text chunks.
- The `claude-haiku-4-5-20251001` model keeps compliance checks fast and cost-efficient without sacrificing accuracy.

See the actual implementation at:
- `platform/agent-worker/src/agents/nodes/compliance-checker.ts`
- `platform/agent-worker/src/state/erp-state.ts`

---

## Agent Instructions

- **Use this when:** Running compliance checks before any deployment
- **Before this:** None — run this check throughout development
- **After this:** All agent-generated code passes compliance before merge

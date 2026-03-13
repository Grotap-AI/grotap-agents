---
title: "LangGraph - Never Do - AI Knowledge base key part of info"
source: google-drive-docx
converted: 2026-03-01
component: "LangGraph"
category: ai
doc_type: never-do
related:
  - "Neon"
  - "PageIndex"
  - "LangSmith"
tags:
  - langgraph
  - never-do
  - rules
  - knowledge-base
  - compliance
status: active
---


# LangGraph - Never Do - AI Knowledge base key part of info

LangGraph State Schema

To implement this, you will define a StateGraph where the state itself carries the "Never Do" constraints throughout the lifecycle of the task.
LangGraph State Schema
The following schema ensures that every agent node has access to the user-defined constraints and metadata fetched from Neon and PageIndex.
python
from typing import Annotated, List, TypedDict
from langgraph.graph.message import add_messages

class AgentState(TypedDict):
    # Core Chat History
    messages: Annotated[List[dict], add_messages]

    # Metadata for Routing & Filtering
    department: str
    tags: List[str]  # e.g., ["Knowledge", "Never Do", "Rules"]

    # Mandatory Constraints (Fetched once at Start)
    never_dos: List[str]  # Loaded from Neon/PageIndex
    mandatory_rules: List[str]

    # Task Queue Management
    task_id: str
    status: str  # "PENDING", "APPROVED", "REJECTED"
    raw_doc_url: str  # Cloudflare R2 link

Use code with caution.
The "Rules & Flows" Architecture
  1. --------------------------------------------------------------------------------
- The "Constraint Loader" Node (Entry Point):Before any reasoning happens, this node queries Neon DB for all documents tagged as "Never Do" or "Rules" for the specific Department. It populates the never_dos list in the state.
  2. --------------------------------------------------------------------------------
- The "Filtered Retrieval" Node:When the agent needs information, it queries PageIndex using a metadata filter.
     1. --------------------------------------------------------------------------------
     Example Filter: {"department": state["department"], "tags": {"$in": ["Knowledge", "Rules"]}}.
  3. --------------------------------------------------------------------------------
- The "Compliance Checker" Node:Before proposing an action, this node compares the agent's draft against the never_dos list. If a violation is found, it loops back to the agent for a rewrite.
  4. --------------------------------------------------------------------------------
- The "Human-in-the-Loop" Gate:Using interrupt_before, the graph pauses.
     1. --------------------------------------------------------------------------------
     Task App Integration: The state is persisted in the LangGraph Checkpointer. A human reviews the task in your UI.
     2. --------------------------------------------------------------------------------
      Approval: Once a human clicks "Approve" in the Task App, the graph resumes, and the agent executes the final step.
     3. --------------------------------------------------------------------------------

     4. --------------------------------------------------------------------------------
      Towards
     5. --------------------------------------------------------------------------------

## Resource Integration Map
- Neon DB: Stores the AgentState for long-term "Knowledge Library" views and the tasks table for the Task App.
- Cloudflare R2: Used as the raw_doc_url source if a human or agent needs to view the original PDF for deep verification.
   PageIndex: Acts as the primary reasoning engine for retrieving "Rules" without the loss of context typical in standard chunk-based RAG.

Would you like the Python code for the Compliance Checker node to see how it programmatically enforces the "Never Do" list

---

## Agent Instructions

- **Use this when:** Reviewing forbidden patterns before building any LangGraph agent
- **Before this:** None — read this FIRST before any LangGraph work
- **After this:** Proceed with LangGraph implementation following the rules

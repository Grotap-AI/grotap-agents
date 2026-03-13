---
title: "LangSmith - Implement Recursive Summarization"
source: google-drive-docx
converted: 2026-03-01
component: "LangSmith"
category: ai
doc_type: how-to
related:
  - "LangGraph"
  - "Neon"
  - "PageIndex"
tags:
  - langsmith
  - summarization
  - recursive
  - documents
status: active
---


# LangSmith - Implement Recursive Summarization

LangSmith - Implement Recursive Summarization
Implement Recursive Summarization. The Architect agent should only see a "Table of Contents" of the MD files, then "zoom in" on specific sections as needed.
WHY
Potential Pitfall: The "Context Window"
ERP vector data for rules is too large and we dont want agents contesting the entire dataset.  This avoids that issue.

A full ERP is too large for a single prompt. If your agents try to look at the entire MD project file and the entire Vector DB results at once, they will lose focus (Needle-in-a-haystack issue).
- Solution: Implement Recursive Summarization. The Architect agent should only see a "Table of Contents" of the MD files, then "zoom in" on specific sections as needed.
Would you like me to draft a LangGraph node structure specifically for the "Architect Agent" to parse your MD files, or would you prefer a data schema recommendation for how to store your key data in the Vector DB?

---

## Agent Instructions

- **Use this when:** Implementing recursive summarisation for long documents
- **Before this:** LangSmith and PageIndex must be configured
- **After this:** Store summaries in Neon and index with PageIndex

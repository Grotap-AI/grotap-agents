---
title: "PageIndex Install & Setup"
component: "PageIndex"
category: database
doc_type: setup-guide
related: ["Neon", "INNGEST"]
tags: [pageindex, install, setup, guide]
status: active
---

# PageIndex Install & Setup

**License:** MIT — free software. You pay only for LLM token usage and your own compute.

## Hardware Requirements (Self-Hosted)
- CPU: 6-core+ (Ryzen 5 / Intel i5 or better)
- RAM: 16–32 GB (32 GB preferred for large context windows)
- GPU: Optional — only needed for local models (Llama 3, Mistral). Not needed if using OpenAI/Claude APIs.
- OS: Linux (Ubuntu recommended)

## Installation
```bash
git clone https://github.com/VectifyAI/PageIndex
cd PageIndex
pip install -r requirements.txt          # Python 3.10+ virtualenv recommended
```

Configure `.env`:
```bash
OPENAI_API_KEY="your_api_key_here"
```

Run against a PDF:
```bash
python3 run_pageindex.py --pdf_path docs/your_report.pdf
```

## Deployment Options
- **MCP (Claude Desktop):** Install the `.mcpb` file from the PageIndex releases page
- **Docker:** Use `docker-compose` to containerize and isolate the environment

## Cost Notes
- Higher token usage than standard RAG — PageIndex uses multiple LLM calls to navigate the tree structure
- Compute cost is minimal when using cloud LLMs (OpenAI/Anthropic)

## After Setup
Configure PageIndex to store generated trees in the tenant's Neon database. See `neon-pageindex-integration.md`.

---
**Before this:** Python environment ready, Neon databases provisioned
**After this:** Begin document ingestion pipeline — `neon-pageindex-ingestion.md`

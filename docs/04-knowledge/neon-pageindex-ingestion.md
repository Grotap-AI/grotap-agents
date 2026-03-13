---
title: "Neon PageIndex Ingestion with Auto-Summarization"
source: google-drive-docx
converted: 2026-03-01
component: "PageIndex"
category: ai
doc_type: how-to
related:
  - "Neon"
  - "LangGraph"
  - "INNGEST"
tags:
  - pageindex
  - ingestion
  - summarization
  - auto
  - neon
status: active
---


# Neon PageIndex Ingestion with Auto-Summarization

To implement automatic summary generation, you can configure the PageIndex SDK to generate summaries for every node in the document's hierarchical tree during the initial upload. You then use these node-level summaries to create a high-level "Document Description" that is stored in your Neon tenant database for fast filtering.
1. Ingestion with Auto-Summarization
When uploading to PageIndex, set the if_add_node_summary flag to yes. This instructs the engine to summarize each logical section (node) as it builds the tree.

## GitHub
python
from pageindex import PageIndex
import psycopg
import json

pi = PageIndex(api_key="your_api_key")

def ingest_with_summary(tenant_db_url, file_path, doc_name):
    # Step 1: Upload and trigger tree generation with summaries
    # This creates a summary for every node (section) in the document
    upload_res = pi.upload(file_path)
    doc_id = upload_res["doc_id"]

    # Fetch the tree once ready, ensuring node summaries are included
    tree_res = pi.get_tree(doc_id, node_summary=True)
    tree_data = tree_res["result"]

    # Step 2: Generate a global document description from the tree
    # This helps the LLM distinguish this document from others later
    doc_description = pi.generate_doc_description(tree_data)

    # Step 3: Store both the full tree and the summary in the tenant's Neon DB
    with psycopg.connect(tenant_db_url) as conn:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO tenant_knowledge (document_name, index_tree, summary)
                VALUES (%s, %s, %s)
            """, (doc_name, json.dumps(tree_data), doc_description))
        conn.commit()

Use code with caution.
Sources: PageIndex SDK Tree Generation , PageIndex Document Search by Description
2. Benefits of Storing Summaries in Neon
- Vectorless Efficiency: By storing a doc_description alongside the index_tree, you can perform multi-document searches by simply passing the descriptions of all tenant documents to an LLM. The LLM selects the right doc_id based on these summaries without needing a vector database.
- Logical Navigation: Each node in the stored JSONB tree  now contains its own summary field. During RAG, the AI can "read" the table of contents and these small summaries to decide which specific section to expand for the final answer.
   Metadata Integration: You can use Neon's GIN indexes to filter by specific fields within the JSON summaries if you add structured metadata (e.g., {"author": "Legal Dept", "priority": "high"}).

3. Automated "Search by Description" Prompt
Once your summaries are in Neon, your "Search" agent uses a prompt like this to find the right document:
   "You are given a list of document summaries from the tenant's database. Identify which document ID is most relevant to the user's query: [User Query]. Directly return the ID."

   docs.pageindex.ai
This ensures that even with hundreds of documents, the system remains fast and cost-effective because it only "opens" the full PageIndex tree  for the most relevant match

---

## Agent Instructions

- **Use this when:** Running auto-summarisation during document ingestion
- **Before this:** PageIndex and LangSmith recursive summarisation configured
- **After this:** Summaries stored in Neon and indexed for fast retrieval

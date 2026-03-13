---
title: "Implementation of Neon and PageIndex Integration"
source: google-drive-docx
converted: 2026-03-01
component: "Neon"
category: database
doc_type: how-to
related:
  - "PageIndex"
  - "FastAPI"
  - "INNGEST"
tags:
  - neon
  - pageindex
  - integration
  - implementation
status: active
---


# Implementation of Neon and PageIndex Integration

To implement this, you can use the PageIndex SDK to generate the document tree and the Neon Serverless Driver (or standard drivers) to store that tree in your tenant's specific database.
Node.js Implementation
This example uses the @neondatabase/serverless driver and the PageIndex SDK.
javascript
import { PageIndex } from 'pageindex';
import { neon } from '@neondatabase/serverless';

// 1. Initialize PageIndex client
const pi = new PageIndex({ apiKey: process.env.PAGEINDEX_API_KEY });

async function processTenantDocument(tenantDbUrl, filePath, docName) {
  // 2. Connect to the specific tenant's Neon database
  const sql = neon(tenantDbUrl);

  // 3. Generate the PageIndex tree from a PDF
  const { doc_id } = await pi.upload(filePath);

  // Wait for processing if necessary, then fetch the tree
  const treeResponse = await pi.getTree(doc_id, { node_summary: true });
  const treeJson = treeResponse.result;

  // 4. Insert the JSON tree into the tenant's Neon database
  await sql`
    INSERT INTO tenant_knowledge (document_name, index_tree)
    VALUES (${docName}, ${JSON.stringify(treeJson)})
  `;

  console.log(`Knowledge tree for ${docName} stored in tenant DB.`);
}

Use code with caution.
Sources: Connect Node.js to Neon , PageIndex SDK Tree Generation

## Python Implementation
This example uses psycopg2 or psycopg to interact with Neon.
python
import os
import json
import psycopg
from pageindex import PageIndex

# 1. Initialize PageIndex
pi = PageIndex(api_key=os.environ["PAGEINDEX_API_KEY"])

def ingest_tenant_data(tenant_conn_string, file_path, doc_name):
    # 2. Generate the hierarchical tree
    doc_id = pi.upload(file_path)["doc_id"]
    tree_data = pi.get_tree(doc_id, node_summary=True)["result"]

    # 3. Connect to the isolated Neon tenant database
    with psycopg.connect(tenant_conn_string) as conn:
        with conn.cursor() as cur:
            # 4. Insert the tree as a JSONB object
            cur.execute(
                "INSERT INTO tenant_knowledge (document_name, index_tree) VALUES (%s, %s)",
                (doc_name, json.dumps(tree_data))
            )
        conn.commit()

    print(f"Successfully isolated knowledge for: {doc_name}")

Use code with caution.
Sources: Connect Python to Neon , PageIndex Simple RAG Cookbook
Key Details for Integration
- Tree Retrieval: PageIndex returns a hierarchical "table of contents" as a JSON object, which maps perfectly to Postgres jsonb.
- Dynamic Connection: Since you are using a database-per-tenant model, your application logic must dynamically select the tenant_conn_string (the Neon connection URL) based on the active user session.
- Vectorless Search: When querying, you don't need a vector index. You retrieve the index_tree from Neon and pass it to a Reasoning Agent to find the correct data node

---

## Agent Instructions

- **Use this when:** Implementing the full Neon + PageIndex integration
- **Before this:** Neon per-tenant databases and PageIndex install complete
- **After this:** Test document ingestion and retrieval end-to-end

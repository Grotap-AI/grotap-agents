---
title: "Backend_ FastAPI Middleware & RLS Context"
source: google-drive-docx
converted: 2026-03-01
component: "FastAPI"
category: backend
doc_type: architecture
related:
  - "Neon"
  - "WorkOS"
tags:
  - fastapi
  - middleware
  - rls
  - context
  - multitenant
  - row-level-security
status: active
---


# Backend_ FastAPI Middleware & RLS Context

Backend: FastAPI Middleware & RLS Context

To implement multi-tenant context switching, your strategy should use FastAPI Middleware to extract a tenant identifier and a Scoped Database Dependency that sets a PostgreSQL session variable  (e.g., app.current_tenant_id) before executing any queries.

## Crunchy
1. Backend: FastAPI Middleware & RLS Context
In FastAPI, use ContextVar to store the tenant_id safely across asynchronous requests and a dependency to apply it to the database connection.

python
from fastapi import Request, Depends, HTTPException
from contextvars import ContextVar
from .database import SessionLocal

# Thread-safe context
tenant_context: ContextVar[str] = ContextVar("tenant_id", default=None)

async def get_db_with_tenant(request: Request):
    """Dependency sets RLS context per request"""
    tenant_id = request.headers.get("X-Tenant-ID")
    if not tenant_id:
        raise HTTPException(status_code=400, detail="X-Tenant-ID missing")

    db = SessionLocal()
    try:
        # Apply RLS setting
        db.execute(f"SET app.current_tenant_id = '{tenant_id}'")
        yield db
    finally:
        db.close()

Use code with caution.
   Postgres Setup: Enable RLS with: USING (tenant_id = current_setting('app.current_tenant_id')).

2. Frontend: React Axios Interceptor
Use an Axios interceptor to inject the X-Tenant-ID header into all requests.

javascript
import axios from 'axios';
const api = axios.create({ baseURL: '/api' });

api.interceptors.request.use((config) => {
  const tenant = localStorage.getItem('activeTenant'); // Or state
  if (tenant) config.headers['X-Tenant-ID'] = tenant;
  return config;
});
export default api;

Use code with caution.
3. Integrated Flow
  1. --------------------------------------------------------------------------------
- React sends request with X-Tenant-ID.
  2. --------------------------------------------------------------------------------
- FastAPI extracts header and sets session variable.
  3. --------------------------------------------------------------------------------
- Database enforces RLS based on app.current_tenant_id

---

## Agent Instructions

- **Use this when:** Implementing FastAPI middleware for per-tenant RLS context
- **Before this:** WorkOS auth configured, Neon per-tenant schema ready
- **After this:** All API routes will automatically scope to the correct tenant

---
title: "Neon PageIndex Inngest realtime"
source: google-drive-docx
converted: 2026-03-01
component: "INNGEST"
category: backend
doc_type: how-to
related:
  - "Neon"
  - "PageIndex"
tags:
  - inngest
  - pageindex
  - neon
  - realtime
  - events
  - streaming
status: active
---


# Neon PageIndex Inngest realtime

In a multitenant ERP, you can use Inngest Realtime or Socket.io  to bridge the gap between your background worker and your React or Vue frontend.
Option 1: React with Inngest Realtime (Modern)
If you are using Inngest, the @inngest/realtime/hooks package provides a fully typed React hook  to subscribe to document ingestion updates.
tsx
import { useInngestSubscription } from "@inngest/realtime/hooks";
import { useState } from "react";

export function IngestionStatus({ tenantId }) {
  const [progress, setProgress] = useState({ status: "Waiting...", percent: 0 });

  // 1. Subscribe to the tenant's specific channel
  // The 'fetchRealtimeToken' is a server action that secures the channel
  useInngestSubscription({
    channel: `tenant:${tenantId}`,
    topic: "upload-progress",
    onData: (data) => {
      setProgress(data);
    },
  });

  return (
    <div className="p-4 border rounded">
      <h3 className="font-bold">{progress.status}</h3>
      <div className="w-full bg-gray-200 h-2 rounded mt-2">
        <div
          className="bg-blue-600 h-2 rounded transition-all duration-500"
          style={{ width: `${progress.percent}%` }}
        />
      </div>
    </div>
  );
}

Use code with caution.
Source: Inngest Realtime Hooks Documentation
Option 2: Vue with Socket.io (Standard)
For a Socket.io implementation , your Vue component should join a tenant-specific "room"  to ensure isolation.
html
<template>
  <div class="progress-container">
    <p>{{ status }}</p>
    <progress :value="percent" max="100"></progress>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { io } from 'socket.io-client';

const props = defineProps(['tenantId']);
const status = ref('Initializing...');
const percent = ref(0);
let socket;

onMounted(() => {
  // 1. Connect and join the tenant's private room
  socket = io('https://your-api.com');
  socket.emit('join-tenant-room', props.tenantId);

  // 2. Listen for isolated ingestion events
  socket.on('ingestion-status', (data) => {
    status.value = data.status;
    percent.value = data.percent;
  });
});

onUnmounted(() => socket.disconnect());
</script>

Use code with caution.
Source: Socket.io Room Management Guide
Key Frontend Practices for Multitenancy
- Security (Subscription Tokens): Don't just subscribe to a channel by ID. Use a server-side token  to verify the user belongs to the tenant before allowing them to see progress.
- Isolated Channels: Always include the tenant_id in your channel or room names (e.g., tenant:123:ingest) to prevent cross-tenant data leakage in the frontend state.
- Cleanup: Always disconnect or unsubscribe  in useEffect cleanup or onUnmounted to avoid memory leaks as users navigate between ERP modules

---

## Agent Instructions

- **Use this when:** Implementing real-time PageIndex updates via INNGEST events
- **Before this:** INNGEST background jobs working, PageIndex integrated
- **After this:** Agents see document updates in near real-time

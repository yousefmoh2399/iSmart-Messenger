# Socket.IO Horizontal Scaling (`docs/socketio-scaling.md`)

## 1. Cross-Instance Architecture

```text
Client A (Mobile)  ---> Backend #1 (vm-app1) ──┐
                                               ├──► Redis Pub/Sub (@socket.io/redis-adapter)
Client B (Desktop) ---> Backend #2 (vm-app2) ──┘
```

## 2. Key Mechanisms Implemented in `chat.socket.js`

1. **`@socket.io/redis-adapter` Integration:**  
   All room broadcasts (`user:<userId>`, `user:<userId>:desktop`, `user:<userId>:mobile`, `conversation:<id>`, `lobby`) and direct socket emissions (`io.to(socketId).emit(...)`) automatically traverse across all Backend nodes via Redis Pub/Sub.
2. **Instance-Scoped Startup Reset:**  
   On startup, a Backend node only resets `DeviceSession` entries with its own `instanceId` (`process.env.INSTANCE_ID`), preserving active user connections on other Backend nodes.
3. **Cluster-Wide Presence Reconciliation:**  
   Protected by `withDistributedLock("socket:cluster_presence_reconcile", 45000)`, the reconciler checks `DeviceSession` across the entire cluster (`lastSeenAt` within 3 minutes) before marking any user `offline`.
4. **Shared Print/Save/Receive Job Routing:**  
   Job ownership (`print`, `save`, `receive`) and printer catalogs are synchronized via Redis in [`print-job-store.js`](file:///g:/iSmart-Messenger-Full/backend/src/chat/services/print-job-store.js), so a Mobile client on Backend #1 can print or transfer files to a Desktop client on Backend #2.

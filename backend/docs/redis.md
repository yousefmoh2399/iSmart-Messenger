# Redis Shared Infrastructure (`docs/redis.md`)

## 1. Role of Redis in iSmart HA

Redis is used **strictly for transient shared cluster coordination** — never as a primary permanent database (MongoDB remains the single source of permanent truth).

1. **Socket.IO Cross-Instance Pub/Sub Adapter** (`@socket.io/redis-adapter` in [`chat.socket.js`](file:///g:/iSmart-Messenger-Full/backend/src/chat/sockets/chat.socket.js))
2. **Distributed Cron & Backup Locks** ([`src/utils/distributed-lock.js`](file:///g:/iSmart-Messenger-Full/backend/src/utils/distributed-lock.js))
3. **Distributed Rate Limiting Store** ([`src/config/rate-limit-store.js`](file:///g:/iSmart-Messenger-Full/backend/src/config/rate-limit-store.js))
4. **Transient Job Ownership & Printer Catalog Cache** ([`src/chat/services/print-job-store.js`](file:///g:/iSmart-Messenger-Full/backend/src/chat/services/print-job-store.js))

## 2. Graceful Degradation if Redis Fails

Configured in [`src/config/redis.js`](file:///g:/iSmart-Messenger-Full/backend/src/config/redis.js):
* `maxRetriesPerRequest: 0` and `enableOfflineQueue: false` ensure API requests **never hang** if Redis is unreachable.
* Rate limiting falls back automatically to in-memory `MemoryStore`.
* Scheduled messages use atomic MongoDB `findOneAndUpdate({ _id, isScheduled: true })` so even if Redis is down, duplicate messages cannot be sent.

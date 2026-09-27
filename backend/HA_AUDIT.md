# iSmart Backend — High Availability Architecture Audit

> **تاريخ الفحص:** 2026-09-27  
> **الإصدار الفحوص:** iSmart Backend v1.0.0  
> **المنهجية:** قراءة شاملة لجميع ملفات المشروع — لم يُعدَّل أي كود بعد.

---

## الجزء الأول — الهيكل الحالي (Current Architecture)

### 1.1 التوزيع الفعلي للمشروع

```text
iSmart-Messenger-Full/
├── backend/          ← Node.js + Express + Socket.IO (الملف المفحوص)
├── mobile_app/       ← Flutter (Android + iOS)
├── desktop_app/      ← Flutter Desktop (Windows + Linux)
└── docs/             ← وثائق المشروع
```

### 1.2 رسم الهيكل الحالي

```text
┌─────────────────────────────────────────────┐
│          Clients (Windows Desktop)           │
│          Clients (Flutter Mobile)            │
└─────────────────────┬───────────────────────┘
                       │  HTTPS + WebSocket (WSS)
                       │  https://ismartdbacd.dpdns.org
                       ▼
┌─────────────────────────────────────────────┐
│         Node.js Process (Single)            │
│         Express 4 + Socket.IO 4             │
│         Port: 5000 (dev) / 2020 (prod exe) │
│                                             │
│  ┌───────────────────────────────────────┐  │
│  │  In-Memory State (13 Maps)            │  │
│  │  - userSockets (Map)                  │  │
│  │  - socketPresence (Map)               │  │
│  │  - socketClientType (Map)             │  │
│  │  - typingState (Map)                  │  │
│  │  - typingTimeouts (Map)               │  │
│  │  - printJobOwnerById (Map)            │  │
│  │  - printerCatalogByUser (Map)         │  │
│  │  - desktopStorageByUser (Map)         │  │
│  │  - saveJobOwnerById (Map)             │  │
│  │  - receiveJobOwnerById (Map)          │  │
│  │  - publishedPresenceState (Map)       │  │
│  │  - printJobs (Map)                    │  │
│  │  - clientRequestToJobId (Map)         │  │
│  └───────────────────────────────────────┘  │
└────────┬──────────────────┬─────────────────┘
         │                  │
         ▼                  ▼
┌─────────────────┐   ┌────────────────────────┐
│  MongoDB        │   │  Redis (optional)       │
│  Single Node    │   │  redis://127.0.0.1:6379 │
│  127.0.0.1:27017│   │                         │
│  No Replica Set │   │  Used ONLY for:         │
│                 │   │  - Rate limiting store  │
│  Collections:   │   │  - OTA update progress  │
│  - users        │   │                         │
│  - messages     │   │  NOT used for:          │
│  - conversations│   │  - Socket.IO adapter    │
│  - documents    │   │  - Presence state       │
│  - tickets      │   │  - Session storage      │
│  - ...          │   └────────────────────────┘
└─────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│  Local Filesystem                           │
│  /data/ismart/uploads    ← Chat files       │
│  /data/ismart/backups    ← DB Backups       │
│  /data/ismart/releases   ← App Updates      │
│  <backend>/logs/         ← Log files        │
└─────────────────────────────────────────────┘
```

### 1.3 طريقة النشر الحالية

| البند | الوضع الحالي |
|---|---|
| **Process Management** | OS Service فقط (systemd Linux / Windows Service) |
| **Binary** | `pkg`-bundled EXE: `ismart-backend-linux` / `ismart-backend-win.exe` |
| **PM2** | ❌ غير مستخدم |
| **Docker** | ❌ غير موجود |
| **Cluster Mode** | ❌ غير مستخدم |
| **Horizontal Scaling** | ❌ غير ممكن بالبنية الحالية |
| **Installation** | Wizard تفاعلي عبر `--install` flag |
| **Service Restart** | ✅ مفعّل (3 محاولات / 5 ثوانٍ على Windows، indefinite على Linux) |

---

## الجزء الثاني — فحص المكونات التفصيلي

### 2.1 Authentication & Session Management

#### الوضع الحالي

```text
Client Login
    ↓
POST /api/auth/login
    ↓
bcrypt.compare(password, hash)
    ↓
JWT access token (1 hour) + JWT refresh token (30 days)
    ↓
Refresh nonce stored in: user.refreshSessions[] (MongoDB)
    ↓
Per-device sessions (each deviceUid gets own nonce)
```

#### تفاصيل token strategy

| الخاصية | القيمة |
|---|---|
| **نوع الـ Authentication** | JWT (stateless) |
| **Access Token** | 1 ساعة، محمول في `Authorization: Bearer` |
| **Refresh Token** | 30 يوم، rotating nonce (anti-replay) |
| **تخزين الـ nonce** | `user.refreshSessions[]` في MongoDB |
| **Global Logout** | `user.tokenVersion` increment |
| **Per-device Logout** | حذف entry محدد من `refreshSessions` |
| **Token Revocation** | DB lookup بكل request (يتحقق من `tokenVersion` + `isActive`) |
| **Cookies** | ❌ غير مستخدم — كل شيء في headers/body |

#### تقييم HA

✅ **الجيد:** JWT stateless — لا session store مطلوب بين الـ instances  
✅ **الجيد:** refresh nonces في MongoDB — تعمل بشكل موحّد مع Replica Set  
✅ **الجيد:** JWT_SECRET موجود في env (مشترك بين الـ instances ممكن)  
⚠️ **تحذير:** كل authenticated request يضرب MongoDB مرة (للتحقق من `tokenVersion`)  

---

### 2.2 MongoDB

#### الوضع الحالي

```text
MONGODB_URI=mongodb://127.0.0.1:27017/workplace_documents
```

```javascript
// database.js
mongoose.set("bufferCommands", false);  // fail-fast ✅
await mongoose.connect(mongodbUri, {
  serverSelectionTimeoutMS: 5000,       // 5s timeout ✅
});
// NO: replicaSet, writeConcern, readConcern, poolSize config
```

#### Collections المكتشفة

| Collection | الاستخدام | وجود Index |
|---|---|---|
| `users` | Auth، Presence، User management | `username`, `branchCode`, `isOnline` |
| `messages` | Chat messages | يتطلب مراجعة |
| `conversations` | Chat rooms | يتطلب مراجعة |
| `conversation_member_states` | Read status، mute settings | يتطلب مراجعة |
| `documents` | PDF documents | `userId`, `localSyncStatus` |
| `devicesessions` | Socket connection tracking | `userId`, `socketId`, `clientType`, `isOnline` |
| `pushdevices` | FCM tokens | يتطلب مراجعة |
| `tickets` | Support tickets | يتطلب مراجعة |
| `departments` | Department structure | يتطلب مراجعة |
| `branches` | Branch structure | يتطلب مراجعة |
| `roles` | Custom roles + permissions | يتطلب مراجعة |
| `announcements` | System announcements | يتطلب مراجعة |
| `appsettings` | Singleton app config | `singletonKey` (unique) |
| `clienterrors` | Error reports | يتطلب مراجعة |

#### تقييم HA

🔴 **CRITICAL:** MongoDB Single Node — لا Replica Set، لا Failover  
🔴 **CRITICAL:** لو MongoDB مات، الـ application تموت كاملاً  
⚠️ **تحذير:** `bufferCommands: false` جيد (fail-fast) لكن لا reconnect strategy مخصصة  
⚠️ **تحذير:** لا write concern مخصص (يستخدم default `w: 1`)  

---

### 2.3 Socket.IO

#### الوضع الحالي

```javascript
// chat.socket.js — initializeChatSocketServer
const io = new Server(httpServer, {
  maxHttpBufferSize: 96 * 1024 * 1024, // 96 MB
  cors: { origin: socketCorsOrigin, credentials: true },
});
// NO: io.adapter(redisAdapter) ← مش موجود!
```

#### الـ In-Memory State الخطير

```javascript
// 13 Map أو Set كلهم module-level — يعيشون فقط في process memory

// [1] الأهم — تتبع الـ sockets
const userSockets    = new Map(); // userId → Set<socketId>
const socketPresence = new Map(); // socketId → status
const socketClientType = new Map(); // socketId → clientType

// [2] typing indicators
const typingState    = new Map(); // "convId:userId" → timestamp
const typingTimeouts = new Map(); // "convId:userId" → timer handle

// [3] Print/Save/Receive jobs
const printJobOwnerById   = new Map(); // jobId → userId
const saveJobOwnerById    = new Map(); // jobId → userId
const receiveJobOwnerById = new Map(); // jobId → userId
const printerCatalogByUser  = new Map(); // userId → printers
const desktopStorageByUser  = new Map(); // userId → storage settings

// [4] Presence dedup cache
const publishedPresenceState = new Map(); // userId → "1:online"

// في print-job-store.js
const printJobs            = new Map(); // jobId → { state, payload }
const clientRequestToJobId = new Map(); // clientRequestId → jobId
```

#### أخطر سلوكيات تكسر Multi-Instance

**⛔ مشكلة 1 — Startup Reset:**
```javascript
// chat.socket.js line 467 — عند بداية كل instance
User.updateMany(
  { isOnline: true, ... },
  { $set: { isOnline: false, presenceStatus: "offline" } }
);
// Instance #2 يرفع → يعتقد أنه أول server → يُنزل كل users متصلين بـ Instance #1
```

**⛔ مشكلة 2 — 60s Reconcile Loop:**
```javascript
// chat.socket.js lines 492-530 — كل 60 ثانية
const staleUsers = await User.find({ isOnline: true, _id: { $nin: activeSocketUserIds } });
// Instance #1 يعتقد أن users متصلين بـ Instance #2 هم "stale" → يُنزلهم offline!
```

**⛔ مشكلة 3 — Cross-Instance Message Routing:**
```javascript
// Client A → Backend 1
// Client B → Backend 2
// A sends message to B:
io.to(`user:${B_userId}`).emit("receive_message", msg);
// هذا يصل فقط لـ Backend 1's sockets — B لن يتلقى الرسالة أبداً
```

**⛔ مشكلة 4 — Print Job Routing:**
```javascript
// Mobile يرسل print_request → Backend 1 → يحفظ { jobId → userId } في memory Backend 1
// Desktop يرسل print_job_status_update → Backend 2 → يبحث عن ownerUserId → مش موجود!
// النتيجة: update يذهب لـ currentUser (Desktop) بدلاً من صاحب الطباعة
```

#### Rooms & Namespaces

| Room | الغرض | مشكلة HA |
|---|---|---|
| `lobby` | All users — presence broadcasts | لن تصل للـ users على instances أخرى بدون Redis |
| `user:{userId}` | Private per-user | نفس المشكلة |
| `conversation:{id}` | Per-conversation | نفس المشكلة |

#### تقييم HA

🔴 **CRITICAL:** لا `@socket.io/redis-adapter` — الرسائل تصل فقط للـ clients على نفس instance  
🔴 **CRITICAL:** Startup reset يُنهي sessions الـ users المتصلين بـ instances أخرى  
🔴 **CRITICAL:** 60s reconciler يُنزل users المتصلين بـ instances أخرى offline  
🔴 **CRITICAL:** Print job routing يفشل في multi-instance  

---

### 2.4 File Storage

#### الوضع الحالي

```bash
UPLOADS_DIR=/data/ismart/uploads
```

```text
/data/ismart/uploads/
├── {userId}/                    ← Documents (PDF only)
│   └── 1727454428123-abc.pdf
├── avatars/
│   └── {userId}/
│       └── 1727454428123-xyz.jpg
├── chat/
│   └── {scopeId}/
│       └── {timestamp}-{random}.{ext}
└── chat_transfers/
    └── {userId}/
        └── {timestamp}-{random}.{ext}
```

#### كيف تُخدَّم الملفات

```text
GET /api/documents/:id/download
    → requireAuth (RBAC)
    → getAccessibleDocument()
    → sendUploadFile(res, doc.filePath)
    → resolveStoredUploadPath(filePath)
    → res.sendFile(absolutePath)
```

- **لا Static Middleware** — كل الملفات تمر بالـ authentication
- `filePath` مخزن في MongoDB كـ relative path: `userId/file.pdf`
- البيانات المؤقتة (chat_transfers) تُحذف تلقائياً بعد 7 أيام

#### تقييم HA

🔴 **CRITICAL:** الملفات على الـ filesystem المحلي للـ server  
🔴 **CRITICAL:** Backend 1 و Backend 2 يجب أن يروا نفس الـ `/data/ismart/uploads`  
🔴 **CRITICAL:** لو Server 1 مات، ملفاته لن تكون متاحة من Server 2  
⚠️ **تحذير:** الـ cleanup (upload-retention.js) يعمل داخل الـ process — في multi-instance يعمل مرتين! (يحذف ملفات قبل وقتها إذا كان mtime check متفاوتاً)  
✅ **الجيد:** Path traversal protection فعّال (`sanitizePathSegment` + `isPathInsideRoot`)  
✅ **الجيد:** Dual-layer validation (MIME + Extension) على الـ uploads  

---

### 2.5 Redis

#### الوضع الحالي

```bash
REDIS_URL=redis://127.0.0.1:6379  # local، single node
```

```javascript
// redis.js — Graceful degradation
client = new Redis(redisUrl, {
  maxRetriesPerRequest: 0,      // fail fast
  enableOfflineQueue: false,    // no blocking
  connectTimeout: 1500,         // 1.5s
  retryStrategy: (n) => Math.min(n * 500, 5000),
});
```

#### الاستخدامات الحالية لـ Redis

| الاستخدام | الملف | هل يعمل بدون Redis؟ |
|---|---|---|
| Rate limiting store | `config/rate-limit-store.js` | ✅ نعم (يعود لـ memory) |
| OTA update progress throttle | `services/update.service.js` | ✅ نعم |

#### الاستخدامات المفقودة

| الاستخدام المطلوب | الحالة |
|---|---|
| Socket.IO Redis Adapter | ❌ غير موجود |
| Presence state sharing | ❌ غير موجود |
| Distributed locks (cron) | ❌ غير موجود |
| Session cache | ❌ غير مطلوب (JWT stateless) |

#### تقييم HA

⚠️ **Redis نفسه SPOF:** Single Redis instance بدون Sentinel أو Cluster  
✅ **الجيد:** الـ app يعمل بدون Redis (graceful degradation)  
⚠️ **تحذير:** في multi-instance بدون Redis → rate limits per-process (600/min لكل instance بدلاً من مجموع)  

---

### 2.6 Background Jobs & Cron

#### الوظائف المكتشفة

**[1] Message Scheduler** (`services/scheduler.service.js`)
```javascript
// يعمل كل دقيقة
cron.schedule("* * * * *", async () => {
  // يبحث عن messages scheduled للإرسال
  // يُرسل عبر Socket.IO + FCM
});
// ⛔ في multi-instance: كل instance يُشغّل هذا الـ cron!
// → نفس الرسالة تُرسل مرتين أو أكثر
```

**[2] Printer Scheduler** (`printers/services/printer-scheduler.service.js`)
```javascript
// يعمل على مسح printers عبر SNMP
// ⛔ في multi-instance: يُشغَّل مضاعفاً
```

**[3] Upload Retention Cleanup** (`utils/upload-retention.js`)
```javascript
// setTimeout 30s بعد start → ثم setInterval كل ساعة
// يحذف ملفات قديمة من filesystem
// ⛔ في multi-instance: محاولتان للحذف من نفس filesystem
//    (أقل خطورة لأن ENOENT يُبتلع)
```

**[4] Presence Reconcile Loop** (`chat/sockets/chat.socket.js`)
```javascript
setInterval(..., 60000); // كل 60 ثانية
// ⛔ كل instance يُنزل users الـ instances الأخرى offline
```

**[5] Presence Sweep** (`chat/sockets/chat.socket.js`)
```javascript
setInterval(..., 25000); // كل 25 ثانية
// يُعيد نشر presence — في multi-instance يسبب تضارباً
```

#### تقييم HA

🔴 **CRITICAL:** Message scheduler يُرسل رسائل مزدوجة في multi-instance  
🔴 **CRITICAL:** Presence reconciler يُنهي sessions instances أخرى  
⚠️ **تحذير:** Printer scheduler يعمل مضاعفاً (낭비 resources)  
⚠️ **تحذير:** File retention يعمل مضاعفاً (خطر race condition على الـ filesystem)  

---

### 2.7 FCM / Push Notifications

#### الوضع الحالي

```javascript
// push-notification.service.js
// Firebase initialized lazily (singleton) per-process
let cachedMessaging = null;

// Service account loaded from:
// 1. FIREBASE_SERVICE_ACCOUNT_JSON (env var - JSON string)
// 2. FIREBASE_SERVICE_ACCOUNT_BASE64 (env var - base64)
// 3. FIREBASE_SERVICE_ACCOUNT_PATH (file path)
// 4. fallback: bundled JSON file
```

```javascript
// push suppression logic (in chat.socket.js)
shouldNotifyUser: (userId) => !getUserDeliveryContext(io, userId).hasMobile
// ⛔ getUserDeliveryContext يتحقق من local Maps فقط
// في multi-instance: Instance 1 لا يعرف أن المستخدم متصل بـ Instance 2
// → يُرسل FCM لشخص جالس أمام الهاتف!
```

#### تقييم HA

⚠️ **تحذير:** Push notification suppression logic تعمل فقط locally  
✅ **الجيد:** Firebase SDK نفسه يعمل من أي instance بنفس credentials  
✅ **الجيد:** Invalid tokens تُعطَّل تلقائياً في MongoDB  

---

### 2.8 Logging

#### الوضع الحالي

```javascript
// utils/logger.js — يحتاج مراجعة كاملة
// printer-sync-file-logger.js — ملف log sync في filesystem
// LOG_FILE = path.join(getBackendRoot(), "logs/printer-sync.log")
// Morgan middleware → stdout
```

#### تقييم HA

⚠️ **تحذير:** Printer sync logs تُكتب محلياً فقط  
⚠️ **تحذير:** لا `instanceId` في الـ logs (لو نشرنا أكثر من instance، لن نعرف من أين جاء الـ log)  
⚠️ **تحذير:** لا centralized logging (ELK / Loki / etc.)  

---

### 2.9 Health Check

#### الوضع الحالي

```javascript
// app.js
app.get("/health", (req, res) => {
  const payload = {
    status: "ok",
    service: "workplace-document-backend",
  };
  if (allowDetailedHealth) {
    payload.database = getDatabaseStatus(); // connected/disconnected/etc.
    payload.redis = getRedisStatus();       // { enabled, status, ready }
  }
  res.status(200).json(payload);
});
```

#### تقييم HA

✅ **الجيد:** `/health` موجود ويعمل  
✅ **الجيد:** إذا MongoDB disconnected يظل يرجع `{ status: "ok", database: "disconnected" }` (يمكن تحسينه)  
⚠️ **تحذير:** `allowDetailedHealth` مغلق في production افتراضياً (يحتاج تفعيل مخصص)  
⚠️ **تحذير:** لا `/ready` endpoint مستقل (Liveness vs Readiness)  
⚠️ **تحذير:** لا storage health check في الـ endpoint  

---

### 2.10 Security Review

#### الإعدادات الحالية

| المكون | الوضع | التقييم |
|---|---|---|
| **CORS** | `CORS_ORIGIN` whitelist في production | ✅ جيد |
| **Helmet** | مفعّل | ✅ جيد |
| **Rate Limiting** | 600 req/min global؛ 25/15min login؛ 120/5min refresh | ✅ جيد |
| **JWT** | HS256، secret قوي في production | ✅ جيد |
| **Path Traversal** | محمي (`sanitizePathSegment` + `isPathInsideRoot`) | ✅ جيد |
| **File Type Validation** | MIME + Extension dual check | ✅ جيد |
| **Executable Block** | 20+ extension blocked | ✅ جيد |
| **Sensitive Data in Logs** | `token|password|secret` → `***` | ✅ جيد |
| **Query Tokens** | مغلق في production | ✅ جيد |
| **HTTPS** | External (يعتمد على proxy) | ⚠️ تحقق |
| **MongoDB Auth** | غير مذكور في URI | ⚠️ يحتاج مراجعة |
| **Redis Auth** | غير موجود في URL | ⚠️ يحتاج password |
| **Firebase JSON** | ملف حساس في root directory | ⚠️ يجب نقله |

---

## الجزء الثالث — نقاط الفشل الفردي (Single Points of Failure)

```text
┌─────────────────────────────────────────────────────────────────┐
│                    SINGLE POINTS OF FAILURE                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [SPOF-1] Node.js Process                                       │
│  ████████████████████████████████████████████████████ CRITICAL  │
│  Process crash → تطبيق كامل يتوقف                              │
│  Process restart: OS Service ✅ (لكن downtime ~5-10 ثوانٍ)     │
│                                                                 │
│  [SPOF-2] MongoDB (Single Node)                                 │
│  ████████████████████████████████████████████████████ CRITICAL  │
│  MongoDB crash → قاعدة بيانات غير متاحة                        │
│  لا replica set، لا failover، لا election                       │
│  Recovery: manual restart فقط                                  │
│                                                                 │
│  [SPOF-3] Local Filesystem (/data/ismart/uploads)               │
│  ████████████████████████████████████████████████████ CRITICAL  │
│  Disk failure → فقدان كل ملفات المستخدمين                      │
│  لا redundancy، لا replication                                 │
│                                                                 │
│  [SPOF-4] Redis (Single Node)                                   │
│  ████████████████████████████  HIGH                             │
│  Redis crash → rate limits per-process (دمار مزدوج)            │
│  لكن الـ app يعمل بـ memory fallback (تدهور مقبول)            │
│                                                                 │
│  [SPOF-5] Physical Server / VM                                  │
│  ████████████████████████████████████████████████████ CRITICAL  │
│  Server crash → كل شيء يموت (Node + MongoDB + Redis + Files)   │
│                                                                 │
│  [SPOF-6] Network Connectivity                                  │
│  ████████████████████████████  HIGH                             │
│  NIC failure → لا اتصال                                        │
│                                                                 │
│  [SPOF-7] FCM / Firebase                                        │
│  ████████████████  MEDIUM                                       │
│  Firebase down → لا push notifications (الـ chat يعمل)         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## الجزء الرابع — الـ Stateful Components

```text
┌───────────────────────────────────────────────────────────────────────────┐
│                        STATEFUL COMPONENTS MAP                            │
├───────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  WHERE           WHAT                       SHAREABLE?  MIGRATION PATH    │
│  ─────────────────────────────────────────────────────────────────────   │
│  Node.js RAM     userSockets (Map)          ❌ No       → Redis (Set)     │
│  Node.js RAM     socketPresence (Map)       ❌ No       → Redis (Hash)    │
│  Node.js RAM     socketClientType (Map)     ❌ No       → Redis (Hash)    │
│  Node.js RAM     typingState (Map)          ❌ No       → Redis (TTL key) │
│  Node.js RAM     typingTimeouts (Map)       ❌ No       → Redis (TTL key) │
│  Node.js RAM     printJobOwnerById (Map)    ❌ No       → Redis (Hash)    │
│  Node.js RAM     printerCatalogByUser (Map) ❌ No       → Redis/Accept    │
│  Node.js RAM     desktopStorageByUser (Map) ❌ No       → Redis/Accept    │
│  Node.js RAM     saveJobOwnerById (Map)     ❌ No       → Redis (Hash)    │
│  Node.js RAM     receiveJobOwnerById (Map)  ❌ No       → Redis (Hash)    │
│  Node.js RAM     publishedPresenceState     ❌ No       → Redis (Hash)    │
│  Node.js RAM     printJobs (Map)            ❌ No       → Redis (Hash)    │
│  Node.js RAM     clientRequestToJobId       ❌ No       → Redis (Hash)    │
│                                                                           │
│  MongoDB         user.refreshSessions[]     ✅ Yes      Already shared    │
│  MongoDB         DeviceSession collection   ✅ Yes      Already shared    │
│  MongoDB         user.isOnline + status     ✅ Yes      Already shared    │
│  MongoDB         All business data          ✅ Yes      Needs Replica Set │
│                                                                           │
│  Filesystem      /data/ismart/uploads       ❌ No       → Shared Storage  │
│  Filesystem      /data/ismart/backups       ❌ No       → Shared Storage  │
│  Filesystem      /data/ismart/releases      ❌ No       → Shared Storage  │
│  Filesystem      logs/                      ❌ No       → Centralized Log  │
│                                                                           │
│  Redis           Rate limit counters        ✅ Yes (with Redis)           │
│  Redis           OTA update progress        ✅ Yes (with Redis)           │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## الجزء الخامس — الـ Architecture المقترحة

### 5.1 رسم الهيكل المستهدف

```text
                         Clients
                     (Desktop + Mobile)
                            │
                            │ https://ismart.company.local (Internal DNS)
                            │
                    ┌───────▼───────┐
                    │  Virtual IP   │
                    │ 172.17.X.VIP  │
                    └───────┬───────┘
                            │ Keepalived VRRP
                  ┌─────────┴──────────┐
                  │                    │
                  ▼                    ▼
            ┌──────────┐         ┌──────────┐
            │ HAProxy  │         │ HAProxy  │
            │ MASTER   │         │ BACKUP   │
            │ VM-HAP1  │         │ VM-HAP2  │
            └──────────┘         └──────────┘
                  │                    │
                  └──────────┬─────────┘
                             │ Load Balancing
                             │ Health Checks (/health)
                  ┌──────────┴──────────┐
                  │                     │
                  ▼                     ▼
          ┌────────────┐         ┌────────────┐
          │ Backend #1  │         │ Backend #2  │
          │ Node.js     │         │ Node.js     │
          │ Port: 5000  │         │ Port: 5000  │
          │ VM-APP1     │         │ VM-APP2     │
          └─────┬───────┘         └─────┬───────┘
                │                       │
                └──────────┬────────────┘
                           │
                           ▼
                    ┌──────────┐
                    │  Redis   │
                    │ VM-REDIS │
                    │ Port:6379│
                    │          │
                    │ Uses:    │
                    │ - Socket │
                    │   Adapter│
                    │ - Rate   │
                    │   Limits │
                    │ - Job    │
                    │   Routing│
                    │ - Typing │
                    │   State  │
                    └──────────┘
                           │
                  ┌─────────┴──────────┐
                  │                    │
                  ▼                    ▼
          ┌────────────┐       ┌────────────────────┐
          │ MongoDB    │       │  Shared File        │
          │ Replica    │       │  Storage            │
          │ Set        │       │  (NFS / MinIO)      │
          │            │       │                     │
          │ VM-MONGO1  │       │  /data/ismart/      │
          │ PRIMARY    │       │  uploads/           │
          │            │       │                     │
          │ VM-MONGO2  │       │  Mounted on:        │
          │ SECONDARY  │       │  Backend #1 ✅       │
          │            │       │  Backend #2 ✅       │
          │ VM-MONGO3  │       └────────────────────┘
          │ SECONDARY  │
          │ (Voter)    │
          └────────────┘
```

---

## الجزء السادس — التعديلات المطلوبة

### 6.1 تعديلات الكود (Backend Code)

#### الأولوية CRITICAL

| # | الملف | التعديل | السبب |
|---|---|---|---|
| 1 | `chat/sockets/chat.socket.js` | إضافة `@socket.io/redis-adapter` | Socket cross-instance messaging |
| 2 | `chat/sockets/chat.socket.js` | تعطيل الـ startup reset أو جعله instance-aware | يُنهي sessions الـ instances الأخرى |
| 3 | `chat/sockets/chat.socket.js` | إصلاح الـ 60s reconciler | يُنزل users instances أخرى offline |
| 4 | `chat/services/print-job-store.js` | نقل print job ownership إلى Redis | job routing يفشل في multi-instance |
| 5 | `services/scheduler.service.js` | إضافة distributed lock للـ cron | رسائل scheduled تُرسل مزدوجة |
| 6 | `config/database.js` | إضافة Replica Set connection options | يدعم failover تلقائياً |

#### الأولوية HIGH

| # | الملف | التعديل | السبب |
|---|---|---|---|
| 7 | `app.js` | تحسين `/health` ليكون Liveness+Readiness | HAProxy health checks دقيقة |
| 8 | `utils/logger.js` | إضافة `instanceId` في كل log | تمييز الـ instances |
| 9 | `utils/upload-retention.js` | إضافة distributed lock | لا تشغيل مزدوج في multi-instance |
| 10 | `chat/sockets/chat.socket.js` | نقل job Maps الحساسة إلى Redis | File save/receive routing |

#### الأولوية MEDIUM

| # | الملف | التعديل | السبب |
|---|---|---|---|
| 11 | `services/push-notification.service.js` | إصلاح push suppression logic | يرسل FCM لمستخدمين متصلين بـ instances أخرى |
| 12 | `config/multer.js` | إضافة storage abstraction layer | تمهيداً لـ shared storage |
| 13 | `config/rate-limit-store.js` | لا تعديل — already robust | ممتاز كما هو |

---

### 6.2 تعديلات Infrastructure

#### MongoDB

```text
Action Required:
1. إنشاء MongoDB Replica Set (3 members)
2. تغيير MONGODB_URI في .env:
   MONGODB_URI=mongodb://mongo1:27017,mongo2:27017,mongo3:27017/workplace_documents?replicaSet=ismartRS

الإعدادات الموصى بها:
- Write Concern: w: "majority"
- Journal: j: true
- Read Concern: "local" (acceptable for internal app)
- Read Preference: primaryPreferred (تدعم القراءة من secondaries عند الحاجة)
```

#### Redis

```text
Action Required:
1. Redis Standalone (قابل للترقية لـ Sentinel لاحقاً)
2. تأكد من persistence (AOF + RDB)
3. إضافة requirepass في redis.conf
4. تحديث REDIS_URL في .env لـ instances الاثنين:
   REDIS_URL=redis://:password@vm-redis:6379
```

#### HAProxy

```text
Action Required:
1. إنشاء 2 VMs للـ HAProxy
2. تثبيت HAProxy + Keepalived
3. تكوين Virtual IP
4. تكوين health checks على /health endpoint
5. تكوين sticky sessions للـ WebSocket (IP hash أو cookie-based)
```

#### Shared File Storage

```text
Options (من الأبسط للأكثر تعقيداً):
Option A (الموصى به للبداية): NFS Mount
  - VM مخصص للـ NFS server
  - Mount نفس الـ directory على Backend 1 و Backend 2
  - /data/ismart/uploads → NFS

Option B (للمستقبل): MinIO
  - Object storage self-hosted
  - يتطلب تغيير في storage abstraction
  - High availability مدمج

Option C: DRBD (Distributed Replicated Block Device)
  - Replication على مستوى الـ block
  - أكثر تعقيداً في الإعداد
```

---

## الجزء السابع — خطة VM Architecture

### 7.1 جدول الـ VMs المقترح

| # | VM Name | Role | vCPU | RAM | Disk | OS |
|---|---|---|---|---|---|---|
| 1 | vm-hap1 | HAProxy MASTER + Keepalived | 2 | 2 GB | 20 GB | Ubuntu 22.04 |
| 2 | vm-hap2 | HAProxy BACKUP + Keepalived | 2 | 2 GB | 20 GB | Ubuntu 22.04 |
| 3 | vm-app1 | Backend Node.js #1 | 4 | 4 GB | 40 GB | Ubuntu 22.04 |
| 4 | vm-app2 | Backend Node.js #2 | 4 | 4 GB | 40 GB | Ubuntu 22.04 |
| 5 | vm-mongo1 | MongoDB PRIMARY | 4 | 8 GB | 100 GB | Ubuntu 22.04 |
| 6 | vm-mongo2 | MongoDB SECONDARY | 4 | 8 GB | 100 GB | Ubuntu 22.04 |
| 7 | vm-mongo3 | MongoDB SECONDARY (Voter) | 2 | 4 GB | 50 GB | Ubuntu 22.04 |
| 8 | vm-redis | Redis | 2 | 4 GB | 20 GB | Ubuntu 22.04 |
| 9 | vm-storage | NFS Server / MinIO | 4 | 8 GB | **500 GB+** | Ubuntu 22.04 |

**إجمالي موارد مقترحة (تقريبي):** ~28 vCPU، ~52 GB RAM، ~900+ GB Disk

### 7.2 جدول الـ IPs والـ Ports (مع Placeholders)

| Component | VM | IP | Port | Purpose |
|---|---|---|---|---|
| Virtual IP (VIP) | — | `<VIP_IP>` | 80/443 | Entry point للـ clients |
| HAProxy 1 | vm-hap1 | `<HAP1_IP>` | 80/443 | Load Balancer MASTER |
| HAProxy 2 | vm-hap2 | `<HAP2_IP>` | 80/443 | Load Balancer BACKUP |
| Backend 1 | vm-app1 | `<APP1_IP>` | 5000 | Node.js instance 1 |
| Backend 2 | vm-app2 | `<APP2_IP>` | 5000 | Node.js instance 2 |
| MongoDB 1 | vm-mongo1 | `<MONGO1_IP>` | 27017 | Primary |
| MongoDB 2 | vm-mongo2 | `<MONGO2_IP>` | 27017 | Secondary |
| MongoDB 3 | vm-mongo3 | `<MONGO3_IP>` | 27017 | Secondary / Voter |
| Redis | vm-redis | `<REDIS_IP>` | 6379 | Shared state |
| Storage | vm-storage | `<STORAGE_IP>` | 2049 (NFS) | Shared files |

### 7.3 توزيع VMs على ESXi Hosts

> **تحذير مهم:** إذا كانت جميع الـ VMs على نفس ESXi Host فيزيقي، فالنظام محمي فقط من **VM failure وليس من Host failure**.

```text
الموصى به (إذا توفر أكثر من host):

ESXi Host 1:
  ├── vm-hap1    (HAProxy MASTER)
  ├── vm-app1    (Backend #1)
  ├── vm-mongo1  (MongoDB PRIMARY)
  └── vm-redis   (Redis)

ESXi Host 2:
  ├── vm-hap2    (HAProxy BACKUP)
  ├── vm-app2    (Backend #2)
  ├── vm-mongo2  (MongoDB SECONDARY)
  └── vm-storage (Shared Storage)

ESXi Host 3 (أو lightweight على Host 2):
  └── vm-mongo3  (MongoDB SECONDARY/Voter)

إذا ESXi Host واحد فقط:
  ✅ محمي من: VM crash, process crash, service failure
  ❌ ليس محمياً من: Physical host failure, power failure, disk failure at host level
  → ذكر هذا بوضوح في الوثائق
```

---

## الجزء الثامن — خطة الـ Migration

### 8.1 مراحل التنفيذ (تسلسلي)

```text
PHASE 1 — Backend Stateless (لا يحتاج infrastructure جديد)
  ├── 1.1 تثبيت @socket.io/redis-adapter
  ├── 1.2 إصلاح startup online reset
  ├── 1.3 إصلاح 60s reconciler
  ├── 1.4 نقل job ownership إلى Redis
  ├── 1.5 إضافة distributed lock للـ message scheduler
  ├── 1.6 تحسين /health endpoint
  └── 1.7 إضافة instanceId للـ logs

PHASE 2 — MongoDB HA
  ├── 2.1 إنشاء VMs mongo1, mongo2, mongo3
  ├── 2.2 تثبيت MongoDB على الثلاثة
  ├── 2.3 تكوين Replica Set
  ├── 2.4 نقل البيانات الموجودة (mongodump/mongorestore)
  └── 2.5 تحديث MONGODB_URI في .env

PHASE 3 — Shared File Storage
  ├── 3.1 إنشاء vm-storage
  ├── 3.2 تثبيت NFS Server
  ├── 3.3 نسخ /data/ismart/uploads إلى vm-storage
  ├── 3.4 Mount NFS على Backend (vm-app1 و vm-app2)
  └── 3.5 اختبار upload/download من الـ backend الثاني

PHASE 4 — Redis Shared
  ├── 4.1 إنشاء vm-redis
  ├── 4.2 تثبيت Redis + persistence config
  ├── 4.3 تحديث REDIS_URL في .env لكلا الـ backends
  └── 4.4 اختبار rate limiting وSocket adapter

PHASE 5 — Backend #2 Deployment
  ├── 5.1 إنشاء vm-app2
  ├── 5.2 نسخ backend config
  ├── 5.3 تحديث INSTANCE_ID=backend-02
  ├── 5.4 Mount NFS storage
  └── 5.5 تشغيل اختبار Socket.IO cross-instance

PHASE 6 — HAProxy + Keepalived
  ├── 6.1 إنشاء vm-hap1 و vm-hap2
  ├── 6.2 تثبيت HAProxy + Keepalived
  ├── 6.3 تكوين Virtual IP
  ├── 6.4 تحديث DNS الداخلي → VIP
  └── 6.5 اختبار failover (kill vm-hap1 → vm-hap2 يستلم)

PHASE 7 — Client Migration
  ├── 7.1 اختبار Flutter Mobile مع الـ HA endpoint
  ├── 7.2 اختبار Desktop مع الـ HA endpoint
  └── 7.3 نقل clients للـ internal DNS (ismart.company.local)

PHASE 8 — Monitoring + Backup
  ├── 8.1 إضافة Prometheus + Grafana
  ├── 8.2 تكوين MongoDB backup جديد (يعمل على Primary)
  ├── 8.3 اختبار restore من backup
  └── 8.4 توثيق disaster recovery scenarios
```

---

## الجزء التاسع — المخاطر والـ Rollback

### 9.1 المخاطر

| الخطر | الاحتمالية | التأثير | الحل |
|---|---|---|---|
| **Socket.IO adapter يكسر الـ reconnects** | متوسط | عالٍ | اختبار تدريجي، sticky sessions في HAProxy |
| **MongoDB Replica Set election أثناء write** | منخفض | عالٍ | Write concern majority، retry logic |
| **NFS mount failure** | منخفض | حرج | Redundant NFS أو DRBD |
| **Cron scheduler duplication** | عالٍ | متوسط | Distributed lock (Redis) |
| **Clients يتصلون بـ Backend مباشرة** | منخفض | عالٍ | DNS-only client config |
| **Firebase credentials تتضارب** | منخفض | منخفض | نفس الـ service account على كل instances |

### 9.2 خطة الـ Rollback

لكل phase:
```text
قبل التنفيذ:
  1. git commit للكود الحالي
  2. mongodump للبيانات
  3. نسخة من .env
  4. snapshot للـ VM (ESXi)

إذا فشل شيء:
  Backend Code:
    → git revert + npm install + restart service
  
  MongoDB:
    → restore من mongodump الأخير
    → إعادة MONGODB_URI للـ single node
  
  Storage:
    → إعادة mount المحلي بدلاً من NFS
  
  HAProxy:
    → تحديث DNS مباشرة للـ Backend IP
    → clients لا تحتاج تغيير (DNS فقط)
```

---

## الجزء العاشر — ملاحظات خاصة بالمشروع

### 10.1 نقاط قوة الكود الحالي

✅ JWT stateless — يسهّل الـ multi-instance  
✅ `enableOfflineQueue: false` في Redis — لا blocking  
✅ `bufferCommands: false` في Mongoose — fail-fast  
✅ Graceful shutdown (SIGTERM/SIGINT) — مناسب لـ rolling restarts  
✅ Health endpoint موجود (`/health`)  
✅ TRUST_PROXY configurable  
✅ CORS_ORIGIN whitelist  
✅ Path traversal protection  
✅ Firebase push fallback عند عدم اتصال Mobile  
✅ Rate limit fallback to memory إذا Redis غاب  
✅ Refresh token rotation (anti-replay)  
✅ tokenVersion للـ global logout  

### 10.2 نقاط الكود التي تحتاج أكبر تعديل

1. **`chat.socket.js` (1531 سطر)** — الملف الأكثر تعقيداً في المشروع:
   - 13 in-memory Maps
   - Startup reset destructive
   - 60s reconciler خطير في multi-instance
   - يحتاج تكامل مع `@socket.io/redis-adapter`

2. **`services/scheduler.service.js`** — يحتاج distributed lock بسيطة

3. **`config/database.js`** — يحتاج Replica Set options

4. **`services/push-notification.service.js`** — يحتاج إصلاح suppression logic

### 10.3 ما لن يتغير (Preserved by design)

- ✅ جميع API contracts و routes
- ✅ جميع request/response formats
- ✅ MongoDB schemas (ممكن إضافة indexes فقط)
- ✅ JWT authentication flow
- ✅ CORS configuration mechanism
- ✅ Business logic (tickets, chat, documents, etc.)
- ✅ File upload security (MIME + extension checks)
- ✅ Flutter و Desktop clients — لا تعديل مطلوب على الـ API

---

## ملخص تنفيذي

```text
الوضع الحالي: نظام single-server متين لكن غير جاهز للـ HA

المشاكل الحرجة (CRITICAL):
  [1] Socket.IO لا يدعم multi-instance (لا Redis adapter)
  [2] In-memory state (13 Maps) غير مشتركة
  [3] Startup reset يُنهي sessions الـ servers الأخرى
  [4] MongoDB single node (no failover)
  [5] File storage محلي (no sharing)
  [6] Message scheduler يُرسل مزدوجاً

التعديلات الأساسية على الكود:
  [A] إضافة @socket.io/redis-adapter (~50 سطر)
  [B] إصلاح startup/reconcile logic (~30 سطر)
  [C] نقل job routing إلى Redis (~100 سطر)
  [D] إضافة distributed lock للـ cron (~20 سطر)
  [E] تحسين /health endpoint (~20 سطر)
  [F] تحديث MongoDB connection string

الـ Infrastructure المطلوب:
  [1] MongoDB Replica Set (3 VMs)
  [2] Shared File Storage (NFS أو MinIO)
  [3] Second Backend Node
  [4] HAProxy × 2 + Keepalived
  [5] Redis (يوجد، يحتاج فقط تكوين أفضل)

الجدول الزمني المقترح: 3-4 أسابيع للـ phases الأساسية
```

---

**انتهى الـ Audit — في انتظار موافقتك قبل البدء في التنفيذ.**

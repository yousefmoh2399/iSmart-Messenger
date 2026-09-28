/**
 * test/integration-ha-runner.js
 *
 * اختبار تكامل حقيقي ومعزول لمرحلة High Availability (HA) على جهاز واحد:
 * - يستخدم WebSocket (ws) المدمج في backend/node_modules للتخاطب المباشر مع بروتوكول Socket.IO v4 (EIO=4) دون الحاجة لـ socket.io-client.
 * - يستخدم نموذج User الحقيقي (src/models/user.model.js) وبنية JWT المطابقة لـ src/services/auth.service.js.
 * - يفحص خلو المنافذ (3101, 3102) وتوفر منافذ الاختبار المعزولة (27018, 6389) قبل البدء.
 * - يقرأ stdout/stderr للعمليتين بأمان لمنع امتلاء الأنابيب (Pipe Deadlock).
 * - يفرض مهلًا زمنية (Timeouts) صارمة لكل من /ready، واتصال Socket.IO، وردود الـ ACK.
 * - يعزل مفاتيح Redis لكل تشغيلة عبر معرف تشغيل فريد (runId).
 * - يختبر فعليًا:
 *   1) جاهزية /ready وحالة Redis + PubSub + Adapter على العقدتين.
 *   2) 50 طلب طباعة متزامن عبر العقدتين (25 على App1 و25 على App2) وإثبات إنشاء وظيفة واحدة فقط في Redis واستلام حدث واحد فقط على Desktop.
 *   3) انتقالات حالة الوظيفة الذرية عبر العقد (forwarded -> processing -> submitted) ومنع الانتقال العكسي.
 *   4) تجميع الحضور (Presence Priority: online > meeting > lunch > idle > offline) عبر العقدتين.
 * - يضمن إغلاق المقابس والعمليتين المنشأتين فقط داخل بلوك finally حتى عند حدوث خطأ.
 */

const { spawn, execFileSync } = require("child_process");
const http = require("http");
const net = require("net");
const path = require("path");
const crypto = require("crypto");
const mongoose = require("mongoose");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const Redis = require("ioredis");
const WebSocket = require("ws");

// استيراد النماذج الحقيقية لضمان التطابق التام مع الـ Schema والـ Middleware
const User = require("../src/models/user.model");
const DeviceSession = require("../src/models/device-session.model");

const MONGO_CONTAINER_NAME = "ismart-test-mongo";
const REDIS_CONTAINER_NAME = "ismart-test-redis";
const MONGO_HOST = "127.0.0.1";
const MONGO_PORT = 27018;
const REDIS_HOST = "127.0.0.1";
const REDIS_PORT = 6389;
const APP1_PORT = 3101;
const APP2_PORT = 3102;

const MONGO_URI = `mongodb://${MONGO_HOST}:${MONGO_PORT}/ismart_isolated_test`;
const REDIS_URL = `redis://${REDIS_HOST}:${REDIS_PORT}`;
const JWT_SECRET = "test_ha_secret_key_isolated_2026_xyz";

const STORAGE_APP1 = path.resolve(__dirname, "../temp_test_storage/app1/uploads");
const STORAGE_APP2 = path.resolve(__dirname, "../temp_test_storage/app2/uploads");

/**
 * عميل Socket.IO v4 (Engine.IO v4) خفيف ومعتمد على مكتبة ws المتوفرة في المشروع
 * يدعم handshake.auth، استقبال الأحداث، وإرسال الأحداث مع ACK بمهلة محددة.
 */
class SocketIOv4Client {
  constructor(url, { auth = {}, connectTimeoutMs = 8000 } = {}) {
    this.url = url.replace(/^http/, "ws") + "/socket.io/?EIO=4&transport=websocket";
    this.auth = auth;
    this.connectTimeoutMs = connectTimeoutMs;
    this.ws = null;
    this.id = null;
    this.connected = false;
    this.nextAckId = 1;
    this.pendingAcks = new Map();
    this.listeners = new Map();
  }

  on(event, handler) {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, []);
    }
    this.listeners.get(event).push(handler);
    return this;
  }

  _emitLocal(event, ...args) {
    const handlers = this.listeners.get(event) || [];
    for (const fn of handlers) {
      try {
        fn(...args);
      } catch (_) {}
    }
  }

  connect() {
    return new Promise((resolve, reject) => {
      let settled = false;
      const timer = setTimeout(() => {
        if (!settled) {
          settled = true;
          this.close();
          reject(new Error(`Socket.IO connect timeout (${this.connectTimeoutMs}ms) to ${this.url}`));
        }
      }, this.connectTimeoutMs);

      this.ws = new WebSocket(this.url);

      this.ws.on("message", (rawBuf) => {
        const msg = rawBuf.toString("utf8");
        if (!msg) return;

        // Engine.IO OPEN packet ('0{...}')
        if (msg[0] === "0") {
          // إرسال حزمة Socket.IO CONNECT ('40') مع بيانات المصادقة auth
          const authJson = JSON.stringify(this.auth || {});
          this.ws.send(`40${authJson}`);
          return;
        }

        // Engine.IO PING ('2') -> رد فوري بـ PONG ('3')
        if (msg === "2") {
          if (this.ws.readyState === WebSocket.OPEN) {
            this.ws.send("3");
          }
          return;
        }

        // Engine.IO MESSAGE ('4...')
        if (msg[0] === "4") {
          const sioType = msg[1];

          // Socket.IO CONNECT ACK ('40{"sid":"..."}')
          if (sioType === "0") {
            const body = msg.slice(2);
            try {
              const parsed = body ? JSON.parse(body) : {};
              this.id = parsed.sid || null;
            } catch (_) {}
            this.connected = true;
            if (!settled) {
              settled = true;
              clearTimeout(timer);
              resolve(this);
            }
            return;
          }

          // Socket.IO CONNECT_ERROR ('44{"message":"..."}')
          if (sioType === "4") {
            const body = msg.slice(2);
            let errMsg = "Socket.IO connection error";
            try {
              const parsed = JSON.parse(body);
              if (parsed?.message) errMsg = parsed.message;
            } catch (_) {}
            if (!settled) {
              settled = true;
              clearTimeout(timer);
              this.close();
              reject(new Error(errMsg));
            }
            return;
          }

          // Socket.IO EVENT ('42["event", ...]' أو '42<id>["event", ...]')
          if (sioType === "2") {
            const rest = msg.slice(2);
            const bracketIdx = rest.indexOf("[");
            if (bracketIdx === -1) return;
            const jsonStr = rest.slice(bracketIdx);
            try {
              const arr = JSON.parse(jsonStr);
              if (Array.isArray(arr) && arr.length >= 1) {
                const [eventName, ...args] = arr;
                this._emitLocal(eventName, ...args);
              }
            } catch (_) {}
            return;
          }

          // Socket.IO ACK ('43<id>[...]')
          if (sioType === "3") {
            const rest = msg.slice(2);
            const bracketIdx = rest.indexOf("[");
            if (bracketIdx === -1) return;
            const ackId = Number(rest.slice(0, bracketIdx));
            const jsonStr = rest.slice(bracketIdx);
            const pending = this.pendingAcks.get(ackId);
            if (pending) {
              this.pendingAcks.delete(ackId);
              clearTimeout(pending.timer);
              try {
                const arr = JSON.parse(jsonStr);
                pending.resolve(arr[0]);
              } catch (err) {
                pending.reject(err);
              }
            }
          }
        }
      });

      this.ws.on("error", (err) => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          reject(err);
        }
      });

      this.ws.on("close", () => {
        this.connected = false;
        for (const [, pending] of this.pendingAcks.entries()) {
          clearTimeout(pending.timer);
          pending.reject(new Error("Socket closed before ACK received"));
        }
        this.pendingAcks.clear();
      });
    });
  }

  emitWithAck(eventName, payload, timeoutMs = 10000) {
    return new Promise((resolve, reject) => {
      if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
        return reject(new Error(`Socket not open for event ${eventName}`));
      }
      const ackId = this.nextAckId++;
      const timer = setTimeout(() => {
        this.pendingAcks.delete(ackId);
        reject(new Error(`ACK timeout (${timeoutMs}ms) for event "${eventName}" (ackId=${ackId})`));
      }, timeoutMs);

      this.pendingAcks.set(ackId, { resolve, reject, timer });
      const packet = `42${ackId}${JSON.stringify([eventName, payload])}`;
      this.ws.send(packet);
    });
  }

  close() {
    for (const [, pending] of this.pendingAcks.entries()) {
      clearTimeout(pending.timer);
      pending.reject(new Error("Socket closed by runner"));
    }
    this.pendingAcks.clear();
    if (this.ws) {
      try {
        this.ws.close();
      } catch (_) {}
      this.ws = null;
    }
    this.connected = false;
  }
}

// بناء بيئة معزولة تمامًا دون وراثة متغيرات بيئة النظام/الإنتاج
function createCleanEnv(port, instanceId, storageDir) {
  return {
    SystemRoot: process.env.SystemRoot || "C:\\Windows",
    PATH: process.env.PATH || "",
    TEMP: process.env.TEMP || "C:\\Temp",
    TMP: process.env.TMP || "C:\\Temp",

    NODE_ENV: "test",
    FORCE_REDIS_IN_TESTS: "true",
    DISABLE_DOTENV: "true",
    BOOTSTRAP_ADMIN_ENABLED: "false",
    CLUSTER_MODE: "true",
    INSTANCE_ID: instanceId,
    HOST: "127.0.0.1",
    PORT: String(port),
    MONGODB_URI: MONGO_URI,
    REDIS_URL: REDIS_URL,
    JWT_SECRET: JWT_SECRET,
    CORS_ORIGIN: "*",
    UPLOADS_DIR: storageDir,

    FIREBASE_DISABLED: "true",
    FIREBASE_SERVICE_ACCOUNT_JSON: "",
    FIREBASE_SERVICE_ACCOUNT_BASE64: "",
    FIREBASE_SERVICE_ACCOUNT_PATH: "",
  };
}

// فحص أن المنفذ غير مشغول قبل تشغيل العمليات
function assertPortFree(host, port) {
  return new Promise((resolve, reject) => {
    const tester = net.createServer()
      .once("error", (err) => {
        if (err.code === "EADDRINUSE") {
          reject(new Error(`المنفذ ${host}:${port} مشغول بالفعل قبل بدء الاختبار!`));
        } else {
          reject(err);
        }
      })
      .once("listening", () => {
        tester.close(() => resolve());
      })
      .listen(port, host);
  });
}

// فحص أن خدمة الاختبار المعزولة (Mongo / Redis) تستجيب على المنفذ المحدد
function assertPortOpen(host, port, serviceName, timeoutMs = 3000) {
  return new Promise((resolve, reject) => {
    const socket = new net.Socket();
    socket.setTimeout(timeoutMs);
    socket.once("connect", () => {
      socket.destroy();
      resolve();
    });
    socket.once("timeout", () => {
      socket.destroy();
      reject(new Error(`انتهت مهلة الاتصال بخدمة الاختبار ${serviceName} على ${host}:${port}`));
    });
    socket.once("error", (err) => {
      socket.destroy();
      reject(new Error(`تعذر الاتصال بخدمة الاختبار ${serviceName} على ${host}:${port}: ${err.message}`));
    });
    socket.connect(port, host);
  });
}

// إرفاق قارئ آمن لـ stdout/stderr لمنع امتلاء الـ Buffer والاحتفاظ بآخر 80 سطرًا للتشخيص
function attachProcessLogCollector(childProc, label) {
  const logs = [];
  const pushChunk = (streamName, chunk) => {
    const lines = chunk.toString("utf8").split(/\r?\n/).filter(Boolean);
    for (const line of lines) {
      logs.push(`[${label}:${streamName}] ${line}`);
      if (logs.length > 80) logs.shift();
    }
  };
  if (childProc.stdout) {
    childProc.stdout.on("data", (c) => pushChunk("OUT", c));
  }
  if (childProc.stderr) {
    childProc.stderr.on("data", (c) => pushChunk("ERR", c));
  }
  return logs;
}

// فحص /ready مع التحقق من JSON الحالة ومهلة صارمة
function waitForReady(port, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  return new Promise((resolve, reject) => {
    const attempt = () => {
      if (Date.now() > deadline) {
        return reject(new Error(`انتهت مهلة انتظار جاهزية /ready على المنفذ ${port} (${timeoutMs}ms)`));
      }
      const req = http.get(`http://127.0.0.1:${port}/ready`, { timeout: 2000 }, (res) => {
        let raw = "";
        res.on("data", (chunk) => { raw += chunk; });
        res.on("end", () => {
          if (res.statusCode === 200) {
            try {
              const body = JSON.parse(raw);
              if (
                body.status === "ok" &&
                body.redis === "connected" &&
                body.pubsub === "connected" &&
                body.adapter === "attached"
              ) {
                return resolve(body);
              }
            } catch (_) {}
          }
          setTimeout(attempt, 400);
        });
      });
      req.on("error", () => setTimeout(attempt, 400));
      req.on("timeout", () => {
        req.destroy();
        setTimeout(attempt, 400);
      });
    };
    attempt();
  });
}

async function stopChildProcessSafely(childProc) {
  if (!childProc || childProc.exitCode !== null || childProc.killed) return;
  await new Promise((resolve) => {
    const killTimer = setTimeout(() => {
      try { childProc.kill("SIGKILL"); } catch (_) {}
      resolve();
    }, 3000);
    childProc.once("exit", () => {
      clearTimeout(killTimer);
      resolve();
    });
    try {
      childProc.kill("SIGTERM");
    } catch (_) {
      clearTimeout(killTimer);
      resolve();
    }
  });
}

// التحقق الصارم قبل أي كتابة من أن المنفذين 27018 و 6389 تابعان فعليًا للحاويتين الاختباريتين المقصودتين
async function verifyTestContainersOwnership(mongooseConn, redisClient) {
  // 1. فحص حاوية Mongo عبر docker inspect ومطابقة الـ Hostname الداخلي مع اتصال Mongoose الفعلي
  const mongoInspectRaw = execFileSync(
    "docker",
    ["inspect", "--format", "{{.State.Running}}|{{.Config.Hostname}}|{{json .NetworkSettings.Ports}}", MONGO_CONTAINER_NAME],
    { encoding: "utf8" }
  ).trim();
  const [mongoRunning, mongoContainerHostname, mongoPortsJson] = mongoInspectRaw.split("|");
  if (mongoRunning !== "true" || !mongoContainerHostname) {
    throw new Error(`الحاوية ${MONGO_CONTAINER_NAME} ليست في حالة تشغيل!`);
  }
  const mongoPorts = JSON.parse(mongoPortsJson || "{}");
  const mongoBinding = (mongoPorts["27017/tcp"] || [])[0];
  if (!mongoBinding || mongoBinding.HostIp !== MONGO_HOST || String(mongoBinding.HostPort) !== String(MONGO_PORT)) {
    throw new Error(`الحاوية ${MONGO_CONTAINER_NAME} غير مربوطة حصريًا بـ ${MONGO_HOST}:${MONGO_PORT}!`);
  }
  const hostInfo = await mongooseConn.db.command({ hostInfo: 1 });
  const connectedMongoHost = String(hostInfo?.system?.hostname || "").split(":")[0];
  if (!connectedMongoHost || !connectedMongoHost.startsWith(mongoContainerHostname)) {
    throw new Error(
      `فشل التحقق من هوية Mongo على ${MONGO_HOST}:${MONGO_PORT}: المتصل به (${connectedMongoHost}) لا يطابق حاوية الاختبار (${mongoContainerHostname})!`
    );
  }

  // 2. فحص حاوية Redis عبر docker inspect ومطابقة الـ run_id الفريد مع اتصال Redis الفعلي
  const redisInspectRaw = execFileSync(
    "docker",
    ["inspect", "--format", "{{.State.Running}}|{{json .NetworkSettings.Ports}}", REDIS_CONTAINER_NAME],
    { encoding: "utf8" }
  ).trim();
  const [redisRunning, redisPortsJson] = redisInspectRaw.split("|");
  if (redisRunning !== "true") {
    throw new Error(`الحاوية ${REDIS_CONTAINER_NAME} ليست في حالة تشغيل!`);
  }
  const redisPorts = JSON.parse(redisPortsJson || "{}");
  const redisBinding = (redisPorts["6379/tcp"] || [])[0];
  if (!redisBinding || redisBinding.HostIp !== REDIS_HOST || String(redisBinding.HostPort) !== String(REDIS_PORT)) {
    throw new Error(`الحاوية ${REDIS_CONTAINER_NAME} غير مربوطة حصريًا بـ ${REDIS_HOST}:${REDIS_PORT}!`);
  }
  const containerRedisInfo = execFileSync(
    "docker",
    ["exec", REDIS_CONTAINER_NAME, "redis-cli", "INFO", "server"],
    { encoding: "utf8" }
  );
  const socketRedisInfo = await redisClient.info("server");
  const extractRunId = (txt) => (txt.match(/run_id:([a-f0-9]+)/i) || [])[1] || null;
  const containerRunId = extractRunId(containerRedisInfo);
  const socketRunId = extractRunId(socketRedisInfo);
  if (!containerRunId || containerRunId !== socketRunId) {
    throw new Error(
      `فشل التحقق من هوية Redis على ${REDIS_HOST}:${REDIS_PORT}: run_id المتصل به (${socketRunId}) لا يطابق حاوية الاختبار (${containerRunId})!`
    );
  }
}

async function runIntegrationSuite() {
  const runId = `${Date.now()}_${crypto.randomBytes(3).toString("hex")}`;
  const createdSockets = [];
  const createdRedisKeys = new Set();
  let testPassed = false;
  let testUserId = null;
  let redisClient = null;
  let app1 = null;
  let app2 = null;
  let app1Logs = [];
  let app2Logs = [];

  const trackSocket = (s) => {
    createdSockets.push(s);
    return s;
  };

  try {
    console.log(`=== [RunID: ${runId}] بدء اختبار تكامل HA المعزول ===`);

    // 1. فحص البيئة والمنافذ قبل التشغيل
    const sampleEnv = createCleanEnv(APP1_PORT, "app1", STORAGE_APP1);
    console.log("[1/7] أسماء المتغيرات الممررة للعمليتين فقط (دون القيم):", Object.keys(sampleEnv).join(", "));

    await assertPortFree("127.0.0.1", APP1_PORT);
    await assertPortFree("127.0.0.1", APP2_PORT);
    await assertPortOpen(MONGO_HOST, MONGO_PORT, "MongoDB-Test");
    await assertPortOpen(REDIS_HOST, REDIS_PORT, "Redis-Test");
    console.log("✓ فحص المنافذ: 3101 و 3102 شاغران، و 27018 (Mongo) و 6389 (Redis) يستجيبان.");

    // 2. التحقق الصارم من تبعية المنفذين للحاويتين الاختباريتين قبل أي كتابة
    console.log("[2/7] التحقق من تبعية Mongo (27018) و Redis (6389) للحاويتين الاختباريتين قبل الكتابة...");
    await mongoose.connect(MONGO_URI, { serverSelectionTimeoutMS: 5000 });
    redisClient = new Redis(REDIS_URL, { maxRetriesPerRequest: 2 });
    await verifyTestContainersOwnership(mongoose.connection, redisClient);
    console.log(`✓ تم إثبات تبعية المنفذين 27018 و 6389 للحاويتين (${MONGO_CONTAINER_NAME}, ${REDIS_CONTAINER_NAME}).`);

    // 3. إنشاء مستخدم الاختبار الحقيقي وتوليد JWT مطابق للـ Middleware
    console.log("[3/7] تهيئة مستخدم الاختبار عبر النموذج الحقيقي User...");
    const username = `ha_user_${runId}`.toLowerCase();
    const passwordHash = await bcrypt.hash("HaTestPassword!2026", 4);
    const testUser = await User.create({
      username,
      passwordHash,
      fullName: `HA User ${runId}`,
      role: "user",
      branchCode: "MAIN",
      isActive: true,
      tokenVersion: 1,
    });
    testUserId = testUser._id.toString();

    const testToken = jwt.sign(
      {
        sub: testUserId,
        username: testUser.username,
        role: testUser.role,
        tokenVersion: 1,
      },
      JWT_SECRET,
      { expiresIn: "1h" }
    );
    console.log(`✓ تم إنشاء المستخدم الحقيقي: username=${username}, id=${testUserId}`);

    // 4. تشغيل العمليتين المعزولتين App1 و App2 مع قراءة آمنة للمخرجات
    console.log("[4/7] تشغيل العمليتين App1 (3101) و App2 (3102)...");
    const serverEntry = path.resolve(__dirname, "../src/server.js");

    app1 = spawn(process.execPath, [serverEntry], {
      cwd: path.resolve(__dirname, ".."),
      env: createCleanEnv(APP1_PORT, "ha-node-1", STORAGE_APP1),
      stdio: ["ignore", "pipe", "pipe"],
    });
    app1Logs = attachProcessLogCollector(app1, "APP1");

    app2 = spawn(process.execPath, [serverEntry], {
      cwd: path.resolve(__dirname, ".."),
      env: createCleanEnv(APP2_PORT, "ha-node-2", STORAGE_APP2),
      stdio: ["ignore", "pipe", "pipe"],
    });
    app2Logs = attachProcessLogCollector(app2, "APP2");

    const [ready1, ready2] = await Promise.all([
      waitForReady(APP1_PORT, 15000),
      waitForReady(APP2_PORT, 15000),
    ]);
    console.log("✓ App1 /ready:", JSON.stringify(ready1));
    console.log("✓ App2 /ready:", JSON.stringify(ready2));

    // 5. السيناريو الأول: حجز الطباعة الذري عبر العقدتين (50 طلب متزامن)
    console.log("[5/7] اختبار 50 طلب طباعة متزامن (25 عبر App1 و 25 عبر App2)...");
    const desktopSocket = trackSocket(
      new SocketIOv4Client(`http://127.0.0.1:${APP1_PORT}`, {
        auth: { token: testToken, clientType: "desktop", deviceInfo: { deviceName: "Desktop-App1" } },
      })
    );
    await desktopSocket.connect();

    const receivedPrintEvents = [];
    desktopSocket.on("print_job_requested", (job) => {
      receivedPrintEvents.push(job);
    });

    const mobileApp1 = trackSocket(
      new SocketIOv4Client(`http://127.0.0.1:${APP1_PORT}`, {
        auth: { token: testToken, clientType: "mobile", deviceInfo: { deviceName: "Mobile-App1" } },
      })
    );
    const mobileApp2 = trackSocket(
      new SocketIOv4Client(`http://127.0.0.1:${APP2_PORT}`, {
        auth: { token: testToken, clientType: "mobile", deviceInfo: { deviceName: "Mobile-App2" } },
      })
    );
    await Promise.all([mobileApp1.connect(), mobileApp2.connect()]);

    const clientRequestId = `req_${runId}`;
    const reservationKey = `ismart:printreq:${testUserId}:${clientRequestId}`;
    createdRedisKeys.add(reservationKey);
    createdRedisKeys.add(`ismart:printreq:${clientRequestId}`);

    const printPayload = {
      clientRequestId,
      fileName: `doc_${runId}.pdf`,
      inlineFileBase64: Buffer.from(`Isolated HA Print Content ${runId}`).toString("base64"),
      mimeType: "application/pdf",
    };

    const concurrentPromises = [];
    for (let i = 0; i < 25; i++) {
      concurrentPromises.push(mobileApp1.emitWithAck("print_request", printPayload, 10000));
      concurrentPromises.push(mobileApp2.emitWithAck("print_request", printPayload, 10000));
    }

    const acks = await Promise.all(concurrentPromises);
    await new Promise((r) => setTimeout(r, 1000));

    // فحص مفاتيح Redis الخاصة بهذا الـ runId فقط عبر GET + JSON.parse (وليس HGETALL)
    const reservedJobId = await redisClient.get(reservationKey);

    const allJobKeys = await redisClient.keys("ismart:printjob:*");
    const matchingJobsInRedis = [];
    for (const key of allJobKeys) {
      const rawJson = await redisClient.get(key);
      if (!rawJson) continue;
      try {
        const parsed = JSON.parse(rawJson);
        if (
          parsed?.payload?.clientRequestId === clientRequestId &&
          parsed?.payload?.requestedByUserId === testUserId
        ) {
          createdRedisKeys.add(key);
          if (parsed?.payload?.jobId) {
            createdRedisKeys.add(`ismart:jobowner:print:${parsed.payload.jobId}`);
          }
          matchingJobsInRedis.push({ key, record: parsed });
        }
      } catch (_) {}
    }

    const returnedJobIds = new Set(
      acks.filter((a) => a && a.ok && a.data && a.data.jobId).map((a) => a.data.jobId)
    );
    const inFlightRetries = acks.filter((a) => a && !a.ok && a.retryable === true && a.status === "in_flight");

    console.log(`  - أحداث print_job_requested المستلمة على Desktop: ${receivedPrintEvents.length}`);
    console.log(`  - عدد الوظائف المسجلة في Redis لهذا الطلب (${clientRequestId}): ${matchingJobsInRedis.length}`);
    console.log(`  - قيمة مفتاح الحجز في Redis: ${reservedJobId}`);
    console.log(`  - عدد معرفات الوظائف الفريدة في ردود ACK الناجحة: ${returnedJobIds.size} (مع ${inFlightRetries.length} رد in_flight قابل لإعادة المحاولة)`);

    if (receivedPrintEvents.length !== 1) {
      throw new Error(`فشل: استلم Desktop ${receivedPrintEvents.length} حدث طباعة بدلًا من 1`);
    }
    if (matchingJobsInRedis.length !== 1) {
      throw new Error(`فشل: تم إنشاء ${matchingJobsInRedis.length} وظيفة في Redis لهذا الطلب بدلًا من 1`);
    }
    const winningJobId = matchingJobsInRedis[0].record.payload.jobId;
    if (reservedJobId !== winningJobId || receivedPrintEvents[0].jobId !== winningJobId) {
      throw new Error(`فشل عدم تطابق معرف الوظيفة الفائزة: redis=${reservedJobId}, job=${winningJobId}`);
    }
    if (returnedJobIds.size !== 1 || !returnedJobIds.has(winningJobId)) {
      throw new Error(`فشل: ردود ACK أرجعت معرفات وظائف غير متطابقة: ${[...returnedJobIds].join(", ")}`);
    }
    console.log(`✓ نجاح السيناريو 1: 50 طلب متزامن عبر العقدتين أنتج وظيفة واحدة فقط (${winningJobId}) وحدثًا واحدًا فقط.`);

    // 5-ب. اختبار تنافس APP1 و APP2 بعد انتهاء TTL الحجز على Redis الفعلي
    console.log("[5-ب/7] اختبار تنافس APP1 و APP2 بعد انتهاء TTL الحجز على Redis الفعلي...");
    process.env.DISABLE_DOTENV = "true";
    process.env.REDIS_URL = REDIS_URL;
    process.env.FORCE_REDIS_IN_TESTS = "true";
    process.env.CLUSTER_MODE = "true";
    const { getRedisClient, closeRedisClient } = require("../src/config/redis");
    const localPrintStore = require("../src/chat/services/print-job-store");
    const storeRedis = getRedisClient();
    if (storeRedis && storeRedis.status !== "ready") {
      await new Promise((resolve, reject) => {
        const t = setTimeout(() => reject(new Error("storeRedis ready timeout")), 3000);
        storeRedis.once("ready", () => { clearTimeout(t); resolve(); });
      });
    }
    try {
      const expReqId = `req_exp_${runId}`;
      const expJobIdApp1 = `job_exp_app1_${runId}`;
      const expJobIdApp2 = `job_exp_app2_${runId}`;
      createdRedisKeys.add(`ismart:printreq:${testUserId}:${expReqId}`);
      createdRedisKeys.add(`ismart:printreq:${expReqId}`);
      createdRedisKeys.add(`ismart:printjob:${expJobIdApp1}`);
      createdRedisKeys.add(`ismart:printjob:${expJobIdApp2}`);

      // APP1 تحجز بمهلة 40ms وتنشئ وظيفتها بالانتظار (createJobAsync) وتنقلها إلى forwarded
      const resApp1 = await localPrintStore.reservePrintRequest({
        userId: testUserId,
        clientRequestId: expReqId,
        ttlMs: 40,
      });
      await localPrintStore.createJobAsync(expJobIdApp1, {
        jobId: expJobIdApp1,
        clientRequestId: expReqId,
        requestedByUserId: testUserId,
        fileName: "app1_expired.pdf",
      });
      await localPrintStore.validateAndTransitionAsync(expJobIdApp1, "forwarded");

      // انتظار انتهاء صلاحية مفتاح الحجز (PX 40ms) في Redis
      await new Promise((r) => setTimeout(r, 80));

      // APP2 تحجز نفس الطلب وتنشئ وظيفتها وتنقلها إلى forwarded وتثبتها بنجاح
      const resApp2 = await localPrintStore.reservePrintRequest({
        userId: testUserId,
        clientRequestId: expReqId,
        ttlMs: 5000,
      });
      await localPrintStore.createJobAsync(expJobIdApp2, {
        jobId: expJobIdApp2,
        clientRequestId: expReqId,
        requestedByUserId: testUserId,
        fileName: "app2_winner.pdf",
      });
      await localPrintStore.validateAndTransitionAsync(expJobIdApp2, "forwarded");
      const commitApp2 = await localPrintStore.commitPrintRequest({
        userId: testUserId,
        clientRequestId: expReqId,
        token: resApp2.token,
        jobId: expJobIdApp2,
      });

      // APP1 تحاول التثبيت بـ tokenApp1 المنتهي -> يفشل ويحذف وظيفة APP1 فقط دون المساس بوظيفة ومفتاح APP2
      const commitApp1 = await localPrintStore.commitPrintRequest({
        userId: testUserId,
        clientRequestId: expReqId,
        token: resApp1.token,
        jobId: expJobIdApp1,
      });
      if (!commitApp1) {
        await localPrintStore.deleteJobAsync(expJobIdApp1);
      }

      const app1JobInRedis = await redisClient.get(`ismart:printjob:${expJobIdApp1}`);
      const app2JobInRedis = await redisClient.get(`ismart:printjob:${expJobIdApp2}`);
      const reqKeyInRedis = await redisClient.get(`ismart:printreq:${testUserId}:${expReqId}`);

      if (
        commitApp2 !== true ||
        commitApp1 !== false ||
        app1JobInRedis !== null ||
        !app2JobInRedis ||
        JSON.parse(app2JobInRedis).state !== "forwarded" ||
        reqKeyInRedis !== expJobIdApp2
      ) {
        throw new Error(
          `فشل سيناريو تنافس TTL: commitApp2=${commitApp2}, commitApp1=${commitApp1}, app1Job=${app1JobInRedis}, reqKey=${reqKeyInRedis}`
        );
      }
      console.log("✓ نجاح السيناريو 1-ب: حُذفت وظيفة APP1 المنتهية وبقيت وظيفة ومفتاح APP2 المثبّت في Redis.");
    } finally {
      await closeRedisClient();
    }

    // 6. السيناريو الثاني: انتقالات حالة الوظيفة الذرية عبر العقدتين (باستخدام GET + JSON.parse)
    console.log("[6/7] اختبار انتقالات حالة الوظيفة الذرية عبر العقد (forwarded -> processing -> submitted)...");
    const statusEventsOnApp2 = [];
    mobileApp2.on("print_job_status", (ev) => {
      if (ev && ev.jobId === winningJobId) statusEventsOnApp2.push(ev);
    });

    const procAck = await desktopSocket.emitWithAck("print_job_status_update", {
      jobId: winningJobId,
      status: "processing",
    });
    const subAck = await desktopSocket.emitWithAck("print_job_status_update", {
      jobId: winningJobId,
      status: "submitted",
    });
    const invalidBackAck = await desktopSocket.emitWithAck("print_job_status_update", {
      jobId: winningJobId,
      status: "processing",
    });

    await new Promise((r) => setTimeout(r, 500));
    const finalJobRaw = await redisClient.get(`ismart:printjob:${winningJobId}`);
    const finalJobRecord = finalJobRaw ? JSON.parse(finalJobRaw) : null;

    if (
      !procAck.ok ||
      !subAck.ok ||
      invalidBackAck.ok !== false ||
      !finalJobRecord ||
      finalJobRecord.state !== "submitted"
    ) {
      throw new Error(
        `فشل انتقال الحالة الذري: proc=${procAck.ok}, sub=${subAck.ok}, invalidBack=${invalidBackAck.ok}, state=${finalJobRecord?.state}`
      );
    }
    if (statusEventsOnApp2.length < 2) {
      throw new Error(`فشل وصول إشعارات حالة الطباعة عبر Redis Adapter إلى العميل المتصل بـ App2 (وصل ${statusEventsOnApp2.length})`);
    }
    console.log("✓ نجاح السيناريو 2: انتقالات الحالة الذرية في Redis ومنع الانتقال العكسي ووصول الإشعارات عبر العقدتين.");

    // 7. السيناريو الثالث: تجميع أولوية الحضور (Presence Priority) عبر العقدتين
    console.log("[7/7] اختبار تجميع أولوية الحضور عبر العقدتين (online > meeting > offline)...");
    const presAck1 = await desktopSocket.emitWithAck("presence:activity", { status: "meeting" });
    const presAck2 = await mobileApp1.emitWithAck("presence:activity", { status: "meeting" });
    if (!presAck1.ok || !presAck2.ok) {
      throw new Error("فشل تحديث حالة الحضور عبر حدث presence:activity");
    }
    await new Promise((r) => setTimeout(r, 400));

    const userWhileApp2Online = await User.findById(testUserId).lean();
    if (userWhileApp2Online.presenceStatus !== "online" || userWhileApp2Online.isOnline !== true) {
      throw new Error(`فشل أولوية الحضور: المتوقع 'online' لوجود جلسة متصلة على App2، لكن الفعلي '${userWhileApp2Online.presenceStatus}'`);
    }

    mobileApp2.close();
    await new Promise((r) => setTimeout(r, 800));

    const userAfterApp2Disconnect = await User.findById(testUserId).lean();
    if (userAfterApp2Disconnect.presenceStatus !== "meeting" || userAfterApp2Disconnect.isOnline !== true) {
      throw new Error(
        `فشل تجميع الحضور بعد فصل عقدة: المتوقع isOnline=true و presenceStatus='meeting'، الفعلي isOnline=${userAfterApp2Disconnect.isOnline}, status='${userAfterApp2Disconnect.presenceStatus}'`
      );
    }
    console.log("✓ نجاح السيناريو 3: أولوية الحضور عبر العقدتين حافظت على 'online' ثم انتقلت إلى 'meeting' عند غلق جلسة App2.");
    console.log("ℹ️ [NOT RUN] سيناريو انقطاع/عودة Redis الفعلي مفصول في خطة مستقلة بانتظار الموافقة اللاحقة.");

    testPassed = true;
    console.log("\n========================================================");
    console.log(`🎉 اكتملت سيناريوهات التكامل الموزع (3/3) بنجاح (RunID: ${runId})`);
    console.log("========================================================");
  } catch (err) {
    console.error("\n❌ فشل اختبار التكامل:", err.message);
    if (app1Logs.length) {
      console.error("--- آخر مخرجات APP1 ---\n" + app1Logs.slice(-20).join("\n"));
    }
    if (app2Logs.length) {
      console.error("--- آخر مخرجات APP2 ---\n" + app2Logs.slice(-20).join("\n"));
    }
    process.exitCode = 1;
  } finally {
    console.log("[Finally] إغلاق المقابس والعمليتين App1 و App2...");
    for (const s of createdSockets) {
      try { s.close(); } catch (_) {}
    }
    await stopChildProcessSafely(app1);
    await stopChildProcessSafely(app2);

    if (testPassed) {
      // عند النجاح فقط: تنظيف مقيد بمفاتيح Redis ومستخدم Mongo الذين أنشأهم هذا التشغيل فقط
      if (redisClient && createdRedisKeys.size > 0) {
        try {
          await redisClient.del(...createdRedisKeys);
        } catch (_) {}
      }
      if (testUserId && mongoose.connection.readyState === 1) {
        try {
          await DeviceSession.deleteMany({ userId: testUserId });
          await User.deleteOne({ _id: testUserId });
        } catch (_) {}
      }
      console.log("✓ تم حذف مستخدم ومفاتيح هذا التشغيل الناجح فقط دون المساس بأي مفاتيح أخرى.");
    } else {
      // عند الفشل: عدم حذف أدلة التشغيل من حاويتي الاختبار لتمكين الفحص الجنائي
      console.error("⚠️ تم الاحتفاظ بأدلة هذا التشغيل الفاشل في حاويتي الاختبار دون حذفها:", {
        runId,
        testUserId,
        preservedRedisKeys: [...createdRedisKeys],
      });
    }

    if (redisClient) {
      try { await redisClient.quit(); } catch (_) {}
    }
    if (mongoose.connection.readyState !== 0) {
      try { await mongoose.disconnect(); } catch (_) {}
    }
    console.log("✓ تم إغلاق المقابس والعمليتين App1 و App2 بأمان.");
  }
}

if (require.main === module) {
  runIntegrationSuite();
}

module.exports = {
  SocketIOv4Client,
  createCleanEnv,
};

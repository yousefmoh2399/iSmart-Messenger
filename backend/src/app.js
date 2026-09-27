const { TextEncoder, TextDecoder } = require("text-encoding");
const util = require("util");
global.TextEncoder = TextEncoder;
global.TextDecoder = TextDecoder;
util.TextEncoder = TextEncoder;
util.TextDecoder = TextDecoder;

const express = require("express");
const compression = require("compression");
const cors = require("cors");
const helmet = require("helmet");
const morgan = require("morgan");
const rateLimit = require("express-rate-limit");
const {
  allowDetailedHealth,
  allowUnsafeCors,
  corsOrigin,
  env,
  trustProxy,
  instanceId,
} = require("./config/env");
const { getDatabaseStatus } = require("./config/database");
const { getRedisStatus, getPubSubStatus } = require("./config/redis");
const { storage } = require("./utils/storage-provider");
const { getConnectedSocketStats, getAdapterStatus } = require("./chat/sockets/chat.socket");
const authRoutes = require("./routes/auth.routes");
const documentRoutes = require("./routes/document.routes");
const userRoutes = require("./routes/user.routes");
const adminBackupRoutes = require("./admin/backup/backup.routes");
const adminUpdateRoutes = require("./admin/updates/update-admin.routes");
const updateClientRoutes = require("./admin/updates/update-client.routes");
const announcementRoutes = require("./admin/announcements/announcement.routes");
const adminAppSettingsRoutes = require("./admin/app-settings/app-settings.routes");
const appSettingsRoutes = require("./routes/app-settings.routes");
const departmentRoutes = require("./chat/routes/department.routes");
const adminDepartmentRoutes = require("./chat/routes/admin-department.routes");
const branchRoutes = require("./chat/routes/branch.routes");
const adminBranchRoutes = require("./chat/routes/admin-branch.routes");
const adminRoleRoutes = require("./chat/routes/admin-role.routes");
const chatRoutes = require("./chat/routes/chat.routes");
const ticketRoutes = require("./tickets/routes/ticket.routes");
const printerRoutes = require("./printers/routes/printer.routes");
const purchasingRoutes = require("./purchasing/routes/purchasing.routes");
const {
  notFoundHandler,
  errorHandler,
} = require("./middleware/error.middleware");

const app = express();

app.set("trust proxy", trustProxy);

function buildCorsOrigin() {
  if (corsOrigin === "*") {
    if (env === "production" && !allowUnsafeCors) {
      throw new Error(
        "CORS_ORIGIN=* is not allowed in production. Set CORS_ORIGIN to explicit origins.",
      );
    }
    return true;
  }
  return corsOrigin;
}

function sanitizeMorganUrl(url) {
  try {
    const parsed = new URL(url, "http://local");
    for (const key of ["token", "accessToken", "refreshToken"]) {
      if (parsed.searchParams.has(key)) {
        parsed.searchParams.set(key, "[redacted]");
      }
    }
    return `${parsed.pathname}${parsed.search}${parsed.hash}`;
  } catch (_) {
    return String(url || "").replace(
      /([?&](?:token|accessToken|refreshToken)=)[^&]+/gi,
      "$1[redacted]",
    );
  }
}

morgan.token("safe-url", (req) => sanitizeMorganUrl(req.originalUrl || req.url));

app.use(
  cors({
    origin: buildCorsOrigin(),
  }),
);
app.use(compression());
app.use(helmet());
app.use(
  morgan(":method :safe-url :status :response-time ms - :res[content-length]", {
    skip: (req) =>
      req.method === "POST" &&
      /^\/api\/updates\/tasks\/[a-f0-9]{24}\/progress$/i.test(
        req.originalUrl || req.url || "",
      ),
  }),
);
app.use(express.json({ limit: "1mb" }));
app.use(express.urlencoded({ extended: true, limit: "1mb" }));

app.use(
  "/api",
  rateLimit({
    windowMs: 60 * 1000,
    max: 600,
    skip: (req) =>
      req.method === "POST" &&
      /^\/api\/updates\/tasks\/[a-f0-9]{24}\/progress$/i.test(
        req.originalUrl || req.url || "",
      ),
    standardHeaders: true,
    legacyHeaders: false,
    message: {
      success: false,
      message: "تم تجاوز عدد الطلبات المسموح. حاول مرة أخرى بعد قليل.",
    },
  }),
);

// Increase timeout for upload endpoints
app.use("/api/admin/updates/releases", (req, res, next) => {
  req.setTimeout(15 * 60 * 1000); // 15 minutes for releases upload
  res.setTimeout(15 * 60 * 1000);
  next();
});
app.use("/api/updates", (req, res, next) => {
  req.setTimeout(10 * 60 * 1000); // 10 minutes for update endpoints
  res.setTimeout(10 * 60 * 1000);
  next();
});
app.use("/api/chat/transfers", (req, res, next) => {
  req.setTimeout(15 * 60 * 1000);
  res.setTimeout(15 * 60 * 1000);
  next();
});

app.use((req, res, next) => {
  res.setHeader("X-Instance-Id", instanceId);
  next();
});

app.get("/", (req, res) => {
  res.status(200).json({
    status: "ok",
    service: "workplace-document-backend",
    instanceId,
  });
});

let cachedStorageHealth = null;
let lastStorageCheckTime = 0;
let isCheckingStorage = false;
const STORAGE_CACHE_TTL_MS = 5000;

async function checkStorageHealthCached() {
  const now = Date.now();
  if (cachedStorageHealth && now - lastStorageCheckTime < STORAGE_CACHE_TTL_MS) {
    return cachedStorageHealth;
  }
  if (isCheckingStorage) {
    return cachedStorageHealth || { available: false, status: "checking" };
  }

  isCheckingStorage = true;
  try {
    const storagePromise = storage.checkHealth().catch((e) => ({
      available: false,
      status: "error",
      error: e?.message,
    }));
    const storageTimeout = new Promise((resolve) =>
      setTimeout(() => resolve({ available: false, status: "timeout" }), 1000)
    );
    cachedStorageHealth = await Promise.race([storagePromise, storageTimeout]);
    lastStorageCheckTime = Date.now();
  } finally {
    isCheckingStorage = false;
  }
  return cachedStorageHealth;
}

async function buildHealthPayload() {
  const dbStatus = getDatabaseStatus();
  const redisInfo = getRedisStatus();
  const pubSubInfo = typeof getPubSubStatus === "function"
    ? getPubSubStatus()
    : { enabled: false, ready: false, status: "disabled" };
  const adapterInfo = typeof getAdapterStatus === "function"
    ? getAdapterStatus()
    : { attached: false, configured: false };

  // Cached storage check to prevent libuv threadpool starvation during NFS outages
  const storageInfo = await checkStorageHealthCached();

  const redisLabel = !redisInfo.enabled
    ? "disabled"
    : redisInfo.ready
      ? "connected"
      : redisInfo.status || "disconnected";

  // Strict cluster mode: only enforced if CLUSTER_MODE=true or if REDIS_URL is configured alongside INSTANCE_ID
  const isMultiNode = Boolean(
    process.env.CLUSTER_MODE === "true" ||
    (process.env.CLUSTER_MODE !== "false" && Boolean(process.env.REDIS_URL) && Boolean(process.env.INSTANCE_ID && process.env.INSTANCE_ID !== "default"))
  );

  let redisHealthy = !redisInfo.enabled || redisInfo.ready;
  let pubSubHealthy = true;

  if (pubSubInfo.enabled) {
    pubSubHealthy = pubSubInfo.ready && (adapterInfo.attached || !isMultiNode);
  }

  const isReady =
    dbStatus === "connected" &&
    storageInfo.available &&
    redisHealthy &&
    (!isMultiNode || pubSubHealthy);

  const payload = {
    status: isReady ? "ok" : "degraded",
    service: "ismart-api",
    version: "1.0.0",
    instanceId,
    database: dbStatus,
    redis: redisLabel,
    pubSub: pubSubInfo.status,
    adapter: adapterInfo.attached
      ? "attached"
      : adapterInfo.configured
        ? "failed"
        : "disabled",
    storage: storageInfo.status,
  };

  if (allowDetailedHealth) {
    payload.sockets = getConnectedSocketStats();
    if (adapterInfo.error) {
      payload.adapterError = adapterInfo.error;
    }
  }

  return { isReady, payload };
}

// Liveness check endpoint (Node process is responsive and event loop is healthy)
app.get("/health", async (req, res) => {
  const { payload } = await buildHealthPayload();
  // Liveness returns 200 as long as Express server process is up and responding
  res.status(200).json(payload);
});

// Readiness check endpoint for HAProxy (verifies MongoDB, Storage, and Redis)
app.get("/ready", async (req, res) => {
  const { isReady, payload } = await buildHealthPayload();
  res.status(isReady ? 200 : 503).json({
    ...payload,
    ready: isReady,
  });
});

app.use("/api/auth", authRoutes);
app.use("/api/documents", documentRoutes);
app.use("/api/users", userRoutes);
app.use("/api/admin/users", userRoutes);

// Increase timeout for admin backup operations
app.use("/api/admin/backup", (req, res, next) => {
  req.setTimeout(15 * 60 * 1000); // 15 minutes
  res.setTimeout(15 * 60 * 1000);
  next();
});
app.use("/api/admin/backup", adminBackupRoutes);

app.use("/api/admin/updates", adminUpdateRoutes);
app.use("/api/admin/app-settings", adminAppSettingsRoutes);
app.use("/api/admin/system-monitor", require("./admin/system-monitor/system-monitor.routes"));
app.use("/api/updates", updateClientRoutes);
app.use("/api/announcements", announcementRoutes);
app.use("/api/app-settings", appSettingsRoutes);
app.use("/api/client-errors", require("./routes/client-error.routes"));
app.use("/api/departments", departmentRoutes);
app.use("/api/admin/departments", adminDepartmentRoutes);
app.use("/api/branches", branchRoutes);
app.use("/api/admin/branches", adminBranchRoutes);
app.use("/api/admin/roles", adminRoleRoutes);
app.use("/api/chat", chatRoutes);


app.use("/api/tickets", ticketRoutes);
app.use("/api/admin/tickets", ticketRoutes);
app.use("/api/printers", printerRoutes);
app.use("/api/admin/printers", printerRoutes);
app.use("/api/purchase-requests", purchasingRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

module.exports = app;

let totalRequests = 0;
let activeRequests = 0;
const statusCounts = { "2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0 };
const recentRequests = [];
const MAX_RECENT_REQUESTS = 60;

// Rolling 10-second window for requests per second (RPS) calculation
const rpsBuckets = [];
const MAX_RPS_SECONDS = 10;
let latencySum = 0;
let latencyCount = 0;

function pruneOldBuckets(nowSec) {
  while (rpsBuckets.length > 0 && nowSec - rpsBuckets[0].sec >= MAX_RPS_SECONDS) {
    rpsBuckets.shift();
  }
}

function recordTelemetryEntry(io, entry) {
  if (!entry) return;

  recentRequests.unshift(entry);
  if (recentRequests.length > MAX_RECENT_REQUESTS) {
    recentRequests.pop();
  }

  // Telemetry is consumed by the admin operations monitor only. Broadcasting
  // each API/socket event to every connected client multiplies traffic by the
  // number of online devices and can saturate branch VPN links at peak hours.
  try {
    if (io && typeof io.emit === "function") {
      io.to("admin:monitor").emit("api_request_telemetry", entry);
    }
  } catch (_) {}
}

function recordSocketTelemetry(io, socket, eventName, durationMs = 8, details = {}) {
  const user = socket?.user || {};
  const handshake = socket?.handshake || {};

  let rawHost =
    handshake.headers?.["x-device-name"] ||
    handshake.headers?.["x-host-name"] ||
    handshake.auth?.deviceName ||
    handshake.auth?.deviceInfo?.deviceName ||
    handshake.auth?.deviceInfo?.hostname ||
    handshake.auth?.deviceInfo?.hostName ||
    user.deviceInfo?.hostName ||
    user.deviceInfo?.deviceName ||
    user.deviceInfo?.hostname ||
    null;
  if (rawHost && typeof rawHost === "string") {
    try {
      rawHost = decodeURIComponent(rawHost);
    } catch (_) {}
  }

  const branchCode = String(
    user.branchCode ||
    handshake.headers?.["x-branch-code"] ||
    handshake.auth?.branchCode ||
    "MAIN"
  ).toUpperCase();

  const deviceUid =
    user.deviceUid ||
    handshake.headers?.["x-device-uid"] ||
    handshake.auth?.deviceUid ||
    user.deviceInfo?.deviceUid ||
    null;

  const clientType =
    user.clientType ||
    handshake.headers?.["x-client-type"] ||
    handshake.auth?.clientType ||
    "desktop";

  const clientIp =
    user.ipAddress ||
    handshake.headers?.["x-forwarded-for"] ||
    handshake.address ||
    "-";

  const entry = {
    id: `${Date.now()}-${Math.random().toString(36).substring(2, 7)}`,
    timestamp: new Date().toISOString(),
    method: "SOCKET",
    path: details.path || `/socket/${eventName}`,
    statusCode: details.statusCode || 200,
    durationMs: Math.max(1, durationMs),
    clientIp: clientIp,
    hostName: rawHost,
    deviceUid: deviceUid,
    platform: clientType,
    branchCode: branchCode,
    actionLabel: details.label || null,
    user: {
      username: user.username || (rawHost ? `host:${rawHost}` : "-"),
      fullName: user.fullName || rawHost || (user.username ? user.username : "جهاز بالفرع"),
      role: user.role || "branch",
      branchCode: branchCode,
      hostName: rawHost,
      deviceUid: deviceUid,
    },
  };

  recordTelemetryEntry(io, entry);
}

function requestTelemetryMiddleware(req, res, next) {
  // Ignore static assets, health checks, avatars/progress streams, and monitor polls to prevent telemetry overhead/self-loops
  const p = req.path || "";
  if (
    p.startsWith("/assets") ||
    p.startsWith("/uploads") ||
    p === "/favicon.ico" ||
    p.includes("/system-monitor/") ||
    p.includes("/request-telemetry") ||
    p.includes("/progress") ||
    p.endsWith("/avatar") ||
    p.endsWith("/file") ||
    p.endsWith("/devices/heartbeat") ||
    p === "/health" ||
    p === "/api/health"
  ) {
    return next();
  }

  const start = Date.now();
  totalRequests++;
  activeRequests++;

  const nowSec = Math.floor(start / 1000);
  pruneOldBuckets(nowSec);
  let currentBucket = rpsBuckets.find((b) => b.sec === nowSec);
  if (!currentBucket) {
    currentBucket = { sec: nowSec, count: 0 };
    rpsBuckets.push(currentBucket);
  }
  currentBucket.count++;

  res.on("finish", () => {
    activeRequests = Math.max(0, activeRequests - 1);
    const duration = Date.now() - start;

    latencySum += duration;
    latencyCount++;
    if (latencyCount > 1000) {
      latencySum = Math.round(latencySum / 2);
      latencyCount = Math.round(latencyCount / 2);
    }

    const sc = res.statusCode;
    if (sc >= 200 && sc < 300) statusCounts["2xx"]++;
    else if (sc >= 300 && sc < 400) statusCounts["3xx"]++;
    else if (sc >= 400 && sc < 500) statusCounts["4xx"]++;
    else if (sc >= 500) statusCounts["5xx"]++;

    let rawHost =
      req.headers["x-device-name"] ||
      req.headers["x-host-name"] ||
      req.body?.hostName ||
      req.body?.deviceName ||
      req.body?.hostname ||
      req.user?.deviceInfo?.hostName ||
      req.user?.deviceInfo?.deviceName ||
      req.user?.deviceInfo?.hostname ||
      null;
    if (rawHost && typeof rawHost === "string") {
      try {
        rawHost = decodeURIComponent(rawHost);
      } catch (_) {}
    }

    const deviceUid =
      req.headers["x-device-uid"] ||
      req.body?.deviceUid ||
      req.user?.deviceUid ||
      req.user?.deviceInfo?.deviceUid ||
      null;
    const platform =
      req.headers["x-device-platform"] ||
      req.body?.platform ||
      (req.headers["user-agent"]?.includes("Android") ? "mobile_android" : "desktop_windows");
    const branchCode =
      req.user?.branchCode ||
      req.body?.branchCode ||
      req.headers["x-branch-code"] ||
      "MAIN";

    const username = req.user?.username || req.body?.username || null;
    const fullName = req.user?.fullName || req.body?.fullName || null;

    const entry = {
      id: `${Date.now()}-${Math.random().toString(36).substring(2, 7)}`,
      timestamp: new Date().toISOString(),
      method: req.method,
      path: req.originalUrl || req.url,
      statusCode: sc,
      durationMs: duration,
      clientIp: req.ip || req.headers["x-forwarded-for"] || req.socket?.remoteAddress || "-",
      hostName: rawHost,
      deviceUid: deviceUid,
      platform: platform,
      branchCode: String(branchCode).toUpperCase(),
      user: {
        username: username || (rawHost ? `host:${rawHost}` : "-"),
        fullName: fullName || rawHost || (username ? username : "جهاز بالشبكة"),
        role: req.user?.role || "branch",
        branchCode: String(branchCode).toUpperCase(),
        hostName: rawHost,
        deviceUid: deviceUid,
      },
    };

    recordTelemetryEntry(req.app?.get?.("io"), entry);
  });

  next();
}

function getTelemetrySnapshot() {
  const nowSec = Math.floor(Date.now() / 1000);
  pruneOldBuckets(nowSec);

  const windowSeconds = Math.max(1, rpsBuckets.length);
  const totalWindowRequests = rpsBuckets.reduce((sum, b) => sum + b.count, 0);
  const rps = Math.round((totalWindowRequests / windowSeconds) * 10) / 10;

  const avgLatency = latencyCount > 0 ? Math.round(latencySum / latencyCount) : 12;

  return {
    totalRequests,
    activeRequests,
    rps,
    avgLatencyMs: avgLatency,
    statusCounts: { ...statusCounts },
    recentRequests: [...recentRequests],
  };
}

module.exports = {
  requestTelemetryMiddleware,
  recordTelemetryEntry,
  recordSocketTelemetry,
  getTelemetrySnapshot,
};

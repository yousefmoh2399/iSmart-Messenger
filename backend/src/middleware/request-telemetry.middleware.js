let totalRequests = 0;
let activeRequests = 0;
const statusCounts = { "2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0 };
const recentRequests = [];
const MAX_RECENT_REQUESTS = 50;

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

function requestTelemetryMiddleware(req, res, next) {
  // Ignore static assets / health checks to keep telemetry focused on actual API usage
  if (req.path.startsWith("/assets") || req.path.startsWith("/uploads") || req.path === "/favicon.ico") {
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

    // Only record non-telemetry requests in recent list to prevent telemetry self-loop
    if (!req.path.includes("/system-monitor/request-telemetry") && !req.path.includes("/system-monitor/stats")) {
      const entry = {
        id: `${Date.now()}-${Math.random().toString(36).substring(2, 7)}`,
        timestamp: new Date().toISOString(),
        method: req.method,
        path: req.originalUrl || req.url,
        statusCode: sc,
        durationMs: duration,
        clientIp: req.ip || req.headers["x-forwarded-for"] || req.socket?.remoteAddress || "-",
        user: req.user ? { username: req.user.username, fullName: req.user.fullName, role: req.user.role } : null,
      };

      recentRequests.unshift(entry);
      if (recentRequests.length > MAX_RECENT_REQUESTS) {
        recentRequests.pop();
      }
    }
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
  getTelemetrySnapshot,
};

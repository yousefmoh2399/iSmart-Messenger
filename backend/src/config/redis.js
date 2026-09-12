const Redis = require("ioredis");
const { redisUrl } = require("./env");
const logger = require("../utils/logger");

let client = null;
let attempted = false;
let loggedConnectError = false;

function getRedisStatus() {
  if (!client) {
    return { enabled: false, status: "disabled" };
  }
  const status = client.status || "unknown";
  return {
    enabled: true,
    status,
    ready: status === "ready",
  };
}

function getRedisClient() {
  if (attempted) {
    return client;
  }
  attempted = true;

  if (!redisUrl) {
    client = null;
    return client;
  }

  client = new Redis(redisUrl, {
    maxRetriesPerRequest: 2,
    enableReadyCheck: true,
    lazyConnect: true,
    connectTimeout: 1500,
  });

  // Best-effort connection; if Redis is down, we still want the app to run.
  // Errors are logged once (not per-retry) so operators can see Redis is
  // unavailable without flooding the logs on every reconnect attempt.
  client.connect().catch((error) => {
    if (!loggedConnectError) {
      loggedConnectError = true;
      logger.warn("redis.connect_failed", { errorMessage: error?.message });
    }
  });
  client.on("error", (error) => {
    if (!loggedConnectError) {
      loggedConnectError = true;
      logger.warn("redis.client_error", { errorMessage: error?.message });
    }
  });
  client.on("ready", () => {
    loggedConnectError = false;
  });

  return client;
}

async function closeRedisClient() {
  if (!client) {
    return;
  }
  try {
    await client.quit();
  } catch (_) {
    try {
      client.disconnect();
    } catch (_) {}
  }
}

module.exports = {
  getRedisClient,
  getRedisStatus,
  closeRedisClient,
};


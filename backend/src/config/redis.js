const Redis = require("ioredis");
const { redisUrl } = require("./env");
const logger = require("../utils/logger");

let client = null;
let pubClient = null;
let subClient = null;
let attempted = false;
let loggedConnectError = false;

function getRedisStatus() {
  if (!client) {
    return { enabled: Boolean(redisUrl), status: redisUrl ? "initializing" : "disabled", ready: false };
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

  const isTestRunner =
    Boolean(process.env.NODE_TEST_CONTEXT) ||
    process.env.NODE_ENV === "test" ||
    process.execArgv.includes("--test") ||
    process.argv.includes("--test");

  if (!redisUrl || (isTestRunner && !process.env.FORCE_REDIS_IN_TESTS)) {
    client = null;
    return client;
  }

  client = new Redis(redisUrl, {
    // Redis is an optional acceleration/rate-limit/distributed-state store. Do not keep API
    // requests queued while the Redis service is unavailable.
    maxRetriesPerRequest: 0,
    enableOfflineQueue: false,
    enableReadyCheck: true,
    lazyConnect: true,
    connectTimeout: 2000,
    retryStrategy: (attempt) => Math.min(attempt * 500, 5000),
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
    if (loggedConnectError) {
      logger.info("redis.reconnected");
    }
    loggedConnectError = false;
  });

  return client;
}

function createRedisPubSubClients() {
  if (!redisUrl) {
    return null;
  }
  if (pubClient && subClient) {
    return { pubClient, subClient };
  }

  const baseOptions = {
    maxRetriesPerRequest: null,
    enableReadyCheck: true,
    lazyConnect: true,
    connectTimeout: 2500,
    retryStrategy: (attempt) => Math.min(attempt * 500, 5000),
  };

  pubClient = new Redis(redisUrl, baseOptions);
  subClient = pubClient.duplicate();

  pubClient.on("error", (err) => {
    logger.warn("redis.pubsub.pub_error", { errorMessage: err?.message });
  });
  subClient.on("error", (err) => {
    logger.warn("redis.pubsub.sub_error", { errorMessage: err?.message });
  });

  return { pubClient, subClient };
}

function getPubSubStatus() {
  if (!redisUrl) {
    return { enabled: false, ready: false, status: "disabled" };
  }
  if (!pubClient || !subClient) {
    return { enabled: true, ready: false, status: "not_initialized" };
  }
  const pubStatus = pubClient.status || "unknown";
  const subStatus = subClient.status || "unknown";
  const ready = pubStatus === "ready" && subStatus === "ready";
  return {
    enabled: true,
    ready,
    pubStatus,
    subStatus,
    status: ready ? "connected" : `${pubStatus}/${subStatus}`,
  };
}

async function closeOneClient(redisInstance) {
  if (!redisInstance) return;
  try {
    await redisInstance.quit();
  } catch (_) {
    try {
      redisInstance.disconnect();
    } catch (_) {}
  }
}

async function closeRedisClient() {
  await Promise.all([
    closeOneClient(client),
    closeOneClient(pubClient),
    closeOneClient(subClient),
  ]);
  client = null;
  pubClient = null;
  subClient = null;
  attempted = false;
}

module.exports = {
  getRedisClient,
  createRedisPubSubClients,
  getRedisStatus,
  getPubSubStatus,
  closeRedisClient,
};

const crypto = require("crypto");
const { getRedisClient } = require("../config/redis");
const { instanceId } = require("../config/env");
const logger = require("./logger");

const localLocks = new Map();

const RELEASE_LOCK_LUA = `
if redis.call("get", KEYS[1]) == ARGV[1] then
  return redis.call("del", KEYS[1])
else
  return 0
end
`;

function acquireLocalLock(key, token, ttlMs) {
  const now = Date.now();
  const existing = localLocks.get(key);
  if (existing && existing.expiresAt > now) {
    return false;
  }
  localLocks.set(key, {
    token,
    expiresAt: now + ttlMs,
  });
  return true;
}

function releaseLocalLock(key, token) {
  const existing = localLocks.get(key);
  if (existing && existing.token === token) {
    localLocks.delete(key);
  }
}

/**
 * Acquire a distributed lock across all Backend instances via Redis.
 *
 * In a multi-instance cluster, fallbackToLocal defaults to false to prevent
 * split-brain execution when Redis is unreachable. In single-instance dev/test,
 * it defaults to true.
 *
 * @param {string} lockName - Logical lock name (e.g. "cron:message_scheduler")
 * @param {number} ttlMs - Lock expiration time in milliseconds
 * @param {Function} taskFn - Async function to execute while holding the lock
 * @param {Object} [options]
 * @param {boolean} [options.fallbackToLocal] - Whether to fall back to a local process lock if Redis is unavailable
 * @param {boolean} [options.autoRelease=true] - Whether to automatically release lock after task completes
 * @param {boolean} [options.releaseOnError=true] - If autoRelease is false, release the lock anyway if taskFn throws
 * @returns {Promise<{ acquired: boolean, result?: any }>}
 */
async function withDistributedLock(
  lockName,
  ttlMs,
  taskFn,
  { fallbackToLocal, autoRelease = true, releaseOnError = true } = {}
) {
  const isCluster = Boolean(
    process.env.CLUSTER_MODE === "true" ||
    (process.env.INSTANCE_ID && process.env.INSTANCE_ID !== "default" && process.env.REDIS_URL)
  );
  const effectiveFallback =
    typeof fallbackToLocal === "boolean" ? fallbackToLocal : !isCluster;

  const redisKey = `ismart:lock:${lockName}`;
  const token = `${instanceId}:${crypto.randomBytes(8).toString("hex")}`;
  const redis = getRedisClient();

  let usedRedis = false;
  let acquired = false;

  if (redis && redis.status === "ready") {
    try {
      const res = await redis.set(redisKey, token, "PX", ttlMs, "NX");
      usedRedis = true;
      acquired = res === "OK";
    } catch (err) {
      logger.warn("distributed_lock.redis_error", {
        lockName,
        errorMessage: err?.message,
      });
      usedRedis = false;
    }
  }

  if (!usedRedis) {
    if (!effectiveFallback) {
      return { acquired: false };
    }
    acquired = acquireLocalLock(redisKey, token, ttlMs);
  }

  if (!acquired) {
    return { acquired: false };
  }

  let taskSucceeded = false;
  try {
    const result = await taskFn();
    taskSucceeded = true;
    return { acquired: true, result };
  } finally {
    const shouldRelease = autoRelease || (!taskSucceeded && releaseOnError);
    if (shouldRelease) {
      if (usedRedis && redis && redis.status === "ready") {
        try {
          await redis.eval(RELEASE_LOCK_LUA, 1, redisKey, token);
        } catch (_) {}
      } else {
        releaseLocalLock(redisKey, token);
      }
    }
  }
}

module.exports = {
  withDistributedLock,
};

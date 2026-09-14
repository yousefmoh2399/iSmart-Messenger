const { MemoryStore } = require("express-rate-limit");
const { RedisStore } = require("rate-limit-redis");
const { getRedisClient } = require("./redis");

const REDIS_RETRY_DELAY_MS = 5000;

function createRateLimitStore(prefix) {
  const memoryStore = new MemoryStore();
  let redisStore = null;
  let redisInitPromise = null;
  let lastRedisAttemptAt = 0;

  function init(options) {
    memoryStore.init(options);
  }

  async function getRedisStore() {
    const redis = getRedisClient();
    if (!redis || redis.status !== "ready") {
      return null;
    }

    if (redisStore) {
      return redisStore;
    }
    if (redisInitPromise) {
      return redisInitPromise;
    }

    const now = Date.now();
    if (now - lastRedisAttemptAt < REDIS_RETRY_DELAY_MS) {
      return null;
    }
    lastRedisAttemptAt = now;

    redisInitPromise = (async () => {
      const candidate = new RedisStore({
        sendCommand: (...args) => redis.call(...args),
        prefix,
      });
      candidate.init({ windowMs: memoryStore.windowMs });

      // RedisStore starts script loading in its constructor. Observe both
      // promises immediately so an unavailable Redis cannot become unhandled.
      await Promise.all([candidate.incrementScriptSha, candidate.getScriptSha]);
      redisStore = candidate;
      return candidate;
    })()
      .catch(() => null)
      .finally(() => {
        redisInitPromise = null;
      });

    return redisInitPromise;
  }

  async function increment(key) {
    const store = await getRedisStore();
    if (store) {
      try {
        return await store.increment(key);
      } catch (_) {
        redisStore = null;
      }
    }
    return memoryStore.increment(key);
  }

  async function decrement(key) {
    const store = await getRedisStore();
    if (store?.decrement) {
      try {
        return await store.decrement(key);
      } catch (_) {
        redisStore = null;
      }
    }
    return memoryStore.decrement(key);
  }

  async function resetKey(key) {
    const store = await getRedisStore();
    if (store) {
      try {
        return await store.resetKey(key);
      } catch (_) {
        redisStore = null;
      }
    }
    return memoryStore.resetKey(key);
  }

  async function resetAll() {
    redisStore?.resetAll?.();
    return memoryStore.resetAll();
  }

  return {
    init,
    increment,
    decrement,
    resetKey,
    resetAll,
  };
}

module.exports = { createRateLimitStore };

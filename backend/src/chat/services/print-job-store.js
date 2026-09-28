const crypto = require("crypto");
const logger = require("../../utils/logger");
const { getRedisClient } = require("../../config/redis");

const clientRequestToJobId = new Map(); // key -> { status, token, jobId, expiresAt, timestamp }
const printJobs = new Map(); // jobId -> { state, payload, timestamp, version, retryCount }
const jobOwners = new Map(); // `${type}:${jobId}` -> userId

const ALLOWED_TRANSITIONS = {
  "pending": ["forwarded"],
  "forwarded": ["processing", "failed"],
  "processing": ["submitted", "failed"],
  "failed": ["processing"],
  "submitted": [] // terminal state
};

// Periodic 24-hour cleanup for local maps
const RETENTION_MS = 24 * 60 * 60 * 1000;
const RETENTION_SECONDS = 24 * 60 * 60;
const CLEANUP_INTERVAL_MS = 60 * 60 * 1000; // hourly check

const cleanupInterval = setInterval(() => {
  const now = Date.now();
  for (const [requestId, entry] of clientRequestToJobId.entries()) {
    if (now - (entry.timestamp || 0) > RETENTION_MS) {
      clientRequestToJobId.delete(requestId);
    }
  }
  for (const [jobId, entry] of printJobs.entries()) {
    if (now - (entry.timestamp || 0) > RETENTION_MS) {
      printJobs.delete(jobId);
    }
  }
}, CLEANUP_INTERVAL_MS);

if (typeof cleanupInterval.unref === "function") {
  cleanupInterval.unref();
}

async function syncJobToRedis(jobId, job) {
  if (!printJobs.has(jobId)) return;
  const redis = getRedisClient();
  if (!redis || redis.status !== "ready") return;
  try {
    await redis.set(`ismart:printjob:${jobId}`, JSON.stringify(job), "EX", RETENTION_SECONDS);
  } catch (_) {}
}

function getRequestScopedKey(clientRequestId, userId = null) {
  return userId ? `${userId}:${clientRequestId}` : String(clientRequestId);
}

function syncRequestToRedis(clientRequestId, jobId, userId = null) {
  const redis = getRedisClient();
  if (!redis || redis.status !== "ready") return;
  const key = `ismart:printreq:${getRequestScopedKey(clientRequestId, userId)}`;
  redis
    .set(key, String(jobId), "EX", RETENTION_SECONDS)
    .catch(() => {});
  // Also set unscoped key for backward-compatibility if scoped
  if (userId) {
    redis
      .set(`ismart:printreq:${clientRequestId}`, String(jobId), "EX", RETENTION_SECONDS)
      .catch(() => {});
  }
}

function setJobOwner(type, jobId, userId) {
  if (!jobId || !userId) return;
  const key = `${type}:${jobId}`;
  jobOwners.set(key, String(userId));
  const redis = getRedisClient();
  if (redis && redis.status === "ready") {
    redis
      .set(`ismart:jobowner:${key}`, String(userId), "EX", RETENTION_SECONDS)
      .catch(() => {});
  }
}

async function resolveJobOwner(type, jobId, fallbackUserId = null) {
  if (!jobId) return fallbackUserId;
  const key = `${type}:${jobId}`;
  const localOwner = jobOwners.get(key);
  if (localOwner) return localOwner;

  const redis = getRedisClient();
  if (redis && redis.status === "ready") {
    try {
      const remoteOwner = await redis.get(`ismart:jobowner:${key}`);
      if (remoteOwner) {
        jobOwners.set(key, remoteOwner);
        return remoteOwner;
      }
    } catch (_) {}
  }
  return fallbackUserId;
}

function deleteJobOwner(type, jobId) {
  if (!jobId) return;
  const key = `${type}:${jobId}`;
  jobOwners.delete(key);
  const redis = getRedisClient();
  if (redis && redis.status === "ready") {
    redis.del(`ismart:jobowner:${key}`).catch(() => {});
  }
}

function getJobIdForRequest(clientRequestId, userId = null) {
  if (!clientRequestId) return null;
  const scopedKey = getRequestScopedKey(clientRequestId, userId);
  let entry = clientRequestToJobId.get(scopedKey);
  if (!entry && userId) {
    entry = clientRequestToJobId.get(clientRequestId);
  }
  if (entry && entry.jobId) {
    entry.timestamp = Date.now();
    return entry.jobId;
  }
  return null;
}

async function getJobIdForRequestAsync(clientRequestId, userId = null) {
  if (!clientRequestId) return null;
  const localId = getJobIdForRequest(clientRequestId, userId);
  if (localId) return localId;

  const redis = getRedisClient();
  if (redis && redis.status === "ready") {
    try {
      const scopedKey = getRequestScopedKey(clientRequestId, userId);
      let remoteVal = await redis.get(`ismart:printreq:${scopedKey}`);
      if (!remoteVal && userId) {
        remoteVal = await redis.get(`ismart:printreq:${clientRequestId}`);
      }
      if (remoteVal && !remoteVal.startsWith("RESERVED:")) {
        clientRequestToJobId.set(scopedKey, {
          status: "committed",
          jobId: remoteVal,
          timestamp: Date.now(),
        });
        return remoteVal;
      }
    } catch (_) {}
  }
  return null;
}

function isClusterModeActive() {
  return Boolean(
    process.env.CLUSTER_MODE === "true" ||
    (process.env.CLUSTER_MODE !== "false" && Boolean(process.env.REDIS_URL) && Boolean(process.env.INSTANCE_ID && process.env.INSTANCE_ID !== "default"))
  );
}

/**
 * Atomically reserve a clientRequestId for a given user across cluster nodes.
 * Prevents check-then-create race conditions between APP1 and APP2.
 * In CLUSTER_MODE=true, local fallback is strictly prohibited.
 *
 * @param {Object} options
 * @param {string} options.userId - Scoping user ID
 * @param {string} options.clientRequestId - Unique request ID from client
 * @param {number} [options.ttlMs=15000] - Reservation TTL in milliseconds
 * @returns {Promise<{ status: "reserved" | "existing" | "in_flight" | "failed", token?: string, jobId?: string, error?: string }>}
 */
async function reservePrintRequest({ userId, clientRequestId, ttlMs = 15000 }) {
  if (!clientRequestId) {
    return { status: "reserved", token: crypto.randomBytes(8).toString("hex") };
  }
  const scopedKey = getRequestScopedKey(clientRequestId, userId);
  const token = crypto.randomBytes(8).toString("hex");
  const isCluster = isClusterModeActive();
  const redis = getRedisClient();

  if (redis && redis.status === "ready") {
    try {
      const redisKey = `ismart:printreq:${scopedKey}`;
      const res = await redis.set(redisKey, `RESERVED:${token}`, "PX", ttlMs, "NX");
      if (res === "OK") {
        clientRequestToJobId.set(scopedKey, {
          status: "reserved",
          token,
          expiresAt: Date.now() + ttlMs,
          timestamp: Date.now(),
        });
        return { status: "reserved", token };
      }

      // Key already exists in Redis: inspect current value
      const existingVal = await redis.get(redisKey);
      if (existingVal && existingVal.startsWith("RESERVED:")) {
        return { status: "in_flight", token: existingVal.slice("RESERVED:".length) };
      }
      if (existingVal) {
        clientRequestToJobId.set(scopedKey, {
          status: "committed",
          jobId: existingVal,
          timestamp: Date.now(),
        });
        return { status: "existing", jobId: existingVal };
      }
    } catch (err) {
      logger.warn("print_job.reserve.redis_failed", { scopedKey, error: err?.message });
      if (isCluster) {
        return {
          status: "failed",
          error: "CLUSTER_MODE requires operational Redis for distributed print reservation.",
        };
      }
    }
  } else if (isCluster) {
    logger.error("print_job.reserve.cluster_redis_unavailable", { scopedKey });
    return {
      status: "failed",
      error: "CLUSTER_MODE requires operational Redis for distributed print reservation.",
    };
  }

  // Local process reservation (single node / non-cluster dev mode ONLY)
  const now = Date.now();
  const existing = clientRequestToJobId.get(scopedKey);
  if (existing) {
    if (existing.status === "reserved" && existing.expiresAt > now) {
      return { status: "in_flight", token: existing.token };
    }
    if (existing.jobId) {
      return { status: "existing", jobId: existing.jobId };
    }
  }

  clientRequestToJobId.set(scopedKey, {
    status: "reserved",
    token,
    expiresAt: now + ttlMs,
    timestamp: now,
  });
  return { status: "reserved", token };
}

const COMMIT_PRINT_REQ_LUA = `
local curr = redis.call("get", KEYS[1])
if curr == ARGV[1] then
  redis.call("set", KEYS[1], ARGV[2], "EX", ARGV[3])
  return 1
else
  return 0
end
`;

/**
 * Deletes an uncommitted or aborted job from both local memory and Redis
 * so that it is never counted as a valid job or left dispatchable.
 */
async function deleteJobAsync(jobId) {
  if (!jobId) return;
  printJobs.delete(jobId);
  jobOwners.delete(`print:${jobId}`);
  const redis = getRedisClient();
  if (redis && redis.status === "ready") {
    try {
      await redis.del(`ismart:printjob:${jobId}`, `ismart:jobowner:print:${jobId}`);
    } catch (_) {}
  }
}

/**
 * Commits a reserved print request to a confirmed jobId.
 * Returns true if commit succeeded, or false (and deletes the job from Redis/memory)
 * if the reservation token expired or was invalidated.
 */
async function commitPrintRequest({ userId, clientRequestId, token, jobId }) {
  if (!clientRequestId || !jobId) {
    await deleteJobAsync(jobId);
    return false;
  }
  const scopedKey = getRequestScopedKey(clientRequestId, userId);
  const isCluster = isClusterModeActive();
  const redis = getRedisClient();

  if (redis && redis.status === "ready") {
    try {
      const redisKey = `ismart:printreq:${scopedKey}`;
      const expectedTokenVal = token ? `RESERVED:${token}` : null;
      if (expectedTokenVal) {
        const res = await redis.eval(
          COMMIT_PRINT_REQ_LUA,
          1,
          redisKey,
          expectedTokenVal,
          String(jobId),
          RETENTION_SECONDS
        );
        if (Number(res) !== 1) {
          logger.warn("print_job.commit.token_expired_or_mismatched", { scopedKey, token, jobId });
          await deleteJobAsync(jobId);
          return false;
        }
      } else {
        if (isCluster) {
          logger.warn("print_job.commit.missing_token_in_cluster", { scopedKey, jobId });
          await deleteJobAsync(jobId);
          return false;
        }
        await redis.set(redisKey, String(jobId), "EX", RETENTION_SECONDS);
      }
      if (userId) {
        await redis.set(`ismart:printreq:${clientRequestId}`, String(jobId), "EX", RETENTION_SECONDS);
      }
    } catch (err) {
      logger.error("print_job.commit.redis_error", { scopedKey, error: err?.message });
      if (isCluster) {
        await deleteJobAsync(jobId);
        return false;
      }
    }
  } else if (isCluster) {
    logger.error("print_job.commit.cluster_redis_unavailable", { scopedKey, jobId });
    await deleteJobAsync(jobId);
    return false;
  } else {
    // Validate reservation token and expiry in local mode
    const localEntry = clientRequestToJobId.get(scopedKey);
    const now = Date.now();
    const isExpired =
      localEntry &&
      localEntry.status === "reserved" &&
      localEntry.expiresAt &&
      now >= localEntry.expiresAt;
    if (
      !localEntry ||
      localEntry.status !== "reserved" ||
      (token && localEntry.token !== token) ||
      isExpired
    ) {
      if (isExpired && (!token || localEntry.token === token)) {
        clientRequestToJobId.delete(scopedKey);
      }
      logger.warn("print_job.commit.local_token_expired_or_mismatched", { scopedKey, token, jobId });
      await deleteJobAsync(jobId);
      return false;
    }
  }

  // Update local map only when verified
  clientRequestToJobId.set(scopedKey, {
    status: "committed",
    jobId,
    timestamp: Date.now(),
  });
  if (userId) {
    clientRequestToJobId.set(clientRequestId, {
      status: "committed",
      jobId,
      timestamp: Date.now(),
    });
  }
  return true;
}

const RELEASE_PRINT_REQ_LUA = `
if redis.call("get", KEYS[1]) == ARGV[1] then
  return redis.call("del", KEYS[1])
else
  return 0
end
`;

/**
 * Releases a reservation if job creation failed or was aborted.
 */
async function releasePrintReservation({ userId, clientRequestId, token }) {
  if (!clientRequestId || !token) return;
  const scopedKey = getRequestScopedKey(clientRequestId, userId);
  const localEntry = clientRequestToJobId.get(scopedKey);
  if (localEntry && localEntry.token === token) {
    clientRequestToJobId.delete(scopedKey);
  }

  const redis = getRedisClient();
  if (redis && redis.status === "ready") {
    try {
      await redis.eval(
        RELEASE_PRINT_REQ_LUA,
        1,
        `ismart:printreq:${scopedKey}`,
        `RESERVED:${token}`
      );
    } catch (_) {}
  }
}

function registerRequest(clientRequestId, jobId, userId = null) {
  if (!clientRequestId) return;
  const scopedKey = getRequestScopedKey(clientRequestId, userId);
  clientRequestToJobId.set(scopedKey, { status: "committed", jobId, timestamp: Date.now() });
  if (userId) {
    clientRequestToJobId.set(clientRequestId, { status: "committed", jobId, timestamp: Date.now() });
  }
  syncRequestToRedis(clientRequestId, jobId, userId);
}

function createJob(jobId, payload) {
  const job = {
    state: "pending",
    payload,
    timestamp: Date.now(),
    version: 1,
    retryCount: 0
  };
  printJobs.set(jobId, job);
  syncJobToRedis(jobId, job);
  return job;
}

async function createJobAsync(jobId, payload) {
  const job = {
    state: "pending",
    payload,
    timestamp: Date.now(),
    version: 1,
    retryCount: 0
  };
  printJobs.set(jobId, job);
  await syncJobToRedis(jobId, job);
  return job;
}

function getJob(jobId) {
  return printJobs.get(jobId) || null;
}

async function getJobAsync(jobId) {
  const local = printJobs.get(jobId);
  const redis = getRedisClient();

  if (redis && redis.status === "ready") {
    try {
      const raw = await redis.get(`ismart:printjob:${jobId}`);
      if (raw) {
        const remote = JSON.parse(raw);
        const remoteVer = remote.version || 0;
        const localVer = local?.version || 0;
        const remoteTime = remote.timestamp || 0;
        const localTime = local?.timestamp || 0;

        if (!local || remoteVer > localVer || (remoteVer === localVer && remoteTime >= localTime)) {
          printJobs.set(jobId, remote);
          return remote;
        }
        return local;
      }
    } catch (_) {}
  }

  return local || null;
}

function validateAndTransition(jobId, nextState) {
  const job = printJobs.get(jobId);
  if (!job) {
    throw new Error(`Job not found: ${jobId}`);
  }

  const currentState = job.state;
  if (currentState === nextState) {
    return true; // Already in target state
  }

  const allowed = ALLOWED_TRANSITIONS[currentState] || [];
  if (!allowed.includes(nextState)) {
    throw new Error(`Invalid print job state transition from ${currentState} to ${nextState}`);
  }

  // Update state, timestamp, and version
  job.state = nextState;
  job.timestamp = Date.now();
  job.version = (job.version || 0) + 1;
  if (nextState === "processing" && currentState === "failed") {
    job.retryCount++;
  }
  syncJobToRedis(jobId, job);
  return true;
}

const TRANSITION_JOB_LUA = `
local raw = redis.call("get", KEYS[1])
if not raw then
  return redis.error_reply("JOB_NOT_FOUND")
end
local job = cjson.decode(raw)
local currState = job["state"]
local nextState = ARGV[1]

if currState == nextState then
  return raw
end

local allowed = false
if currState == "pending" and nextState == "forwarded" then
  allowed = true
elseif currState == "forwarded" and (nextState == "processing" or nextState == "failed") then
  allowed = true
elseif currState == "processing" and (nextState == "submitted" or nextState == "failed") then
  allowed = true
elseif currState == "failed" and nextState == "processing" then
  allowed = true
  job["retryCount"] = (job["retryCount"] or 0) + 1
end

if not allowed then
  return redis.error_reply("INVALID_TRANSITION:" .. currState .. "->" .. nextState)
end

job["state"] = nextState
job["timestamp"] = tonumber(ARGV[2])
job["version"] = (job["version"] or 0) + 1
local updated = cjson.encode(job)
redis.call("set", KEYS[1], updated, "EX", tonumber(ARGV[3]))
return updated
`;

async function validateAndTransitionAsync(jobId, nextState) {
  const redis = getRedisClient();
  if (redis && redis.status === "ready") {
    try {
      const updatedRaw = await redis.eval(
        TRANSITION_JOB_LUA,
        1,
        `ismart:printjob:${jobId}`,
        nextState,
        Date.now(),
        RETENTION_SECONDS
      );
      if (updatedRaw) {
        const updatedJob = JSON.parse(updatedRaw);
        printJobs.set(jobId, updatedJob);
        return updatedJob;
      }
    } catch (err) {
      if (err.message && err.message.includes("INVALID_TRANSITION")) {
        throw new Error(err.message);
      }
      if (err.message && err.message.includes("JOB_NOT_FOUND")) {
        throw new Error(`Job not found: ${jobId}`);
      }
      logger.warn("print_job.transition_lua_failed", { jobId, error: err?.message });
      if (isClusterModeActive()) {
        throw new Error(`CLUSTER_MODE distributed transition failed: ${err?.message}`);
      }
    }
  } else if (isClusterModeActive()) {
    throw new Error("CLUSTER_MODE requires operational Redis for distributed state transitions");
  }

  // Fallback to local process transition (single-node dev mode ONLY)
  validateAndTransition(jobId, nextState);
  return printJobs.get(jobId);
}

function clearAll() {
  clientRequestToJobId.clear();
  printJobs.clear();
  jobOwners.clear();
}

module.exports = {
  getJobIdForRequest,
  getJobIdForRequestAsync,
  registerRequest,
  reservePrintRequest,
  commitPrintRequest,
  releasePrintReservation,
  createJob,
  createJobAsync,
  deleteJobAsync,
  getJob,
  getJobAsync,
  setJobOwner,
  resolveJobOwner,
  deleteJobOwner,
  validateAndTransition,
  validateAndTransitionAsync,
  clearAll,
  RETENTION_MS
};

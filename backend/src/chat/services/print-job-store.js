const logger = require("../../utils/logger");

const clientRequestToJobId = new Map(); // clientRequestId -> { jobId, timestamp }
const printJobs = new Map(); // jobId -> { state, payload, timestamp, retryCount }

const ALLOWED_TRANSITIONS = {
  "pending": ["forwarded"],
  "forwarded": ["processing", "failed"],
  "processing": ["submitted", "failed"],
  "failed": ["processing"],
  "submitted": [] // terminal state
};

// Periodic 24-hour cleanup for both maps
const RETENTION_MS = 24 * 60 * 60 * 1000;
const CLEANUP_INTERVAL_MS = 60 * 60 * 1000; // hourly check

const cleanupInterval = setInterval(() => {
  const now = Date.now();
  for (const [requestId, entry] of clientRequestToJobId.entries()) {
    if (now - entry.timestamp > RETENTION_MS) {
      clientRequestToJobId.delete(requestId);
    }
  }
  for (const [jobId, entry] of printJobs.entries()) {
    if (now - entry.timestamp > RETENTION_MS) {
      printJobs.delete(jobId);
    }
  }
}, CLEANUP_INTERVAL_MS);

if (typeof cleanupInterval.unref === "function") {
  cleanupInterval.unref();
}

function getJobIdForRequest(clientRequestId) {
  if (!clientRequestId) return null;
  const entry = clientRequestToJobId.get(clientRequestId);
  if (entry) {
    entry.timestamp = Date.now();
    return entry.jobId;
  }
  return null;
}

function registerRequest(clientRequestId, jobId) {
  if (!clientRequestId) return;
  clientRequestToJobId.set(clientRequestId, { jobId, timestamp: Date.now() });
}

function createJob(jobId, payload) {
  const job = {
    state: "pending",
    payload,
    timestamp: Date.now(),
    retryCount: 0
  };
  printJobs.set(jobId, job);
  return job;
}

function getJob(jobId) {
  return printJobs.get(jobId) || null;
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

  // Update state and timestamp
  job.state = nextState;
  job.timestamp = Date.now();
  if (nextState === "processing" && currentState === "failed") {
    job.retryCount++;
  }
  return true;
}

function clearAll() {
  clientRequestToJobId.clear();
  printJobs.clear();
}

module.exports = {
  getJobIdForRequest,
  registerRequest,
  createJob,
  getJob,
  validateAndTransition,
  clearAll,
  RETENTION_MS
};

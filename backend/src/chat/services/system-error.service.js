const SystemErrorLog = require("../models/system-error-log.model");

function sanitizeMessage(value, maxLength = 5000) {
  return String(value || "").trim().slice(0, maxLength);
}

async function logSystemError({
  actorId = null,
  method = "",
  path = "",
  statusCode = 500,
  errorName = "Error",
  message = "",
  stack = null,
  meta = null,
}) {
  if (!path || !message) {
    return null;
  }

  try {
    return await SystemErrorLog.create({
      actorId,
      method: sanitizeMessage(method, 16),
      path: sanitizeMessage(path, 500),
      statusCode: Number(statusCode || 500),
      errorName: sanitizeMessage(errorName, 120) || "Error",
      message: sanitizeMessage(message),
      stack: stack ? sanitizeMessage(stack, 12000) : null,
      meta,
    });
  } catch (_) {
    return null;
  }
}

async function listSystemErrors({ actor, limit = 100, statusCode = null }) {
  const query = {};

  if (actor?.role !== "admin") {
    query.actorId = actor?.id || null;
  }

  if (statusCode) {
    query.statusCode = Number(statusCode);
  }

  return SystemErrorLog.find(query)
    .sort({ createdAt: -1 })
    .limit(Math.max(1, Math.min(Number(limit || 100), 200)))
    .lean();
}

module.exports = {
  logSystemError,
  listSystemErrors,
};

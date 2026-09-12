const AuditLog = require("../models/audit-log.model");

async function logAuditEvent({ actorId, action, entityType, entityId, payload = null }) {
  if (!actorId || !action || !entityType || !entityId) {
    return null;
  }

  return AuditLog.create({
    actorId,
    action,
    entityType,
    entityId: String(entityId),
    payload,
  });
}

async function listAuditLogs({ actor, departmentId = null, limit = 100 }) {
  const query = {};

  if (actor?.role === "manager" && departmentId) {
    query["payload.departmentId"] = departmentId;
  } else if (actor?.role !== "admin" && actor?.role !== "manager") {
    query.actorId = actor?.id || null;
  }

  return AuditLog.find(query)
    .sort({ createdAt: -1 })
    .limit(Math.max(1, Math.min(limit, 200)))
    .lean();
}

module.exports = {
  logAuditEvent,
  listAuditLogs,
};

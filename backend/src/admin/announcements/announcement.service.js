const Announcement = require("./announcement.model");
const ApiError = require("../../utils/api-error");
const { logAuditEvent } = require("../../chat/services/audit.service");
const { userHasPermission } = require("../../chat/services/role.service");

async function assertCanManage(actor) {
  if (actor?.role === "admin") return;
  const allowed = await userHasPermission(actor, "canManageAnnouncements");
  if (!allowed) {
    throw new ApiError(403, "Announcement management access required.");
  }
}

function serializeAnnouncement(entry) {
  return {
    id: entry._id.toString(),
    title: entry.title,
    message: entry.message,
    tone: entry.tone || "info",
    isPinned: entry.isPinned === true,
    isActive: entry.isActive !== false,
    startsAt: entry.startsAt || null,
    endsAt: entry.endsAt || null,
    createdBy: entry.createdBy?.toString?.() || entry.createdBy || null,
    createdAt: entry.createdAt,
    updatedAt: entry.updatedAt,
    deletedAt: entry.deletedAt || null,
  };
}

function normalizeOptionalDate(value) {
  if (value == null || value == "") {
    return null;
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new ApiError(400, "Invalid announcement date.");
  }
  return parsed;
}

function validateWindow(startsAt, endsAt) {
  if (startsAt && endsAt && endsAt < startsAt) {
    throw new ApiError(400, "Announcement end date must be after start date.");
  }
}

function buildActiveQuery(now = new Date()) {
  return {
    deletedAt: null,
    isActive: true,
    $and: [
      {
        $or: [{ startsAt: null }, { startsAt: { $lte: now } }],
      },
      {
        $or: [{ endsAt: null }, { endsAt: { $gte: now } }],
      },
    ],
  };
}

async function listAnnouncements(actor, { includeInactive = false } = {}) {
  let canManage = false;
  if (actor) {
    if (actor.role === "admin") {
      canManage = true;
    } else {
      canManage = await userHasPermission(actor, "canManageAnnouncements");
    }
  }

  const query =
    includeInactive && canManage
      ? { deletedAt: null }
      : buildActiveQuery();

  const entries = await Announcement.find(query)
    .sort({ isPinned: -1, updatedAt: -1, createdAt: -1 })
    .lean();

  return entries.map(serializeAnnouncement);
}

async function createAnnouncement(actor, payload) {
  await assertCanManage(actor);

  const startsAt = normalizeOptionalDate(payload.startsAt);
  const endsAt = normalizeOptionalDate(payload.endsAt);
  validateWindow(startsAt, endsAt);

  const entry = await Announcement.create({
    title: String(payload.title || "").trim(),
    message: String(payload.message || "").trim(),
    tone: String(payload.tone || "info").trim(),
    isPinned: payload.isPinned === true,
    isActive: payload.isActive !== false,
    startsAt,
    endsAt,
    createdBy: actor.id,
  });

  await logAuditEvent({
    actorId: actor.id,
    action: "announcement.created",
    entityType: "Announcement",
    entityId: entry._id,
    payload: {
      tone: entry.tone,
      isPinned: entry.isPinned,
      isActive: entry.isActive,
    },
  });

  return serializeAnnouncement(entry);
}

async function updateAnnouncement(actor, announcementId, payload) {
  await assertCanManage(actor);

  const entry = await Announcement.findOne({
    _id: announcementId,
    deletedAt: null,
  });
  if (!entry) {
    throw new ApiError(404, "Announcement not found.");
  }

  const startsAt = Object.prototype.hasOwnProperty.call(payload, "startsAt")
    ? normalizeOptionalDate(payload.startsAt)
    : entry.startsAt;
  const endsAt = Object.prototype.hasOwnProperty.call(payload, "endsAt")
    ? normalizeOptionalDate(payload.endsAt)
    : entry.endsAt;
  validateWindow(startsAt, endsAt);

  if (payload.title != null) {
    entry.title = String(payload.title).trim();
  }
  if (payload.message != null) {
    entry.message = String(payload.message).trim();
  }
  if (payload.tone != null) {
    entry.tone = String(payload.tone).trim();
  }
  if (payload.isPinned != null) {
    entry.isPinned = payload.isPinned === true;
  }
  if (payload.isActive != null) {
    entry.isActive = payload.isActive === true;
  }
  entry.startsAt = startsAt;
  entry.endsAt = endsAt;

  await entry.save();
  await logAuditEvent({
    actorId: actor.id,
    action: "announcement.updated",
    entityType: "Announcement",
    entityId: entry._id,
    payload: {
      tone: entry.tone,
      isPinned: entry.isPinned,
      isActive: entry.isActive,
    },
  });

  return serializeAnnouncement(entry);
}

async function updateAnnouncementStatus(actor, announcementId, isActive) {
  await assertCanManage(actor);
  const entry = await Announcement.findOne({
    _id: announcementId,
    deletedAt: null,
  });
  if (!entry) {
    throw new ApiError(404, "Announcement not found.");
  }

  entry.isActive = Boolean(isActive);
  await entry.save();

  await logAuditEvent({
    actorId: actor.id,
    action: "announcement.status.updated",
    entityType: "Announcement",
    entityId: entry._id,
    payload: { isActive: entry.isActive },
  });

  return serializeAnnouncement(entry);
}

async function deleteAnnouncement(actor, announcementId) {
  await assertCanManage(actor);
  const entry = await Announcement.findOne({
    _id: announcementId,
    deletedAt: null,
  });
  if (!entry) {
    throw new ApiError(404, "Announcement not found.");
  }

  entry.deletedAt = new Date();
  await entry.save();

  await logAuditEvent({
    actorId: actor.id,
    action: "announcement.deleted",
    entityType: "Announcement",
    entityId: entry._id,
  });
}

module.exports = {
  listAnnouncements,
  createAnnouncement,
  updateAnnouncement,
  updateAnnouncementStatus,
  deleteAnnouncement,
};

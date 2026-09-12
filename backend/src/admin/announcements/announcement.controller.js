const asyncHandler = require("../../utils/async-handler");
const { sendChatResponse } = require("../../chat/utils/chat-response");
const {
  listAnnouncements,
  createAnnouncement,
  updateAnnouncement,
  updateAnnouncementStatus,
  deleteAnnouncement,
} = require("./announcement.service");

function emitAnnouncementsUpdated(req, payload = {}) {
  const io = req.app.get("io");
  if (!io) {
    return;
  }
  io.emit("announcements_updated", {
    at: new Date().toISOString(),
    ...payload,
  });
}

const getAnnouncements = asyncHandler(async (req, res) => {
  const announcements = await listAnnouncements(req.user, {
    includeInactive: req.query.includeInactive === "true",
  });
  sendChatResponse(res, {
    data: { announcements },
    legacy: { announcements },
  });
});

const createManagedAnnouncement = asyncHandler(async (req, res) => {
  const announcement = await createAnnouncement(req.user, req.body);
  emitAnnouncementsUpdated(req, {
    action: "created",
    announcementId: announcement.id,
  });
  sendChatResponse(res, {
    status: 201,
    data: { announcement },
    legacy: { announcement },
  });
});

const updateManagedAnnouncement = asyncHandler(async (req, res) => {
  const announcement = await updateAnnouncement(req.user, req.params.id, req.body);
  emitAnnouncementsUpdated(req, {
    action: "updated",
    announcementId: announcement.id,
    isActive: announcement.isActive,
  });
  sendChatResponse(res, {
    data: { announcement },
    legacy: { announcement },
  });
});

const updateManagedAnnouncementStatus = asyncHandler(async (req, res) => {
  const announcement = await updateAnnouncementStatus(
    req.user,
    req.params.id,
    req.body.isActive
  );
  emitAnnouncementsUpdated(req, {
    action: "status_updated",
    announcementId: announcement.id,
    isActive: announcement.isActive,
  });
  sendChatResponse(res, {
    data: { announcement },
    legacy: { announcement },
  });
});

const deleteManagedAnnouncement = asyncHandler(async (req, res) => {
  await deleteAnnouncement(req.user, req.params.id);
  emitAnnouncementsUpdated(req, {
    action: "deleted",
    announcementId: req.params.id,
  });
  sendChatResponse(res, {
    data: { deleted: true },
    legacy: { deleted: true },
  });
});

module.exports = {
  getAnnouncements,
  createManagedAnnouncement,
  updateManagedAnnouncement,
  updateManagedAnnouncementStatus,
  deleteManagedAnnouncement,
};

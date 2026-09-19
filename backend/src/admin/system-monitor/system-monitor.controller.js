const asyncHandler = require("../../utils/async-handler");
const DeviceSession = require("../../models/device-session.model");
const ClientError = require("../../models/client-error.model");

const getConnections = asyncHandler(async (req, res) => {
  const page = parseInt(req.query.page, 10) || 1;
  const limit = parseInt(req.query.limit, 10) || 50;
  const skip = (page - 1) * limit;
  const status = req.query.status; // 'online', 'offline', 'all'
  const clientType = req.query.clientType;
  const search = req.query.search;

  let query = {};

  if (status === "online") {
    query.isOnline = true;
  } else if (status === "offline") {
    query.isOnline = false;
  }

  if (clientType && clientType !== "all") {
    query.clientType = clientType;
  }

  // Populate user first to allow searching, or search inside User model and match
  if (search && search.trim() !== "") {
    const User = require("../../models/user.model");
    const regex = new RegExp(search.trim(), "i");
    const matchedUsers = await User.find({
      $or: [{ username: regex }, { fullName: regex }],
    }).select("_id");
    const userIds = matchedUsers.map((u) => u._id);
    query.userId = { $in: userIds };
  }

  const sessions = await DeviceSession.find(query)
    .populate("userId", "username fullName role avatarUrl isOnline")
    .sort({ lastSeenAt: -1, startedAt: -1 })
    .skip(skip)
    .limit(limit)
    .lean();

  const total = await DeviceSession.countDocuments(query);
  const hasMore = skip + sessions.length < total;

  res.json({
    success: true,
    data: {
      sessions,
      pagination: {
        page,
        limit,
        total,
        hasMore,
      },
    },
  });
});

const getErrors = asyncHandler(async (req, res) => {
  const page = parseInt(req.query.page, 10) || 1;
  const limit = parseInt(req.query.limit, 10) || 50;
  const skip = (page - 1) * limit;
  const userId = req.query.userId;
  const sessionId = req.query.sessionId;
  const resolved = req.query.resolved;

  let query = {};
  if (userId) query.userId = userId;
  if (sessionId) query.sessionId = sessionId;
  if (resolved !== undefined) query.resolved = resolved === "true";

  const errors = await ClientError.find(query)
    .populate("userId", "username fullName")
    .populate("sessionId", "ipAddress clientType deviceInfo")
    .sort({ createdAt: -1 })
    .skip(skip)
    .limit(limit)
    .lean();

  const total = await ClientError.countDocuments(query);
  const hasMore = skip + errors.length < total;

  res.json({
    success: true,
    data: {
      errors,
      pagination: {
        page,
        limit,
        total,
        hasMore,
      },
    },
  });
});

const markErrorResolved = asyncHandler(async (req, res) => {
  const errorId = req.params.id;
  const updated = await ClientError.findByIdAndUpdate(
    errorId,
    { resolved: true },
    { new: true }
  ).lean();

  if (!updated) {
    return res.status(404).json({ success: false, message: "Error not found" });
  }

  res.json({ success: true, data: updated });
});

const deleteAllErrors = asyncHandler(async (req, res) => {
  await ClientError.deleteMany({});
  res.json({ success: true, message: "All errors deleted" });
});

module.exports = {
  getConnections,
  getErrors,
  markErrorResolved,
  deleteAllErrors,
};

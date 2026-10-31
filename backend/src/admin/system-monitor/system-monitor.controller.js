const os = require("os");
const process = require("process");
const mongoose = require("mongoose");
const asyncHandler = require("../../utils/async-handler");
const DeviceSession = require("../../models/device-session.model");
const ClientError = require("../../models/client-error.model");
const User = require("../../models/user.model");
function safeGetLiveSocketMetrics() {
  try {
    const chatSocket = require("../../chat/sockets/chat.socket");
    if (typeof chatSocket?.getLiveSocketMetrics === "function") {
      return chatSocket.getLiveSocketMetrics();
    }
  } catch (_) {}
  return {
    totalConnections: 0,
    usersOnline: 0,
    desktopSockets: 0,
    mobileSockets: 0,
    webSockets: 0,
    otherSockets: 0,
  };
}

const getSystemStats = asyncHandler(async (req, res) => {
  const liveMetrics = safeGetLiveSocketMetrics();

  // OS & Hardware Metrics
  const totalMem = os.totalmem();
  const freeMem = os.freemem();
  const usedMem = totalMem - freeMem;
  const memUsagePercent = Math.round((usedMem / totalMem) * 100);

  const procMem = process.memoryUsage();
  const cpus = os.cpus() || [];
  const cpuModel = cpus[0]?.model || "Unknown CPU";
  const cpuCores = cpus.length;
  const loadAvg = os.loadavg();

  // Database Connection Status
  const dbState = mongoose.connection.readyState;
  const dbStatus =
    dbState === 1 ? "connected" : dbState === 2 ? "connecting" : "disconnected";

  // System Counts
  const totalUsers = await User.countDocuments();
  const totalSessions = await DeviceSession.countDocuments();
  const totalErrors = await ClientError.countDocuments();
  const unresolvedErrors = await ClientError.countDocuments({ resolved: false });

  // Client Type Counts for currently online sessions
  const activeSessions = await DeviceSession.find({ isOnline: true }).select("clientType socketId userId").lean();
  let desktopCount = 0;
  let mobileCount = 0;
  let webCount = 0;

  for (const s of activeSessions) {
    const isLive = s.socketId
      ? liveMetrics.isSocketConnected(s.socketId)
      : s.userId
        ? liveMetrics.isUserOnline(s.userId)
        : false;
    if (isLive) {
      if (s.clientType === "desktop") desktopCount++;
      else if (s.clientType === "mobile") mobileCount++;
      else if (s.clientType === "web") webCount++;
    }
  }

  res.json({
    success: true,
    data: {
      uptimeSeconds: Math.floor(process.uptime()),
      systemUptimeSeconds: Math.floor(os.uptime()),
      nodeVersion: process.version,
      platform: os.platform(),
      osType: os.type(),
      osRelease: os.release(),
      hostname: os.hostname(),
      cpu: {
        model: cpuModel,
        cores: cpuCores,
        loadAvg: loadAvg.map((l) => Math.round(l * 100) / 100),
      },
      memory: {
        totalBytes: totalMem,
        usedBytes: usedMem,
        freeBytes: freeMem,
        usagePercent: memUsagePercent,
        processHeapUsed: procMem.heapUsed,
        processHeapTotal: procMem.heapTotal,
        processRss: procMem.rss,
      },
      database: {
        status: dbStatus,
        name: mongoose.connection.name || "ismart",
        host: mongoose.connection.host || "localhost",
      },
      sockets: {
        liveSocketsCount: liveMetrics.liveSocketCount,
        liveUsersCount: liveMetrics.liveUserCount,
      },
      summary: {
        totalUsers,
        totalSessions,
        unresolvedErrors,
        totalErrors,
        activeClients: {
          desktop: desktopCount,
          mobile: mobileCount,
          web: webCount,
        },
      },
    },
  });
});

const getConnections = asyncHandler(async (req, res) => {
  const page = parseInt(req.query.page, 10) || 1;
  const limit = parseInt(req.query.limit, 10) || 50;
  const skip = (page - 1) * limit;
  const status = req.query.status; // 'online', 'offline', 'all'
  const clientType = req.query.clientType;
  const search = req.query.search;

  const liveMetrics = safeGetLiveSocketMetrics();

  let query = {};

  if (clientType && clientType !== "all") {
    query.clientType = clientType;
  }

  if (search && search.trim() !== "") {
    const regex = new RegExp(search.trim(), "i");
    const matchedUsers = await User.find({
      $or: [{ username: regex }, { fullName: regex }],
    }).select("_id");
    const userIds = matchedUsers.map((u) => u._id);
    query.userId = { $in: userIds };
  }

  const rawSessions = await DeviceSession.find(query)
    .populate("userId", "username fullName role avatarUrl isOnline jobTitleBranch department")
    .sort({ lastSeenAt: -1, startedAt: -1 })
    .lean();

  // Reconcile each session against real-time live socket metrics
  const reconciledSessions = [];
  for (const s of rawSessions) {
    const isLive = s.socketId
      ? liveMetrics.isSocketConnected(s.socketId)
      : s.userId
        ? liveMetrics.isUserOnline(s.userId._id || s.userId)
        : false;

    // Fix database if out of sync
    if (s.isOnline && !isLive) {
      DeviceSession.findByIdAndUpdate(s._id, { isOnline: false }).catch(() => {});
      s.isOnline = false;
    } else if (!s.isOnline && isLive) {
      DeviceSession.findByIdAndUpdate(s._id, { isOnline: true }).catch(() => {});
      s.isOnline = true;
    }

    // Apply status filter based on verified live state
    if (status === "online" && !s.isOnline) {
      continue;
    }
    if (status === "offline" && s.isOnline) {
      continue;
    }

    reconciledSessions.push(s);
  }

  const total = reconciledSessions.length;
  const paginated = reconciledSessions.slice(skip, skip + limit);
  const hasMore = skip + paginated.length < total;

  res.json({
    success: true,
    data: {
      sessions: paginated,
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
    .populate("userId", "username fullName role avatarUrl jobTitleBranch")
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
  getSystemStats,
  getConnections,
  getErrors,
  markErrorResolved,
  deleteAllErrors,
};

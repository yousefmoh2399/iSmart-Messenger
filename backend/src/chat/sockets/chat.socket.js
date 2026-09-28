const fs = require("fs");
const { Server } = require("socket.io");
const { createAdapter } = require("@socket.io/redis-adapter");
const jwt = require("jsonwebtoken");
const User = require("../../models/user.model");
const DeviceSession = require("../../models/device-session.model");
const { jwtSecret, corsOrigin, instanceId } = require("../../config/env");
const { getRedisClient, createRedisPubSubClients } = require("../../config/redis");
const { withDistributedLock } = require("../../utils/distributed-lock");
const { resolveStoredUploadPath } = require("../../utils/storage-paths");
const logger = require("../../utils/logger");
const printJobStore = require("../services/print-job-store");
const {
  getConversationById,
  getConversationSnapshotForUserId,
  createMessage,
  markConversationDelivered,
  markPendingDeliveriesForUser,
  markConversationSeen,
  getConversationRoom,
  assertConversationAccess,
  getUserPresence,
} = require("../services/chat.service");
const { getEffectivePermissionsForUser } = require("../services/role.service");
const {
  getUnreadCountsForUser,
} = require("../services/chat-member-state.service");
const {
  setUserPresence,
  touchUserActivity,
} = require("../../services/user.service");
const { getChatTransferForUser } = require("../services/chat-transfer.service");
const {
  sendChatPushNotifications,
} = require("../../services/push-notification.service");

const typingState = new Map();
const typingTimeouts = new Map();
const userSockets = new Map();
const socketPresence = new Map();
const socketClientType = new Map();
const publishedPresenceState = new Map();
const printerCatalogByUser = new Map();
const printJobOwnerById = new Map();
const desktopStorageByUser = new Map();
const saveJobOwnerById = new Map();
const receiveJobOwnerById = new Map();
const SOCKET_MAX_PAYLOAD_BYTES =
  Number(process.env.SOCKET_MAX_PAYLOAD_BYTES) || 96 * 1024 * 1024;
const ADMIN_TRANSFER_MAX_BYTES = 200 * 1024 * 1024;
const USER_TRANSFER_MAX_BYTES = 30 * 1024 * 1024;

const redisAdapterStatus = {
  configured: false,
  attached: false,
  error: null,
};

function getAdapterStatus() {
  return { ...redisAdapterStatus };
}

function normalizeClientType(value) {
  const normalized = String(value || "")
    .trim()
    .toLowerCase();
  if (
    normalized === "desktop" ||
    normalized === "mobile" ||
    normalized === "web"
  ) {
    return normalized;
  }
  return "unknown";
}

function emitPresence(io, userId, isOnline, status, extra = {}) {
  const payload = {
    userId,
    isOnline,
    presenceStatus: status,
    ...extra,
  };
  io.to("lobby").emit("presence_updated", payload);
  io.to("lobby").emit(isOnline ? "user_online" : "user_offline", payload);
}

function registerUserSocket(userId, socketId) {
  const sockets = userSockets.get(userId) || new Set();
  sockets.add(socketId);
  userSockets.set(userId, sockets);
}

function unregisterUserSocket(userId, socketId) {
  const sockets = userSockets.get(userId);
  socketPresence.delete(socketId);
  socketClientType.delete(socketId);
  if (!sockets) {
    return;
  }
  sockets.delete(socketId);
  if (!sockets.size) {
    userSockets.delete(userId);
    publishedPresenceState.delete(userId);
  }
}

function hasLiveSocketId(io, socketId) {
  const registry = io?.sockets?.sockets;
  if (!registry) {
    return true;
  }
  if (typeof registry.has === "function") {
    return registry.has(socketId);
  }
  if (typeof registry.get === "function") {
    return Boolean(registry.get(socketId));
  }
  if (typeof registry === "object") {
    return Boolean(registry[socketId]);
  }
  return true;
}

function pruneUserSockets(io, userId) {
  const sockets = userSockets.get(userId) || new Set();
  for (const socketId of [...sockets]) {
    if (!hasLiveSocketId(io, socketId)) {
      sockets.delete(socketId);
      socketPresence.delete(socketId);
      socketClientType.delete(socketId);
    }
  }
  if (!sockets.size) {
    userSockets.delete(userId);
    publishedPresenceState.delete(userId);
  } else {
    userSockets.set(userId, sockets);
  }
  return sockets;
}

const remoteMobileOnlineUsers = new Set();
const remoteDesktopOnlineUsers = new Set();

async function refreshClusterClientTypeSets() {
  try {
    const cutoff = new Date(Date.now() - 3 * 60 * 1000);
    const activeSessions = await DeviceSession.find(
      { isOnline: true, lastSeenAt: { $gte: cutoff } },
      "userId clientType"
    ).lean();
    remoteMobileOnlineUsers.clear();
    remoteDesktopOnlineUsers.clear();
    for (const s of activeSessions) {
      const uid = String(s.userId || "");
      if (!uid) continue;
      if (s.clientType === "mobile") remoteMobileOnlineUsers.add(uid);
      if (s.clientType === "desktop") remoteDesktopOnlineUsers.add(uid);
    }
  } catch (_) {}
}

function getDesktopSocketIds(io, userId) {
  const sockets = pruneUserSockets(io, userId);
  const desktopSockets = [...sockets].filter(
    (socketId) =>
      socketClientType.get(socketId) === "desktop" &&
      (socketPresence.get(socketId) || "online") !== "offline",
  );
  return desktopSockets.length
    ? [desktopSockets[desktopSockets.length - 1]]
    : [];
}

async function resolveClusterDesktopTargets(io, userId) {
  const localIds = getDesktopSocketIds(io, userId);
  if (localIds.length) {
    return localIds;
  }
  try {
    const cutoff = new Date(Date.now() - 3 * 60 * 1000);
    const sessions = await DeviceSession.find(
      {
        userId,
        clientType: "desktop",
        isOnline: true,
        lastSeenAt: { $gte: cutoff },
        socketId: { $ne: null },
      },
      "socketId"
    )
      .sort({ lastSeenAt: -1 })
      .lean();
    if (sessions.length && sessions[0].socketId) {
      return [sessions[0].socketId];
    }
  } catch (_) {}
  return [];
}

function getMobileSocketIds(io, userId) {
  const sockets = pruneUserSockets(io, userId);
  return [...sockets].filter(
    (socketId) =>
      socketClientType.get(socketId) === "mobile" &&
      (socketPresence.get(socketId) || "online") !== "offline",
  );
}

async function resolveClusterMobileTargets(io, userId) {
  const localIds = getMobileSocketIds(io, userId);
  if (localIds.length) {
    return localIds;
  }
  try {
    const cutoff = new Date(Date.now() - 3 * 60 * 1000);
    const sessions = await DeviceSession.find(
      {
        userId,
        clientType: "mobile",
        isOnline: true,
        lastSeenAt: { $gte: cutoff },
        socketId: { $ne: null },
      },
      "socketId"
    ).lean();
    return sessions.map((s) => s.socketId).filter(Boolean);
  } catch (_) {
    return [];
  }
}

function maxTransferBytesForRole(role) {
  return role === "admin" ? ADMIN_TRANSFER_MAX_BYTES : USER_TRANSFER_MAX_BYTES;
}

async function buildInlineTransferPayload(transferMeta, role) {
  if (!transferMeta) {
    return null;
  }
  const allowedBytes = maxTransferBytesForRole(role);
  const declaredSize = Number(transferMeta.fileSize || 0);
  if (
    !Number.isFinite(declaredSize) ||
    declaredSize <= 0 ||
    declaredSize > allowedBytes
  ) {
    return null;
  }
  const resolvedPath = resolveStoredUploadPath(transferMeta.storedFilePath);
  if (!resolvedPath) {
    return null;
  }
  try {
    const bytes = await fs.promises.readFile(resolvedPath);
    if (!bytes.length || bytes.length > allowedBytes) {
      return null;
    }
    return bytes.toString("base64");
  } catch (_) {
    return null;
  }
}

function getUserDeliveryContext(io, userId) {
  const uid = String(userId || "");
  const sockets = pruneUserSockets(io, uid);
  let hasDesktop = remoteDesktopOnlineUsers.has(uid);
  let hasMobile = remoteMobileOnlineUsers.has(uid);
  let hasWeb = false;
  for (const socketId of sockets) {
    if ((socketPresence.get(socketId) || "online") === "offline") {
      continue;
    }
    const clientType = socketClientType.get(socketId);
    if (clientType === "desktop") {
      hasDesktop = true;
    }
    if (clientType === "mobile") {
      hasMobile = true;
    }
    if (clientType === "web") {
      hasWeb = true;
    }
  }
  return {
    hasDesktop,
    hasMobile,
    hasWeb,
  };
}

function getAggregatedPresence(io, userId) {
  const sockets = pruneUserSockets(io, userId);
  if (!sockets || !sockets.size) {
    return { isOnline: false, status: "offline" };
  }

  let hasOnlineSocket = false;
  let hasMeetingSocket = false;
  let hasLunchSocket = false;
  let hasIdleSocket = false;
  for (const socketId of sockets) {
    const status = socketPresence.get(socketId) || "online";
    if (status === "online") {
      hasOnlineSocket = true;
      break;
    }
    if (status === "meeting") {
      hasMeetingSocket = true;
      continue;
    }
    if (status === "lunch") {
      hasLunchSocket = true;
      continue;
    }
    if (status === "idle") {
      hasIdleSocket = true;
    }
  }

  if (hasOnlineSocket) return { isOnline: true, status: "online" };
  if (hasMeetingSocket) return { isOnline: true, status: "meeting" };
  if (hasLunchSocket) return { isOnline: true, status: "lunch" };
  if (hasIdleSocket) return { isOnline: true, status: "idle" };
  return { isOnline: false, status: "offline" };
}

async function publishAggregatedPresence(io, userId, extra = {}) {
  const aggregated = getAggregatedPresence(io, userId);
  let effectiveOnline = aggregated.isOnline;
  let effectiveStatus = aggregated.status;

  // Check active device sessions across cluster instances whenever local status is below "online"
  // so that cross-node sessions properly respect online > meeting > lunch > idle > offline
  if (effectiveStatus !== "online") {
    try {
      const cutoff = new Date(Date.now() - 3 * 60 * 1000);
      const otherSessions = await DeviceSession.find(
        { userId, isOnline: true, lastSeenAt: { $gte: cutoff } },
        "presenceStatus"
      ).lean();

      if (otherSessions.length > 0) {
        effectiveOnline = true;
        const statuses = new Set(otherSessions.map((s) => s.presenceStatus || "online"));
        if (aggregated.isOnline && aggregated.status) {
          statuses.add(aggregated.status);
        }
        if (statuses.has("online")) {
          effectiveStatus = "online";
        } else if (statuses.has("meeting")) {
          effectiveStatus = "meeting";
        } else if (statuses.has("lunch")) {
          effectiveStatus = "lunch";
        } else if (statuses.has("idle")) {
          effectiveStatus = "idle";
        } else {
          effectiveStatus = "online";
        }
      }
    } catch (_) {}
  }

  const nextSignature = `${effectiveOnline ? "1" : "0"}:${effectiveStatus}`;
  const hasExtra = extra && Object.keys(extra).length > 0;
  const currentSignature = publishedPresenceState.get(userId);
  if (!hasExtra && currentSignature === nextSignature) {
    return;
  }
  await setUserPresence(userId, {
    isOnline: effectiveOnline,
    status: effectiveStatus,
  });
  publishedPresenceState.set(userId, nextSignature);

  const payload = { ...extra };
  if (effectiveOnline) {
    payload.lastActiveAt = payload.lastActiveAt || new Date().toISOString();
  } else {
    payload.lastSeen = payload.lastSeen || new Date().toISOString();
  }

  emitPresence(io, userId, effectiveOnline, effectiveStatus, payload);
}

async function markActive(io, currentUser, socketId) {
  registerUserSocket(currentUser.id, socketId);
  socketPresence.set(socketId, "online");
  try {
    await touchUserActivity(currentUser.id, "online");
    await publishAggregatedPresence(io, currentUser.id, {
      lastActiveAt: new Date().toISOString(),
    });
  } catch (error) {
    logger.warn("chat.presence.mark_active_failed", {
      userId: currentUser?.id,
      errorName: error?.name,
      errorMessage: error?.message,
    });
  }
}

function socketAck(ack, payload) {
  if (typeof ack === "function") {
    ack(payload);
  }
}

function resolveTokenVersion(value) {
  return Number.isInteger(value) && value > 0 ? value : 1;
}

async function resolveSocketUser(socket) {
  const rawToken =
    socket.handshake.auth?.token ||
    socket.handshake.headers?.authorization?.replace(/^Bearer\s+/i, "");

  if (!rawToken) {
    throw new Error("Authentication required.");
  }

  const payload = jwt.verify(rawToken, jwtSecret);
  const user = await User.findById(payload.sub).lean();
  if (!user || user.isActive === false) {
    throw new Error("User not found.");
  }
  if (
    resolveTokenVersion(user.tokenVersion) !==
    resolveTokenVersion(payload.tokenVersion)
  ) {
    throw new Error("Session expired. Please login again.");
  }

  const clientType =
    socket.handshake.auth?.clientType ||
    socket.handshake.headers?.["x-client-type"] ||
    socket.handshake.query?.clientType ||
    "unknown";

  const deviceInfo = socket.handshake.auth?.deviceInfo || {};
  console.log("Extracted deviceInfo from auth:", deviceInfo);
  const ipAddress = socket.handshake.headers?.["x-forwarded-for"] || socket.handshake.address || null;

  return {
    id: user._id.toString(),
    username: user.username,
    fullName: user.fullName,
    role: user.role,
    departmentId: user.departmentId ? user.departmentId.toString() : null,
    permissions: await getEffectivePermissionsForUser(user),
    clientType: normalizeClientType(clientType),
    deviceInfo,
    ipAddress,
  };
}

function emitMessageToRecipients(io, message) {
  const recipients = new Set(
    (message.deliveredTo || [])
      .map((entry) => entry.userId?.toString?.() || entry.userId)
      .filter(Boolean),
  );

  if (message.senderId) {
    io.to(`user:${message.senderId}`).emit("receive_message", message);
  }

  for (const userId of recipients) {
    io.to(`user:${userId}`).emit("receive_message", message);
    io.to(`user:${userId}`).emit("message_delivered", {
      conversationId: message.conversationId,
      messageId: message.id,
      userId,
    });
  }
}

async function emitConversationToUsers(io, conversationId, userIds = []) {
  const uniqueUserIds = [
    ...new Set((userIds || []).map(String).filter(Boolean)),
  ];
  await Promise.all(
    uniqueUserIds.map(async (userId) => {
      try {
        const conversation = await getConversationSnapshotForUserId(
          conversationId,
          userId,
        );
        if (conversation) {
          io.to(`user:${userId}`).emit("conversation_updated", conversation);
        }
      } catch (error) {
        logger.warn("chat.conversation_updated.emit_failed", {
          conversationId: String(conversationId),
          userId,
          errorName: error?.name,
          errorMessage: error?.message,
        });
      }
    }),
  );
}

async function emitUnreadCount(io, userId, conversationId) {
  const unreadMap = await getUnreadCountsForUser(userId);
  io.to(`user:${userId}`).emit("unread_count_updated", {
    conversationId,
    unreadCount: unreadMap[conversationId] || 0,
    unreadMap,
  });
}

function getTypingKey(conversationId, userId) {
  return `${conversationId}:${userId}`;
}

function setTyping(io, conversationId, userId) {
  const key = getTypingKey(conversationId, userId);
  typingState.set(key, Date.now());
  const existingTimer = typingTimeouts.get(key);
  if (existingTimer) {
    clearTimeout(existingTimer);
  }
  const timer = setTimeout(() => {
    typingState.delete(key);
    typingTimeouts.delete(key);
    io.to(getConversationRoom(conversationId)).emit("stop_typing", {
      conversationId,
      userId,
    });
  }, 3500);
  if (typeof timer.unref === "function") {
    timer.unref();
  }
  typingTimeouts.set(key, timer);
}

function clearTyping(conversationId, userId) {
  const key = getTypingKey(conversationId, userId);
  typingState.delete(key);
  const existingTimer = typingTimeouts.get(key);
  if (existingTimer) {
    clearTimeout(existingTimer);
  }
  typingTimeouts.delete(key);
}

function clearSocketTyping(socket, userId) {
  for (const room of socket.rooms || []) {
    if (typeof room !== "string" || !room.startsWith("conversation:")) {
      continue;
    }
    const conversationId = room.slice("conversation:".length);
    clearTyping(conversationId, userId);
    socket.to(room).emit("stop_typing", {
      conversationId,
      userId,
    });
  }
}

async function emitConversationToMembers(io, conversationId, members = null) {
  try {
    const conversation = await getConversationById(conversationId);
    if (!conversation) return;
    const memberIds = Array.isArray(members)
      ? members.map((m) => String(m?.userId || m?._id || m))
      : (conversation.members || []).map((m) => String(m?.userId || m?._id || m));
    await emitConversationToUsers(io, conversationId, memberIds);
  } catch (error) {
    logger.warn("chat.conversation_members.emit_failed", {
      conversationId: String(conversationId),
      errorMessage: error?.message,
    });
  }
}

function getConnectedSocketStats() {
  let totalSockets = 0;
  for (const set of userSockets.values()) {
    totalSockets += set.size;
  }
  return {
    connectedUsersLocal: userSockets.size,
    connectedSocketsLocal: totalSockets,
  };
}

async function initializeChatSocketServer(httpServer) {
  const socketCorsOrigin =
    corsOrigin === "*"
      ? true
      : Array.isArray(corsOrigin)
        ? corsOrigin
        : String(corsOrigin || "")
            .split(",")
            .map((entry) => entry.trim())
            .filter(Boolean);
  const io = new Server(httpServer, {
    // Base64 inline transfers (mobile -> desktop save/print) can exceed
    // the default Engine.IO limit (~1MB), which causes silent disconnect/ack timeouts.
    maxHttpBufferSize: SOCKET_MAX_PAYLOAD_BYTES,
    cors: {
      origin: socketCorsOrigin,
      credentials: true,
    },
  });

  // Attach Redis Adapter for cross-instance Socket.IO rooms/events when REDIS_URL is configured
  const pubSub = createRedisPubSubClients();
  if (pubSub && pubSub.pubClient && pubSub.subClient) {
    redisAdapterStatus.configured = true;
    try {
      // Connect both clients concurrently; do NOT swallow errors with .catch(() => {})!
      await Promise.all([
        pubSub.pubClient.connect(),
        pubSub.subClient.connect(),
      ]);
      io.adapter(createAdapter(pubSub.pubClient, pubSub.subClient));
      redisAdapterStatus.attached = true;
      redisAdapterStatus.error = null;
      logger.info("socketio.redis_adapter.attached", { instanceId });
    } catch (err) {
      redisAdapterStatus.attached = false;
      redisAdapterStatus.error = err?.message || "Adapter connection failed";
      logger.error("socketio.redis_adapter.attach_failed", {
        instanceId,
        errorMessage: err?.message,
      });
    }
  } else {
    redisAdapterStatus.configured = false;
    redisAdapterStatus.attached = false;
    redisAdapterStatus.error = null;
    logger.info("socketio.redis_adapter.disabled_single_node", { instanceId });
  }

  // Instance-scoped startup cleanup: ONLY clear sessions that belonged to THIS instanceId
  // from a previous process crash/restart, without touching users connected to other Backend nodes!
  (async () => {
    try {
      const prevSessions = await DeviceSession.find(
        { instanceId, isOnline: true },
        "userId"
      ).lean();
      if (prevSessions.length > 0) {
        await DeviceSession.updateMany(
          { instanceId, isOnline: true },
          { $set: { isOnline: false, presenceStatus: "offline", lastSeenAt: new Date() } }
        );
        const affectedUserIds = [
          ...new Set(prevSessions.map((s) => String(s.userId)).filter(Boolean)),
        ];
        const stillOnline = await DeviceSession.distinct("userId", {
          userId: { $in: affectedUserIds },
          isOnline: true,
        });
        const stillOnlineSet = new Set(stillOnline.map(String));
        const toOfflineIds = affectedUserIds.filter(
          (id) => !stillOnlineSet.has(id)
        );
        if (toOfflineIds.length > 0) {
          await User.updateMany(
            { _id: { $in: toOfflineIds } },
            {
              $set: {
                isOnline: false,
                presenceStatus: "offline",
                lastSeen: new Date(),
              },
            }
          );
        }
      }
      await refreshClusterClientTypeSets();
    } catch (_) {}
  })();

  const sweepInterval = setInterval(async () => {
    const localUserIds = [...userSockets.keys()];
    if (localUserIds.length > 0) {
      await DeviceSession.updateMany(
        { instanceId, userId: { $in: localUserIds }, isOnline: true },
        { $set: { lastSeenAt: new Date() } }
      ).catch(() => {});
    }
    await refreshClusterClientTypeSets();
    for (const userId of localUserIds) {
      publishAggregatedPresence(io, userId).catch(() => {});
    }
  }, 25000);
  if (typeof sweepInterval.unref === "function") {
    sweepInterval.unref();
  }

  const reconcileInterval = setInterval(async () => {
    for (const userId of [...userSockets.keys()]) {
      pruneUserSockets(io, userId);
    }
    await withDistributedLock(
      "socket:cluster_presence_reconcile",
      45_000,
      async () => {
        try {
          const staleCutoff = new Date(Date.now() - 3 * 60 * 1000);
          // Mark any DeviceSession across the cluster whose heartbeat is older than 3 minutes as offline
          await DeviceSession.updateMany(
            { isOnline: true, lastSeenAt: { $lt: staleCutoff } },
            { $set: { isOnline: false, presenceStatus: "offline" } }
          );

          // Any user with at least one active DeviceSession on ANY Backend instance is genuinely online
          const clusterOnlineUserIds = await DeviceSession.distinct("userId", {
            isOnline: true,
            lastSeenAt: { $gte: staleCutoff },
          });
          const activeUserIdStrings = [
            ...new Set([
              ...clusterOnlineUserIds.map(String),
              ...[...userSockets.keys()].map(String),
            ]),
          ];

          const staleFilter = activeUserIdStrings.length
            ? { isOnline: true, _id: { $nin: activeUserIdStrings } }
            : { isOnline: true };
          const staleUsers = await User.find(staleFilter, "_id").lean();
          if (!staleUsers.length) {
            return;
          }
          const staleIds = staleUsers.map((entry) => entry._id.toString());
          await User.updateMany(
            { _id: { $in: staleIds } },
            {
              $set: {
                isOnline: false,
                presenceStatus: "offline",
                lastSeen: new Date(),
              },
            }
          );
          for (const userId of staleIds) {
            emitPresence(io, userId, false, "offline", {
              lastSeen: new Date().toISOString(),
            });
          }
        } catch (error) {
          logger.warn("chat.presence.reconcile_failed", {
            errorName: error?.name,
            errorMessage: error?.message,
          });
        }
      }
    );
  }, 60000);
  if (typeof reconcileInterval.unref === "function") {
    reconcileInterval.unref();
  }

  io.use(async (socket, next) => {
    try {
      socket.user = await resolveSocketUser(socket);
      next();
    } catch (error) {
      next(error);
    }
  });

  io.on("connection", async (socket) => {
    const currentUser = socket.user;
    const normalizedClientType = currentUser.clientType || "unknown";
    socket.join(`user:${currentUser.id}`);
    socket.join(`user:${currentUser.id}:${normalizedClientType}`);
    socket.join("lobby");
    registerUserSocket(currentUser.id, socket.id);
    socketPresence.set(socket.id, "online");
    socketClientType.set(socket.id, normalizedClientType);
    if (normalizedClientType === "mobile") {
      remoteMobileOnlineUsers.add(currentUser.id);
    } else if (normalizedClientType === "desktop") {
      remoteDesktopOnlineUsers.add(currentUser.id);
    }

    try {
      const filter = {
        userId: currentUser.id,
        instanceId,
        ipAddress: currentUser.ipAddress,
        clientType: normalizedClientType,
      };
      const update = {
        $set: {
          socketId: socket.id,
          instanceId,
          isOnline: true,
          presenceStatus: "online",
          lastSeenAt: new Date(),
          deviceInfo: currentUser.deviceInfo || {},
        },
      };
      const session = await DeviceSession.findOneAndUpdate(filter, update, {
        new: true,
        upsert: true,
        setDefaultsOnInsert: true,
      });
      socket.deviceSessionId = session._id;
    } catch (e) {
      logger.warn("Failed to create or update DeviceSession", e);
    }

    try {
      await publishAggregatedPresence(io, currentUser.id, {
        lastActiveAt: new Date().toISOString(),
      });
      const pendingDeliveries = await markPendingDeliveriesForUser(currentUser);
      for (const entry of pendingDeliveries) {
        io.to(getConversationRoom(entry.conversationId)).emit(
          "message_delivered",
          entry,
        );
      }
    } catch (error) {
      socket.emit("socket_error", {
        message: error?.message || "Socket initialization failed.",
      });
    }
    socket.onAny(async (eventName) => {
      if (
        [
          "disconnect",
          "leave_conversation",
          "presence:get",
          "presence:activity",
        ].includes(eventName)
      ) {
        return;
      }
      try {
        await markActive(io, currentUser, socket.id);
      } catch (error) {
        logger.warn("chat.presence.touch_active_failed", {
          userId: currentUser?.id,
          errorName: error?.name,
          errorMessage: error?.message,
        });
      }
    });

    socket.on("join_conversation", async (payload = {}, ack) => {
      try {
        const conversation = await getConversationById(payload.conversationId);
        await assertConversationAccess(currentUser, conversation);
        socket.join(getConversationRoom(payload.conversationId));
        const deliveredMessageIds = await markConversationDelivered(
          currentUser,
          payload.conversationId,
        );
        if (deliveredMessageIds.length) {
          io.to(getConversationRoom(payload.conversationId)).emit(
            "message_delivered",
            {
              conversationId: payload.conversationId,
              userId: currentUser.id,
              messageIds: deliveredMessageIds,
            },
          );
        }
        socketAck(ack, {
          ok: true,
          success: true,
          data: {
            conversationId: payload.conversationId,
            deliveredMessageIds,
          },
        });
      } catch (error) {
        socketAck(ack, { ok: false, success: false, error: error.message });
      }
    });

    socket.on("leave_conversation", async (payload = {}, ack) => {
      socket.leave(getConversationRoom(payload.conversationId));
      clearTyping(payload.conversationId, currentUser.id);
      socket
        .to(getConversationRoom(payload.conversationId))
        .emit("stop_typing", {
          conversationId: payload.conversationId,
          userId: currentUser.id,
        });
      socketAck(ack, {
        ok: true,
        success: true,
        data: { conversationId: payload.conversationId },
      });
    });

    socket.on("send_message", async (payload = {}, ack) => {
      try {
        clearTyping(payload.conversationId, currentUser.id);
        socket
          .to(getConversationRoom(payload.conversationId))
          .emit("stop_typing", {
            conversationId: payload.conversationId,
            userId: currentUser.id,
          });
        const result = await createMessage(currentUser, payload, null);
        if (result.alreadyExists) {
          socketAck(ack, {
            ok: true,
            success: true,
            data: {
              message: result.message,
              conversation: result.conversation,
            },
          });
          return;
        }
        emitMessageToRecipients(io, result.message);
        const audienceIds = [
          ...new Set(
            (result.audienceUserIds || []).map((entry) => String(entry)),
          ),
        ];
        if (audienceIds.length > 0) {
          await emitConversationToUsers(
            io,
            result.message.conversationId,
            audienceIds,
          );
        }

        const deliveredUsers = [
          ...new Set(
            (result.message.deliveredTo || [])
              .map((entry) => entry.userId?.toString?.() || entry.userId)
              .filter(Boolean),
          ),
        ];
        await Promise.all(
          deliveredUsers.map((userId) =>
            emitUnreadCount(io, userId, result.message.conversationId),
          ),
        );

        sendChatPushNotifications({
          recipientUserIds: result.recipientUserIds || [],
          conversation: result.conversation,
          message: result.message,
          senderName:
            currentUser.fullName || currentUser.username || "New message",
          shouldNotifyUser: (userId) =>
            !getUserDeliveryContext(io, userId).hasMobile,
        }).catch((error) => {
          logger.error("chat.push.send_failed", {
            conversationId: String(result.message.conversationId),
            messageId: String(result.message.id),
            errorName: error?.name,
            errorMessage: error?.message,
          });
        });

        socketAck(ack, {
          ok: true,
          success: true,
          data: { message: result.message, conversation: result.conversation },
        });
      } catch (error) {
        socketAck(ack, { ok: false, success: false, error: error.message });
      }
    });

    socket.on("typing", async (payload = {}, ack) => {
      try {
        const conversation = await getConversationById(payload.conversationId);
        await assertConversationAccess(currentUser, conversation);
        setTyping(io, payload.conversationId, currentUser.id);
        socket.to(getConversationRoom(payload.conversationId)).emit("typing", {
          conversationId: payload.conversationId,
          userId: currentUser.id,
          fullName: currentUser.fullName,
        });
        socketAck(ack, { ok: true, success: true });
      } catch (error) {
        socketAck(ack, { ok: false, success: false, error: error.message });
      }
    });

    socket.on("stop_typing", async (payload = {}, ack) => {
      clearTyping(payload.conversationId, currentUser.id);
      socket
        .to(getConversationRoom(payload.conversationId))
        .emit("stop_typing", {
          conversationId: payload.conversationId,
          userId: currentUser.id,
        });
      socketAck(ack, { ok: true, success: true });
    });

    socket.on("message_seen", async (payload = {}, ack) => {
      try {
        const messageIds = await markConversationSeen(
          currentUser,
          payload.conversationId,
        );
        io.to(getConversationRoom(payload.conversationId)).emit(
          "message_seen",
          {
            conversationId: payload.conversationId,
            userId: currentUser.id,
            messageIds,
          },
        );
        await emitUnreadCount(io, currentUser.id, payload.conversationId);
        socketAck(ack, {
          ok: true,
          success: true,
          data: { messageIds },
        });
      } catch (error) {
        socketAck(ack, { ok: false, success: false, error: error.message });
      }
    });

    socket.on("presence:get", async (payload = {}, ack) => {
      try {
        const presence = await getUserPresence(currentUser, payload.userId);
        socketAck(ack, { ok: true, success: true, data: { presence } });
      } catch (error) {
        socketAck(ack, { ok: false, success: false, error: error.message });
      }
    });

    socket.on("presence:activity", async (payload = {}, ack) => {
      const requestedStatus =
        payload.status === "idle"
          ? "idle"
          : payload.status === "meeting"
            ? "meeting"
            : payload.status === "lunch"
              ? "lunch"
              : payload.status === "offline"
                ? "offline"
                : "online";

      const isOnline = requestedStatus !== "offline";
      socketPresence.set(socket.id, requestedStatus);

      if (socket.deviceSessionId) {
        try {
          await DeviceSession.findByIdAndUpdate(socket.deviceSessionId, {
            isOnline,
            presenceStatus: requestedStatus,
            lastSeenAt: new Date(),
          });
        } catch (e) {
          logger.warn("Failed to update DeviceSession on presence:activity", e);
        }
      }

      if (requestedStatus === "offline") {
        await publishAggregatedPresence(io, currentUser.id, {
          lastSeen: new Date().toISOString(),
        });
      } else {
        await publishAggregatedPresence(io, currentUser.id, {
          lastActiveAt: new Date().toISOString(),
        });
      }

      socketAck(ack, {
        ok: true,
        success: true,
        data: { status: requestedStatus },
      });
    });

    socket.on("printers:update", (payload = {}, ack) => {
      if (socketClientType.get(socket.id) !== "desktop") {
        socketAck(ack, {
          ok: false,
          success: false,
          error: "Only desktop clients can publish printers.",
        });
        return;
      }

      const rawPrinters = Array.isArray(payload.printers)
        ? payload.printers
        : [];
      const printers = [
        ...new Set(rawPrinters.map((entry) => String(entry || "").trim())),
      ]
        .filter(Boolean)
        .slice(0, 50);
      const defaultPrinter =
        String(payload.defaultPrinter || "").trim() || null;
      const catalog = {
        printers,
        defaultPrinter,
        updatedAt: new Date().toISOString(),
      };
      printerCatalogByUser.set(currentUser.id, catalog);
      const redis = getRedisClient();
      if (redis && redis.status === "ready") {
        redis
          .set(`ismart:printers:${currentUser.id}`, JSON.stringify(catalog), "EX", 86400)
          .catch(() => {});
      }
      io.to(`user:${currentUser.id}`).emit("printers_catalog_updated", catalog);
      socketAck(ack, { ok: true, success: true, data: catalog });
    });

    socket.on("printers:get", async (payload = {}, ack) => {
      const desktopSocketIds = await resolveClusterDesktopTargets(io, currentUser.id);
      for (const desktopSocketId of desktopSocketIds) {
        io.to(desktopSocketId).emit("printers_catalog_refresh_requested", {
          requestedByUserId: currentUser.id,
          at: new Date().toISOString(),
        });
      }
      let catalog = printerCatalogByUser.get(currentUser.id);
      if (!catalog) {
        const redis = getRedisClient();
        if (redis && redis.status === "ready") {
          try {
            const raw = await redis.get(`ismart:printers:${currentUser.id}`);
            if (raw) {
              catalog = JSON.parse(raw);
              printerCatalogByUser.set(currentUser.id, catalog);
            }
          } catch (_) {}
        }
      }
      catalog = catalog || {
        printers: [],
        defaultPrinter: null,
        updatedAt: null,
      };
      socketAck(ack, {
        ok: true,
        success: true,
        data: {
          ...catalog,
          hasDesktop: desktopSocketIds.length > 0,
        },
      });
    });

    socket.on("desktop_storage:update", (payload = {}, ack) => {
      if (socketClientType.get(socket.id) !== "desktop") {
        socketAck(ack, {
          ok: false,
          success: false,
          error: "Only desktop clients can publish desktop storage settings.",
        });
        return;
      }

      const autoSaveAfterScan = payload.autoSaveAfterScan === true;
      const storage = {
        autoSaveAfterScan,
        updatedAt: new Date().toISOString(),
      };
      desktopStorageByUser.set(currentUser.id, storage);
      const redis = getRedisClient();
      if (redis && redis.status === "ready") {
        redis
          .set(`ismart:desktop_storage:${currentUser.id}`, JSON.stringify(storage), "EX", 86400)
          .catch(() => {});
      }
      io.to(`user:${currentUser.id}`).emit("desktop_storage_updated", storage);
      socketAck(ack, { ok: true, success: true, data: storage });
    });

    socket.on("desktop_storage:get", async (payload = {}, ack) => {
      let storage = desktopStorageByUser.get(currentUser.id);
      if (!storage) {
        const redis = getRedisClient();
        if (redis && redis.status === "ready") {
          try {
            const raw = await redis.get(`ismart:desktop_storage:${currentUser.id}`);
            if (raw) {
              storage = JSON.parse(raw);
              desktopStorageByUser.set(currentUser.id, storage);
            }
          } catch (_) {}
        }
      }
      storage = storage || {
        autoSaveAfterScan: false,
        updatedAt: null,
      };
      const desktopTargets = await resolveClusterDesktopTargets(io, currentUser.id);
      socketAck(ack, {
        ok: true,
        success: true,
        data: {
          ...storage,
          hasDesktop: desktopTargets.length > 0,
        },
      });
    });

    socket.on("print_request", async (payload = {}, ack) => {
      const allDesktopSocketIds = await resolveClusterDesktopTargets(io, currentUser.id);

      if (!allDesktopSocketIds.length) {
        socketAck(ack, {
          ok: false,
          success: false,
          error: "Desktop app is not connected for this account.",
        });
        return;
      }

      const inlineFileBase64 = String(payload.inlineFileBase64 || "").trim();
      const downloadUrl = String(payload.downloadUrl || "").trim();
      const requestAuthToken = String(payload.requestAuthToken || "").trim();
      if (!inlineFileBase64 && !downloadUrl) {
        socketAck(ack, {
          ok: false,
          success: false,
          error: "downloadUrl or inlineFileBase64 is required.",
        });
        return;
      }

      const fileName =
        String(payload.fileName || "")
          .trim()
          .slice(0, 255) || "print_file";
      const mimeType =
        String(payload.mimeType || "")
          .trim()
          .slice(0, 120) || null;
      const preferredPrinterName =
        String(payload.preferredPrinterName || "")
          .trim()
          .slice(0, 120) || null;
      const source = String(payload.source || "unknown")
        .trim()
        .slice(0, 40);

      // clientRequestId mapping and validation with atomic reservation
      const clientRequestId = String(payload.clientRequestId || "").trim();
      let jobId = null;
      let existingJob = null;
      let reservationToken = null;

      if (clientRequestId) {
        let reservation = await printJobStore.reservePrintRequest({
          userId: currentUser.id,
          clientRequestId,
          ttlMs: 15000,
        });

        // If in-flight by a concurrent node/request, briefly poll (up to 3x 100ms) to allow commit
        if (reservation.status === "in_flight") {
          for (let attempt = 0; attempt < 3; attempt++) {
            await new Promise((r) => setTimeout(r, 100));
            const committedJobId = await printJobStore.getJobIdForRequestAsync(
              clientRequestId,
              currentUser.id
            );
            if (committedJobId) {
              reservation = { status: "existing", jobId: committedJobId };
              break;
            }
          }
        }

        if (reservation.status === "failed") {
          socketAck(ack, {
            ok: false,
            success: false,
            retryable: true,
            error: reservation.error || "Cluster print reservation failed.",
          });
          return;
        }

        if (reservation.status === "existing") {
          jobId = reservation.jobId;
          existingJob = await printJobStore.getJobAsync(jobId);
        } else if (reservation.status === "reserved") {
          reservationToken = reservation.token;
        } else {
          logger.info("event=print_job_in_flight_ignored", {
            clientRequestId,
            userId: currentUser.id,
          });
          socketAck(ack, {
            ok: false,
            success: false,
            retryable: true,
            status: "in_flight",
            error: "Print request is currently in-flight on another cluster instance. Please retry shortly.",
          });
          return;
        }
      }

      // Backward compatibility fallback for clientRequestId
      const effectiveClientRequestId =
        clientRequestId ||
        `fallback-req-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

      if (existingJob) {
        // If job is already pending, forwarded, processing or submitted, do NOT reprint
        if (
          ["pending", "forwarded", "processing", "submitted"].includes(existingJob.state)
        ) {
          logger.info("event=print_job_duplicate_ignored", {
            jobId,
            clientRequestId: effectiveClientRequestId,
            reason: `already_${existingJob.state}`,
          });
          socketAck(ack, {
            ok: true,
            success: true,
            data: {
              jobId,
              status:
                existingJob.state === "submitted"
                  ? "completed"
                  : existingJob.state === "pending"
                    ? "forwarded"
                    : existingJob.state,
              executionState:
                existingJob.state === "pending" ? "forwarded" : existingJob.state,
            },
          });
          return;
        }

        // If it was failed, retry allows transitioning failed -> processing
        if (existingJob.state === "failed") {
          try {
            await printJobStore.validateAndTransitionAsync(jobId, "processing");
          } catch (err) {
            socketAck(ack, { ok: false, success: false, error: err.message });
            return;
          }
        }
      } else {
        // Create new job
        jobId = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
        const printJob = {
          jobId,
          clientRequestId: effectiveClientRequestId,
          requestedByUserId: currentUser.id,
          requestedByName:
            currentUser.fullName || currentUser.username || "User",
          fileName,
          mimeType,
          downloadUrl: downloadUrl || null,
          inlineFileBase64: inlineFileBase64 || null,
          requestAuthToken: requestAuthToken || null,
          preferredPrinterName,
          source,
          createdAt: new Date().toISOString(),
        };
        // Create new job and await initial persistence in Redis before transition
        try {
          await printJobStore.createJobAsync(jobId, printJob);
          await printJobStore.validateAndTransitionAsync(jobId, "forwarded");
        } catch (err) {
          await printJobStore.deleteJobAsync(jobId);
          if (reservationToken) {
            await printJobStore.releasePrintReservation({
              userId: currentUser.id,
              clientRequestId,
              token: reservationToken,
            });
          }
          socketAck(ack, { ok: false, success: false, error: err.message });
          return;
        }

        if (clientRequestId) {
          const committed = await printJobStore.commitPrintRequest({
            userId: currentUser.id,
            clientRequestId,
            token: reservationToken,
            jobId,
          });
          if (!committed) {
            await printJobStore.deleteJobAsync(jobId);
            socketAck(ack, {
              ok: false,
              success: false,
              retryable: true,
              error: "Print reservation expired or was invalidated. Please retry.",
            });
            return;
          }
        }
      }

      const printJob = (await printJobStore.getJobAsync(jobId))?.payload || printJobStore.getJob(jobId)?.payload;

      // Explicit target check
      let targetDesktopSocketId = null;
      const explicitTarget =
        payload.targetDesktopId ||
        payload.deviceId ||
        payload.targetDesktopSocketId;
      if (explicitTarget && allDesktopSocketIds.includes(explicitTarget)) {
        targetDesktopSocketId = explicitTarget;
      } else {
        targetDesktopSocketId =
          allDesktopSocketIds[allDesktopSocketIds.length - 1]; // last connected
      }

      logger.info("event=print_job_received", {
        jobId,
        clientRequestId: effectiveClientRequestId,
        socketInstanceId: socket.id,
        targetDesktopSocketId,
        availableDesktopSocketCount: allDesktopSocketIds.length,
      });

      printJobOwnerById.set(jobId, currentUser.id);
      printJobStore.setJobOwner("print", jobId, currentUser.id);
      io.to(targetDesktopSocketId).emit("print_job_requested", printJob);

      socketAck(ack, {
        ok: true,
        success: true,
        data: { jobId, status: "forwarded", executionState: "forwarded" },
      });
    });

    socket.on("print_job_status_update", async (payload = {}, ack) => {
      const jobId = String(payload.jobId || "").trim();
      const status = String(payload.status || "").trim();
      const printExecutionId = String(payload.printExecutionId || "").trim();
      const errorCode = String(payload.errorCode || "").trim();
      const errorMessage = String(payload.errorMessage || "").trim();

      const jobRecord = await printJobStore.getJobAsync(jobId);
      if (jobRecord) {
        try {
          await printJobStore.validateAndTransitionAsync(jobId, status);
        } catch (err) {
          logger.warn(
            "chat.socket.print_job_status_update.invalid_transition",
            {
              jobId,
              status,
              error: err.message,
            },
          );
          socketAck(ack, { ok: false, success: false, error: err.message });
          return;
        }
      }

      const ownerUserId =
        printJobOwnerById.get(jobId) ||
        (await printJobStore.resolveJobOwner("print", jobId, currentUser.id));
      io.to(`user:${ownerUserId}`).emit("print_job_status", {
        jobId,
        status: status === "submitted" ? "completed" : status,
        executionState: status,
        printExecutionId: printExecutionId || null,
        desktopSocketId: socket.id,
        updatedAt: new Date().toISOString(),
        errorCode: errorCode || null,
        errorMessage: errorMessage || null,
      });

      socketAck(ack, { ok: true, success: true });
    });

    socket.on("print_job_result", async (payload = {}, ack) => {
      const jobId = String(payload.jobId || "").trim();
      const success = payload.success === true;
      const status = success ? "submitted" : "failed";
      const printExecutionId = String(payload.printExecutionId || "").trim();
      const errorCode = String(payload.errorCode || "").trim();
      const errorMessage = String(
        payload.errorMessage || payload.message || "",
      ).trim();

      const jobRecord = await printJobStore.getJobAsync(jobId);
      if (jobRecord) {
        try {
          printJobStore.validateAndTransition(jobId, status);
        } catch (err) {
          logger.warn("chat.socket.print_job_result.invalid_transition", {
            jobId,
            status,
            error: err.message,
          });
          socketAck(ack, { ok: false, success: false, error: err.message });
          return;
        }
      }

      const ownerUserId =
        printJobOwnerById.get(jobId) ||
        (await printJobStore.resolveJobOwner("print", jobId, currentUser.id));
      if (jobId && success) {
        printJobOwnerById.delete(jobId);
        printJobStore.deleteJobOwner("print", jobId);
      }

      const resultPayload = {
        jobId: jobId || null,
        success,
        status: success ? "completed" : "failed", // Return completed externally for backward compatibility
        executionState: success ? "submitted" : "failed",
        printExecutionId: printExecutionId || null,
        desktopSocketId: socket.id,
        updatedAt: new Date().toISOString(),
        errorCode: errorCode || null,
        errorMessage: errorMessage || null,
      };

      io.to(`user:${ownerUserId}`).emit("print_job_status", resultPayload);
      socketAck(ack, { ok: true, success: true, data: resultPayload });
    });

    socket.on("file_save_request", async (payload = {}, ack) => {
      let targetUserId = String(payload.targetUserId || "").trim();
      if (!targetUserId) {
        targetUserId = currentUser.id;
      }
      if (targetUserId !== currentUser.id) {
        const targetUser = await User.findById(
          targetUserId,
          "branchCode role isActive",
        ).lean();
        const sameBranch =
          targetUser &&
          targetUser.isActive !== false &&
          String(targetUser.branchCode || "")
            .trim()
            .toLowerCase() ===
            String(currentUser.branchCode || "")
              .trim()
              .toLowerCase();
        if (!sameBranch && currentUser.role !== "admin") {
          socketAck(ack, {
            ok: false,
            success: false,
            error: "Target desktop is not available for this account.",
          });
          return;
        }
      }

      const desktopSocketIds = await resolveClusterDesktopTargets(io, targetUserId);
      if (!desktopSocketIds.length) {
        socketAck(ack, {
          ok: false,
          success: false,
          error: "Desktop app is not connected for the selected target.",
        });
        return;
      }

      const transferId = String(payload.transferId || "").trim();
      let inlineFileBase64 = String(payload.inlineFileBase64 || "").trim();
      let downloadUrl = String(payload.downloadUrl || "").trim();
      let fileName =
        String(payload.fileName || "")
          .trim()
          .slice(0, 255) || "file";
      let mimeType =
        String(payload.mimeType || "")
          .trim()
          .slice(0, 120) || null;
      let fileSize = Number(payload.fileSize || 0);
      let transferMeta = null;

      if (transferId) {
        try {
          transferMeta = await getChatTransferForUser(currentUser, transferId);
          downloadUrl = `/api/chat/transfers/${transferMeta.id}/download`;
          fileName = transferMeta.fileName || fileName;
          mimeType = transferMeta.mimeType || mimeType;
          fileSize = Number(transferMeta.fileSize || fileSize || 0);
        } catch (error) {
          socketAck(ack, {
            ok: false,
            success: false,
            error: error.message || "Transfer not found.",
          });
          return;
        }
      }

      if (!inlineFileBase64 && transferMeta) {
        const inlinePayload = await buildInlineTransferPayload(
          transferMeta,
          currentUser.role,
        );
        if (inlinePayload) {
          inlineFileBase64 = inlinePayload;
          downloadUrl = "";
        }
      }

      if (!inlineFileBase64 && !downloadUrl && !transferId) {
        socketAck(ack, {
          ok: false,
          success: false,
          error: "transferId, downloadUrl or inlineFileBase64 is required.",
        });
        return;
      }

      const source = String(payload.source || "unknown")
        .trim()
        .slice(0, 40);
      if (inlineFileBase64) {
        const inlineBytes = Buffer.byteLength(inlineFileBase64, "base64");
        const allowedBytes = maxTransferBytesForRole(currentUser.role);
        if (inlineBytes > allowedBytes) {
          socketAck(ack, {
            ok: false,
            success: false,
            error:
              currentUser.role === "admin"
                ? "حجم الملف يتجاوز 200 ميجا."
                : "حجم الملف يتجاوز 30 ميجا لحسابك.",
          });
          return;
        }
      }
      const jobId = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

      const saveJob = {
        jobId,
        requestedByUserId: currentUser.id,
        targetUserId,
        requestedByName: currentUser.fullName || currentUser.username || "User",
        fileName,
        mimeType,
        fileSize,
        transferId: transferMeta?.id || transferId || null,
        downloadUrl: downloadUrl || null,
        inlineFileBase64: inlineFileBase64 || null,
        source,
        createdAt: new Date().toISOString(),
      };

      saveJobOwnerById.set(jobId, currentUser.id);
      printJobStore.setJobOwner("save", jobId, currentUser.id);
      for (const desktopSocketId of desktopSocketIds) {
        io.to(desktopSocketId).emit("file_save_requested", saveJob);
      }

      socketAck(ack, {
        ok: true,
        success: true,
        data: { jobId, forwardedTo: desktopSocketIds.length },
      });
    });

    socket.on("file_receive_request", async (payload = {}, ack) => {
      const mobileSocketIds = await resolveClusterMobileTargets(io, currentUser.id);
      if (!mobileSocketIds.length) {
        socketAck(ack, {
          ok: false,
          success: false,
          error: "Mobile app is not connected for this account.",
        });
        return;
      }

      const transferId = String(payload.transferId || "").trim();
      const inlineFileBase64 = String(payload.inlineFileBase64 || "").trim();
      let downloadUrl = String(payload.downloadUrl || "").trim();
      let fileName =
        String(payload.fileName || "")
          .trim()
          .slice(0, 255) || "file";
      let mimeType =
        String(payload.mimeType || "")
          .trim()
          .slice(0, 120) || null;
      let fileSize = Number(payload.fileSize || 0);
      let transferMeta = null;

      if (transferId) {
        try {
          transferMeta = await getChatTransferForUser(currentUser, transferId);
          downloadUrl = `/api/chat/transfers/${transferMeta.id}/download`;
          fileName = transferMeta.fileName || fileName;
          mimeType = transferMeta.mimeType || mimeType;
          fileSize = Number(transferMeta.fileSize || fileSize || 0);
        } catch (error) {
          socketAck(ack, {
            ok: false,
            success: false,
            error: error.message || "Transfer not found.",
          });
          return;
        }
      }

      if (!inlineFileBase64 && !downloadUrl && !transferId) {
        socketAck(ack, {
          ok: false,
          success: false,
          error: "transferId, downloadUrl or inlineFileBase64 is required.",
        });
        return;
      }

      const source = String(payload.source || "unknown")
        .trim()
        .slice(0, 40);
      if (inlineFileBase64) {
        const inlineBytes = Buffer.byteLength(inlineFileBase64, "base64");
        const allowedBytes = maxTransferBytesForRole(currentUser.role);
        if (inlineBytes > allowedBytes) {
          socketAck(ack, {
            ok: false,
            success: false,
            error:
              currentUser.role === "admin"
                ? "حجم الملف يتجاوز 200 ميجا."
                : "حجم الملف يتجاوز 30 ميجا لحسابك.",
          });
          return;
        }
      }
      const jobId = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

      const receiveJob = {
        jobId,
        requestedByUserId: currentUser.id,
        requestedByName: currentUser.fullName || currentUser.username || "User",
        fileName,
        mimeType,
        fileSize,
        transferId: transferMeta?.id || transferId || null,
        downloadUrl: downloadUrl || null,
        inlineFileBase64: inlineFileBase64 || null,
        source,
        createdAt: new Date().toISOString(),
      };

      receiveJobOwnerById.set(jobId, currentUser.id);
      printJobStore.setJobOwner("receive", jobId, currentUser.id);
      for (const mobileSocketId of mobileSocketIds) {
        io.to(mobileSocketId).emit("file_receive_requested", receiveJob);
      }

      socketAck(ack, {
        ok: true,
        success: true,
        data: { jobId, forwardedTo: mobileSocketIds.length },
      });
    });

    socket.on("file_save_progress", async (payload = {}, ack) => {
      const jobId = String(payload.jobId || "").trim();
      const ownerUserId =
        saveJobOwnerById.get(jobId) ||
        (await printJobStore.resolveJobOwner("save", jobId, currentUser.id));
      const resultPayload = {
        jobId: jobId || null,
        stage: String(payload.stage || "unknown").trim() || "unknown",
        progress: Number(payload.progress || 0),
        message: String(payload.message || "").trim() || null,
        savedPath: String(payload.savedPath || "").trim() || null,
        byClientType: socketClientType.get(socket.id) || "unknown",
        at: new Date().toISOString(),
      };
      io.to(`user:${ownerUserId}`).emit("file_save_progress", resultPayload);
      socketAck(ack, { ok: true, success: true, data: resultPayload });
    });

    socket.on("file_receive_progress", async (payload = {}, ack) => {
      const jobId = String(payload.jobId || "").trim();
      const ownerUserId =
        receiveJobOwnerById.get(jobId) ||
        (await printJobStore.resolveJobOwner("receive", jobId, currentUser.id));
      const resultPayload = {
        jobId: jobId || null,
        stage: String(payload.stage || "unknown").trim() || "unknown",
        progress: Number(payload.progress || 0),
        message: String(payload.message || "").trim() || null,
        savedPath: String(payload.savedPath || "").trim() || null,
        byClientType: socketClientType.get(socket.id) || "unknown",
        at: new Date().toISOString(),
      };
      io.to(`user:${ownerUserId}`).emit("file_receive_progress", resultPayload);
      socketAck(ack, { ok: true, success: true, data: resultPayload });
    });

    socket.on("file_save_result", async (payload = {}, ack) => {
      const jobId = String(payload.jobId || "").trim();
      const ownerUserId =
        saveJobOwnerById.get(jobId) ||
        (await printJobStore.resolveJobOwner("save", jobId, currentUser.id));
      if (jobId) {
        saveJobOwnerById.delete(jobId);
        printJobStore.deleteJobOwner("save", jobId);
      }
      const resultPayload = {
        jobId: jobId || null,
        success: payload.success === true,
        message:
          String(payload.message || "").trim() ||
          (payload.success === true ? "File saved." : "File save failed."),
        savedPath: String(payload.savedPath || "").trim() || null,
        byClientType: socketClientType.get(socket.id) || "unknown",
        at: new Date().toISOString(),
      };
      io.to(`user:${ownerUserId}`).emit("file_save_status", resultPayload);
      socketAck(ack, { ok: true, success: true, data: resultPayload });
    });

    socket.on("file_receive_result", async (payload = {}, ack) => {
      const jobId = String(payload.jobId || "").trim();
      const ownerUserId =
        receiveJobOwnerById.get(jobId) ||
        (await printJobStore.resolveJobOwner("receive", jobId, currentUser.id));
      if (jobId) {
        receiveJobOwnerById.delete(jobId);
        printJobStore.deleteJobOwner("receive", jobId);
      }
      const resultPayload = {
        jobId: jobId || null,
        success: payload.success === true,
        message:
          String(payload.message || "").trim() ||
          (payload.success === true
            ? "File saved on mobile."
            : "Mobile save failed."),
        savedPath: String(payload.savedPath || "").trim() || null,
        byClientType: socketClientType.get(socket.id) || "unknown",
        at: new Date().toISOString(),
      };
      io.to(`user:${ownerUserId}`).emit("file_receive_status", resultPayload);
      socketAck(ack, { ok: true, success: true, data: resultPayload });
    });

    socket.on("disconnecting", () => {
      clearSocketTyping(socket, currentUser.id);
    });

    socket.on("report_client_error", async (payload = {}, ack) => {
      try {
        const ClientError = require("../../models/client-error.model");
        const err = new ClientError({
          userId: currentUser.id,
          sessionId: socket.deviceSessionId,
          clientType: currentUser.clientType || "unknown",
          source: String(payload.source || "app").slice(0, 100),
          errorMessage: String(payload.errorMessage || "Unknown error").slice(0, 5000),
          errorContext: payload.errorContext || {},
          stackTrace: payload.stackTrace ? String(payload.stackTrace).slice(0, 15000) : null,
        });
        await err.save();
        if (ack) socketAck(ack, { ok: true, success: true });
      } catch (e) {
        logger.warn("Failed to report client error", e);
        if (ack) socketAck(ack, { ok: false, success: false });
      }
    });

    socket.on("disconnect", async () => {
      socketPresence.delete(socket.id);
      unregisterUserSocket(currentUser.id, socket.id);
      socketClientType.delete(socket.id);
      printerCatalogByUser.delete(currentUser.id);
      desktopStorageByUser.delete(currentUser.id);
      
      if (socket.deviceSessionId) {
        let hasOtherSocketForSession = false;
        for (const [, s] of io.sockets.sockets.entries()) {
           if (s.id !== socket.id && s.deviceSessionId?.toString() === socket.deviceSessionId.toString()) {
              hasOtherSocketForSession = true;
              break;
           }
        }
        
        if (!hasOtherSocketForSession) {
          try {
            await DeviceSession.findByIdAndUpdate(socket.deviceSessionId, {
              isOnline: false,
              presenceStatus: "offline",
              lastSeenAt: new Date()
            });
          } catch (e) {
            logger.warn("Failed to update DeviceSession on disconnect", e);
          }
        }
      }

      await publishAggregatedPresence(io, currentUser.id, {
        lastSeen: new Date().toISOString(),
      });
    });
  });

  return io;
}

module.exports = {
  initializeChatSocketServer,
  getUserDeliveryContext,
  emitMessageToRecipients,
  emitConversationToUsers,
  emitConversationToMembers,
  getConnectedSocketStats,
  getAdapterStatus,
};

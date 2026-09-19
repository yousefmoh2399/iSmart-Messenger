const fs = require("fs");
const { Server } = require("socket.io");
const jwt = require("jsonwebtoken");
const User = require("../../models/user.model");
const DeviceSession = require("../../models/device-session.model");
const { jwtSecret, corsOrigin } = require("../../config/env");
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

function getMobileSocketIds(io, userId) {
  const sockets = pruneUserSockets(io, userId);
  return [...sockets].filter(
    (socketId) =>
      socketClientType.get(socketId) === "mobile" &&
      (socketPresence.get(socketId) || "online") !== "offline",
  );
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
  const sockets = pruneUserSockets(io, userId);
  let hasDesktop = false;
  let hasMobile = false;
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
  const nextSignature = `${aggregated.isOnline ? "1" : "0"}:${aggregated.status}`;
  const hasExtra = extra && Object.keys(extra).length > 0;
  const currentSignature = publishedPresenceState.get(userId);
  if (!hasExtra && currentSignature === nextSignature) {
    return;
  }
  await setUserPresence(userId, {
    isOnline: aggregated.isOnline,
    status: aggregated.status,
  });
  publishedPresenceState.set(userId, nextSignature);

  const payload = { ...extra };
  if (aggregated.isOnline) {
    payload.lastActiveAt = payload.lastActiveAt || new Date().toISOString();
  } else {
    payload.lastSeen = payload.lastSeen || new Date().toISOString();
  }

  emitPresence(io, userId, aggregated.isOnline, aggregated.status, payload);
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

function initializeChatSocketServer(httpServer) {
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

  // On server restart, clear stale online flags from previous process lifetime.
  User.updateMany(
    {
      $or: [
        { isOnline: true },
        { presenceStatus: { $in: ["online", "idle", "meeting", "lunch"] } },
      ],
    },
    {
      $set: {
        isOnline: false,
        presenceStatus: "offline",
        lastSeen: new Date(),
      },
    },
  ).catch(() => {});

  const sweepInterval = setInterval(() => {
    for (const userId of [...userSockets.keys()]) {
      publishAggregatedPresence(io, userId).catch(() => {});
    }
  }, 25000);
  if (typeof sweepInterval.unref === "function") {
    sweepInterval.unref();
  }

  const reconcileInterval = setInterval(async () => {
    try {
      for (const userId of [...userSockets.keys()]) {
        pruneUserSockets(io, userId);
      }
      const activeSocketUserIds = [...userSockets.keys()];
      const staleFilter = activeSocketUserIds.length
        ? { isOnline: true, _id: { $nin: activeSocketUserIds } }
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
        },
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
    socket.join(`user:${currentUser.id}`);
    socket.join("lobby");
    registerUserSocket(currentUser.id, socket.id);
    socketPresence.set(socket.id, "online");
    socketClientType.set(socket.id, currentUser.clientType || "unknown");
    
    try {
      const newSession = await DeviceSession.create({
        userId: currentUser.id,
        socketId: socket.id,
        ipAddress: currentUser.ipAddress,
        clientType: currentUser.clientType || "unknown",
        deviceInfo: currentUser.deviceInfo || {},
        isOnline: true,
      });
      socket.deviceSessionId = newSession._id;
    } catch (e) {
      logger.warn("Failed to create DeviceSession", e);
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

      if (requestedStatus === "offline") {
        socketPresence.set(socket.id, "offline");
        await publishAggregatedPresence(io, currentUser.id, {
          lastSeen: new Date().toISOString(),
        });
      } else {
        socketPresence.set(socket.id, requestedStatus);
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
      io.to(`user:${currentUser.id}`).emit("printers_catalog_updated", catalog);
      socketAck(ack, { ok: true, success: true, data: catalog });
    });

    socket.on("printers:get", (payload = {}, ack) => {
      const desktopSocketIds = getDesktopSocketIds(io, currentUser.id);
      for (const desktopSocketId of desktopSocketIds) {
        io.to(desktopSocketId).emit("printers_catalog_refresh_requested", {
          requestedByUserId: currentUser.id,
          at: new Date().toISOString(),
        });
      }
      const catalog = printerCatalogByUser.get(currentUser.id) || {
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
      io.to(`user:${currentUser.id}`).emit("desktop_storage_updated", storage);
      socketAck(ack, { ok: true, success: true, data: storage });
    });

    socket.on("desktop_storage:get", (payload = {}, ack) => {
      const storage = desktopStorageByUser.get(currentUser.id) || {
        autoSaveAfterScan: false,
        updatedAt: null,
      };
      socketAck(ack, {
        ok: true,
        success: true,
        data: {
          ...storage,
          hasDesktop: getDesktopSocketIds(io, currentUser.id).length > 0,
        },
      });
    });

    socket.on("print_request", (payload = {}, ack) => {
      const allDesktopSocketIds = [
        ...pruneUserSockets(io, currentUser.id),
      ].filter(
        (socketId) =>
          socketClientType.get(socketId) === "desktop" &&
          (socketPresence.get(socketId) || "online") !== "offline",
      );

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

      // clientRequestId mapping and validation
      const clientRequestId = String(payload.clientRequestId || "").trim();
      let jobId = null;
      let existingJob = null;

      if (clientRequestId) {
        jobId = printJobStore.getJobIdForRequest(clientRequestId);
        if (jobId) {
          existingJob = printJobStore.getJob(jobId);
        }
      }

      // Backward compatibility fallback for clientRequestId
      const effectiveClientRequestId =
        clientRequestId ||
        `fallback-req-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

      if (existingJob) {
        // If job is already forwarded, processing or submitted, do NOT reprint
        if (
          ["forwarded", "processing", "submitted"].includes(existingJob.state)
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
                  : existingJob.state,
              executionState: existingJob.state,
            },
          });
          return;
        }

        // If it was failed, retry allows transitioning failed -> processing
        if (existingJob.state === "failed") {
          try {
            printJobStore.validateAndTransition(jobId, "processing");
          } catch (err) {
            socketAck(ack, { ok: false, success: false, error: err.message });
            return;
          }
        }
      } else {
        // Create new job
        jobId = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
        if (clientRequestId) {
          printJobStore.registerRequest(clientRequestId, jobId);
        }
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
        printJobStore.createJob(jobId, printJob);
      }

      const printJob = printJobStore.getJob(jobId).payload;

      // Update state to forwarded
      try {
        printJobStore.validateAndTransition(jobId, "forwarded");
      } catch (err) {
        socketAck(ack, { ok: false, success: false, error: err.message });
        return;
      }

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
      io.to(targetDesktopSocketId).emit("print_job_requested", printJob);

      socketAck(ack, {
        ok: true,
        success: true,
        data: { jobId, status: "forwarded", executionState: "forwarded" },
      });
    });

    socket.on("print_job_status_update", (payload = {}, ack) => {
      const jobId = String(payload.jobId || "").trim();
      const status = String(payload.status || "").trim();
      const printExecutionId = String(payload.printExecutionId || "").trim();
      const errorCode = String(payload.errorCode || "").trim();
      const errorMessage = String(payload.errorMessage || "").trim();

      const jobRecord = printJobStore.getJob(jobId);
      if (jobRecord) {
        try {
          printJobStore.validateAndTransition(jobId, status);
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

      const ownerUserId = printJobOwnerById.get(jobId) || currentUser.id;
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

    socket.on("print_job_result", (payload = {}, ack) => {
      const jobId = String(payload.jobId || "").trim();
      const success = payload.success === true;
      const status = success ? "submitted" : "failed";
      const printExecutionId = String(payload.printExecutionId || "").trim();
      const errorCode = String(payload.errorCode || "").trim();
      const errorMessage = String(
        payload.errorMessage || payload.message || "",
      ).trim();

      const jobRecord = printJobStore.getJob(jobId);
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

      const ownerUserId = printJobOwnerById.get(jobId) || currentUser.id;
      if (jobId && success) {
        printJobOwnerById.delete(jobId);
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

      const desktopSocketIds = getDesktopSocketIds(io, targetUserId);
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
      const mobileSocketIds = getMobileSocketIds(io, currentUser.id);
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
      for (const mobileSocketId of mobileSocketIds) {
        io.to(mobileSocketId).emit("file_receive_requested", receiveJob);
      }

      socketAck(ack, {
        ok: true,
        success: true,
        data: { jobId, forwardedTo: mobileSocketIds.length },
      });
    });

    socket.on("file_save_progress", (payload = {}, ack) => {
      const jobId = String(payload.jobId || "").trim();
      const ownerUserId = saveJobOwnerById.get(jobId) || currentUser.id;
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

    socket.on("file_receive_progress", (payload = {}, ack) => {
      const jobId = String(payload.jobId || "").trim();
      const ownerUserId = receiveJobOwnerById.get(jobId) || currentUser.id;
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

    socket.on("file_save_result", (payload = {}, ack) => {
      const jobId = String(payload.jobId || "").trim();
      const ownerUserId = saveJobOwnerById.get(jobId) || currentUser.id;
      if (jobId) {
        saveJobOwnerById.delete(jobId);
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

    socket.on("file_receive_result", (payload = {}, ack) => {
      const jobId = String(payload.jobId || "").trim();
      const ownerUserId = receiveJobOwnerById.get(jobId) || currentUser.id;
      if (jobId) {
        receiveJobOwnerById.delete(jobId);
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
        DeviceSession.findByIdAndUpdate(socket.deviceSessionId, {
          isOnline: false,
          lastSeenAt: new Date()
        }).catch(e => logger.warn("Failed to update DeviceSession on disconnect", e));
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
};

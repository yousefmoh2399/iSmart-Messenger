const ApiError = require("../../utils/api-error");
const asyncHandler = require("../../utils/async-handler");
const logger = require("../../utils/logger");
const { sendUploadFile } = require("../../utils/send-upload-file");
const Conversation = require("../models/conversation.model");
const User = require("../../models/user.model");
const { listRoles } = require("../services/role.service");
const {
  getVisibleUsersForChat,
  listConversationsForUser,
  listManageableConversations,
  getConversationDetailsForUser,
  getConversationSnapshotForUserId,
  createConversation,
  updateConversation,
  updateConversationPreferences,
  setConversationPinnedMessage,
  clearConversationPinnedMessage,
  deleteConversation,
  listMessagesForConversation,
  createMessage,
  markConversationDelivered,
  updateMessage,
  toggleMessageReaction,
  toggleMessageFavorite,
  markConversationSeen,
  markMessageSeen,
  deleteMessage,
  joinConversation,
  leaveConversation,
  listConversationMembers,
  addConversationMembers,
  removeConversationMember,
  promoteConversationAdmin,
  demoteConversationAdmin,
  blockConversationMember,
  unblockConversationMember,
  searchMessages,
  listFavoriteMessages,
  getUserPresence,
  getMessageAttachment,
  requestAttachmentRehydrate,
  restoreAttachmentFromSender,
  votePollMessage,
  exportPollToExcel,
} = require("../services/chat.service");
const { listAuditLogs } = require("../services/audit.service");
const { listSystemErrors } = require("../services/system-error.service");
const {
  createChatTransfer,
  getChatTransferForUser,
} = require("../services/chat-transfer.service");
const { sendChatResponse } = require("../utils/chat-response");
const { getUserDeliveryContext } = require("../sockets/chat.socket");
const {
  sendChatPushNotifications,
  sendChatReactionPushNotifications,
} = require("../../services/push-notification.service");

const ADMIN_CHAT_ATTACHMENT_MAX_BYTES = 200 * 1024 * 1024;
const USER_CHAT_ATTACHMENT_MAX_BYTES = 20 * 1024 * 1024;
const USER_DIRECT_TRANSFER_MAX_BYTES = 30 * 1024 * 1024;

async function resolveConversationAudienceUserIds(conversationId) {
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
  })
    .select("type members departmentId")
    .lean();

  if (!conversation) {
    return [];
  }

  const userIds = new Set(
    (conversation.members || [])
      .map((entry) => entry?.toString?.() || entry)
      .filter(Boolean)
      .map(String)
  );

  if (conversation.type === "department" && conversation.departmentId) {
    const departmentUsers = await User.find(
      {
        departmentId: conversation.departmentId,
        isActive: true,
      },
      "_id"
    ).lean();
    for (const user of departmentUsers) {
      userIds.add(user._id.toString());
    }
  }

  return [...userIds];
}

function emitMessageToRecipients(io, message) {
  const deliveredUsers = new Set(
    (message.deliveredTo || [])
      .map((entry) => entry.userId?.toString?.() || entry.userId)
      .filter(Boolean)
  );

  if (message.senderId) {
    io.to(`user:${message.senderId}`).emit("receive_message", message);
  }

  for (const userId of deliveredUsers) {
    io.to(`user:${userId}`).emit("receive_message", message);
    io.to(`user:${userId}`).emit("message_delivered", {
      conversationId: message.conversationId,
      messageId: message.id,
      userId,
    });
  }
}

async function emitConversationToUsers(io, conversationId, userIds = []) {
  const uniqueUserIds = [...new Set((userIds || []).map(String).filter(Boolean))];
  await Promise.all(
    uniqueUserIds.map(async (userId) => {
      try {
        const conversation = await getConversationSnapshotForUserId(
          conversationId,
          userId
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
    })
  );
}

async function emitConversationToMembers(io, conversationId, extraUserIds = []) {
  const audienceUserIds = await resolveConversationAudienceUserIds(conversationId);
  emitConversationToUsers(io, conversationId, [
    ...audienceUserIds,
    ...(extraUserIds || []),
  ]);
}

const getChatDirectoryUsers = asyncHandler(async (req, res) => {
  const { users, pagination } = await getVisibleUsersForChat(req.user, req.query);
  sendChatResponse(res, {
    data: { users, pagination },
    legacy: { users, pagination },
  });
});

const postChatTransfer = asyncHandler(async (req, res) => {
  if (!req.file) {
    throw new ApiError(400, "Transfer file is required.");
  }

  const allowedBytes =
    req.user.role === "admin"
      ? ADMIN_CHAT_ATTACHMENT_MAX_BYTES
      : USER_DIRECT_TRANSFER_MAX_BYTES;

  if (Number(req.file.size || 0) > allowedBytes) {
    try {
      fs.unlinkSync(req.file.path);
    } catch (_) {}
    throw new ApiError(
      400,
      req.user.role === "admin"
        ? "حجم الملف يتجاوز 200 ميجا."
        : "حجم الملف يتجاوز 30 ميجا لحسابك."
    );
  }

  const transfer = createChatTransfer(req.user, req.file, req.body || {});
  sendChatResponse(res, {
    status: 201,
    data: { transfer },
    legacy: { transfer },
  });
});

const downloadChatTransfer = asyncHandler(async (req, res) => {
  const transfer = await getChatTransferForUser(req.user, req.params.id);
  if (transfer.fileSize > 0) {
    res.setHeader("Content-Length", String(transfer.fileSize));
  }
  await sendUploadFile(res, transfer.storedFilePath, {
    contentType: transfer.mimeType || "application/octet-stream",
    disposition: "attachment",
    fileName: transfer.fileName || "file",
    notFoundMessage: "Transfer file is no longer available.",
    logLabel: "chat-transfer-download",
  });
});

const getChatRoles = asyncHandler(async (req, res) => {
  const roles = await listRoles();
  sendChatResponse(res, {
    data: { roles },
    legacy: { roles },
  });
});

const getConversations = asyncHandler(async (req, res) => {
  const conversations = await listConversationsForUser(req.user);
  sendChatResponse(res, {
    data: { conversations },
    legacy: { conversations },
  });
});

const getManageableConversations = asyncHandler(async (req, res) => {
  const conversations = await listManageableConversations(req.user);
  sendChatResponse(res, {
    data: { conversations },
    legacy: { conversations },
  });
});

const createChatConversation = asyncHandler(async (req, res) => {
  const conversation = await createConversation(req.user, req.body);
  sendChatResponse(res, {
    status: 201,
    data: { conversation },
    legacy: { conversation },
  });
});

const updateChatConversation = asyncHandler(async (req, res) => {
  const conversation = await updateConversation(req.user, req.params.id, req.body);
  const io = req.app.get("io");
  if (io) {
    const payload = {
      conversationId: conversation.id,
      isActive: conversation.isActive,
    };
    io.to(`conversation:${conversation.id}`).emit("conversation_state_changed", payload);

    const audienceUserIds = await resolveConversationAudienceUserIds(conversation.id);
    for (const userId of audienceUserIds) {
      io.to(`user:${userId}`).emit("conversation_state_changed", payload);
    }
    emitConversationToMembers(io, conversation.id);
  }
  sendChatResponse(res, {
    data: { conversation },
    legacy: { conversation },
  });
});

const updateChatConversationPreferences = asyncHandler(async (req, res) => {
  const conversation = await updateConversationPreferences(
    req.user,
    req.params.id,
    req.body
  );
  const io = req.app.get("io");
  if (io) {
    io.to(`user:${req.user.id}`).emit("conversation_updated", conversation);
  }
  sendChatResponse(res, {
    data: { conversation },
    legacy: { conversation },
  });
});

const setGroupPinnedMessage = asyncHandler(async (req, res) => {
  const result = await setConversationPinnedMessage(
    req.user,
    req.params.id,
    req.body
  );
  const io = req.app.get("io");
  if (io) {
    emitConversationToMembers(io, result.conversation.id);
    if (result.systemMessage) {
      emitMessageToRecipients(io, result.systemMessage);
    }
  }
  sendChatResponse(res, {
    data: { conversation: result.conversation },
    legacy: { conversation: result.conversation },
  });
});

const clearGroupPinnedMessage = asyncHandler(async (req, res) => {
  const result = await clearConversationPinnedMessage(req.user, req.params.id);
  const io = req.app.get("io");
  if (io) {
    emitConversationToMembers(io, result.conversation.id);
    if (result.systemMessage) {
      emitMessageToRecipients(io, result.systemMessage);
    }
  }
  sendChatResponse(res, {
    data: { conversation: result.conversation },
    legacy: { conversation: result.conversation },
  });
});

const deleteChatConversation = asyncHandler(async (req, res) => {
  const scope = String(req.query.scope || "self").toLowerCase();
  const deleted = await deleteConversation(req.user, req.params.id, { scope });
  const io = req.app.get("io");
  if (io && deleted) {
    if (deleted.mode === "global_deleted") {
      const payload = { conversationId: deleted.conversationId };
      io.to(`conversation:${deleted.conversationId}`).emit("conversation_deleted", payload);
      for (const userId of deleted.memberIds || []) {
        io.to(`user:${userId}`).emit("conversation_deleted", payload);
      }
    } else if (deleted.mode === "self_cleared" && deleted.conversation) {
      io.to(`user:${req.user.id}`).emit("conversation_updated", deleted.conversation);
    }
  }
  sendChatResponse(res, {
    data: {
      deleted: deleted.mode === "global_deleted",
      cleared: deleted.mode === "self_cleared",
      conversation: deleted.conversation || null,
    },
    legacy: {
      deleted: deleted.mode === "global_deleted",
      cleared: deleted.mode === "self_cleared",
      conversation: deleted.conversation || null,
    },
  });
});

const getConversation = asyncHandler(async (req, res) => {
  const conversation = await getConversationDetailsForUser(req.user, req.params.id);
  sendChatResponse(res, {
    data: { conversation },
    legacy: { conversation },
  });
});

const joinChatConversation = asyncHandler(async (req, res) => {
  const conversation = await joinConversation(req.user, req.params.id);
  sendChatResponse(res, {
    data: { conversation },
    legacy: { conversation },
  });
});

const leaveChatConversation = asyncHandler(async (req, res) => {
  await leaveConversation(req.user, req.params.id);
  sendChatResponse(res, {
    data: { left: true },
    legacy: { left: true },
  });
});

const getConversationMembers = asyncHandler(async (req, res) => {
  const members = await listConversationMembers(req.user, req.params.id);
  sendChatResponse(res, {
    data: { members },
    legacy: { members },
  });
});

const addMembers = asyncHandler(async (req, res) => {
  const result = await addConversationMembers(
    req.user,
    req.params.id,
    req.body.userIds || []
  );
  const io = req.app.get("io");
  if (io) {
    emitConversationToMembers(
      io,
      result.conversation.id,
      result.addedUserIds
    );
    if (result.systemMessage) {
      emitMessageToRecipients(io, result.systemMessage);
    }
  }
  sendChatResponse(res, {
    data: { conversation: result.conversation },
    legacy: { conversation: result.conversation },
  });
});

const removeMember = asyncHandler(async (req, res) => {
  const result = await removeConversationMember(
    req.user,
    req.params.id,
    req.params.userId
  );
  const io = req.app.get("io");
  if (io) {
    emitConversationToMembers(
      io,
      result.conversation.id,
      result.affectedUserIds
    );
    if (result.systemMessage) {
      emitMessageToRecipients(io, result.systemMessage);
    }
  }
  sendChatResponse(res, {
    data: { conversation: result.conversation },
    legacy: { conversation: result.conversation },
  });
});

const promoteMemberAdmin = asyncHandler(async (req, res) => {
  const result = await promoteConversationAdmin(
    req.user,
    req.params.id,
    req.params.userId
  );
  const io = req.app.get("io");
  if (io) {
    emitConversationToMembers(
      io,
      result.conversation.id,
      result.affectedUserIds
    );
    if (result.systemMessage) {
      emitMessageToRecipients(io, result.systemMessage);
    }
  }
  sendChatResponse(res, {
    data: { conversation: result.conversation },
    legacy: { conversation: result.conversation },
  });
});

const demoteMemberAdmin = asyncHandler(async (req, res) => {
  const result = await demoteConversationAdmin(
    req.user,
    req.params.id,
    req.params.userId
  );
  const io = req.app.get("io");
  if (io) {
    emitConversationToMembers(
      io,
      result.conversation.id,
      result.affectedUserIds
    );
    if (result.systemMessage) {
      emitMessageToRecipients(io, result.systemMessage);
    }
  }
  sendChatResponse(res, {
    data: { conversation: result.conversation },
    legacy: { conversation: result.conversation },
  });
});

const blockMember = asyncHandler(async (req, res) => {
  const conversation = await blockConversationMember(
    req.user,
    req.params.id,
    req.params.userId
  );
  const io = req.app.get("io");
  if (io) {
    emitConversationToMembers(io, conversation.id);
  }
  sendChatResponse(res, {
    data: { conversation },
    legacy: { conversation },
  });
});

const unblockMember = asyncHandler(async (req, res) => {
  const conversation = await unblockConversationMember(
    req.user,
    req.params.id,
    req.params.userId
  );
  const io = req.app.get("io");
  if (io) {
    emitConversationToMembers(io, conversation.id);
  }
  sendChatResponse(res, {
    data: { conversation },
    legacy: { conversation },
  });
});

const getConversationMessages = asyncHandler(async (req, res) => {
  const result = await listMessagesForConversation(req.user, req.params.id, {
    cursor: req.query.cursor || null,
    limit: req.query.limit || 50,
  });
  sendChatResponse(res, {
    data: { messages: result.messages },
    meta: result.meta,
    legacy: { messages: result.messages, meta: result.meta },
  });
});

const postChatMessage = asyncHandler(async (req, res) => {
  if (req.file) {
    const maxBytes =
      req.user?.role === "admin"
        ? ADMIN_CHAT_ATTACHMENT_MAX_BYTES
        : USER_CHAT_ATTACHMENT_MAX_BYTES;
    if (Number(req.file.size || 0) > maxBytes) {
      try {
        fs.unlinkSync(req.file.path);
      } catch (_) {}
      throw new ApiError(
        400,
        req.user?.role === "admin"
          ? "حجم الملف يتجاوز الحد الأقصى 200 ميجا."
          : "حجم الملف يتجاوز الحد الأقصى 20 ميجا لحسابك."
      );
    }
  }
  if (typeof req.body.metadata === "string") {
    try {
      req.body.metadata = JSON.parse(req.body.metadata);
    } catch (_) {
      req.body.metadata = null;
    }
  }
  const result = await createMessage(req.user, req.body, req.file);
  const io = req.app.get("io");
  
  const isScheduledFuture = result.message.isScheduled && new Date(result.message.scheduledFor) > new Date();

  if (io && !isScheduledFuture) {
    emitMessageToRecipients(io, result.message);
    const audienceIds = [
      ...new Set((result.audienceUserIds || []).map((entry) => String(entry))),
    ];
    if (audienceIds.length > 0) {
      emitConversationToUsers(
        io,
        result.message.conversationId,
        audienceIds
      );
    } else {
      emitConversationToMembers(io, result.message.conversationId);
    }

    sendChatPushNotifications({
      recipientUserIds: result.recipientUserIds || [],
      conversation: result.conversation,
      message: result.message,
      senderName: req.user.fullName || req.user.username || "New message",
      shouldNotifyUser: (userId) => !getUserDeliveryContext(io, userId).hasMobile,
    }).catch((error) => {
      logger.error("chat.push.send_failed", {
        conversationId: String(result.message.conversationId),
        messageId: String(result.message.id),
        errorName: error?.name,
        errorMessage: error?.message,
      });
    });
  }
  sendChatResponse(res, {
    status: 201,
    data: result,
    legacy: result,
  });
});

const patchChatMessage = asyncHandler(async (req, res) => {
  const message = await updateMessage(req.user, req.params.id, req.body);
  const io = req.app.get("io");
  if (io) {
    io.to(`conversation:${message.conversationId}`).emit("message_updated", message);
    emitConversationToMembers(io, message.conversationId);
  }
  sendChatResponse(res, {
    data: { message },
    legacy: { message },
  });
});

const reactToChatMessage = asyncHandler(async (req, res) => {
  const toggleResult = await toggleMessageReaction(
    req.user,
    req.params.id,
    req.body.emoji
  );
  const message = toggleResult.message;
  const io = req.app.get("io");
  if (io) {
    io.to(`conversation:${message.conversationId}`).emit("message_updated", message);
    if (toggleResult.reactionAdded) {
      const senderId = String(message.senderId || "").trim();
      const reactorId = String(req.user.id);
      if (senderId && senderId !== reactorId) {
        const reactorName =
          req.user.fullName || req.user.username || "مستخدم";
        io.to(`user:${senderId}`).emit("message_reaction_added", {
          conversationId: message.conversationId,
          messageId: message.id,
          emoji: toggleResult.emoji,
          reactorName,
        });
        sendChatReactionPushNotifications({
          recipientUserIds: [senderId],
          conversationId: message.conversationId,
          messageId: message.id,
          emoji: toggleResult.emoji,
          reactorName,
          shouldNotifyUser: (userId) =>
            !getUserDeliveryContext(io, userId).hasMobile,
        }).catch((error) => {
          console.error("Failed to send chat reaction push notification:", error);
        });
      }
    }
  }
  sendChatResponse(res, {
    data: { message },
    legacy: { message },
  });
});

const toggleFavoriteChatMessage = asyncHandler(async (req, res) => {
  const message = await toggleMessageFavorite(req.user, req.params.id);
  const io = req.app.get("io");
  if (io) {
    io.to(`user:${req.user.id}`).emit("message_updated", message);
  }
  sendChatResponse(res, {
    data: { message },
    legacy: { message },
  });
});

const markSeen = asyncHandler(async (req, res) => {
  const messageIds = await markConversationSeen(req.user, req.params.id);
  const io = req.app.get("io");
  if (io) {
    io.to(`conversation:${req.params.id}`).emit("message_seen", {
      conversationId: req.params.id,
      userId: req.user.id,
      messageIds,
    });
    io.to(`user:${req.user.id}`).emit("unread_count_updated", {
      conversationId: req.params.id,
      unreadCount: 0,
    });
  }
  sendChatResponse(res, {
    data: { messageIds },
    legacy: { messageIds },
  });
});

const markSingleMessageSeen = asyncHandler(async (req, res) => {
  const message = await markMessageSeen(req.user, req.params.id);
  sendChatResponse(res, {
    data: { message },
    legacy: { message },
  });
});

const removeMessage = asyncHandler(async (req, res) => {
  const message = await deleteMessage(req.user, req.params.id);
  const io = req.app.get("io");
  if (io) {
    io.to(`conversation:${message.conversationId}`).emit("message_deleted", {
      messageId: message.id,
      conversationId: message.conversationId,
    });
    emitConversationToMembers(io, message.conversationId);
  }
  sendChatResponse(res, {
    data: { message },
    legacy: { message },
  });
});

const searchChatMessages = asyncHandler(async (req, res) => {
  const result = await searchMessages(req.user, {
    q: req.query.q,
    conversationId: req.query.conversationId || null,
    cursor: req.query.cursor || null,
    limit: req.query.limit || 30,
  });
  sendChatResponse(res, {
    data: { messages: result.messages },
    meta: result.meta,
    legacy: { messages: result.messages, meta: result.meta },
  });
});

const getFavoriteChatMessages = asyncHandler(async (req, res) => {
  const result = await listFavoriteMessages(req.user, {
    cursor: req.query.cursor || null,
    limit: req.query.limit || 30,
  });
  sendChatResponse(res, {
    data: { items: result.items },
    meta: result.meta,
    legacy: { items: result.items, meta: result.meta },
  });
});

const getPresence = asyncHandler(async (req, res) => {
  const presence = await getUserPresence(req.user, req.params.userId);
  sendChatResponse(res, {
    data: { presence },
    legacy: { presence },
  });
});

const getAttachmentFile = asyncHandler(async (req, res) => {
  const message = await getMessageAttachment(
    req.user,
    req.params.conversationId,
    req.params.storedName,
    { requireDownload: false }
  );
  await sendUploadFile(res, message.storedFilePath, {
    contentType:
      message.mimeType ||
      (message.messageType === "pdf"
        ? "application/pdf"
        : "application/octet-stream"),
    disposition: "inline",
    fileName: message.fileName || "attachment",
    notFoundMessage: "Attachment not found.",
    logLabel: "chat-attachment-inline",
  });
});

const downloadAttachment = asyncHandler(async (req, res) => {
  const message = await getMessageAttachment(
    req.user,
    req.params.conversationId,
    req.params.storedName,
    { requireDownload: true }
  );
  await sendUploadFile(res, message.storedFilePath, {
    contentType:
      message.mimeType ||
      (message.messageType === "pdf"
        ? "application/pdf"
        : "application/octet-stream"),
    disposition: "attachment",
    fileName: message.fileName || "attachment",
    notFoundMessage: "Attachment not found.",
    logLabel: "chat-attachment-download",
  });
});

const requestAttachmentRestore = asyncHandler(async (req, res) => {
  const result = await requestAttachmentRehydrate(req.user, req.params.id);
  const io = req.app.get("io");
  if (io && result.requested && result.targetUserId) {
    io.to(`user:${result.targetUserId}`).emit(
      "attachment_rehydrate_requested",
      result.payload
    );
  }
  sendChatResponse(res, {
    status: result.alreadyAvailable ? 200 : 202,
    data: {
      requested: result.requested,
      alreadyAvailable: result.alreadyAvailable,
    },
    legacy: {
      requested: result.requested,
      alreadyAvailable: result.alreadyAvailable,
    },
  });
});

const restoreAttachment = asyncHandler(async (req, res) => {
  const message = await restoreAttachmentFromSender(
    req.user,
    req.params.id,
    req.file
  );
  const io = req.app.get("io");
  if (io) {
    io.to(`conversation:${message.conversationId}`).emit(
      "message_updated",
      message
    );
  }
  sendChatResponse(res, {
    data: { message },
    legacy: { message },
  });
});

const getAuditLogs = asyncHandler(async (req, res) => {
  const logs = await listAuditLogs({
    actor: req.user,
    departmentId: req.query.departmentId || req.user.departmentId || null,
    limit: req.query.limit || 100,
  });
  sendChatResponse(res, {
    data: { logs },
    legacy: { logs },
  });
});

const getSystemErrors = asyncHandler(async (req, res) => {
  const logs = await listSystemErrors({
    actor: req.user,
    limit: req.query.limit || 100,
    statusCode: req.query.statusCode || null,
  });
  sendChatResponse(res, {
    data: { logs },
    legacy: { logs },
  });
});

const votePoll = asyncHandler(async (req, res) => {
  const result = await votePollMessage(
    req.user,
    req.params.id,
    req.body.optionIds
  );

  const io = req.app.get("io");
  if (io) {
    io.to(`conversation:${result.message.conversationId}`).emit("message_updated", result.message);
  }

  sendChatResponse(res, {
    message: "ØªÙ… ØªØ³Ø¬ÙŠÙ„ Ø§Ù„ØªØµÙˆÙŠØª.",
    data: { message: result.message },
    legacy: { message: result.message },
  });
});

const exportPoll = asyncHandler(async (req, res) => {
  const { buffer, filename } = await exportPollToExcel(req.user, req.params.id);

  res.setHeader(
    "Content-Type",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  );
  res.setHeader(
    "Content-Disposition",
    `attachment; filename="${encodeURIComponent(filename)}"`
  );

  res.send(buffer);
});

module.exports = {
  votePoll,
  exportPoll,
  getChatDirectoryUsers,
  getChatRoles,
  getConversations,
  getManageableConversations,
  createChatConversation,
  updateChatConversation,
  updateChatConversationPreferences,
  setGroupPinnedMessage,
  clearGroupPinnedMessage,
  deleteChatConversation,
  getConversation,
  joinChatConversation,
  leaveChatConversation,
  getConversationMembers,
  addMembers,
  removeMember,
  promoteMemberAdmin,
  demoteMemberAdmin,
  blockMember,
  unblockMember,
  getConversationMessages,
  postChatMessage,
  patchChatMessage,
  reactToChatMessage,
  toggleFavoriteChatMessage,
  markSeen,
  markSingleMessageSeen,
  removeMessage,
  searchChatMessages,
  getFavoriteChatMessages,
  getPresence,
  getAttachmentFile,
  downloadAttachment,
  requestAttachmentRestore,
  restoreAttachment,
  postChatTransfer,
  downloadChatTransfer,
  getAuditLogs,
  getSystemErrors,
};

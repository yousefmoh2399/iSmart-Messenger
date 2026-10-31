const Message = require("../chat/models/message.model");
const User = require("../models/user.model");
const {
  getConversationById,
  serializeConversation,
  serializeMessage,
} = require("../chat/services/chat.service");
const {
  incrementUnreadCounts,
} = require("../chat/services/chat-member-state.service");
const {
  emitMessageToRecipients,
  emitConversationToUsers,
  emitConversationToMembers,
} = require("../chat/services/socket.service");
const { sendChatPushNotifications } = require("../services/push-notification.service");
const { getUserDeliveryContext } = require("../chat/services/presence.service");
const ApiError = require("../utils/api-error");
const logger = require("../utils/logger");

/**
 * Process and dispatch a single scheduled message immediately
 */
async function processSingleScheduledMessage(msgData, io) {
  const now = new Date();

  // 1. Update message: mark isScheduled as false and update timestamp to now so it lands chronologically
  const message = await Message.findByIdAndUpdate(
    msgData._id,
    {
      isScheduled: false,
      scheduledFor: null,
      createdAt: now,
      updatedAt: now,
    },
    { new: true }
  ).populate(
    "senderId",
    "username fullName role jobTitle departmentId branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
  );

  if (!message) return null;

  const sender = message.senderId;
  const senderId = sender?._id
    ? String(sender._id)
    : (sender ? String(sender) : "");

  const conversation = await getConversationById(message.conversationId);
  if (!conversation) return null;

  // 2. Extract recipient IDs directly from conversation members (excluding sender)
  let recipientUserIds = (conversation.members || [])
    .map((entry) => String(entry?._id || entry))
    .filter((id) => id && id !== senderId);

  if (conversation.type === "broadcast") {
    const targets = message.metadata?.broadcastTargets;
    if (targets && Array.isArray(targets.userIds) && targets.userIds.length > 0) {
      recipientUserIds = targets.userIds
        .map(String)
        .filter((id) => id && id !== senderId);
    }
  }

  // 3. Mark live delivery receipts for currently connected recipients
  if (io) {
    const liveRecipientIds = recipientUserIds.filter((userId) => {
      const delivery = getUserDeliveryContext(io, userId);
      return delivery.hasMobile || delivery.hasDesktop || delivery.hasWeb;
    });

    if (liveRecipientIds.length > 0) {
      const existingDelivered = new Set(
        (message.deliveredTo || []).map((entry) => String(entry.userId || entry))
      );
      const newReceipts = liveRecipientIds
        .filter((id) => !existingDelivered.has(id))
        .map((userId) => ({ userId, at: now }));
      if (newReceipts.length > 0) {
        message.deliveredTo = [...(message.deliveredTo || []), ...newReceipts];
        await message.save();
      }
    }
  }

  // 4. Update conversation lastMessage & lastActivityAt
  conversation.lastMessage = {
    content: message.content || message.fileName || "",
    senderId,
    senderName: sender?.fullName || sender?.username || "User",
    messageType: message.messageType,
    createdAt: now,
  };
  conversation.lastActivityAt = now;
  await conversation.save();

  // 5. Increment unread count for recipients
  await incrementUnreadCounts(
    conversation._id,
    recipientUserIds,
    senderId
  );

  // 6. Serialize
  const serializedConversation = await serializeConversation(conversation, senderId);
  const serializedMessage = serializeMessage(message, sender);

  // 7. Emit to sockets
  if (io) {
    emitMessageToRecipients(io, serializedMessage, recipientUserIds);

    // Also notify active conversation room & sender that scheduled message has been dispatched
    io.to(`conversation:${message.conversationId}`).emit("scheduled_message_sent", {
      conversationId: String(message.conversationId),
      messageId: String(message._id),
      message: serializedMessage,
    });
    if (senderId) {
      io.to(`user:${senderId}`).emit("scheduled_message_sent", {
        conversationId: String(message.conversationId),
        messageId: String(message._id),
        message: serializedMessage,
      });
      io.to(`user:${senderId}`).emit("receive_message", serializedMessage);
    }

    let audienceIds = [];
    if (conversation.type === "broadcast") {
      const publisherIds = (conversation.broadcastPublisherIds || []).map(
        (entry) => String(entry?._id || entry)
      );
      audienceIds = Array.from(
        new Set([senderId, ...recipientUserIds, ...publisherIds])
      );
    } else {
      const memberIds = (conversation.members || []).map(
        (entry) => String(entry?._id || entry)
      );
      audienceIds = Array.from(
        new Set([senderId, ...recipientUserIds, ...memberIds])
      );
    }

    if (audienceIds.length > 0) {
      await emitConversationToUsers(io, message.conversationId, audienceIds);
    } else {
      await emitConversationToMembers(io, message.conversationId);
    }

    // 8. Push Notification
    sendChatPushNotifications({
      recipientUserIds: recipientUserIds,
      conversation: serializedConversation,
      message: serializedMessage,
      senderName: sender?.fullName || sender?.username || "New message",
      shouldNotifyUser: (userId) => !getUserDeliveryContext(io, userId).hasMobile,
    }).catch((error) => {
      logger.error("chat.push.send_failed_scheduled", {
        conversationId: String(message.conversationId),
        messageId: String(message._id),
        errorName: error?.name,
        errorMessage: error?.message,
      });
    });
  }

  return serializedMessage;
}

/**
 * Manually trigger sending a scheduled message now
 */
async function sendScheduledNow(currentUser, messageId, io) {
  const msg = await Message.findOne({
    _id: messageId,
    isScheduled: true,
    isDeleted: { $ne: true },
  }).lean();

  if (!msg) {
    throw new ApiError(404, "Scheduled message not found.");
  }

  const senderId = msg.senderId?._id ? String(msg.senderId._id) : String(msg.senderId);
  const isOwner = senderId === String(currentUser.id || currentUser._id);
  const isAdmin = currentUser.role === "admin";
  if (!isOwner && !isAdmin) {
    throw new ApiError(403, "Permission denied.");
  }

  const result = await processSingleScheduledMessage(msg, io);
  return result;
}

let isProcessing = false;

async function checkAndProcessScheduled(io) {
  if (isProcessing) return;
  isProcessing = true;
  try {
    const now = new Date();
    const scheduledMessages = await Message.find({
      isScheduled: true,
      scheduledFor: { $lte: now },
      isDeleted: { $ne: true },
    }).lean();

    if (scheduledMessages.length === 0) {
      return;
    }

    for (const msgData of scheduledMessages) {
      try {
        await processSingleScheduledMessage(msgData, io);
      } catch (msgErr) {
        logger.error("scheduler.process_message_failed", {
          messageId: String(msgData._id),
          error: msgErr?.message,
        });
      }
    }
  } catch (err) {
    logger.error("scheduler.failed", { error: err?.message });
  } finally {
    isProcessing = false;
  }
}

function startMessageScheduler(io) {
  // Check every 5 seconds for high responsiveness
  const intervalId = setInterval(() => {
    checkAndProcessScheduled(io);
  }, 5000);

  // Check immediately at startup
  checkAndProcessScheduled(io);

  logger.info("Message scheduler started (5s interval).");
  return intervalId;
}

module.exports = {
  startMessageScheduler,
  sendScheduledNow,
  processSingleScheduledMessage,
};

const cron = require("node-cron");
const Message = require("../chat/models/message.model");
const User = require("../models/user.model");
const { getConversationById, serializeConversation, serializeMessage } = require("../chat/services/chat.service");
const { emitMessageToRecipients, emitConversationToUsers, emitConversationToMembers } = require("../chat/services/socket.service");
const { sendChatPushNotifications } = require("../services/push-notification.service");
const { getUserDeliveryContext } = require("../chat/services/presence.service");
const { withDistributedLock } = require("../utils/distributed-lock");
const logger = require("../utils/logger");

function startMessageScheduler(io) {
  // Run every minute — protected by distributed lock + atomic MongoDB claim
  cron.schedule("* * * * *", async () => {
    await withDistributedLock("cron:message_scheduler", 50_000, async () => {
      try {
        const now = new Date();
        // Find messages scheduled for now or in the past that are still pending
        const scheduledMessages = await Message.find({
          isScheduled: true,
          scheduledFor: { $lte: now },
          isDeleted: { $ne: true },
        })
          .select("_id")
          .lean();

        if (scheduledMessages.length === 0) {
          return;
        }

        for (const msgData of scheduledMessages) {
          try {
            // Atomically claim the message only if isScheduled is still true
            const message = await Message.findOneAndUpdate(
              { _id: msgData._id, isScheduled: true },
              { $set: { isScheduled: false, scheduledFor: null } },
              { new: true }
            ).populate(
              "senderId",
              "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
            );

            if (!message) continue;

            const conversation = await getConversationById(message.conversationId);
            if (!conversation) continue;

            const recipientUserIds = (message.deliveredTo || []).map((r) =>
              String(r.userId || r)
            );
            const serializedConversation = await serializeConversation(
              conversation,
              message.senderId._id
            );
            const serializedMessage = serializeMessage(message, message.senderId);

            // Emit to sockets (propagates across all Backend instances via Redis adapter)
            if (io) {
              emitMessageToRecipients(io, serializedMessage);

              let audienceIds = [];
              if (conversation.type === "broadcast") {
                const publisherIds = (conversation.broadcastPublisherIds || []).map(
                  (entry) => String(entry)
                );
                audienceIds = Array.from(
                  new Set([
                    String(message.senderId._id),
                    ...recipientUserIds,
                    ...publisherIds,
                  ])
                );
              }

              if (audienceIds.length > 0) {
                await emitConversationToUsers(
                  io,
                  message.conversationId,
                  audienceIds
                );
              } else {
                await emitConversationToMembers(io, message.conversationId);
              }

              // Push Notification
              const sender = await User.findById(message.senderId._id).lean();
              sendChatPushNotifications({
                recipientUserIds,
                conversation: serializedConversation,
                message: serializedMessage,
                senderName:
                  sender?.fullName || sender?.username || "New message",
                shouldNotifyUser: (userId) =>
                  !getUserDeliveryContext(io, userId).hasMobile,
              }).catch((error) => {
                logger.error("chat.push.send_failed_scheduled", {
                  conversationId: String(message.conversationId),
                  messageId: String(message._id),
                  errorName: error?.name,
                  errorMessage: error?.message,
                });
              });
            }
          } catch (msgErr) {
            logger.error("scheduler.process_message_failed", {
              messageId: String(msgData._id),
              error: msgErr?.message,
            });
          }
        }
      } catch (err) {
        logger.error("scheduler.failed", { error: err?.message });
      }
    });
  });
  logger.info("Message scheduler started (HA lock enabled).");
}

module.exports = { startMessageScheduler };

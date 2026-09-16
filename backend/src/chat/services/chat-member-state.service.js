const ConversationMemberState = require("../models/conversation-member-state.model");

async function ensureConversationMemberStates(conversationId, memberIds) {
  if (!conversationId || !Array.isArray(memberIds) || memberIds.length === 0) {
    return;
  }

  const operations = memberIds.map((userId) => ({
    updateOne: {
      filter: { conversationId, userId },
      update: {
        $setOnInsert: {
          conversationId,
          userId,
          unreadCount: 0,
          joinedAt: new Date(),
        },
      },
      upsert: true,
    },
  }));

  if (operations.length > 0) {
    await ConversationMemberState.bulkWrite(operations, { ordered: false });
  }
}

async function removeConversationMemberState(conversationId, userId) {
  await ConversationMemberState.deleteOne({ conversationId, userId });
}

async function syncConversationMemberStates(conversationId, memberIds) {
  const normalized = [...new Set((memberIds || []).map(entry => {
    if (!entry) return "";
    if (typeof entry === "string") return entry;
    if (entry._id) return entry._id.toString();
    return entry.toString();
  }).filter(Boolean))];

  await ensureConversationMemberStates(conversationId, normalized);
  await ConversationMemberState.deleteMany({
    conversationId,
    userId: { $nin: normalized },
  });
}

async function incrementUnreadCounts(conversationId, recipientIds, exceptUserId = null) {
  const filtered = (recipientIds || []).filter(
    (userId) => String(userId) !== String(exceptUserId || "")
  );
  if (filtered.length === 0) {
    return;
  }

  await ConversationMemberState.updateMany(
    {
      conversationId,
      userId: { $in: filtered },
    },
    {
      $inc: { unreadCount: 1 },
    }
  );
}

async function markConversationRead({ conversationId, userId, lastReadMessageId = null }) {
  await ConversationMemberState.updateOne(
    { conversationId, userId },
    {
      $set: {
        unreadCount: 0,
        lastReadAt: new Date(),
        ...(lastReadMessageId ? { lastReadMessageId } : {}),
      },
      $setOnInsert: {
        joinedAt: new Date(),
      },
    },
    { upsert: true }
  );
}

async function getUnreadCountsForUser(userId) {
  const states = await ConversationMemberState.find({ userId })
    .select("conversationId unreadCount isMuted isArchived isPinned isFavorite")
    .lean();

  return Object.fromEntries(
    states.map((state) => [state.conversationId.toString(), state.unreadCount || 0])
  );
}

async function getConversationState(userId, conversationId) {
  return ConversationMemberState.findOne({ userId, conversationId }).lean();
}

async function clearConversationHistoryForUser(conversationId, userId, clearAt = new Date()) {
  await ConversationMemberState.updateOne(
    { conversationId, userId },
    {
      $set: {
        unreadCount: 0,
        lastReadAt: clearAt,
        clearHistoryAt: clearAt,
      },
      $setOnInsert: {
        conversationId,
        userId,
        joinedAt: new Date(),
      },
    },
    { upsert: true }
  );
}

async function updateConversationState(userId, conversationId, payload = {}) {
  const update = {};

  if (Object.prototype.hasOwnProperty.call(payload, "isMuted")) {
    update.isMuted = Boolean(payload.isMuted);
  }
  if (Object.prototype.hasOwnProperty.call(payload, "isArchived")) {
    update.isArchived = Boolean(payload.isArchived);
  }
  if (Object.prototype.hasOwnProperty.call(payload, "isPinned")) {
    update.isPinned = Boolean(payload.isPinned);
  }
  if (Object.prototype.hasOwnProperty.call(payload, "isFavorite")) {
    update.isFavorite = Boolean(payload.isFavorite);
  }
  if (Object.prototype.hasOwnProperty.call(payload, "clearHistoryAt")) {
    update.clearHistoryAt = payload.clearHistoryAt || null;
  }

  await ConversationMemberState.updateOne(
    { conversationId, userId },
    {
      $set: update,
      $setOnInsert: {
        conversationId,
        userId,
        unreadCount: 0,
        joinedAt: new Date(),
      },
    },
    { upsert: true }
  );

  return getConversationState(userId, conversationId);
}

module.exports = {
  ensureConversationMemberStates,
  removeConversationMemberState,
  syncConversationMemberStates,
  incrementUnreadCounts,
  markConversationRead,
  getUnreadCountsForUser,
  getConversationState,
  clearConversationHistoryForUser,
  updateConversationState,
};

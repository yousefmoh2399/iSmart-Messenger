const ConversationMemberState = require("../models/conversation-member-state.model");

function extractObjectId(entry) {
  if (!entry) return null;
  if (typeof entry === "string") {
    const trimmed = entry.trim();
    if (/^[a-fA-F0-9]{24}$/.test(trimmed)) return trimmed;
    const match = trimmed.match(/['"]?_?id['"]?\s*[:=]\s*(?:new\s+ObjectId\(['"])?([a-fA-F0-9]{24})['"]?\)?/i);
    if (match && match[1]) return match[1];
    return null;
  }
  if (entry._id) {
    const str = entry._id.toString();
    if (/^[a-fA-F0-9]{24}$/.test(str)) return str;
  }
  if (entry.id) {
    const str = entry.id.toString();
    if (/^[a-fA-F0-9]{24}$/.test(str)) return str;
  }
  if (typeof entry.toString === "function") {
    const str = entry.toString();
    if (/^[a-fA-F0-9]{24}$/.test(str)) return str;
  }
  return null;
}

async function ensureConversationMemberStates(conversationId, memberIds) {
  const cleanMemberIds = Array.isArray(memberIds)
    ? [...new Set(memberIds.map(extractObjectId).filter(Boolean))]
    : [];
  if (!conversationId || cleanMemberIds.length === 0) {
    return;
  }

  const operations = cleanMemberIds.map((userId) => ({
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
  const cleanUserId = extractObjectId(userId);
  if (!cleanUserId) return;
  await ConversationMemberState.deleteOne({ conversationId, userId: cleanUserId });
}

async function syncConversationMemberStates(conversationId, memberIds) {
  const normalized = [...new Set((memberIds || []).map(extractObjectId).filter(Boolean))];

  await ensureConversationMemberStates(conversationId, normalized);
  await ConversationMemberState.deleteMany({
    conversationId,
    userId: { $nin: normalized },
  });
}

async function incrementUnreadCounts(conversationId, recipientIds, exceptUserId = null) {
  const exceptId = exceptUserId ? extractObjectId(exceptUserId) : null;
  const filtered = (recipientIds || [])
    .map(extractObjectId)
    .filter((userId) => Boolean(userId) && userId !== exceptId);
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

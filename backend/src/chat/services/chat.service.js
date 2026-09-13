const path = require("path");
const fs = require("fs");
const crypto = require("crypto");
const Conversation = require("../models/conversation.model");
const Message = require("../models/message.model");
const Department = require("../models/department.model");
const ConversationMemberState = require("../models/conversation-member-state.model");
const User = require("../../models/user.model");
const ApiError = require("../../utils/api-error");
const { deleteFileIfExists } = require("../../utils/file.util");
const exceljs = require("exceljs");
const {
  ensureDirectory,
  fileExists,
  resolveStoredUploadPath,
  toRelativeUploadPath,
} = require("../../utils/storage-paths");
const { userHasPermission } = require("./role.service");
const { logAuditEvent } = require("./audit.service");
const {
  ensureConversationMemberStates,
  removeConversationMemberState,
  syncConversationMemberStates,
  incrementUnreadCounts,
  markConversationRead,
  getUnreadCountsForUser,
  getConversationState,
  clearConversationHistoryForUser,
  updateConversationState,
} = require("./chat-member-state.service");
const { classifyAttachment } = require("./chat-attachment.service");

function getObjectIdString(value) {
  if (!value) return null;
  if (typeof value === "string") return value;
  if (value._id) return value._id.toString();
  if (value.toString) return value.toString();
  return null;
}

function sanitizeMessageContent(value) {
  return String(value || "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 5000);
}

function sanitizeText(value, maxLength = 500) {
  return String(value || "").trim().slice(0, maxLength);
}

function sanitizePinnedMessageContent(value) {
  return String(value || "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 2000);
}

const allowedMessageTypes = new Set([
  "text",
  "file",
  "image",
  "pdf",
  "audio",
  "system",
  "poll",
  "gif",
]);

function sanitizeMessageType(value, fallback = "text") {
  const normalized = String(value || "")
    .trim()
    .toLowerCase();
  if (allowedMessageTypes.has(normalized)) {
    return normalized;
  }
  return fallback;
}

function isMongoIdLike(value) {
  return /^[a-fA-F0-9]{24}$/.test(String(value || "").trim());
}

function normalizeIdList(values) {
  return Array.from(
    new Set((values || []).filter((entry) => isMongoIdLike(entry)).map(String))
  );
}

function sanitizeAttachmentFileName(value, fallback) {
  const fallbackName = sanitizeText(fallback || "", 255);
  let fileName = sanitizeText(value || "", 255);
  if (!fileName) {
    return fallbackName || null;
  }

  fileName = fileName.replace(/[\\/:*?"<>|]/g, "_").trim();
  if (!fileName) {
    return fallbackName || null;
  }

  const fallbackExt = path.extname(fallbackName);
  const customExt = path.extname(fileName);
  if (!customExt && fallbackExt) {
    fileName = `${fileName}${fallbackExt}`;
  }

  return fileName.slice(0, 255);
}

function normalizeMessageMetadata(metadata) {
  if (!metadata || typeof metadata !== "object") {
    return null;
  }

  const nextMetadata = { ...metadata };
  const rawPolicy = nextMetadata.attachmentPolicy;
  if (rawPolicy && typeof rawPolicy === "object") {
    nextMetadata.attachmentPolicy = {
      allowDownload: rawPolicy.allowDownload !== false,
      allowForward: rawPolicy.allowForward !== false,
    };
  }
  return nextMetadata;
}

function normalizeAttachmentArchiveMetadata(metadata) {
  const source =
    metadata && typeof metadata === "object" ? metadata.attachmentArchive : null;
  if (!source || typeof source !== "object") {
    return null;
  }
  const sha256 = String(source.sha256 || "")
    .trim()
    .toLowerCase();
  const size = Number(source.fileSize || source.size || 0);
  if (!/^[a-f0-9]{64}$/.test(sha256) || !Number.isFinite(size) || size < 1) {
    return null;
  }
  return {
    sha256,
    fileSize: size,
    source: "sender_local_archive",
    version: 1,
  };
}

function calculateFileSha256(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash("sha256");
    const stream = fs.createReadStream(filePath);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolve(hash.digest("hex")));
    stream.on("error", reject);
  });
}

function normalizeBroadcastTargetDepartmentIds(rawDepartmentIds) {
  return normalizeIdList(rawDepartmentIds);
}

function escapeRegExp(value) {
  return String(value || "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function normalizeDepartmentCodeList(rawDepartmentCodes) {
  return Array.from(
    new Set(
      (rawDepartmentCodes || [])
        .map((entry) => String(entry || "").trim().toUpperCase())
        .filter(Boolean)
    )
  );
}

function normalizeDepartmentNameList(rawDepartmentNames) {
  return Array.from(
    new Set(
      (rawDepartmentNames || [])
        .map((entry) => String(entry || "").trim().toLowerCase())
        .filter(Boolean)
    )
  );
}

async function resolveBroadcastTargetDepartmentIds(rawTargets) {
  const targets =
    rawTargets && typeof rawTargets === "object" ? rawTargets : {};

  const idMatches = normalizeBroadcastTargetDepartmentIds(targets.departmentIds);
  const codeMatches = normalizeDepartmentCodeList(targets.departmentCodes);
  const nameMatches = normalizeDepartmentNameList(targets.departmentNames);

  if (codeMatches.length === 0 && nameMatches.length === 0) {
    return idMatches;
  }

  const query = { deletedAt: null, $or: [] };
  if (codeMatches.length > 0) {
    query.$or.push({ code: { $in: codeMatches } });
  }
  if (nameMatches.length > 0) {
    query.$or.push({
      name: {
        $in: nameMatches.map(
          (entry) => new RegExp(`^${escapeRegExp(entry)}$`, "i")
        ),
      },
    });
  }

  const departments = await Department.find(query, "_id").lean();
  const resolvedByCodeOrName = departments.map((entry) => entry._id.toString());
  return Array.from(new Set([...idMatches, ...resolvedByCodeOrName]));
}

function extractIdArray(values) {
  return (values || [])
    .map((entry) => {
      if (!entry) return null;
      if (typeof entry === "string") return entry;
      if (entry._id) return entry._id.toString();
      if (entry.id) return entry.id.toString();
      if (entry.userId) return entry.userId.toString();
      if (entry.toString) return entry.toString();
      return null;
    })
    .filter(Boolean)
    .map(String);
}

function canUserViewAllBroadcastMessages(currentUser, conversation) {
  const currentUserId = getObjectIdString(currentUser?.id || currentUser?._id);
  if (!currentUserId) {
    return false;
  }
  if (String(currentUser?.role || "").toLowerCase() === "admin") {
    return true;
  }
  if (getObjectIdString(conversation?.createdBy) === currentUserId) {
    return true;
  }

  const adminIds = new Set(extractIdArray(conversation?.admins));
  if (adminIds.has(currentUserId)) {
    return true;
  }

  const publisherIds = new Set(extractIdArray(conversation?.broadcastPublisherIds));
  return publisherIds.has(currentUserId);
}

function getBroadcastRecipientVisibilityQuery(currentUserId) {
  return {
    $or: [{ senderId: currentUserId }, { "deliveredTo.userId": currentUserId }],
  };
}

function buildLastMessagePayload(message) {
  if (!message) {
    return {
      content: "",
      senderId: null,
      senderName: "",
      messageType: null,
      createdAt: null,
    };
  }

  const senderId = getObjectIdString(message.senderId);
  const senderName =
    message.senderId && typeof message.senderId === "object"
      ? message.senderId.fullName || message.senderId.username || ""
      : "";

  return {
    content: message.content || message.fileName || "",
    senderId,
    senderName,
    messageType: message.messageType || null,
    createdAt: message.createdAt || null,
  };
}

function isAdminRole(role) {
  return String(role || "").trim().toLowerCase() === "admin";
}

function serializeUserLite(user) {
  return {
    id: user._id.toString(),
    username: user.username,
    fullName: user.fullName,
    role: user.role,
    departmentId: user.departmentId ? user.departmentId.toString() : null,
    departmentIds: Array.isArray(user.departmentIds)
      ? user.departmentIds.map((entry) => entry.toString())
      : user.departmentId
        ? [user.departmentId.toString()]
        : [],
    branchId: user.branchId ? user.branchId.toString() : null,
    branchCode: String(user.branchCode || "main").trim().toUpperCase(),
    isOnline: Boolean(user.isOnline),
    presenceStatus: user.presenceStatus || (user.isOnline ? "online" : "offline"),
    isActive: user.isActive !== false,
    avatarUrl: normalizeMediaUrl(user.avatarUrl),
    lastSeen: user.lastSeen || null,
    lastActiveAt: user.lastActiveAt || null,
  };
}

function normalizeMediaUrl(value) {
  if (!value) {
    return null;
  }
  try {
    const parsed = new URL(value);
    return `${parsed.pathname}${parsed.search || ""}${parsed.hash || ""}`;
  } catch (_) {
    return value;
  }
}

function serializeReceipt(entry) {
  return {
    userId: entry.userId.toString(),
    at: entry.at,
  };
}

async function serializeConversation(conversation, currentUserId) {
  const members = (conversation.members || []).map((member) =>
    member._id ? serializeUserLite(member) : { id: member.toString() }
  );
  const admins = (conversation.admins || []).map((admin) =>
    admin._id ? serializeUserLite(admin) : { id: admin.toString() }
  );

  const memberState = await ConversationMemberState.findOne({
    conversationId: conversation._id,
    userId: currentUserId,
  })
    .select("unreadCount isArchived isMuted isPinned isFavorite clearHistoryAt")
    .lean();

  const clearHistoryAt = memberState?.clearHistoryAt
    ? new Date(memberState.clearHistoryAt)
    : null;
  const lastMessageCreatedAt = conversation.lastMessage?.createdAt
    ? new Date(conversation.lastMessage.createdAt)
    : null;
  const shouldHideLastMessage =
    clearHistoryAt &&
    lastMessageCreatedAt &&
    lastMessageCreatedAt.getTime() <= clearHistoryAt.getTime();

  const normalizedLastMessage = shouldHideLastMessage
    ? {
        content: "",
        senderId: null,
        senderName: "",
        messageType: null,
        createdAt: null,
      }
    : (conversation.lastMessage || null);

  return {
    id: conversation._id.toString(),
    type: conversation.type,
    name: conversation.name,
    description: conversation.description || "",
    departmentId: conversation.departmentId
      ? conversation.departmentId._id
        ? conversation.departmentId._id.toString()
        : conversation.departmentId.toString()
      : null,
    createdBy: conversation.createdBy?.toString?.() || conversation.createdBy,
    members,
    admins,
    broadcastPublisherIds: (conversation.broadcastPublisherIds || []).map((entry) =>
      entry._id ? entry._id.toString() : entry.toString()
    ),
    blockedMemberIds: (conversation.blockedMembers || []).map((entry) =>
      entry._id ? entry._id.toString() : entry.toString()
    ),
    blockedMembers: (conversation.blockedMembers || []).map((entry) =>
      entry._id ? serializeUserLite(entry) : { id: entry.toString() }
    ),
    pinnedMessage: conversation.pinnedMessage
      ? {
          content: conversation.pinnedMessage.content || "",
          setBy: getObjectIdString(conversation.pinnedMessage.setBy),
          setByName: conversation.pinnedMessage.setByName || "",
          createdAt: conversation.pinnedMessage.createdAt || null,
          updatedAt: conversation.pinnedMessage.updatedAt || null,
        }
      : null,
    lastMessage: normalizedLastMessage,
    unreadCount: memberState?.unreadCount || 0,
    isArchived: memberState?.isArchived || conversation.isArchived || false,
    isMuted: memberState?.isMuted || false,
    isPinned: memberState?.isPinned || false,
    isFavorite: memberState?.isFavorite || false,
    isActive: conversation.isActive !== false,
    createdAt: conversation.createdAt,
    updatedAt: conversation.updatedAt,
    deletedAt: conversation.deletedAt || null,
  };
}

function serializeMessage(message, sender = null) {
  return {
    id: message._id.toString(),
    conversationId: message.conversationId.toString(),
    senderId: message.senderId.toString(),
    sender: sender ? serializeUserLite(sender) : null,
    content: message.content,
    messageType: message.messageType,
    fileUrl: message.fileUrl,
    fileName: message.fileName,
    fileSize: message.fileSize || null,
    mimeType: message.mimeType || null,
    replyToMessageId: message.replyToMessageId?.toString?.() || null,
    isDeleted: message.isDeleted === true,
    metadata: message.metadata || null,
    createdAt: message.createdAt,
    updatedAt: message.updatedAt,
    seenBy: (message.seenBy || []).map(serializeReceipt),
    deliveredTo: (message.deliveredTo || []).map(serializeReceipt),
  };
}

async function getOnlineActiveUserIds(userIds) {
  const uniqueIds = Array.from(new Set((userIds || []).filter(Boolean).map(String)));
  if (uniqueIds.length === 0) {
    return [];
  }

  const users = await User.find(
    {
      _id: { $in: uniqueIds },
      isActive: true,
      isOnline: true,
    },
    "_id"
  ).lean();

  return users.map((entry) => entry._id.toString());
}

async function buildDeliveryReceipts(userIds) {
  const onlineUserIds = await getOnlineActiveUserIds(userIds);
  return onlineUserIds.map((userId) => ({ userId, at: new Date() }));
}

async function createSystemConversationMessage(conversation, actor, payload) {
  const recipientIds = (conversation.members || [])
    .map((entry) => (entry._id ? entry._id.toString() : entry.toString()))
    .filter((userId) => userId !== actor.id);

  const message = await Message.create({
    conversationId: conversation._id,
    senderId: actor.id,
    content: sanitizeMessageContent(payload.content),
    messageType: "system",
    seenBy: [{ userId: actor.id, at: new Date() }],
    deliveredTo: await buildDeliveryReceipts(recipientIds),
    metadata: {
      ...(payload.metadata || {}),
      system: true,
    },
  });

  conversation.lastMessage = {
    content: message.content,
    senderId: actor.id,
    senderName: actor.fullName || actor.username,
    messageType: "system",
    createdAt: message.createdAt,
  };
  await conversation.save();
  await incrementUnreadCounts(conversation._id, recipientIds, actor.id);

  const populated = await Message.findById(message._id)
    .populate(
      "senderId",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .exec();

  return serializeMessage(populated, populated.senderId);
}

async function refreshConversationLastMessage(conversationId) {
  const latestMessage = await Message.findOne({
    conversationId,
    isDeleted: { $ne: true },
  })
    .sort({ createdAt: -1, _id: -1 })
    .populate(
      "senderId",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .exec();

  const nextLastMessage = latestMessage
    ? {
        content:
          latestMessage.content ||
          latestMessage.fileName ||
          (latestMessage.messageType === "system" ? "System" : ""),
        senderId: latestMessage.senderId?._id?.toString?.() ||
          latestMessage.senderId?.toString?.() ||
          null,
        senderName:
          latestMessage.senderId?.fullName ||
          latestMessage.senderId?.username ||
          "",
        messageType: latestMessage.messageType,
        createdAt: latestMessage.createdAt,
      }
    : {
        content: "",
        senderId: null,
        senderName: "",
        messageType: null,
        createdAt: null,
      };

  await Conversation.updateOne(
    { _id: conversationId },
    {
      $set: {
        lastMessage: nextLastMessage,
      },
    }
  );
}

function getConversationRoom(conversationId) {
  return `conversation:${conversationId}`;
}

function isDepartmentDefaultConversation(conversation) {
  if (conversation?.type !== "department") {
    return false;
  }

  const conversationId = getObjectIdString(conversation?._id || conversation?.id);
  const defaultConversationId = getObjectIdString(
    conversation?.departmentId?.defaultConversationId
  );
  if (conversationId && defaultConversationId && conversationId === defaultConversationId) {
    return true;
  }

  const name = String(conversation?.name || "").trim().toLowerCase();
  return (
    name.includes("department room") ||
    name.includes("غرفة القسم") ||
    name.includes("الغرفة الافتراضية")
  );
}

function isRestrictedDirectTarget(currentUser, targetUser) {
  if (!targetUser || targetUser.isActive === false) {
    return true;
  }

  if (currentUser.role !== "user") {
    return false;
  }

  return isAdminRole(targetUser.role);
}

async function getConversationById(conversationId) {
  return Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
  })
    .populate(
      "members",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .populate(
      "admins",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .populate(
      "blockedMembers",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .populate("departmentId", "name code defaultConversationId")
    .exec();
}

async function getVisibleUsersForChat(currentUser, options = {}) {
  const search = sanitizeText(options.search || options.q || "", 120);
  const shouldPaginate = options.page !== undefined || options.limit !== undefined;
  const page = Math.max(1, Math.min(Number(options.page || 1), 100000));
  const limit = Math.max(1, Math.min(Number(options.limit || 50), 100));
  const skip = (page - 1) * limit;
  const query = {
    isActive: true,
    _id: { $ne: currentUser.id },
  };
  if (currentUser.role === "user") {
    query.role = { $ne: "admin" };
  }

  if (search) {
    const regex = new RegExp(escapeRegExp(search), "i");
    query.$or = [{ username: regex }, { fullName: regex }, { branchCode: regex }];
  }
  if (options.departmentId) {
    const departmentMatch = [
      { departmentId: options.departmentId },
      { departmentIds: options.departmentId },
    ];
    if (query.$or) {
      query.$and = [{ $or: query.$or }, { $or: departmentMatch }];
      delete query.$or;
    } else {
      query.$or = departmentMatch;
    }
  }
  if (options.branchId) {
    query.branchId = options.branchId;
  }

  const usersQuery = User.find(query).sort({ fullName: 1, username: 1, _id: 1 });
  if (shouldPaginate) {
    usersQuery.skip(skip).limit(limit);
  }
  const [users, total] = await Promise.all([
    usersQuery.lean(),
    shouldPaginate ? User.countDocuments(query) : Promise.resolve(null),
  ]);
  const resolvedTotal = total ?? users.length;

  return {
    users: users.map(serializeUserLite),
    pagination: {
      page,
      limit: shouldPaginate ? limit : users.length,
      total: resolvedTotal,
      hasMore: shouldPaginate ? page * limit < resolvedTotal : false,
    },
  };
}

async function assertConversationAccess(currentUser, conversation) {
  if (!conversation || conversation.deletedAt) {
    throw new ApiError(404, "Conversation not found.");
  }

  const currentUserId = getObjectIdString(currentUser.id || currentUser._id);
  const memberIds = (conversation.members || []).map((entry) =>
    entry._id ? entry._id.toString() : entry.toString()
  );

  if (conversation.type === "department") {
    const conversationDepartmentId =
      conversation.departmentId?._id?.toString?.() ||
      conversation.departmentId?.toString?.() ||
      null;
    const currentUserDepartmentId = getObjectIdString(currentUser.departmentId);
    if (
      currentUserDepartmentId &&
      currentUserDepartmentId === conversationDepartmentId
    ) {
      return;
    }
    if (memberIds.includes(currentUserId)) {
      return;
    }
    throw new ApiError(403, "Conversation access denied.");
  }

  if (conversation.type === "broadcast") {
    if (
      memberIds.includes(currentUserId) ||
      canUserViewAllBroadcastMessages(currentUser, conversation)
    ) {
      return;
    }
    throw new ApiError(403, "Conversation access denied.");
  }

  if (conversation.type === "direct" && currentUser.role === "user") {
    const target = (conversation.members || []).find((entry) => {
      const entryId = entry._id ? entry._id.toString() : entry.toString();
      return entryId !== currentUserId;
    });
    if (isRestrictedDirectTarget(currentUser, target)) {
      throw new ApiError(403, "Conversation access denied.");
    }
  }

  if (!memberIds.includes(currentUserId)) {
    throw new ApiError(403, "Conversation access denied.");
  }
}

async function assertConversationManagementAccess(currentUser, conversation) {
  if (!conversation || conversation.deletedAt) {
    throw new ApiError(404, "Conversation not found.");
  }

  if (currentUser.role === "admin") {
    return;
  }

  if (conversation.type === "direct") {
    const memberIds = (conversation.members || []).map((entry) =>
      entry._id ? entry._id.toString() : entry.toString()
    );
    const currentUserId = getObjectIdString(currentUser.id || currentUser._id);
    if (currentUserId && memberIds.includes(currentUserId)) {
      return;
    }
  }

  const adminIds = (conversation.admins || []).map((entry) =>
    entry._id ? entry._id.toString() : entry.toString()
  );
  const currentUserId = getObjectIdString(currentUser.id || currentUser._id);
  if (currentUserId && adminIds.includes(currentUserId)) {
    return;
  }

  if (
    conversation.type === "department" &&
    getObjectIdString(currentUser.departmentId) &&
    getObjectIdString(conversation.departmentId) ===
      getObjectIdString(currentUser.departmentId)
  ) {
    const canModerateDepartment = await userHasPermission(
      currentUser,
      "canModerateDepartment"
    );
    if (canModerateDepartment) {
      return;
    }
  }

  throw new ApiError(403, "Conversation management denied.");
}

function assertGroupOwnerAccess(currentUser, conversation) {
  if (!conversation || conversation.deletedAt) {
    throw new ApiError(404, "Conversation not found.");
  }

  if (conversation.type !== "group") {
    throw new ApiError(400, "This action is available for group conversations only.");
  }

  const currentUserId = getObjectIdString(currentUser.id || currentUser._id);
  if (!currentUserId || conversation.createdBy?.toString() !== currentUserId) {
    throw new ApiError(403, "Only the group creator can manage members.");
  }
}

async function listConversationsForUser(currentUser) {
  const query = {
    deletedAt: null,
    $or: [{ members: currentUser.id }],
  };

  if (currentUser.departmentId) {
    query.$or.push({
      type: "department",
      departmentId: currentUser.departmentId,
    });
  }

  const conversations = await Conversation.find(query)
    .sort({ updatedAt: -1 })
    .populate(
      "members",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .populate(
      "admins",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .populate("departmentId", "name code defaultConversationId")
    .lean({ getters: true });

  const unreadByConversation = await getUnreadCountsForUser(currentUser.id);
  const currentUserId = getObjectIdString(currentUser.id || currentUser._id);
  const visible = [];

  for (const conversation of conversations) {
    try {
      await assertConversationAccess(currentUser, conversation);
      if (isDepartmentDefaultConversation(conversation)) {
        continue;
      }
      const serialized = await serializeConversation(conversation, currentUser.id);
      if (
        conversation.type === "broadcast" &&
        !canUserViewAllBroadcastMessages(currentUser, conversation)
      ) {
        const visibleLastMessage = await Message.findOne({
          conversationId: conversation._id,
          isDeleted: { $ne: true },
          ...getBroadcastRecipientVisibilityQuery(currentUserId),
        })
          .sort({ _id: -1 })
          .populate("senderId", "username fullName")
          .lean();
        serialized.lastMessage = buildLastMessagePayload(visibleLastMessage);
      }
      visible.push({
        ...serialized,
        unreadCount: unreadByConversation[serialized.id] || serialized.unreadCount || 0,
      });
    } catch (_) {
      // Skip unauthorized conversation
    }
  }

  return visible;
}

async function listManageableConversations(currentUser) {
  const isAdmin = currentUser.role === "admin";
  const query = isAdmin
    ? { deletedAt: null, type: { $ne: "direct" } }
    : {
        deletedAt: null,
        $or: [
          { admins: currentUser.id },
          { createdBy: currentUser.id },
          ...(currentUser.departmentId
            ? [{ type: "department", departmentId: currentUser.departmentId }]
            : []),
        ],
      };

  const conversations = await Conversation.find(query)
    .sort({ updatedAt: -1 })
    .populate(
      "members",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .populate(
      "admins",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .populate("departmentId", "name code defaultConversationId")
    .lean({ getters: true });

  const visible = [];
  for (const conversation of conversations) {
    if (isDepartmentDefaultConversation(conversation)) {
      continue;
    }
    visible.push(await serializeConversation(conversation, currentUser.id));
  }
  return visible;
}

async function getConversationDetailsForUser(currentUser, conversationId) {
  const conversation = await getConversationById(conversationId);
  await assertConversationAccess(currentUser, conversation);
  return serializeConversation(conversation, currentUser.id);
}

async function getConversationSnapshotForUserId(conversationId, userId) {
  const conversation = await getConversationById(conversationId);
  if (!conversation) {
    return null;
  }
  return serializeConversation(conversation, userId);
}

async function createConversation(currentUser, payload) {
  const type = String(payload.type || "").trim();
  const memberIds = Array.from(
    new Set([...(payload.memberIds || [])].filter(Boolean).map(String))
  );
  const description = sanitizeText(payload.description, 500);
  const name = sanitizeText(payload.name, 200);

  if (!["direct", "group", "department", "broadcast"].includes(type)) {
    throw new ApiError(400, "Invalid conversation type.");
  }

  if (type === "direct") {
    if (memberIds.length !== 1) {
      throw new ApiError(400, "Direct conversation requires exactly one target user.");
    }

    const targetUser = await User.findById(memberIds[0]).lean();
    if (!targetUser) {
      throw new ApiError(404, "Target user not found.");
    }
    if (isRestrictedDirectTarget(currentUser, targetUser)) {
      throw new ApiError(403, "Direct conversation is not allowed.");
    }

    const directMemberIds = [currentUser.id, memberIds[0]].sort();
    const directKey = directMemberIds.join(":");
    const existing = await Conversation.findOne({
      directKey,
      deletedAt: null,
      isActive: true,
    })
      .populate("members", "username fullName role departmentId isOnline isActive lastSeen")
      .populate("admins", "username fullName role departmentId isOnline isActive lastSeen")
      .exec();

    if (existing) {
      return serializeConversation(existing, currentUser.id);
    }

    const conversation = await Conversation.create({
      type: "direct",
      name: "",
      description,
      directKey,
      createdBy: currentUser.id,
      members: directMemberIds,
      admins: [currentUser.id],
    });
    await ensureConversationMemberStates(conversation._id, directMemberIds);
    return getConversationDetailsForUser(currentUser, conversation._id);
  }

  if (type === "group") {
    const members = Array.from(new Set([currentUser.id, ...memberIds]));
    const conversation = await Conversation.create({
      type,
      name,
      description,
      createdBy: currentUser.id,
      members,
      admins: [currentUser.id],
      blockedMembers: [],
    });
    await ensureConversationMemberStates(conversation._id, members);
    await logAuditEvent({
      actorId: currentUser.id,
      action: "conversation.created",
      entityType: "Conversation",
      entityId: conversation._id,
      payload: { type, name, memberCount: members.length },
    });
    return getConversationDetailsForUser(currentUser, conversation._id);
  }

  if (type === "department") {
    const allowed = await userHasPermission(currentUser, "canCreateRooms");
    if (!allowed && currentUser.role !== "admin") {
      throw new ApiError(403, "Permission denied.");
    }

    const department = await Department.findOne({
      _id: payload.departmentId,
      deletedAt: null,
    }).lean();
    if (!department) {
      throw new ApiError(404, "Department not found.");
    }

    const conversation = await Conversation.create({
      type,
      name: name || `${department.name} room`,
      description,
      departmentId: department._id,
      createdBy: currentUser.id,
      members: memberIds,
      admins: [currentUser.id, ...new Set((payload.adminIds || []).map(String))],
    });
    await ensureConversationMemberStates(conversation._id, memberIds);
    return getConversationDetailsForUser(currentUser, conversation._id);
  }

  const canSendBroadcast = await userHasPermission(currentUser, "canSendBroadcast");
  if (!canSendBroadcast && currentUser.role !== "admin") {
    throw new ApiError(403, "Permission denied.");
  }

  const requestedPublisherIds = normalizeIdList(payload.memberIds);
  const publisherCandidates = Array.from(
    new Set([currentUser.id, ...requestedPublisherIds])
  );
  const existingPublisherUsers = await User.find(
    { _id: { $in: publisherCandidates }, isActive: true },
    "_id"
  ).lean();
  const broadcastPublisherIds = Array.from(
    new Set(existingPublisherUsers.map((entry) => entry._id.toString()))
  );

  const requestedAdminIds = normalizeIdList(payload.adminIds);
  const publisherSet = new Set(broadcastPublisherIds);
  const adminIds = Array.from(
    new Set(
      [currentUser.id, ...requestedAdminIds].filter((id) => publisherSet.has(id))
    )
  );

  const members = [...broadcastPublisherIds];
  const conversation = await Conversation.create({
    type,
    name: name || "Broadcast",
    description,
    createdBy: currentUser.id,
    members,
    admins: adminIds,
    broadcastPublisherIds,
  });
  await ensureConversationMemberStates(conversation._id, members);
  return getConversationDetailsForUser(currentUser, conversation._id);
}

async function updateConversation(currentUser, conversationId, payload) {
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
  });
  await assertConversationManagementAccess(currentUser, conversation);

  if (conversation.type === "direct") {
    throw new ApiError(400, "Direct conversations cannot be edited.");
  }

  if (payload.name != null) {
    conversation.name = sanitizeText(payload.name, 200);
  }
  if (payload.description != null) {
    conversation.description = sanitizeText(payload.description, 500);
  }
  if (payload.isArchived != null) {
    conversation.isArchived = Boolean(payload.isArchived);
  }
  if (payload.isActive != null) {
    conversation.isActive = Boolean(payload.isActive);
  }

  if (conversation.type === "group") {
    if (payload.memberIds != null) {
      const nextMembers = Array.from(
        new Set((payload.memberIds || []).filter(Boolean).map(String))
      );
      conversation.members = nextMembers.includes(currentUser.id)
        ? nextMembers
        : [currentUser.id, ...nextMembers];
      await syncConversationMemberStates(conversation._id, conversation.members);
    }

    if (payload.adminIds != null) {
      conversation.admins = Array.from(
        new Set([currentUser.id, ...(payload.adminIds || []).filter(Boolean).map(String)])
      );
    }
  }
  if (conversation.type === "broadcast") {
    if (payload.memberIds != null) {
      const requestedPublisherIds = normalizeIdList(payload.memberIds);
      const publisherCandidates = Array.from(
        new Set([conversation.createdBy?.toString?.() || currentUser.id, ...requestedPublisherIds])
      );
      const existingPublisherUsers = await User.find(
        { _id: { $in: publisherCandidates }, isActive: true },
        "_id"
      ).lean();
      const broadcastPublisherIds = Array.from(
        new Set(existingPublisherUsers.map((entry) => entry._id.toString()))
      );
      if (broadcastPublisherIds.length === 0) {
        throw new ApiError(400, "Broadcast must include at least one publisher.");
      }
      conversation.broadcastPublisherIds = broadcastPublisherIds;

      const conversationMemberIds = new Set(extractIdArray(conversation.members));
      let hasMemberChanges = false;
      for (const publisherId of broadcastPublisherIds) {
        if (!conversationMemberIds.has(publisherId)) {
          conversationMemberIds.add(publisherId);
          hasMemberChanges = true;
        }
      }
      if (hasMemberChanges) {
        conversation.members = [...conversationMemberIds];
        await syncConversationMemberStates(conversation._id, conversation.members);
      }
    }

    if (payload.adminIds != null) {
      const configuredPublisherIds = new Set(
        (conversation.broadcastPublisherIds || []).map((entry) => entry.toString())
      );
      const publisherIds =
        configuredPublisherIds.size > 0
          ? configuredPublisherIds
          : new Set((conversation.members || []).map((entry) => entry.toString()));
      const requestedAdminIds = normalizeIdList(payload.adminIds);
      const nextAdmins = Array.from(
        new Set(
          [currentUser.id, ...requestedAdminIds].filter((id) => publisherIds.has(id))
        )
      );
      if (nextAdmins.length === 0) {
        throw new ApiError(400, "Broadcast must include at least one admin.");
      }
      conversation.admins = nextAdmins;
    }
  }

  await conversation.save();
  await logAuditEvent({
    actorId: currentUser.id,
    action: "conversation.updated",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: {
      type: conversation.type,
      departmentId: conversation.departmentId?.toString?.() || null,
    },
  });

  return getConversationDetailsForUser(currentUser, conversation._id);
}

async function deleteConversation(currentUser, conversationId, { scope = "self" } = {}) {
  const normalizedScope = String(scope || "self").toLowerCase();
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
  }).lean();

  if (normalizedScope !== "global") {
    await assertConversationAccess(currentUser, conversation);
    await clearConversationHistoryForUser(conversation._id, currentUser.id, new Date());
    const nextConversation = await getConversationDetailsForUser(
      currentUser,
      conversation._id
    );
    await logAuditEvent({
      actorId: currentUser.id,
      action: "conversation.cleared",
      entityType: "Conversation",
      entityId: conversation._id,
      payload: { type: conversation.type },
    });
    return {
      mode: "self_cleared",
      conversation: nextConversation,
      conversationId: conversation._id.toString(),
      memberIds: [currentUser.id],
    };
  }

  await assertConversationManagementAccess(currentUser, conversation);
  if (conversation.type === "department") {
    throw new ApiError(400, "Department conversations are managed through departments.");
  }

  const messages = await Message.find(
    { conversationId: conversation._id, isDeleted: { $ne: true } },
    "storedFilePath"
  ).lean();

  for (const message of messages) {
    if (message.storedFilePath) {
      await deleteFileIfExists(message.storedFilePath);
    }
  }

  await Message.updateMany(
    { conversationId: conversation._id },
    {
      $set: {
        isDeleted: true,
        deletedAt: new Date(),
      },
    }
  );
  await Conversation.updateOne(
    { _id: conversation._id },
    {
      $set: {
        deletedAt: new Date(),
        isActive: false,
      },
    }
  );
  await ConversationMemberState.deleteMany({ conversationId: conversation._id });
  await logAuditEvent({
    actorId: currentUser.id,
    action: "conversation.deleted",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { type: conversation.type },
  });

  const memberIds = Array.from(
    new Set((conversation.members || []).map((entry) => getObjectIdString(entry)).filter(Boolean))
  );
  if (!memberIds.includes(currentUser.id)) {
    memberIds.push(currentUser.id);
  }

  return {
    mode: "global_deleted",
    conversationId: conversation._id.toString(),
    memberIds,
  };
}

async function listMessagesForConversation(
  currentUser,
  conversationId,
  { cursor = null, limit = 50 } = {}
) {
  const conversation = await getConversationById(conversationId);
  await assertConversationAccess(currentUser, conversation);
  const memberState = await getConversationState(currentUser.id, conversationId);
  const clearHistoryAt = memberState?.clearHistoryAt
    ? new Date(memberState.clearHistoryAt)
    : null;

  const pageSize = Math.max(1, Math.min(Number(limit || 50), 100));
  const query = {
    conversationId,
    isDeleted: { $ne: true },
  };
  const currentUserId = getObjectIdString(currentUser.id || currentUser._id);
  if (
    conversation.type === "broadcast" &&
    !canUserViewAllBroadcastMessages(currentUser, conversation)
  ) {
    Object.assign(query, getBroadcastRecipientVisibilityQuery(currentUserId));
  }
  if (cursor) {
    query._id = { $lt: cursor };
  }
  if (clearHistoryAt) {
    query.createdAt = { $gt: clearHistoryAt };
  }

  const messages = await Message.find(query)
    .sort({ _id: -1 })
    .limit(pageSize + 1)
    .populate(
      "senderId",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .exec();

  const hasMore = messages.length > pageSize;
  const sliced = hasMore ? messages.slice(0, pageSize) : messages;
  const nextCursor = hasMore ? sliced[sliced.length - 1]._id.toString() : null;
  const ordered = sliced.reverse();

  return {
    messages: ordered.map((message) => serializeMessage(message, message.senderId)),
    meta: {
      nextCursor,
      hasMore,
      limit: pageSize,
    },
  };
}

async function createMessage(currentUser, payload, file) {
  const conversation = await getConversationById(payload.conversationId);
  await assertConversationAccess(currentUser, conversation);
  const blockedIds = new Set(
    (conversation.blockedMembers || []).map((entry) =>
      entry?._id ? entry._id.toString() : entry.toString()
    )
  );
  if (blockedIds.has(currentUser.id)) {
    if (file?.path) {
      await deleteFileIfExists(file.path);
    }
    throw new ApiError(
      403,
      "You can read this conversation but cannot send messages in it."
    );
  }
  if (conversation.isActive === false) {
    if (file?.path) {
      await deleteFileIfExists(file.path);
    }
    throw new ApiError(
      403,
      "This room is disabled by admin. Messaging is currently read-only."
    );
  }

  const forwardFromMessageId = isMongoIdLike(payload.forwardFromMessageId)
    ? String(payload.forwardFromMessageId)
    : null;

  let forwardedMessage = null;
  if (forwardFromMessageId) {
    forwardedMessage = await Message.findOne({
      _id: forwardFromMessageId,
      isDeleted: { $ne: true },
    })
      .select(
        "conversationId content messageType fileUrl fileName fileSize mimeType storedFilePath metadata"
      )
      .lean();

    if (!forwardedMessage) {
      throw new ApiError(404, "Source message not found.");
    }

    const sourceConversation = await getConversationById(
      forwardedMessage.conversationId
    );
    await assertConversationAccess(currentUser, sourceConversation);

    const sourcePolicy =
      forwardedMessage.metadata &&
      typeof forwardedMessage.metadata === "object" &&
      forwardedMessage.metadata.attachmentPolicy &&
      typeof forwardedMessage.metadata.attachmentPolicy === "object"
        ? forwardedMessage.metadata.attachmentPolicy
        : null;

    if (
      forwardedMessage.storedFilePath &&
      sourcePolicy &&
      sourcePolicy.allowForward === false
    ) {
      throw new ApiError(
        403,
        "This attachment cannot be forwarded by sender policy."
      );
    }
  }

  const forwardingAttachment = Boolean(
    forwardedMessage?.storedFilePath && forwardedMessage?.fileUrl
  );
  if (file || forwardingAttachment) {
    const canUpload = await userHasPermission(currentUser, "canUploadFiles");
    if (!canUpload) {
      await deleteFileIfExists(file?.path);
      throw new ApiError(403, "You are not allowed to upload files.");
    }
  }

  let content = sanitizeMessageContent(payload.content);
  const normalizedMetadata = normalizeMessageMetadata(payload.metadata) || {};
  let recipientIds = [];
  if (conversation.type === "broadcast") {
    const configuredPublisherIds = new Set(
      (conversation.broadcastPublisherIds || []).map((entry) => entry.toString())
    );
    const publisherIds =
      configuredPublisherIds.size > 0
        ? configuredPublisherIds
        : new Set((conversation.members || []).map((entry) => entry.toString()));
    const adminIds = new Set((conversation.admins || []).map((entry) => entry.toString()));
    if (
      currentUser.role !== "admin" &&
      !publisherIds.has(currentUser.id) &&
      !adminIds.has(currentUser.id)
    ) {
      if (file?.path) {
        await deleteFileIfExists(file.path);
      }
      throw new ApiError(403, "You are not allowed to publish in this broadcast.");
    }

    const rawTargets =
      normalizedMetadata.broadcastTargets &&
      typeof normalizedMetadata.broadcastTargets === "object"
        ? normalizedMetadata.broadcastTargets
        : {};
    const mergedRawTargets = {
      departmentIds:
        rawTargets.departmentIds ||
        normalizedMetadata.departmentIds ||
        payload.departmentIds ||
        [],
      departmentCodes:
        rawTargets.departmentCodes ||
        normalizedMetadata.departmentCodes ||
        payload.departmentCodes ||
        [],
      departmentNames:
        rawTargets.departmentNames ||
        normalizedMetadata.departmentNames ||
        payload.departmentNames ||
        [],
    };
    const requestedTargetCount =
      (mergedRawTargets.departmentIds || []).length +
      (mergedRawTargets.departmentCodes || []).length +
      (mergedRawTargets.departmentNames || []).length;
    const targetDepartmentIds = await resolveBroadcastTargetDepartmentIds(
      mergedRawTargets
    );
    if (requestedTargetCount > 0 && targetDepartmentIds.length === 0) {
      throw new ApiError(400, "No valid target departments selected.");
    }
    const userQuery = {
      isActive: true,
      ...(targetDepartmentIds.length > 0
        ? { departmentId: { $in: targetDepartmentIds } }
        : {}),
    };
    const targetUsers = await User.find(userQuery, "_id").lean();
    recipientIds = targetUsers.map((entry) => entry._id.toString());

    const conversationMemberIds = new Set(
      (conversation.members || []).map((entry) => entry.toString())
    );
    for (const publisherId of publisherIds) {
      conversationMemberIds.add(publisherId);
    }
    let hasMemberChanges = false;
    for (const userId of recipientIds) {
      if (!conversationMemberIds.has(userId)) {
        conversationMemberIds.add(userId);
        hasMemberChanges = true;
      }
    }
    if (hasMemberChanges) {
      conversation.members = [...conversationMemberIds];
      await syncConversationMemberStates(conversation._id, conversation.members);
    }

    let targetDepartmentNames = [];
    let targetDepartmentCodes = [];
    if (targetDepartmentIds.length > 0) {
      const departments = await Department.find(
        { _id: { $in: targetDepartmentIds }, deletedAt: null },
        "name code"
      ).lean();
      const departmentNameById = new Map();
      const departmentCodeById = new Map();
      for (const entry of departments) {
        const entryId = entry._id.toString();
        departmentNameById.set(entryId, entry.name);
        departmentCodeById.set(entryId, entry.code);
      }
      targetDepartmentNames = targetDepartmentIds
        .map((id) => departmentNameById.get(id))
        .filter(Boolean);
      targetDepartmentCodes = targetDepartmentIds
        .map((id) => departmentCodeById.get(id))
        .filter(Boolean);
    }
    normalizedMetadata.broadcastTargets = {
      departmentIds: targetDepartmentIds,
      departmentNames: targetDepartmentNames,
      departmentCodes: targetDepartmentCodes,
      sentToAllDepartments: targetDepartmentIds.length === 0,
    };
  } else if (conversation.type === "department" && currentUser.departmentId) {
    const departmentUsers = await User.find(
      { departmentId: currentUser.departmentId, isActive: true },
      "_id"
    ).lean();
    recipientIds = departmentUsers.map((entry) => entry._id.toString());
  } else {
    recipientIds = (conversation.members || []).map((entry) =>
      entry._id ? entry._id.toString() : entry.toString()
    );
  }

  let attachment = file
    ? classifyAttachment({
        ...file,
        conversationId: conversation._id.toString(),
      })
    : classifyAttachment(null);
  let finalFileName = file
    ? sanitizeAttachmentFileName(payload.fileName, attachment.fileName)
    : null;
  let storedFilePath = file?.path ? toRelativeUploadPath(file.path) : null;
  let messageTypeFallback = attachment.messageType || "text";

  if (forwardedMessage) {
    const sourceContent = sanitizeMessageContent(forwardedMessage.content);
    if (!content) {
      content = sourceContent;
    }

    if (forwardedMessage.storedFilePath && forwardedMessage.fileUrl) {
      attachment = classifyAttachment({
        conversationId: conversation._id.toString(),
        path: forwardedMessage.storedFilePath,
        originalname:
          forwardedMessage.fileName ||
          path.basename(forwardedMessage.storedFilePath),
        size: Number(forwardedMessage.fileSize || 0),
        mimetype: forwardedMessage.mimeType || "application/octet-stream",
      });

      storedFilePath = forwardedMessage.storedFilePath;
      finalFileName =
        sanitizeAttachmentFileName(
          payload.fileName,
          forwardedMessage.fileName || attachment.fileName
        ) ||
        sanitizeAttachmentFileName(
          forwardedMessage.fileName,
          attachment.fileName
        );
      const sourceType = sanitizeMessageType(forwardedMessage.messageType, "file");
      messageTypeFallback = sourceType === "system" ? "text" : sourceType;

      const sourcePolicy =
        forwardedMessage.metadata &&
        typeof forwardedMessage.metadata === "object" &&
        forwardedMessage.metadata.attachmentPolicy &&
        typeof forwardedMessage.metadata.attachmentPolicy === "object"
          ? forwardedMessage.metadata.attachmentPolicy
          : null;
      const requestedPolicy =
        normalizedMetadata.attachmentPolicy &&
        typeof normalizedMetadata.attachmentPolicy === "object"
          ? normalizedMetadata.attachmentPolicy
          : {};
      if (sourcePolicy || Object.keys(requestedPolicy).length > 0) {
        normalizedMetadata.attachmentPolicy = {
          allowDownload:
            (sourcePolicy?.allowDownload !== false) &&
            requestedPolicy.allowDownload !== false,
          allowForward:
            (sourcePolicy?.allowForward !== false) &&
            requestedPolicy.allowForward !== false,
        };
      }
    } else {
      attachment = classifyAttachment(null);
      storedFilePath = null;
      finalFileName = null;
      messageTypeFallback = "text";
    }
  }

  if (storedFilePath) {
    const archiveMetadata = normalizeAttachmentArchiveMetadata(
      normalizedMetadata
    );
    if (archiveMetadata) {
      normalizedMetadata.attachmentArchive = archiveMetadata;
    } else {
      delete normalizedMetadata.attachmentArchive;
    }
  } else {
    delete normalizedMetadata.attachmentArchive;
  }

  if (!content && !storedFilePath && payload.messageType !== "poll") {
    throw new ApiError(400, "Message content or attachment is required.");
  }

  if (payload.isSilent) {
    normalizedMetadata.silent = true;
  }

  const targetRecipientIds = recipientIds.filter((userId) => userId !== currentUser.id);

  const message = await Message.create({
    conversationId: conversation._id,
    senderId: currentUser.id,
    content,
    messageType: sanitizeMessageType(payload.messageType, messageTypeFallback),
    fileUrl: attachment.fileUrl,
    fileName: finalFileName,
    fileSize: attachment.fileSize,
    mimeType: attachment.mimeType,
    storedFilePath,
    replyToMessageId: payload.replyToMessageId || null,
    seenBy: [{ userId: currentUser.id, at: new Date() }],
    deliveredTo: await buildDeliveryReceipts(targetRecipientIds),
    metadata: Object.keys(normalizedMetadata).length > 0 ? normalizedMetadata : null,
    isScheduled: payload.isScheduled || false,
    scheduledFor: payload.scheduledFor ? new Date(payload.scheduledFor) : null,
  });

  conversation.lastMessage = {
    content: content || finalFileName || "",
    senderId: currentUser.id,
    senderName: currentUser.fullName || currentUser.username,
    messageType: message.messageType,
    createdAt: message.createdAt,
  };
  await conversation.save();

  await incrementUnreadCounts(conversation._id, targetRecipientIds, currentUser.id);

  let audienceUserIds;
  if (conversation.type === "broadcast") {
    const publisherIds = extractIdArray(conversation.broadcastPublisherIds);
    audienceUserIds = Array.from(
      new Set([currentUser.id, ...targetRecipientIds, ...publisherIds])
    );
  } else {
    audienceUserIds = Array.from(
      new Set([currentUser.id, ...extractIdArray(conversation.members)])
    );
  }

  const populated = await Message.findById(message._id)
    .populate(
      "senderId",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .exec();

  return {
    audienceUserIds,
    recipientUserIds: targetRecipientIds,
    conversation: await serializeConversation(conversation, currentUser.id),
    message: serializeMessage(populated, populated.senderId),
  };
}

async function markConversationSeen(currentUser, conversationId) {
  const conversation = await getConversationById(conversationId);
  await assertConversationAccess(currentUser, conversation);

  const unseenQuery = {
    conversationId,
    isDeleted: { $ne: true },
    senderId: { $ne: currentUser.id },
    "seenBy.userId": { $ne: currentUser.id },
  };
  const currentUserId = getObjectIdString(currentUser.id || currentUser._id);
  if (
    conversation.type === "broadcast" &&
    !canUserViewAllBroadcastMessages(currentUser, conversation)
  ) {
    unseenQuery["deliveredTo.userId"] = currentUserId;
  }

  const unseenMessages = await Message.find(unseenQuery).exec();

  for (const message of unseenMessages) {
    message.seenBy.push({ userId: currentUser.id, at: new Date() });
    await message.save();
  }

  const lastReadMessage = unseenMessages[unseenMessages.length - 1] || null;
  await markConversationRead({
    conversationId,
    userId: currentUser.id,
    lastReadMessageId: lastReadMessage?._id || null,
  });

  return unseenMessages.map((message) => message._id.toString());
}

async function markConversationDelivered(currentUser, conversationId) {
  const conversation = await getConversationById(conversationId);
  await assertConversationAccess(currentUser, conversation);

  const undeliveredMessages = await Message.find({
    conversationId,
    isDeleted: { $ne: true },
    senderId: { $ne: currentUser.id },
    "deliveredTo.userId": { $ne: currentUser.id },
  }).exec();

  for (const message of undeliveredMessages) {
    message.deliveredTo.push({ userId: currentUser.id, at: new Date() });
    await message.save();
  }

  return undeliveredMessages.map((message) => message._id.toString());
}

async function markPendingDeliveriesForUser(currentUser) {
  const conversationQuery = {
    deletedAt: null,
    $or: [{ members: currentUser.id }],
  };

  if (currentUser.departmentId) {
    conversationQuery.$or.push({
      type: "department",
      departmentId: currentUser.departmentId,
    });
  }

  const conversations = await Conversation.find(conversationQuery, "_id").lean();
  const conversationIds = conversations.map((entry) => entry._id);
  if (conversationIds.length === 0) {
    return [];
  }

  const undeliveredMessages = await Message.find({
    conversationId: { $in: conversationIds },
    isDeleted: { $ne: true },
    senderId: { $ne: currentUser.id },
    "deliveredTo.userId": { $ne: currentUser.id },
  }).exec();

  const grouped = new Map();
  for (const message of undeliveredMessages) {
    message.deliveredTo.push({ userId: currentUser.id, at: new Date() });
    await message.save();
    const key = message.conversationId.toString();
    if (!grouped.has(key)) {
      grouped.set(key, []);
    }
    grouped.get(key).push(message._id.toString());
  }

  return [...grouped.entries()].map(([conversationId, messageIds]) => ({
    conversationId,
    userId: currentUser.id,
    messageIds,
  }));
}

async function markMessageSeen(currentUser, messageId) {
  const message = await Message.findById(messageId).exec();
  if (!message || message.isDeleted) {
    throw new ApiError(404, "Message not found.");
  }

  const conversation = await getConversationById(message.conversationId);
  await assertConversationAccess(currentUser, conversation);

  const seen = (message.seenBy || []).some(
    (entry) => entry.userId.toString() === currentUser.id
  );
  if (!seen) {
    message.seenBy.push({ userId: currentUser.id, at: new Date() });
    await message.save();
  }

  await markConversationRead({
    conversationId: message.conversationId,
    userId: currentUser.id,
    lastReadMessageId: message._id,
  });

  return serializeMessage(message);
}

async function deleteMessage(currentUser, messageId) {
  const message = await Message.findById(messageId).exec();
  if (!message || message.isDeleted) {
    throw new ApiError(404, "Message not found.");
  }

  const conversation = await getConversationById(message.conversationId);
  await assertConversationAccess(currentUser, conversation);

  const canDeleteAnyMessage = await userHasPermission(currentUser, "canDeleteMessages");
  const isOwnMessage = message.senderId.toString() === currentUser.id;
  if (!isOwnMessage && !canDeleteAnyMessage) {
    throw new ApiError(403, "Permission denied.");
  }

  if (message.storedFilePath) {
    await deleteFileIfExists(message.storedFilePath);
  }

  message.isDeleted = true;
  message.deletedAt = new Date();
  message.content = "";
  message.fileUrl = null;
  message.fileName = null;
  message.fileSize = null;
  message.mimeType = null;
  message.metadata = {
    ...(message.metadata || {}),
    deletedBy: currentUser.id,
  };
  await message.save();
  await refreshConversationLastMessage(message.conversationId);

  await logAuditEvent({
    actorId: currentUser.id,
    action: "message.deleted",
    entityType: "Message",
    entityId: message._id,
    payload: { conversationId: message.conversationId.toString() },
  });

  return serializeMessage(message);
}

async function updateMessage(currentUser, messageId, payload) {
  const message = await Message.findById(messageId).exec();
  if (!message || message.isDeleted) {
    throw new ApiError(404, "Message not found.");
  }

  const conversation = await getConversationById(message.conversationId);
  await assertConversationAccess(currentUser, conversation);

  const canDeleteAnyMessage = await userHasPermission(currentUser, "canDeleteMessages");
  const isOwnMessage = message.senderId.toString() === currentUser.id;
  if (!isOwnMessage && !canDeleteAnyMessage) {
    throw new ApiError(403, "Permission denied.");
  }

  if (message.fileUrl) {
    throw new ApiError(400, "Attachment messages cannot be edited.");
  }

  const content = sanitizeMessageContent(payload.content);
  if (!content) {
    throw new ApiError(400, "Message content is required.");
  }

  message.content = content;
  message.metadata = {
    ...(message.metadata || {}),
    editedAt: new Date(),
    editedBy: currentUser.id,
  };
  await message.save();
  await refreshConversationLastMessage(message.conversationId);

  const populated = await Message.findById(message._id)
    .populate(
      "senderId",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .exec();

  await logAuditEvent({
    actorId: currentUser.id,
    action: "message.updated",
    entityType: "Message",
    entityId: message._id,
    payload: { conversationId: message.conversationId.toString() },
  });

  return serializeMessage(populated, populated.senderId);
}

async function toggleMessageReaction(currentUser, messageId, emoji) {
  const normalizedEmoji = String(emoji || "").trim().slice(0, 8);
  if (!normalizedEmoji) {
    throw new ApiError(400, "Reaction is required.");
  }

  const message = await Message.findById(messageId).exec();
  if (!message || message.isDeleted) {
    throw new ApiError(404, "Message not found.");
  }

  const conversation = await getConversationById(message.conversationId);
  await assertConversationAccess(currentUser, conversation);

  const metadata = { ...(message.metadata || {}) };
  const reactions = { ...((metadata.reactions && typeof metadata.reactions === "object") ? metadata.reactions : {}) };
  const existing = Array.isArray(reactions[normalizedEmoji])
    ? reactions[normalizedEmoji].map(String)
    : [];

  const reactorId = String(currentUser.id);
  const hadReaction = existing.includes(reactorId);
  const reactionAdded = !hadReaction;

  const userIds = new Set(existing);
  if (userIds.has(reactorId)) {
    userIds.delete(reactorId);
  } else {
    userIds.add(reactorId);
  }

  if (userIds.size === 0) {
    delete reactions[normalizedEmoji];
  } else {
    reactions[normalizedEmoji] = [...userIds];
  }

  metadata.reactions = reactions;
  message.metadata = metadata;
  await message.save();

  const populated = await Message.findById(message._id)
    .populate(
      "senderId",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .exec();

  return {
    message: serializeMessage(populated, populated.senderId),
    reactionAdded,
    emoji: normalizedEmoji,
  };
}

async function toggleMessageFavorite(currentUser, messageId) {
  const message = await Message.findById(messageId).exec();
  if (!message || message.isDeleted) {
    throw new ApiError(404, "Message not found.");
  }

  const conversation = await getConversationById(message.conversationId);
  await assertConversationAccess(currentUser, conversation);

  const metadata = { ...(message.metadata || {}) };
  const existing = Array.isArray(metadata.favoriteBy)
    ? metadata.favoriteBy.map(String)
    : [];
  const userId = String(currentUser.id);
  const favoriteBy = new Set(existing);

  if (favoriteBy.has(userId)) {
    favoriteBy.delete(userId);
  } else {
    favoriteBy.add(userId);
  }

  metadata.favoriteBy = [...favoriteBy];
  message.metadata = metadata;
  await message.save();

  const populated = await Message.findById(message._id)
    .populate(
      "senderId",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .exec();

  return serializeMessage(populated, populated.senderId);
}

async function updateConversationPreferences(currentUser, conversationId, payload) {
  const conversation = await getConversationById(conversationId);
  await assertConversationAccess(currentUser, conversation);

  await updateConversationState(currentUser.id, conversationId, payload);
  return getConversationDetailsForUser(currentUser, conversationId);
}

async function setConversationPinnedMessage(currentUser, conversationId, payload) {
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
    isActive: true,
  }).exec();
  assertGroupOwnerAccess(currentUser, conversation);

  const content = sanitizePinnedMessageContent(payload?.content);
  if (!content) {
    throw new ApiError(400, "Pinned message content is required.");
  }

  const now = new Date();
  conversation.pinnedMessage = {
    messageId: payload?.messageId || null,
    content,
    setBy: currentUser.id,
    setByName: currentUser.fullName || currentUser.username || "",
    createdAt: conversation.pinnedMessage?.createdAt || now,
    updatedAt: now,
  };
  await conversation.save();

  const systemMessage = await createSystemConversationMessage(conversation, currentUser, {
    content: `${currentUser.fullName || currentUser.username} updated the pinned message`,
    metadata: {
      eventType: "group.pinned_message.updated",
    },
  });

  return {
    conversation: await getConversationDetailsForUser(currentUser, conversation._id),
    systemMessage,
  };
}

async function clearConversationPinnedMessage(currentUser, conversationId) {
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
    isActive: true,
  }).exec();
  assertGroupOwnerAccess(currentUser, conversation);

  conversation.pinnedMessage = null;
  await conversation.save();

  const systemMessage = await createSystemConversationMessage(conversation, currentUser, {
    content: `${currentUser.fullName || currentUser.username} removed the pinned message`,
    metadata: {
      eventType: "group.pinned_message.cleared",
    },
  });

  return {
    conversation: await getConversationDetailsForUser(currentUser, conversation._id),
    systemMessage,
  };
}

async function joinConversation(currentUser, conversationId) {
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
    isActive: true,
  }).exec();

  if (!conversation) {
    throw new ApiError(404, "Conversation not found.");
  }
  if (conversation.type === "department" || conversation.type === "broadcast") {
    throw new ApiError(400, "This conversation cannot be joined manually.");
  }

  const canCreateRooms = await userHasPermission(currentUser, "canCreateRooms");
  if (!canCreateRooms && currentUser.role !== "admin") {
    throw new ApiError(403, "Permission denied.");
  }

  const memberIds = new Set((conversation.members || []).map((entry) => entry.toString()));
  memberIds.add(currentUser.id);
  conversation.members = [...memberIds];
  await conversation.save();
  await ensureConversationMemberStates(conversation._id, [currentUser.id]);
  return getConversationDetailsForUser(currentUser, conversation._id);
}

async function leaveConversation(currentUser, conversationId) {
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
    isActive: true,
  }).exec();
  await assertConversationAccess(currentUser, conversation);

  if (conversation.type === "department" || conversation.type === "broadcast") {
    throw new ApiError(400, "This conversation cannot be left.");
  }

  conversation.members = (conversation.members || []).filter(
    (entry) => entry.toString() !== currentUser.id
  );
  conversation.admins = (conversation.admins || []).filter(
    (entry) => entry.toString() !== currentUser.id
  );
  await conversation.save();
  await removeConversationMemberState(conversation._id, currentUser.id);
  return true;
}

async function listConversationMembers(currentUser, conversationId) {
  const conversation = await getConversationById(conversationId);
  await assertConversationAccess(currentUser, conversation);
  return (conversation.members || []).map((member) =>
    member._id ? serializeUserLite(member) : { id: member.toString() }
  );
}

async function addConversationMembers(currentUser, conversationId, userIds) {
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
    isActive: true,
  }).exec();
  assertGroupOwnerAccess(currentUser, conversation);

  const blocked = new Set((conversation.blockedMembers || []).map((entry) => entry.toString()));
  const nextUserIds = Array.from(new Set((userIds || []).map(String))).filter(
    (userId) => !blocked.has(userId)
  );
  if (nextUserIds.length === 0) {
    throw new ApiError(400, "No eligible users to add.");
  }

  const addedUsers = await User.find(
    { _id: { $in: nextUserIds }, isActive: true },
    "username fullName"
  ).lean();
  const addedNames = addedUsers.map((entry) => entry.fullName || entry.username);

  const nextMembers = Array.from(
    new Set([...(conversation.members || []).map(String), ...nextUserIds])
  );
  conversation.members = nextMembers;
  await conversation.save();
  await syncConversationMemberStates(conversation._id, nextMembers);
  const systemMessage = await createSystemConversationMessage(conversation, currentUser, {
    content: `${currentUser.fullName || currentUser.username} أضاف ${addedNames.join("، ")} إلى المجموعة`,
    metadata: {
      eventType: "group.members.added",
      userIds: nextUserIds,
    },
  });
  await logAuditEvent({
    actorId: currentUser.id,
    action: "group.members.added",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { userIds: nextUserIds },
  });
  return {
    conversation: await getConversationDetailsForUser(currentUser, conversation._id),
    systemMessage,
    addedUserIds: nextUserIds,
  };
}

async function removeConversationMember(currentUser, conversationId, userId) {
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
    isActive: true,
  }).exec();
  assertGroupOwnerAccess(currentUser, conversation);
  if (String(userId) === currentUser.id) {
    throw new ApiError(400, "Group creator cannot remove themselves.");
  }

  const memberIds = new Set((conversation.members || []).map((entry) => entry.toString()));
  if (!memberIds.has(String(userId))) {
    throw new ApiError(400, "User is not a member of this group.");
  }
  conversation.admins = (conversation.admins || []).filter(
    (entry) => entry.toString() !== String(userId)
  );
  conversation.blockedMembers.addToSet(userId);
  await conversation.save();
  const target = await User.findById(userId, "username fullName").lean();
  const targetLabel = target?.fullName || target?.username || "عضو";
  const systemMessage = await createSystemConversationMessage(conversation, currentUser, {
    content: `${currentUser.fullName || currentUser.username} أزال ${targetLabel} من الإرسال داخل المجموعة`,
    metadata: {
      eventType: "group.member.removed",
      userIds: [String(userId)],
    },
  });
  await logAuditEvent({
    actorId: currentUser.id,
    action: "group.member.removed",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { userId: String(userId) },
  });
  return {
    conversation: await getConversationDetailsForUser(currentUser, conversation._id),
    systemMessage,
    affectedUserIds: [String(userId)],
  };
}

async function promoteConversationAdmin(currentUser, conversationId, userId) {
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
    isActive: true,
  }).exec();
  assertGroupOwnerAccess(currentUser, conversation);

  const memberIds = new Set((conversation.members || []).map((entry) => entry.toString()));
  if (!memberIds.has(String(userId))) {
    throw new ApiError(400, "User must be a group member first.");
  }

  const adminIds = new Set((conversation.admins || []).map((entry) => entry.toString()));
  adminIds.add(String(userId));
  adminIds.add(currentUser.id);
  conversation.admins = [...adminIds];
  await conversation.save();
  const target = await User.findById(userId, "username fullName").lean();
  const targetLabel = target?.fullName || target?.username || "عضو";
  const systemMessage = await createSystemConversationMessage(conversation, currentUser, {
    content: `${targetLabel} أصبح أدمن في المجموعة`,
    metadata: {
      eventType: "group.admin.promoted",
      userIds: [String(userId)],
    },
  });
  await logAuditEvent({
    actorId: currentUser.id,
    action: "group.admin.promoted",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { userId: String(userId) },
  });
  return {
    conversation: await getConversationDetailsForUser(currentUser, conversation._id),
    systemMessage,
    affectedUserIds: [String(userId)],
  };
}

async function demoteConversationAdmin(currentUser, conversationId, userId) {
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
    isActive: true,
  }).exec();
  assertGroupOwnerAccess(currentUser, conversation);
  if (String(userId) === currentUser.id) {
    throw new ApiError(400, "Group creator cannot be demoted.");
  }

  conversation.admins = (conversation.admins || []).filter(
    (entry) => entry.toString() !== String(userId)
  );
  await conversation.save();
  const target = await User.findById(userId, "username fullName").lean();
  const targetLabel = target?.fullName || target?.username || "عضو";
  const systemMessage = await createSystemConversationMessage(conversation, currentUser, {
    content: `تمت إزالة صلاحية الأدمن من ${targetLabel}`,
    metadata: {
      eventType: "group.admin.demoted",
      userIds: [String(userId)],
    },
  });
  await logAuditEvent({
    actorId: currentUser.id,
    action: "group.admin.demoted",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { userId: String(userId) },
  });
  return {
    conversation: await getConversationDetailsForUser(currentUser, conversation._id),
    systemMessage,
    affectedUserIds: [String(userId)],
  };
}

async function blockConversationMember(currentUser, conversationId, userId) {
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
    isActive: true,
  }).exec();
  assertGroupOwnerAccess(currentUser, conversation);
  if (String(userId) === currentUser.id) {
    throw new ApiError(400, "Group creator cannot block themselves.");
  }

  conversation.members = (conversation.members || []).filter(
    (entry) => entry.toString() !== String(userId)
  );
  conversation.admins = (conversation.admins || []).filter(
    (entry) => entry.toString() !== String(userId)
  );
  conversation.blockedMembers.addToSet(userId);
  await conversation.save();
  await removeConversationMemberState(conversation._id, userId);
  await logAuditEvent({
    actorId: currentUser.id,
    action: "group.member.blocked",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { userId: String(userId) },
  });
  return getConversationDetailsForUser(currentUser, conversation._id);
}

async function unblockConversationMember(currentUser, conversationId, userId) {
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
    isActive: true,
  }).exec();
  assertGroupOwnerAccess(currentUser, conversation);

  conversation.blockedMembers.pull(userId);
  await conversation.save();
  await logAuditEvent({
    actorId: currentUser.id,
    action: "group.member.unblocked",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { userId: String(userId) },
  });
  return getConversationDetailsForUser(currentUser, conversation._id);
}

async function searchMessages(
  currentUser,
  { q = "", conversationId = null, cursor = null, limit = 30 } = {}
) {
  const sanitized = sanitizeMessageContent(q);
  if (!sanitized) {
    return {
      messages: [],
      meta: { nextCursor: null, hasMore: false, limit: 0 },
    };
  }

  let unrestrictedConversationIds = [];
  let restrictedBroadcastConversationIds = [];
  let clearHistoryAt = null;
  const currentUserId = getObjectIdString(currentUser.id || currentUser._id);
  if (conversationId) {
    const conversation = await getConversationById(conversationId);
    await assertConversationAccess(currentUser, conversation);
    const memberState = await getConversationState(currentUser.id, conversationId);
    clearHistoryAt = memberState?.clearHistoryAt
      ? new Date(memberState.clearHistoryAt)
      : null;
    if (
      conversation.type === "broadcast" &&
      !canUserViewAllBroadcastMessages(currentUser, conversation)
    ) {
      restrictedBroadcastConversationIds = [conversationId];
    } else {
      unrestrictedConversationIds = [conversationId];
    }
  } else {
    const conversations = await listConversationsForUser(currentUser);
    for (const conversation of conversations) {
      if (
        conversation.type === "broadcast" &&
        !canUserViewAllBroadcastMessages(currentUser, conversation)
      ) {
        restrictedBroadcastConversationIds.push(conversation.id);
      } else {
        unrestrictedConversationIds.push(conversation.id);
      }
    }
  }

  if (
    unrestrictedConversationIds.length === 0 &&
    restrictedBroadcastConversationIds.length === 0
  ) {
    return {
      messages: [],
      meta: { nextCursor: null, hasMore: false, limit: 0 },
    };
  }

  const baseQuery = {
    isDeleted: { $ne: true },
    content: {
      $regex: sanitized.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
      $options: "i",
    },
  };
  const audienceClauses = [];
  if (unrestrictedConversationIds.length > 0) {
    audienceClauses.push({
      conversationId: { $in: unrestrictedConversationIds },
    });
  }
  if (restrictedBroadcastConversationIds.length > 0) {
    audienceClauses.push({
      conversationId: { $in: restrictedBroadcastConversationIds },
      ...getBroadcastRecipientVisibilityQuery(currentUserId),
    });
  }

  const query =
    audienceClauses.length === 1
      ? {
          ...baseQuery,
          ...audienceClauses[0],
        }
      : {
          ...baseQuery,
          $or: audienceClauses,
        };

  if (cursor) {
    query._id = { $lt: cursor };
  }
  if (clearHistoryAt) {
    query.createdAt = { $gt: clearHistoryAt };
  }

  const pageSize = Math.max(1, Math.min(Number(limit || 30), 100));
  const messages = await Message.find(query)
    .sort({ _id: -1 })
    .limit(pageSize + 1)
    .populate(
      "senderId",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .exec();

  const hasMore = messages.length > pageSize;
  const sliced = hasMore ? messages.slice(0, pageSize) : messages;
  return {
    messages: sliced.map((message) => serializeMessage(message, message.senderId)),
    meta: {
      nextCursor: hasMore ? sliced[sliced.length - 1]._id.toString() : null,
      hasMore,
      limit: pageSize,
    },
  };
}

async function listFavoriteMessages(
  currentUser,
  { cursor = null, limit = 30 } = {}
) {
  const conversations = await listConversationsForUser(currentUser);
  const conversationById = new Map(
    conversations.map((conversation) => [conversation.id, conversation])
  );
  const conversationIds = [...conversationById.keys()];

  if (conversationIds.length === 0) {
    return {
      items: [],
      meta: { nextCursor: null, hasMore: false, limit: 0 },
    };
  }

  const states = await ConversationMemberState.find({
    userId: currentUser.id,
    conversationId: { $in: conversationIds },
  })
    .select("conversationId clearHistoryAt")
    .lean();

  const clearHistoryByConversationId = new Map();
  for (const state of states) {
    if (!state.clearHistoryAt) {
      continue;
    }
    clearHistoryByConversationId.set(
      state.conversationId.toString(),
      new Date(state.clearHistoryAt)
    );
  }

  const pageSize = Math.max(1, Math.min(Number(limit || 30), 100));
  const batchSize = Math.max(pageSize * 3, pageSize + 1);
  const items = [];
  let nextCursor = cursor || null;
  let scannedAll = false;
  let safety = 0;

  while (items.length < pageSize && !scannedAll && safety < 5) {
    safety += 1;

    const query = {
      conversationId: { $in: conversationIds },
      isDeleted: { $ne: true },
      "metadata.favoriteBy": String(currentUser.id),
    };

    if (nextCursor) {
      query._id = { $lt: nextCursor };
    }

    const messages = await Message.find(query)
      .sort({ _id: -1 })
      .limit(batchSize)
      .populate(
        "senderId",
        "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
      )
      .exec();

    if (messages.length === 0) {
      scannedAll = true;
      nextCursor = null;
      break;
    }

    for (const message of messages) {
      nextCursor = message._id.toString();
      const conversationId = message.conversationId.toString();
      const conversation = conversationById.get(conversationId);
      if (!conversation) {
        continue;
      }

      const clearHistoryAt = clearHistoryByConversationId.get(conversationId);
      if (clearHistoryAt && message.createdAt <= clearHistoryAt) {
        continue;
      }

      items.push({
        conversation,
        message: serializeMessage(message, message.senderId),
      });
      if (items.length >= pageSize) {
        break;
      }
    }

    if (messages.length < batchSize) {
      scannedAll = true;
    }
  }

  const hasMore = items.length >= pageSize && !scannedAll;
  return {
    items,
    meta: {
      nextCursor: hasMore ? nextCursor : null,
      hasMore,
      limit: pageSize,
    },
  };
}

async function getUserPresence(currentUser, userId) {
  if (currentUser.role === "user" && currentUser.id !== userId) {
    const visibleUsers = await getVisibleUsersForChat(currentUser);
    if (!visibleUsers.some((entry) => entry.id === userId)) {
      throw new ApiError(403, "Presence access denied.");
    }
  }

  const user = await User.findById(userId).lean();
  if (!user) {
    throw new ApiError(404, "User not found.");
  }

  return {
    userId: user._id.toString(),
    isOnline: Boolean(user.isOnline),
    presenceStatus: user.presenceStatus || (user.isOnline ? "online" : "offline"),
    avatarUrl: normalizeMediaUrl(user.avatarUrl),
    lastSeen: user.lastSeen || null,
    lastActiveAt: user.lastActiveAt || null,
  };
}

async function getMessageAttachment(
  currentUser,
  conversationId,
  storedName,
  { requireDownload = false } = {}
) {
  const conversation = await getConversationById(conversationId);
  await assertConversationAccess(currentUser, conversation);

  const message = await Message.findOne({
    conversationId,
    isDeleted: { $ne: true },
    storedFilePath: {
      $regex: `${storedName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`,
    },
  }).exec();

  if (!message || !message.storedFilePath) {
    throw new ApiError(404, "Attachment not found.");
  }

  const attachmentPolicy =
    message.metadata && typeof message.metadata === "object"
      ? message.metadata.attachmentPolicy
      : null;
  if (
    requireDownload &&
    attachmentPolicy &&
    attachmentPolicy.allowDownload === false
  ) {
    throw new ApiError(403, "Attachment download is disabled by sender.");
  }

  return message;
}

async function requestAttachmentRehydrate(currentUser, messageId) {
  const message = await Message.findOne({
    _id: messageId,
    isDeleted: { $ne: true },
  }).exec();
  if (!message || !message.storedFilePath) {
    throw new ApiError(404, "Attachment not found.");
  }

  const conversation = await getConversationById(message.conversationId);
  await assertConversationAccess(currentUser, conversation);

  const archive = normalizeAttachmentArchiveMetadata(message.metadata);
  if (!archive) {
    throw new ApiError(409, "This attachment cannot be restored automatically.");
  }

  const storedPath = resolveStoredUploadPath(message.storedFilePath);
  const alreadyAvailable = storedPath && (await fileExists(storedPath));
  return {
    requested: !alreadyAvailable,
    alreadyAvailable,
    targetUserId: message.senderId.toString(),
    payload: {
      messageId: message._id.toString(),
      conversationId: message.conversationId.toString(),
      fileName: message.fileName || "attachment",
      fileSize: Number(message.fileSize || archive.fileSize || 0),
      mimeType: message.mimeType || null,
      sha256: archive.sha256,
      requesterId: currentUser.id || currentUser._id?.toString?.() || null,
    },
  };
}

async function restoreAttachmentFromSender(currentUser, messageId, file) {
  const message = await Message.findOne({
    _id: messageId,
    isDeleted: { $ne: true },
  }).exec();
  if (!message || !message.storedFilePath) {
    if (file?.path) await deleteFileIfExists(file.path);
    throw new ApiError(404, "Attachment not found.");
  }
  if (message.senderId.toString() !== String(currentUser.id)) {
    if (file?.path) await deleteFileIfExists(file.path);
    throw new ApiError(403, "Only the original sender can restore this file.");
  }

  const archive = normalizeAttachmentArchiveMetadata(message.metadata);
  if (!archive) {
    if (file?.path) await deleteFileIfExists(file.path);
    throw new ApiError(409, "This attachment cannot be restored automatically.");
  }
  if (!file?.path) {
    throw new ApiError(400, "A restore file is required.");
  }
  if (Number(file.size || 0) !== Number(archive.fileSize || 0)) {
    await deleteFileIfExists(file.path);
    throw new ApiError(400, "Restore file size does not match.");
  }

  const uploadedHash = await calculateFileSha256(file.path);
  if (uploadedHash !== archive.sha256) {
    await deleteFileIfExists(file.path);
    throw new ApiError(400, "Restore file checksum does not match.");
  }

  const targetPath = resolveStoredUploadPath(message.storedFilePath);
  if (!targetPath) {
    await deleteFileIfExists(file.path);
    throw new ApiError(409, "Stored attachment path is invalid.");
  }
  await ensureDirectory(path.dirname(targetPath));
  await fs.promises.copyFile(file.path, targetPath);
  await deleteFileIfExists(file.path);

  message.metadata = {
    ...(message.metadata && typeof message.metadata === "object"
      ? message.metadata
      : {}),
    attachmentArchive: {
      ...archive,
      restoredAt: new Date().toISOString(),
    },
  };
  await message.save();

  const populated = await Message.findById(message._id)
    .populate(
      "senderId",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .exec();
  return serializeMessage(populated, populated.senderId);
}

async function votePollMessage(currentUser, messageId, optionIds) {
  const message = await Message.findById(messageId);
  if (!message || message.isDeleted || message.messageType !== "poll") {
    throw new ApiError(404, "الاستطلاع غير موجود أو محذوف.");
  }
  const conversation = await getConversationById(message.conversationId);
  await assertConversationAccess(currentUser, conversation);

  let metadata = message.metadata || {};
  if (metadata.isClosed) {
    throw new ApiError(400, "التصويت مغلق في هذا الاستطلاع.");
  }
  if (!metadata.options || !Array.isArray(metadata.options)) {
    throw new ApiError(400, "بيانات الاستطلاع تالفة.");
  }
  if (!metadata.isMultipleChoice && optionIds.length > 1) {
    throw new ApiError(400, "هذا الاستطلاع لا يسمح باختيارات متعددة.");
  }

  // Remove the user from all previous votes
  if (!metadata.votes) metadata.votes = {};
  for (const key of Object.keys(metadata.votes)) {
    metadata.votes[key] = (metadata.votes[key] || []).filter(
      (id) => id !== currentUser.id
    );
  }

  // Add the user to the selected options
  for (const optId of optionIds) {
    const optionExists = metadata.options.find((o) => String(o.id) === String(optId));
    if (optionExists) {
      if (!metadata.votes[String(optId)]) metadata.votes[String(optId)] = [];
      metadata.votes[String(optId)].push(currentUser.id);
    }
  }

  message.metadata = metadata;
  message.markModified("metadata");
  await message.save();

  const populated = await Message.findById(message._id)
    .populate(
      "senderId",
      "username fullName role departmentId isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt"
    )
    .exec();

  let audienceUserIds;
  if (conversation.type === "broadcast") {
    const publisherIds = extractIdArray(conversation.broadcastPublisherIds);
    audienceUserIds = Array.from(
      new Set([...extractIdArray(conversation.members), ...publisherIds])
    );
  } else {
    audienceUserIds = extractIdArray(conversation.members);
  }

  return {
    audienceUserIds,
    message: serializeMessage(populated, populated.senderId),
  };
}

async function exportPollToExcel(currentUser, messageId) {
  const message = await Message.findById(messageId).populate("senderId");
  if (!message || message.isDeleted || message.messageType !== "poll") {
    throw new ApiError(404, "الاستطلاع غير موجود أو محذوف.");
  }
  const conversation = await getConversationById(message.conversationId);
  await assertConversationAccess(currentUser, conversation);

  const isAdmin = currentUser.role === "admin" || currentUser.role === "superadmin";
  const isCreator = String(message.senderId._id) === currentUser.id;
  if (!isAdmin && !isCreator) {
    throw new ApiError(403, "ليس لديك صلاحية لتصدير نتائج هذا الاستطلاع.");
  }

  const metadata = message.metadata || {};
  const question = metadata.question || "استطلاع رأي";
  const options = metadata.options || [];
  const votes = metadata.votes || {};
  const isAnonymous = metadata.isAnonymous === true;

  const workbook = new exceljs.Workbook();
  const sheet = workbook.addWorksheet("نتائج الاستطلاع");

  sheet.addRow(["السؤال:", question]);
  sheet.addRow(["مجهول:", isAnonymous ? "نعم" : "لا"]);
  sheet.addRow([]);

  // Header row
  if (isAnonymous) {
    sheet.addRow(["الخيار", "عدد الأصوات", "النسبة"]);
  } else {
    sheet.addRow(["الخيار", "عدد الأصوات", "النسبة", "المصوتون"]);
  }
  
  // formatting header
  const headerRow = sheet.lastRow;
  headerRow.font = { bold: true };
  headerRow.fill = {
    type: "pattern",
    pattern: "solid",
    fgColor: { argb: "FFD3D3D3" },
  };

  let totalVotes = 0;
  for (const opt of options) {
    totalVotes += (votes[String(opt.id)] || []).length;
  }

  // Populate data
  for (const opt of options) {
    const voterIds = votes[String(opt.id)] || [];
    const count = voterIds.length;
    const percentage = totalVotes > 0 ? ((count / totalVotes) * 100).toFixed(1) + "%" : "0%";
    
    if (isAnonymous) {
      sheet.addRow([opt.text, count, percentage]);
    } else {
      // Need to fetch user names
      const users = await User.find({ _id: { $in: voterIds } }).select("fullName username").lean();
      const userNames = users.map(u => u.fullName || u.username).join(", ");
      sheet.addRow([opt.text, count, percentage, userNames]);
    }
  }

  sheet.columns.forEach((column) => {
    column.width = 30;
    column.alignment = { wrapText: true, vertical: "top", horizontal: "right" };
  });

  sheet.views = [{ rightToLeft: true }];

  const buffer = await workbook.xlsx.writeBuffer();
  return {
    buffer,
    filename: `Poll_${Date.now()}.xlsx`,
  };
}

module.exports = {
  votePollMessage,
  exportPollToExcel,
  serializeUserLite,
  serializeConversation,
  serializeMessage,
  getConversationRoom,
  getConversationById,
  getConversationSnapshotForUserId,
  getVisibleUsersForChat,
  listConversationsForUser,
  listManageableConversations,
  getConversationDetailsForUser,
  createConversation,
  updateConversation,
  deleteConversation,
  listMessagesForConversation,
  createMessage,
  updateMessage,
  toggleMessageReaction,
  toggleMessageFavorite,
  markConversationDelivered,
  markPendingDeliveriesForUser,
  markConversationSeen,
  markMessageSeen,
  deleteMessage,
  updateConversationPreferences,
  setConversationPinnedMessage,
  clearConversationPinnedMessage,
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
  assertConversationAccess,
  assertConversationManagementAccess,
};

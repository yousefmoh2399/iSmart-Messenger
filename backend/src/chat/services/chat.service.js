const mongoose = require("mongoose");
const path = require("path");
const fs = require("fs");
const crypto = require("crypto");
const Conversation = require("../models/conversation.model");
const Message = require("../models/message.model");
const Department = require("../models/department.model");
const ConversationMemberState = require("../models/conversation-member-state.model");
const User = require("../../models/user.model");
const ApiError = require("../../utils/api-error");
const logger = require("../../utils/logger");
const { deleteFileIfExists } = require("../../utils/file.util");
const exceljs = require("exceljs");
const {
  ensureDirectory,
  fileExists,
  getConversationAvatarUploadsDir,
  resolveStoredUploadPath,
  toRelativeUploadPath,
} = require("../../utils/storage-paths");
const { userHasPermission } = require("./role.service");
const { logAuditEvent } = require("./audit.service");
const {
  ensureConversationMemberStates,
  markConversationMemberRemoved,
  markConversationMemberLeft,
  markConversationMemberBlocked,
  markConversationMemberUnblocked,
  removeConversationMemberState,
  syncConversationMemberStates,
  incrementUnreadCounts,
  markConversationRead,
  getUnreadCountsForUser,
  getConversationState,
  clearConversationHistoryForUser,
  deleteConversationForUser,
  updateConversationState,
} = require("./chat-member-state.service");
const { classifyAttachment } = require("./chat-attachment.service");

function getObjectIdString(value) {
  if (!value) return null;
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (/^[a-fA-F0-9]{24}$/.test(trimmed)) return trimmed;
    const match = trimmed.match(/['"]?_?id['"]?\s*[:=]\s*(?:new\s+ObjectId\(['"])?([a-fA-F0-9]{24})['"]?\)?/i);
    if (match && match[1]) return match[1];
    return null;
  }
  if (value._id) {
    const str = value._id.toString();
    if (/^[a-fA-F0-9]{24}$/.test(str)) return str;
  }
  if (value.id) {
    const str = value.id.toString();
    if (/^[a-fA-F0-9]{24}$/.test(str)) return str;
  }
  if (typeof value.toString === "function") {
    const str = value.toString();
    if (/^[a-fA-F0-9]{24}$/.test(str)) return str;
  }
  return null;
}

function toMatchObjectIds(id) {
  if (!id) return [];
  const str = String(id).trim();
  const values = [str];
  if (mongoose.Types.ObjectId.isValid(str)) {
    try {
      values.push(new mongoose.Types.ObjectId(str));
    } catch (_) {}
  }
  return values;
}

function sanitizeMessageContent(value) {
  return String(value || "")
    .replace(/\r\n|\r/g, "\n")
    .replace(/[^\S\r\n]+/g, " ")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{4,}/g, "\n\n\n")
    .trim()
    .slice(0, 5000);
}

function sanitizeText(value, maxLength = 500) {
  return String(value || "")
    .trim()
    .slice(0, maxLength);
}

function sanitizePinnedMessageContent(value) {
  return String(value || "")
    .replace(/\r\n|\r/g, "\n")
    .replace(/[^\S\r\n]+/g, " ")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{4,}/g, "\n\n\n")
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
  "checklist",
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
    new Set((values || []).filter((entry) => isMongoIdLike(entry)).map(String)),
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
  if (nextMetadata.allowForward === false || rawPolicy?.allowForward === false) {
    nextMetadata.allowForward = false;
  }
  return nextMetadata;
}

function normalizeAttachmentArchiveMetadata(metadata) {
  const source =
    metadata && typeof metadata === "object"
      ? metadata.attachmentArchive
      : null;
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
        .map((entry) =>
          String(entry || "")
            .trim()
            .toUpperCase(),
        )
        .filter(Boolean),
    ),
  );
}

function normalizeDepartmentNameList(rawDepartmentNames) {
  return Array.from(
    new Set(
      (rawDepartmentNames || [])
        .map((entry) =>
          String(entry || "")
            .trim()
            .toLowerCase(),
        )
        .filter(Boolean),
    ),
  );
}

async function resolveBroadcastTargetDepartmentIds(rawTargets) {
  const targets =
    rawTargets && typeof rawTargets === "object" ? rawTargets : {};

  const idMatches = normalizeBroadcastTargetDepartmentIds(
    targets.departmentIds,
  );
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
          (entry) => new RegExp(`^${escapeRegExp(entry)}$`, "i"),
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

  const publisherIds = new Set(
    extractIdArray(conversation?.broadcastPublisherIds),
  );
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
      id: null,
      content: "",
      senderId: null,
      senderName: "",
      messageType: null,
      seenBy: [],
      deliveredTo: [],
      status: "sent",
      createdAt: null,
    };
  }

  const senderId = getObjectIdString(message.senderId?._id || message.senderId);
  const senderName =
    message.senderId && typeof message.senderId === "object"
      ? message.senderId.fullName || message.senderId.username || ""
      : message.senderName || "";

  let content = message.content || message.fileName || "";
  if (!content && message.messageType === "system") {
    content = "رسالة النظام";
  }

  // For poll/checklist messages with empty content, derive preview from question
  if (!content) {
    const meta = message.metadata || {};
    if (message.messageType === "poll") {
      content = meta.question ? `📊 ${meta.question}` : "📊 استطلاع رأي";
    } else if (message.messageType === "checklist") {
      content = meta.question ? `✅ ${meta.question}` : "✅ قائمة مهام";
    }
  }

  const rawSeenBy = message.seenBy || [];
  const rawDeliveredTo = message.deliveredTo || [];

  const seenBy = rawSeenBy
    .filter((entry) => getObjectIdString(entry.userId || entry) !== senderId)
    .map((entry) => ({
      userId: getObjectIdString(entry.userId || entry),
      at: entry.at || entry.seenAt || new Date(),
    }));

  const deliveredTo = rawDeliveredTo
    .filter((entry) => getObjectIdString(entry.userId || entry) !== senderId)
    .map((entry) => ({
      userId: getObjectIdString(entry.userId || entry),
      at: entry.at || entry.deliveredAt || new Date(),
    }));

  const status =
    message.status ||
    (seenBy.length > 0 ? "read" : deliveredTo.length > 0 ? "delivered" : "sent");

  return {
    id: message._id ? message._id.toString() : (message.id ? message.id.toString() : null),
    content,
    senderId,
    senderName,
    messageType: message.messageType || null,
    seenBy,
    deliveredTo,
    status,
    createdAt: message.createdAt || null,
  };
}

function isAdminRole(role) {
  return (
    String(role || "")
      .trim()
      .toLowerCase() === "admin"
  );
}

function serializeUserLite(user) {
  if (!user) {
    return {
      id: "",
      username: "",
      fullName: "",
      jobTitle: "",
      role: "user",
      departmentId: null,
      departmentIds: [],
      branchId: null,
      branchCode: "MAIN",
      isOnline: false,
      presenceStatus: "offline",
      isActive: false,
      avatarUrl: null,
      lastSeen: null,
      lastActiveAt: null,
    };
  }
  const id = (user._id || user.id || "").toString();
  return {
    id,
    username: user.username || "",
    fullName: user.fullName || "",
    jobTitle: user.jobTitle || "",
    role: user.role || "user",
    departmentId: user.departmentId ? user.departmentId.toString() : null,
    departmentIds: Array.isArray(user.departmentIds)
      ? user.departmentIds.filter(Boolean).map((entry) => entry.toString())
      : user.departmentId
        ? [user.departmentId.toString()]
        : [],
    branchId: user.branchId ? user.branchId.toString() : null,
    branchCode: String(user.branchCode || "main")
      .trim()
      .toUpperCase(),
    isOnline: Boolean(user.isOnline),
    presenceStatus:
      user.presenceStatus || (user.isOnline ? "online" : "offline"),
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
  const userId = entry.userId?._id
    ? entry.userId._id.toString()
    : (entry.userId?.toString?.() || "");
  return {
    userId,
    at: entry.at,
  };
}

async function serializeConversation(conversation, currentUserId) {
  const members = (conversation.members || [])
    .filter(Boolean)
    .map((member) =>
      member._id ? serializeUserLite(member) : { id: member.toString() },
    );
  const admins = (conversation.admins || [])
    .filter(Boolean)
    .map((admin) =>
      admin._id ? serializeUserLite(admin) : { id: admin.toString() },
    );

  const memberState = await ConversationMemberState.findOne({
    conversationId: conversation._id,
    userId: currentUserId,
  })
    .select(
      "unreadCount isArchived isMuted mutedUntil isPinned isFavorite clearHistoryAt membershipStatus removedAt leftAt blockedAt"
    )
    .lean();

  const currentUserIdStr = currentUserId ? String(currentUserId) : "";
  const memberIdsList = (conversation.members || []).map(getObjectIdString).filter(Boolean);
  const isCurrentlyInMembers = memberIdsList.includes(currentUserIdStr);

  const blockedList = (conversation.blockedMembers || []).map(getObjectIdString).filter(Boolean);
  const isUserBlocked = blockedList.includes(currentUserIdStr) || memberState?.membershipStatus === "blocked";

  const publisherIdsList = (conversation.broadcastPublisherIds || []).map(getObjectIdString).filter(Boolean);
  const adminIdsList = (conversation.admins || []).map(getObjectIdString).filter(Boolean);
  const createdByIdStr = getObjectIdString(conversation.createdBy);

  const isDept = conversation.type === "department";
  const isBcast = conversation.type === "broadcast";
  const isMemberOrValidAudience =
    isCurrentlyInMembers ||
    isDept ||
    (isBcast && (
      adminIdsList.includes(currentUserIdStr) ||
      publisherIdsList.includes(currentUserIdStr) ||
      createdByIdStr === currentUserIdStr
    ));

  const effectiveStatus = memberState?.membershipStatus || (isMemberOrValidAudience ? "active" : "removed");
  const isCurrentlyActiveMember = (isMemberOrValidAudience || isCurrentlyInMembers) && effectiveStatus === "active" && !isUserBlocked;

  let canSend = isCurrentlyActiveMember && !isUserBlocked && conversation.isActive !== false;
  if (conversation.type === "broadcast") {
    canSend = !isUserBlocked && conversation.isActive !== false && (
      adminIdsList.includes(currentUserIdStr) ||
      publisherIdsList.includes(currentUserIdStr) ||
      createdByIdStr === currentUserIdStr
    );
  }

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

  let normalizedLastMessage = null;
  const cutoffDate = (!isCurrentlyActiveMember && (memberState?.removedAt || memberState?.leftAt || memberState?.blockedAt))
    ? new Date(memberState.removedAt || memberState.leftAt || memberState.blockedAt)
    : null;

  if (cutoffDate) {
    const lastHistMessage = await Message.findOne({
      conversationId: conversation._id,
      isDeleted: { $ne: true },
      createdAt: {
        $lte: cutoffDate,
        ...(clearHistoryAt ? { $gt: clearHistoryAt } : {}),
      },
      ...(conversation.type === "broadcast"
        ? getBroadcastRecipientVisibilityQuery(currentUserIdStr)
        : {}),
    })
      .sort({ _id: -1 })
      .populate("senderId", "username fullName")
      .lean();

    normalizedLastMessage = lastHistMessage ? buildLastMessagePayload(lastHistMessage) : null;
  } else {
    normalizedLastMessage = shouldHideLastMessage
      ? {
          id: null,
          content: "",
          senderId: null,
          senderName: "",
          messageType: null,
          seenBy: [],
          deliveredTo: [],
          status: "sent",
          createdAt: null,
        }
      : (conversation.lastMessage ? buildLastMessagePayload(conversation.lastMessage) : null);
  }

  const now = new Date();
  const mutedUntil = memberState?.mutedUntil
    ? new Date(memberState.mutedUntil)
    : null;
  const isMuted = Boolean(
    memberState?.isMuted &&
      (!mutedUntil || mutedUntil.getTime() > now.getTime())
  );

  return {
    id: conversation._id.toString(),
    type: conversation.type,
    name: conversation.name,
    description: conversation.description || "",
    avatarUrl: conversation.avatarUrl ? normalizeMediaUrl(conversation.avatarUrl) : null,
    departmentId: conversation.departmentId
      ? conversation.departmentId._id
        ? conversation.departmentId._id.toString()
        : conversation.departmentId.toString()
      : null,
    createdBy: conversation.createdBy?._id
      ? conversation.createdBy._id.toString()
      : conversation.createdBy?.toString?.() || conversation.createdBy,
    members,
    admins,
    broadcastPublisherIds: (() => {
      const raw = (conversation.broadcastPublisherIds || [])
        .filter(Boolean)
        .map((entry) => (entry._id ? entry._id.toString() : entry.toString()));
      if (conversation.type !== "broadcast") {
        return raw;
      }
      const creatorId = conversation.createdBy?._id
        ? conversation.createdBy._id.toString()
        : conversation.createdBy?.toString?.() || conversation.createdBy;
      const adminIdSet = new Set([
        ...(creatorId ? [String(creatorId)] : []),
        ...(conversation.admins || []).map((e) => (e._id ? e._id.toString() : e.toString())),
      ]);
      const totalMembersCount = (conversation.members || []).length;
      if (totalMembersCount > 1 && raw.length >= totalMembersCount) {
        return Array.from(adminIdSet);
      }
      return raw;
    })(),
    blockedMemberIds: (conversation.blockedMembers || [])
      .filter(Boolean)
      .map((entry) => (entry._id ? entry._id.toString() : entry.toString())),
    blockedMembers: (conversation.blockedMembers || [])
      .filter(Boolean)
      .map((entry) =>
        entry._id ? serializeUserLite(entry) : { id: entry.toString() },
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
    isMuted,
    mutedUntil: isMuted && mutedUntil ? mutedUntil.toISOString() : null,
    isPinned: memberState?.isPinned || false,
    isFavorite: memberState?.isFavorite || false,
    isActive: conversation.isActive !== false,
    isMember: isCurrentlyActiveMember,
    membershipStatus: effectiveStatus,
    isBlocked: isUserBlocked,
    canSend,
    createdAt: conversation.createdAt,
    updatedAt: conversation.updatedAt,
      deletedAt: conversation.deletedAt || null,
    };
}

function serializeMessage(message, sender = null) {
  const metadata = message.metadata ? { ...message.metadata } : {};
  delete metadata.status;
  delete metadata.error;
  const clientMessageId =
    message.clientMessageId || metadata.clientMessageId || null;
  if (clientMessageId && !metadata.clientMessageId) {
    metadata.clientMessageId = clientMessageId;
  }
  const senderId = message.senderId?._id
    ? message.senderId._id.toString()
    : (message.senderId?.toString?.() || "");
  return {
    id: message._id.toString(),
    conversationId: message.conversationId.toString(),
    senderId,
    sender: sender ? serializeUserLite(sender) : null,
    content: message.content,
    clientMessageId,
    messageType: message.messageType,
    fileUrl: message.fileUrl,
    fileName: message.fileName,
    fileSize: message.fileSize || null,
    mimeType: message.mimeType || null,
    replyToMessageId: message.replyToMessageId?.toString?.() || null,
    isDeleted: message.isDeleted === true,
    isScheduled: message.isScheduled === true,
    scheduledFor: message.scheduledFor || null,
    metadata: Object.keys(metadata).length > 0 ? metadata : null,
    createdAt: message.createdAt,
    updatedAt: message.updatedAt,
    seenBy: (message.seenBy || [])
      .filter((entry) => {
        const uid = entry.userId?._id
          ? entry.userId._id.toString()
          : (entry.userId?.toString?.() || "");
        return uid && uid !== senderId;
      })
      .map(serializeReceipt),
    deliveredTo: (message.deliveredTo || [])
      .filter((entry) => {
        const uid = entry.userId?._id
          ? entry.userId._id.toString()
          : (entry.userId?.toString?.() || "");
        return uid && uid !== senderId;
      })
      .map(serializeReceipt),
  };
}

async function getOnlineActiveUserIds(userIds) {
  const uniqueIds = Array.from(
    new Set((userIds || []).filter(Boolean).map(String)),
  );
  if (uniqueIds.length === 0) {
    return [];
  }

  const users = await User.find(
    {
      _id: { $in: uniqueIds },
      isActive: true,
      isOnline: true,
    },
    "_id",
  ).lean();

  return users.map((entry) => entry._id.toString());
}

async function buildDeliveryReceipts(userIds) {
  const onlineUserIds = await getOnlineActiveUserIds(userIds);
  return onlineUserIds.map((userId) => ({ userId, at: new Date() }));
}

async function createSystemConversationMessage(conversation, actor, payload) {
  const recipientIds = (conversation.members || [])
    .filter(Boolean)
    .map((entry) => (entry._id ? entry._id.toString() : entry.toString()))
    .filter((userId) => userId !== actor.id);

  const message = await Message.create({
    conversationId: conversation._id,
    senderId: actor.id,
    content: sanitizeMessageContent(payload.content),
    messageType: "system",
    seenBy: [],
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
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
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
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
    )
    .exec();

  const nextLastMessage = buildLastMessagePayload(latestMessage);

  await Conversation.updateOne(
    { _id: conversationId },
    {
      $set: {
        lastMessage: nextLastMessage,
      },
    },
  );
}

function getConversationRoom(conversationId) {
  return `conversation:${conversationId}`;
}

function isDepartmentDefaultConversation(conversation) {
  if (conversation?.type !== "department") {
    return false;
  }

  const conversationId = getObjectIdString(
    conversation?._id || conversation?.id,
  );
  const defaultConversationId = getObjectIdString(
    conversation?.departmentId?.defaultConversationId,
  );
  if (
    conversationId &&
    defaultConversationId &&
    conversationId === defaultConversationId
  ) {
    return true;
  }

  const name = String(conversation?.name || "")
    .trim()
    .toLowerCase();
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
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
    )
    .populate(
      "admins",
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
    )
    .populate(
      "blockedMembers",
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
    )
    .populate("departmentId", "name code defaultConversationId")
    .exec();
}

async function getVisibleUsersForChat(currentUser, options = {}) {
  const search = sanitizeText(options.search || options.q || "", 120);
  const shouldPaginate =
    options.page !== undefined || options.limit !== undefined;
  const page = Math.max(1, Math.min(Number(options.page || 1), 100000));
  const limit = Math.max(1, Math.min(Number(options.limit || 50), 5000));
  const skip = (page - 1) * limit;
  const query = {
    isActive: true,
    _id: { $ne: currentUser.id },
  };

  const andConditions = [];

  if (search) {
    const regex = new RegExp(escapeRegExp(search), "i");
    andConditions.push({
      $or: [
        { username: regex },
        { fullName: regex },
        { branchCode: regex },
        { jobTitle: regex },
      ],
    });
  }
  if (options.departmentId) {
    const matchValues = toMatchObjectIds(options.departmentId);
    andConditions.push({
      $or: [
        { departmentId: { $in: matchValues } },
        { departmentIds: { $in: matchValues } },
      ],
    });
  }
  if (options.branchId) {
    andConditions.push({
      $or: [
        { branchId: options.branchId },
        { branchCode: options.branchId },
      ],
    });
  }

  if (andConditions.length > 0) {
    query.$and = andConditions;
  }

  const usersQuery = User.find(query).sort({
    fullName: 1,
    username: 1,
    _id: 1,
  });
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
  const memberIds = (conversation.members || [])
    .filter(Boolean)
    .map((entry) => (entry._id ? entry._id.toString() : entry.toString()));

  if (conversation.type === "department") {
    const conversationDepartmentId =
      conversation.departmentId?._id?.toString?.() ||
      conversation.departmentId?.toString?.() ||
      null;
    const currentUserDepartmentId = getObjectIdString(currentUser.departmentId);
    const currentUserDeptIds = [
      ...(currentUserDepartmentId ? [currentUserDepartmentId] : []),
      ...(Array.isArray(currentUser.departmentIds)
        ? currentUser.departmentIds.map((d) => getObjectIdString(d)).filter(Boolean)
        : []),
    ];
    if (currentUserDeptIds.includes(conversationDepartmentId)) {
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
    const memberState = await getConversationState(currentUserId, conversation._id);
    if (memberState && !memberState.isDeleted) {
      return;
    }
    throw new ApiError(403, "Conversation access denied.");
  }

  if (conversation.type === "direct" && currentUser.role === "user") {
    const otherMembers = (conversation.members || [])
      .filter(Boolean)
      .filter((entry) => {
        const entryId = entry._id ? entry._id.toString() : entry.toString();
        return entryId !== currentUserId;
      });
    if (otherMembers.length > 0) {
      const target = otherMembers[0];
      if (isRestrictedDirectTarget(currentUser, target)) {
        throw new ApiError(403, "Conversation access denied.");
      }
    }
  }

  if (!memberIds.includes(currentUserId)) {
    const memberState = await getConversationState(currentUserId, conversation._id);
    if (memberState && !memberState.isDeleted) {
      return;
    }
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

  if (conversation.type === "broadcast") {
    const canSendBroadcast = await userHasPermission(
      currentUser,
      "canSendBroadcast",
    );
    if (canSendBroadcast) {
      return;
    }
  }

  if (conversation.type === "direct") {
    const memberIds = (conversation.members || [])
      .filter(Boolean)
      .map((entry) => (entry._id ? entry._id.toString() : entry.toString()));
    const currentUserId = getObjectIdString(currentUser.id || currentUser._id);
    if (currentUserId && memberIds.includes(currentUserId)) {
      return;
    }
  }

  const adminIds = (conversation.admins || [])
    .filter(Boolean)
    .map((entry) => (entry._id ? entry._id.toString() : entry.toString()));
  const currentUserId = getObjectIdString(currentUser.id || currentUser._id);
  const createdById = getObjectIdString(conversation.createdBy);
  if (currentUserId && (adminIds.includes(currentUserId) || createdById === currentUserId)) {
    return;
  }

  if (conversation.type === "department") {
    const conversationDeptId = getObjectIdString(conversation.departmentId);
    const currentUserDeptIds = [
      ...(currentUser.departmentId ? [getObjectIdString(currentUser.departmentId)] : []),
      ...(Array.isArray(currentUser.departmentIds)
        ? currentUser.departmentIds.map((d) => getObjectIdString(d)).filter(Boolean)
        : []),
    ];
    if (currentUserDeptIds.includes(conversationDeptId)) {
      const canModerateDepartment = await userHasPermission(
        currentUser,
        "canModerateDepartment",
      );
      if (canModerateDepartment) {
        return;
      }
    }
  }

  throw new ApiError(403, "Conversation management denied.");
}

function assertGroupOwnerAccess(currentUser, conversation) {
  if (!conversation || conversation.deletedAt) {
    throw new ApiError(404, "Conversation not found.");
  }

  if (conversation.type !== "group" && conversation.type !== "broadcast") {
    throw new ApiError(
      400,
      "This action is available for group and broadcast conversations only.",
    );
  }

  const currentUserId = getObjectIdString(currentUser.id || currentUser._id);
  const isSystemAdmin = currentUser.role === "admin";
  const isCreator = currentUserId && conversation.createdBy?.toString() === currentUserId;
  const isConversationAdmin = (conversation.admins || []).some(
    (a) => getObjectIdString(a) === currentUserId,
  );

  if (!isSystemAdmin && !isCreator && !isConversationAdmin) {
    throw new ApiError(403, "Only the conversation creator or admin can manage members.");
  }
}

async function listConversationsForUser(currentUser) {
  const currentUserId = getObjectIdString(currentUser.id || currentUser._id);

  const userMemberStates = await ConversationMemberState.find({
    userId: currentUserId,
    isDeleted: { $ne: true },
  })
    .select("conversationId")
    .lean();
  const validMemberConvIds = userMemberStates
    .map((s) => s.conversationId)
    .filter(Boolean);

  const query = {
    deletedAt: null,
    $or: [{ members: currentUserId }, { _id: { $in: validMemberConvIds } }],
  };

  const userDeptIds = Array.from(
    new Set([
      ...(currentUser.departmentId ? [currentUser.departmentId] : []),
      ...(Array.isArray(currentUser.departmentIds) ? currentUser.departmentIds : []),
    ].map((d) => getObjectIdString(d)).filter(Boolean)),
  );

  if (userDeptIds.length > 0) {
    query.$or.push({
      type: "department",
      departmentId: { $in: userDeptIds },
    });
  }

  query.$or.push(
    { createdBy: currentUserId },
    { admins: currentUserId },
    { broadcastPublisherIds: currentUserId },
  );

  const conversations = await Conversation.find(query)
    .sort({ updatedAt: -1 })
    .populate(
      "members",
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
    )
    .populate(
      "admins",
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
    )
    .populate("departmentId", "name code defaultConversationId")
    .lean({ getters: true });

  const unreadByConversation = await getUnreadCountsForUser(currentUser.id);
  const visible = [];

  for (const conversation of conversations) {
    try {
      await assertConversationAccess(currentUser, conversation);
      if (isDepartmentDefaultConversation(conversation)) {
        continue;
      }
      const memberState = await getConversationState(
        currentUser.id,
        conversation._id,
      );
      if (memberState?.isDeleted) {
        continue;
      }
      const serialized = await serializeConversation(
        conversation,
        currentUser.id,
      );
      if (
        conversation.type === "broadcast" &&
        serialized.isMember &&
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
        unreadCount: serialized.isMember
          ? (unreadByConversation[serialized.id] || serialized.unreadCount || 0)
          : 0,
      });
    } catch (_) {
      // Skip unauthorized conversation
    }
  }

  return visible;
}

async function listManageableConversations(currentUser) {
  const isAdmin = currentUser.role === "admin";
  const [canCreateRooms, canSendBroadcast] = await Promise.all([
    isAdmin ? true : userHasPermission(currentUser, "canCreateRooms"),
    isAdmin ? true : userHasPermission(currentUser, "canSendBroadcast"),
  ]);
  const hasGlobalRoomAccess = isAdmin || canCreateRooms;

  let query;
  if (hasGlobalRoomAccess) {
    query = {
      deletedAt: null,
      type: { $in: ["group", "department", "broadcast"] },
    };
  } else {
    const orClauses = [
      { admins: currentUser.id },
      { createdBy: currentUser.id },
      ...((() => {
        const userDeptIds = [
          ...(currentUser.departmentId ? [currentUser.departmentId] : []),
          ...(Array.isArray(currentUser.departmentIds) ? currentUser.departmentIds : []),
        ].filter(Boolean);
        return userDeptIds.length
          ? [{ type: "department", departmentId: { $in: userDeptIds } }]
          : [];
      })()),
      ...(canSendBroadcast ? [{ type: "broadcast" }] : []),
    ];
    query = {
      deletedAt: null,
      type: { $in: ["group", "department", "broadcast"] },
      $or: orClauses,
    };
  }

  const conversations = await Conversation.find(query)
    .sort({ updatedAt: -1 })
    .populate(
      "members",
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
    )
    .populate(
      "admins",
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
    )
    .populate("departmentId", "name code defaultConversationId")
    .lean({ getters: true });

  const visible = [];
  for (const conversation of conversations) {
    if (!conversation || conversation.type === "direct") {
      continue;
    }
    try {
      visible.push(await serializeConversation(conversation, currentUser.id));
    } catch (_) {
      // Skip malformed conversation without failing the entire manageable list
    }
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
    new Set([...(payload.memberIds || [])].filter(Boolean).map(String)),
  );
  const description = sanitizeText(payload.description, 500);
  const name = sanitizeText(payload.name, 200);

  if (!["direct", "group", "department", "broadcast"].includes(type)) {
    throw new ApiError(400, "Invalid conversation type.");
  }

  if (type === "direct") {
    if (memberIds.length !== 1) {
      throw new ApiError(
        400,
        "Direct conversation requires exactly one target user.",
      );
    }

    const isSelf = memberIds[0] === currentUser.id;
    const targetUser = isSelf
      ? currentUser
      : await User.findById(memberIds[0]).lean();
    if (!targetUser) {
      throw new ApiError(404, "Target user not found.");
    }
    if (!isSelf && isRestrictedDirectTarget(currentUser, targetUser)) {
      throw new ApiError(403, "Direct conversation is not allowed.");
    }

    const directMemberIds = isSelf
      ? [currentUser.id]
      : [currentUser.id, memberIds[0]].sort();
    const directKey = isSelf
      ? `${currentUser.id}:${currentUser.id}`
      : directMemberIds.join(":");
    const existing = await Conversation.findOne({
      directKey,
      deletedAt: null,
      isActive: true,
    })
      .populate(
        "members",
        "username fullName role departmentId departmentIds isOnline isActive lastSeen",
      )
      .populate(
        "admins",
        "username fullName role departmentId departmentIds isOnline isActive lastSeen",
      )
      .exec();

    if (existing) {
      await ConversationMemberState.updateOne(
        { conversationId: existing._id, userId: currentUser.id },
        { $set: { isDeleted: false, deletedAt: null } }
      );
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
    if (!name) {
      throw new ApiError(400, "Group name is required.");
    }
    if (!Array.isArray(memberIds) || memberIds.length === 0) {
      throw new ApiError(400, "Group must have at least one member.");
    }
    const adminIds = Array.from(
      new Set([currentUser.id, ...(payload.adminIds || []).map(String)]),
    );
    const members = Array.from(new Set([currentUser.id, ...memberIds, ...adminIds]));
    const conversation = await Conversation.create({
      type,
      name,
      description,
      avatarUrl: payload.avatarUrl || null,
      createdBy: currentUser.id,
      members,
      admins: adminIds,
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
      avatarUrl: payload.avatarUrl || null,
      departmentId: department._id,
      createdBy: currentUser.id,
      members: memberIds,
      admins: [
        currentUser.id,
        ...new Set((payload.adminIds || []).map(String)),
      ],
    });
    await ensureConversationMemberStates(conversation._id, memberIds);
    return getConversationDetailsForUser(currentUser, conversation._id);
  }

  const canSendBroadcast = await userHasPermission(
    currentUser,
    "canSendBroadcast",
  );
  if (!canSendBroadcast && currentUser.role !== "admin") {
    throw new ApiError(403, "Permission denied.");
  }

  const requestedMemberIds = normalizeIdList(payload.memberIds);
  const requestedAdminIds = normalizeIdList(payload.adminIds);
  const requestedPublisherIds = normalizeIdList(
    payload.broadcastPublisherIds || payload.publisherIds,
  );

  const allCandidateIds = Array.from(
    new Set([
      currentUser.id,
      ...requestedMemberIds,
      ...requestedAdminIds,
      ...requestedPublisherIds,
    ]),
  );
  const existingUsers = await User.find(
    { _id: { $in: allCandidateIds }, isActive: true },
    "_id",
  ).lean();
  const activeUserSet = new Set(
    existingUsers.map((entry) => entry._id.toString()),
  );

  const adminIds = Array.from(
    new Set(
      [currentUser.id, ...requestedAdminIds].filter((id) =>
        activeUserSet.has(id),
      ),
    ),
  );

  const broadcastPublisherIds = Array.from(
    new Set(
      [...adminIds, ...requestedPublisherIds].filter((id) =>
        activeUserSet.has(id),
      ),
    ),
  );

  const members = Array.from(
    new Set(
      [...broadcastPublisherIds, ...requestedMemberIds].filter((id) =>
        activeUserSet.has(id),
      ),
    ),
  );

  const conversation = await Conversation.create({
    type,
    name: name || "Broadcast",
    description,
    avatarUrl: payload.avatarUrl || null,
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
  if (payload.avatarUrl !== undefined) {
    conversation.avatarUrl = payload.avatarUrl;
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
        new Set((payload.memberIds || []).filter(Boolean).map(String)),
      );
      conversation.members = nextMembers.includes(currentUser.id)
        ? nextMembers
        : [currentUser.id, ...nextMembers];
      await syncConversationMemberStates(
        conversation._id,
        conversation.members,
      );
    }

    if (payload.adminIds != null) {
      conversation.admins = Array.from(
        new Set([
          currentUser.id,
          ...(payload.adminIds || []).filter(Boolean).map(String),
        ]),
      );
    }
  }
  if (conversation.type === "broadcast") {
    const creatorId = conversation.createdBy?.toString?.() || currentUser.id;

    if (payload.broadcastPublisherIds != null || payload.publisherIds != null) {
      const explicitPublishers = normalizeIdList(
        payload.broadcastPublisherIds != null
          ? payload.broadcastPublisherIds
          : payload.publisherIds,
      );
      const activePublishers = await User.find(
        { _id: { $in: explicitPublishers }, isActive: true },
        "_id",
      ).lean();
      const currentAdmins = (conversation.admins || []).map((e) => e.toString());
      const publisherSet = new Set([
        creatorId,
        ...currentAdmins,
        ...activePublishers.map((e) => e._id.toString()),
      ]);
      conversation.broadcastPublisherIds = Array.from(publisherSet);
    }

    if (payload.adminIds != null) {
      const requestedAdminIds = normalizeIdList(payload.adminIds);
      const activeAdmins = await User.find(
        { _id: { $in: requestedAdminIds }, isActive: true },
        "_id",
      ).lean();
      const nextAdmins = Array.from(
        new Set([
          creatorId,
          ...activeAdmins.map((e) => e._id.toString()),
        ]),
      );
      conversation.admins = nextAdmins;

      const publisherSet = new Set(
        (conversation.broadcastPublisherIds || []).map((e) => e.toString()),
      );
      for (const adminId of nextAdmins) {
        publisherSet.add(adminId);
      }
      conversation.broadcastPublisherIds = Array.from(publisherSet);
    }

    if (payload.memberIds != null) {
      const requestedMemberIds = normalizeIdList(payload.memberIds);
      const activeMembers = await User.find(
        { _id: { $in: requestedMemberIds }, isActive: true },
        "_id",
      ).lean();
      const mandatoryMembers = [
        creatorId,
        ...(conversation.admins || []).map((e) => e.toString()),
        ...(conversation.broadcastPublisherIds || []).map((e) => e.toString()),
      ];
      const nextMembers = Array.from(
        new Set([
          ...mandatoryMembers,
          ...activeMembers.map((e) => e._id.toString()),
        ]),
      );
      conversation.members = nextMembers;
      await syncConversationMemberStates(
        conversation._id,
        conversation.members,
      );
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

async function deleteConversation(
  currentUser,
  conversationId,
  { scope = "self" } = {},
) {
  const normalizedScope = String(scope || "self").toLowerCase();
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
  }).lean();

  if (!conversation) {
    throw new ApiError(404, "Conversation not found.");
  }

  if (normalizedScope === "clear") {
    await assertConversationAccess(currentUser, conversation);
    await clearConversationHistoryForUser(
      conversation._id,
      currentUser.id,
      new Date(),
    );
    const nextConversation = await getConversationDetailsForUser(
      currentUser,
      conversation._id,
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

  if (normalizedScope !== "global") {
    await assertConversationAccess(currentUser, conversation);
    await deleteConversationForUser(
      conversation._id,
      currentUser.id,
      new Date(),
    );
    await logAuditEvent({
      actorId: currentUser.id,
      action: "conversation.self_deleted",
      entityType: "Conversation",
      entityId: conversation._id,
      payload: { type: conversation.type },
    });
    return {
      mode: "self_deleted",
      conversation: null,
      conversationId: conversation._id.toString(),
      memberIds: [currentUser.id],
    };
  }

  await assertConversationManagementAccess(currentUser, conversation);
  if (conversation.type === "department") {
    throw new ApiError(
      400,
      "Department conversations are managed through departments.",
    );
  }

  const messages = await Message.find(
    { conversationId: conversation._id, isDeleted: { $ne: true } },
    "storedFilePath",
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
    },
  );
  await Conversation.updateOne(
    { _id: conversation._id },
    {
      $set: {
        deletedAt: new Date(),
        isActive: false,
        directKey: null,
      },
    },
  );
  await ConversationMemberState.deleteMany({
    conversationId: conversation._id,
  });
  await logAuditEvent({
    actorId: currentUser.id,
    action: "conversation.deleted",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { type: conversation.type },
  });

  const memberIds = Array.from(
    new Set(
      (conversation.members || [])
        .map((entry) => getObjectIdString(entry))
        .filter(Boolean),
    ),
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
  { cursor = null, limit = 50, isScheduled = false } = {},
) {
  const conversation = await getConversationById(conversationId);
  await assertConversationAccess(currentUser, conversation);
  const memberState = await getConversationState(
    currentUser.id,
    conversationId,
  );
  const clearHistoryAt = memberState?.clearHistoryAt
    ? new Date(memberState.clearHistoryAt)
    : null;

  const pageSize = Math.max(1, Math.min(Number(limit || 50), 100));
  const query = {
    conversationId,
    isDeleted: { $ne: true },
    isScheduled: isScheduled ? true : { $ne: true },
  };
  const currentUserId = getObjectIdString(currentUser.id || currentUser._id);
  if (isScheduled) {
    query.senderId = currentUserId;
  }
  if (
    conversation.type === "broadcast" &&
    !canUserViewAllBroadcastMessages(currentUser, conversation)
  ) {
    Object.assign(query, getBroadcastRecipientVisibilityQuery(currentUserId));
  }
  if (cursor) {
    query._id = { $lt: cursor };
  }

  if (conversationId && conversation) {
    const memberIdsList = (conversation.members || []).map(getObjectIdString).filter(Boolean);
    const isCurrentlyInMembers = memberIdsList.includes(currentUserId);
    const isBlocked = (conversation.blockedMembers || []).some((b) => getObjectIdString(b) === currentUserId);
    const isDept = conversation.type === "department";
    const isBcast = conversation.type === "broadcast";
    const isMemberOrValidAudience = isCurrentlyInMembers || isDept || isBcast;
    const effectiveStatus = memberState?.membershipStatus || (isMemberOrValidAudience ? "active" : "removed");
    const isCurrentlyActiveMember = (isMemberOrValidAudience || isCurrentlyInMembers) && effectiveStatus === "active" && !isBlocked;
    const isNonActive = !isCurrentlyActiveMember;

    const cutoffDate = isNonActive && (memberState?.removedAt || memberState?.leftAt || memberState?.blockedAt)
      ? new Date(memberState.removedAt || memberState.leftAt || memberState.blockedAt)
      : null;

    if (cutoffDate && clearHistoryAt) {
      query.createdAt = { $gt: clearHistoryAt, $lte: cutoffDate };
    } else if (cutoffDate) {
      query.createdAt = { $lte: cutoffDate };
    } else if (clearHistoryAt) {
      query.createdAt = { $gt: clearHistoryAt };
    }
  } else if (clearHistoryAt) {
    query.createdAt = { $gt: clearHistoryAt };
  }

  const messages = await Message.find(query)
    .sort({ _id: -1 })
    .limit(pageSize + 1)
    .populate(
      "senderId",
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
    )
    .exec();

  const hasMore = messages.length > pageSize;
  const sliced = hasMore ? messages.slice(0, pageSize) : messages;
  const nextCursor = hasMore ? sliced[sliced.length - 1]._id.toString() : null;
  const ordered = sliced.reverse();

  return {
    messages: ordered.map((message) =>
      serializeMessage(message, message.senderId),
    ),
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
  const clientMessageId = String(payload.clientMessageId || "")
    .trim()
    .slice(0, 100);
  if (clientMessageId) {
    const existing = await Message.findOne({
      senderId: currentUser.id,
      clientMessageId,
    })
      .populate(
        "senderId",
        "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
      )
      .exec();
    if (existing) {
      if (file?.path) await deleteFileIfExists(file.path);
      return {
        audienceUserIds: [],
        recipientUserIds: [],
        alreadyExists: true,
        conversation: await serializeConversation(conversation, currentUser.id),
        message: serializeMessage(existing, existing.senderId),
      };
    }
  }
  const blockedIds = new Set(
    (conversation.blockedMembers || []).map((entry) =>
      entry?._id ? entry._id.toString() : entry.toString(),
    ),
  );
  if (blockedIds.has(currentUser.id)) {
    if (file?.path) {
      await deleteFileIfExists(file.path);
    }
    throw new ApiError(
      403,
      "You are blocked from this conversation and cannot send messages.",
    );
  }

  const memberIds = new Set(
    (conversation.members || []).map((entry) =>
      entry?._id ? entry._id.toString() : entry.toString(),
    ),
  );

  let isDepartmentMember = false;
  if (conversation.type === "department") {
    const conversationDepartmentId =
      conversation.departmentId?._id?.toString?.() ||
      conversation.departmentId?.toString?.() ||
      null;
    const currentUserDepartmentId = getObjectIdString(currentUser.departmentId);
    const currentUserDeptIds = [
      ...(currentUserDepartmentId ? [currentUserDepartmentId] : []),
      ...(Array.isArray(currentUser.departmentIds)
        ? currentUser.departmentIds.map((d) => getObjectIdString(d)).filter(Boolean)
        : []),
    ];
    if (currentUserDeptIds.includes(conversationDepartmentId)) {
      isDepartmentMember = true;
      if (!memberIds.has(currentUser.id)) {
        conversation.members.push(currentUser.id);
        await conversation.save().catch(() => {});
      }
    }
  }

  const isBroadcast = conversation.type === "broadcast";
  if (!isBroadcast && !isDepartmentMember && !memberIds.has(currentUser.id)) {
    if (file?.path) {
      await deleteFileIfExists(file.path);
    }
    throw new ApiError(
      403,
      "You are no longer a member of this conversation.",
    );
  }

  if (conversation.isActive === false) {
    if (file?.path) {
      await deleteFileIfExists(file.path);
    }
    throw new ApiError(
      403,
      "This room is disabled by admin. Messaging is currently read-only.",
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
        "conversationId content messageType fileUrl fileName fileSize mimeType storedFilePath metadata",
      )
      .lean();

    if (!forwardedMessage) {
      throw new ApiError(404, "Source message not found.");
    }

    const sourceConversation = await getConversationById(
      forwardedMessage.conversationId,
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
      (sourcePolicy && sourcePolicy.allowForward === false) ||
      (forwardedMessage.metadata && forwardedMessage.metadata.allowForward === false)
    ) {
      throw new ApiError(
        403,
        "This message cannot be forwarded by sender policy.",
      );
    }
  }

  const forwardingAttachment = Boolean(
    forwardedMessage?.storedFilePath && forwardedMessage?.fileUrl,
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
    const creatorId = conversation.createdBy
      ? getObjectIdString(conversation.createdBy)
      : null;
    const adminIds = new Set(
      (conversation.admins || []).map((entry) => getObjectIdString(entry)),
    );
    const configuredPublisherIds = new Set(
      (conversation.broadcastPublisherIds || []).map((entry) =>
        getObjectIdString(entry),
      ),
    );

    const isSystemAdmin = currentUser.role === "admin";
    const isCreator = creatorId === currentUser.id;
    const isConversationAdmin = adminIds.has(currentUser.id);
    const isPublisher = configuredPublisherIds.has(currentUser.id);

    if (!isSystemAdmin && !isCreator && !isConversationAdmin && !isPublisher) {
      if (file?.path) {
        await deleteFileIfExists(file.path);
      }
      throw new ApiError(
        403,
        "هذه قناة بث. فقط المشرفون والناشرون المصرح لهم يمكنهم إرسال الرسائل.",
      );
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
      userIds:
        rawTargets.userIds ||
        normalizedMetadata.userIds ||
        payload.userIds ||
        [],
      userNames:
        rawTargets.userNames ||
        normalizedMetadata.userNames ||
        payload.userNames ||
        [],
    };
    const targetDepartmentIds =
      await resolveBroadcastTargetDepartmentIds(mergedRawTargets);
    const targetUserIds = Array.from(
      new Set(
        (mergedRawTargets.userIds || [])
          .map((entry) => getObjectIdString(entry))
          .filter(Boolean),
      ),
    );
    const requestedTargetCount =
      (mergedRawTargets.departmentIds || []).length +
      (mergedRawTargets.departmentCodes || []).length +
      (mergedRawTargets.departmentNames || []).length +
      targetUserIds.length;
    if (requestedTargetCount > 0 && targetDepartmentIds.length === 0 && targetUserIds.length === 0) {
      throw new ApiError(400, "No valid target departments or users selected.");
    }

    if (targetDepartmentIds.length > 0 && targetUserIds.length > 0) {
      const targetDeptUsers = await User.find(
        {
          isActive: true,
          $or: [
            { departmentId: { $in: targetDepartmentIds } },
            { departmentIds: { $in: targetDepartmentIds } },
          ],
        },
        "_id",
      ).lean();
      const combined = new Set([
        ...targetDeptUsers.map((entry) => entry._id.toString()),
        ...targetUserIds,
      ]);
      recipientIds = Array.from(combined);
    } else if (targetDepartmentIds.length > 0) {
      const targetDeptUsers = await User.find(
        {
          isActive: true,
          $or: [
            { departmentId: { $in: targetDepartmentIds } },
            { departmentIds: { $in: targetDepartmentIds } },
          ],
        },
        "_id",
      ).lean();
      recipientIds = targetDeptUsers.map((entry) => entry._id.toString());
    } else if (targetUserIds.length > 0) {
      recipientIds = targetUserIds;
    } else {
      recipientIds = (conversation.members || [])
        .map((m) => getObjectIdString(m))
        .filter(Boolean);
    }

    const blockedMemberIdsSet = new Set(
      (conversation.blockedMembers || []).map((m) => getObjectIdString(m)).filter(Boolean)
    );
    recipientIds = recipientIds.filter((id) => !blockedMemberIdsSet.has(id));

    const conversationMemberIds = new Set(
      (conversation.members || []).map((entry) => getObjectIdString(entry)),
    );
    const publisherIds = new Set([
      ...(creatorId ? [creatorId] : []),
      ...Array.from(adminIds),
      ...Array.from(configuredPublisherIds),
    ]);
    for (const publisherId of publisherIds) {
      conversationMemberIds.add(publisherId);
    }
    let hasMemberChanges = false;
    if (requestedTargetCount > 0) {
      for (const userId of recipientIds) {
        if (!conversationMemberIds.has(userId) && !blockedMemberIdsSet.has(userId)) {
          conversationMemberIds.add(userId);
          hasMemberChanges = true;
        }
      }
      if (hasMemberChanges) {
        conversation.members = [...conversationMemberIds];
        await syncConversationMemberStates(
          conversation._id,
          conversation.members,
        );
      }
    }

    let targetDepartmentNames = [];
    let targetDepartmentCodes = [];
    if (targetDepartmentIds.length > 0) {
      const departments = await Department.find(
        { _id: { $in: targetDepartmentIds }, deletedAt: null },
        "name code",
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
    let targetUserNames = mergedRawTargets.userNames || [];
    if (targetUserIds.length > 0 && targetUserNames.length === 0) {
      const users = await User.find(
        { _id: { $in: targetUserIds } },
        "fullName username",
      ).lean();
      targetUserNames = users.map((u) => u.fullName || u.username);
    }
    normalizedMetadata.broadcastTargets = {
      departmentIds: targetDepartmentIds,
      departmentNames: targetDepartmentNames,
      departmentCodes: targetDepartmentCodes,
      userIds: targetUserIds,
      userNames: targetUserNames,
      sentToAllDepartments: targetDepartmentIds.length === 0 && targetUserIds.length === 0,
    };
  } else if (conversation.type === "department" && conversation.departmentId) {
    const deptId = conversation.departmentId._id || conversation.departmentId;
    const matchValues = toMatchObjectIds(deptId);
    const departmentUsers = await User.find(
      {
        $or: [
          { departmentId: { $in: matchValues } },
          { departmentIds: { $in: matchValues } },
        ],
        isActive: true,
      },
      "_id",
    ).lean();
    recipientIds = departmentUsers.map((entry) => entry._id.toString());
  } else {
    recipientIds = (conversation.members || []).map((entry) =>
      entry._id ? entry._id.toString() : entry.toString(),
    );
  }

  const blockedMembersSet = new Set(
    (conversation.blockedMembers || []).map((entry) =>
      entry?._id ? entry._id.toString() : entry.toString(),
    ),
  );
  recipientIds = recipientIds.filter((id) => !blockedMembersSet.has(id));

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
          forwardedMessage.fileName || attachment.fileName,
        ) ||
        sanitizeAttachmentFileName(
          forwardedMessage.fileName,
          attachment.fileName,
        );
      const sourceType = sanitizeMessageType(
        forwardedMessage.messageType,
        "file",
      );
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
            sourcePolicy?.allowDownload !== false &&
            requestedPolicy.allowDownload !== false,
          allowForward:
            sourcePolicy?.allowForward !== false &&
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
    const archiveMetadata =
      normalizeAttachmentArchiveMetadata(normalizedMetadata);
    if (archiveMetadata) {
      normalizedMetadata.attachmentArchive = archiveMetadata;
    } else {
      delete normalizedMetadata.attachmentArchive;
    }
  } else {
    delete normalizedMetadata.attachmentArchive;
  }

  if (
    !content &&
    !storedFilePath &&
    !["poll", "checklist"].includes(payload.messageType)
  ) {
    throw new ApiError(400, "Message content or attachment is required.");
  }

  if (payload.isSilent) {
    normalizedMetadata.silent = true;
  }

  delete normalizedMetadata.status;
  delete normalizedMetadata.error;

  const targetRecipientIds = recipientIds.filter(
    (userId) => userId !== currentUser.id,
  );

  const message = await Message.create({
    conversationId: conversation._id,
    senderId: currentUser.id,
    clientMessageId: clientMessageId || null,
    content,
    messageType: sanitizeMessageType(payload.messageType, messageTypeFallback),
    fileUrl: attachment.fileUrl,
    fileName: finalFileName,
    fileSize: attachment.fileSize,
    mimeType: attachment.mimeType,
    storedFilePath,
    replyToMessageId: payload.replyToMessageId || null,
    seenBy: [],
    deliveredTo: await buildDeliveryReceipts(targetRecipientIds),
    metadata:
      Object.keys(normalizedMetadata).length > 0 ? normalizedMetadata : null,
    isScheduled: payload.isScheduled || false,
    scheduledFor: payload.scheduledFor ? new Date(payload.scheduledFor) : null,
  });

  const isScheduledFuture =
    message.isScheduled &&
    message.scheduledFor &&
    new Date(message.scheduledFor) > new Date();

  if (!isScheduledFuture) {
    conversation.lastMessage = buildLastMessagePayload(message);
    await conversation.save();

    await incrementUnreadCounts(
      conversation._id,
      targetRecipientIds,
      currentUser.id,
    );

    await ConversationMemberState.updateMany(
      { conversationId: conversation._id, userId: { $in: [currentUser.id, ...targetRecipientIds] } },
      { $set: { isDeleted: false, deletedAt: null } },
    );
  }

  let audienceUserIds;
  if (conversation.type === "broadcast") {
    const publisherIds = extractIdArray(conversation.broadcastPublisherIds);
    audienceUserIds = Array.from(
      new Set([currentUser.id, ...targetRecipientIds, ...publisherIds]),
    );
  } else {
    audienceUserIds = Array.from(
      new Set([currentUser.id, ...extractIdArray(conversation.members)]),
    );
  }
  audienceUserIds = audienceUserIds.filter((id) => !blockedMembersSet.has(id));

  const populated = await Message.findById(message._id)
    .populate(
      "senderId",
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
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

  if (unseenMessages.length > 0) {
    await refreshConversationLastMessage(conversationId);
  }

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
    if (conversation.type === "broadcast" && message.metadata && message.metadata.broadcastTargets) {
      const targets = message.metadata.broadcastTargets;
      if (targets && targets.sentToAllDepartments === false) {
        const targetDeptIds = (targets.departmentIds || []).map(String);
        const targetUserIds = (targets.userIds || []).map(String);
        const currentUserId = String(currentUser.id || currentUser._id);
        const userDeptId = currentUser.departmentId ? String(currentUser.departmentId) : null;
        const userDeptIds = (currentUser.departmentIds || []).map(String);
        const isUserMatch = targetUserIds.includes(currentUserId);
        const isDeptMatch = targetDeptIds.length > 0 && (
          (userDeptId && targetDeptIds.includes(userDeptId)) ||
          userDeptIds.some((id) => targetDeptIds.includes(id))
        );
        if (!isUserMatch && !isDeptMatch) {
          continue;
        }
      }
    }
    message.deliveredTo.push({ userId: currentUser.id, at: new Date() });
    await message.save();
  }

  if (undeliveredMessages.length > 0) {
    await refreshConversationLastMessage(conversationId);
  }

  return undeliveredMessages.map((message) => message._id.toString());
}

async function markMessageDeliveredForUser(messageId, userId) {
  const receipt = { userId, at: new Date() };
  const updatedMessage = await Message.findOneAndUpdate(
    {
      _id: messageId,
      senderId: { $ne: userId },
      "deliveredTo.userId": { $ne: userId },
    },
    { $push: { deliveredTo: receipt } },
    { new: true },
  ).lean();
  if (updatedMessage) {
    await refreshConversationLastMessage(updatedMessage.conversationId);
  }
  return updatedMessage;
}

async function markPendingDeliveriesForUser(currentUser) {
  const conversationQuery = {
    deletedAt: null,
    $or: [{ members: currentUser.id }],
  };

  const userDeptIds = [
    ...(currentUser.departmentId ? [currentUser.departmentId] : []),
    ...(Array.isArray(currentUser.departmentIds) ? currentUser.departmentIds : []),
  ].filter(Boolean);

  if (userDeptIds.length > 0) {
    const matchValues = [];
    for (const d of userDeptIds) {
      for (const v of toMatchObjectIds(d)) {
        matchValues.push(v);
      }
    }
    conversationQuery.$or.push({
      type: "department",
      departmentId: { $in: matchValues },
    });
  }

  const conversations = await Conversation.find(
    conversationQuery,
    "_id type",
  ).lean();
  const conversationIds = conversations.map((entry) => entry._id);
  const conversationTypeMap = new Map(conversations.map(c => [c._id.toString(), c.type]));
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
    const type = conversationTypeMap.get(message.conversationId.toString());
    if (type === "broadcast" && message.metadata && message.metadata.broadcastTargets) {
      const targets = message.metadata.broadcastTargets;
      if (targets && targets.sentToAllDepartments === false) {
        const targetDeptIds = (targets.departmentIds || []).map(String);
        const targetUserIds = (targets.userIds || []).map(String);
        const currentUserId = String(currentUser.id || currentUser._id);
        const userDeptId = currentUser.departmentId ? String(currentUser.departmentId) : null;
        const userDeptIds = (currentUser.departmentIds || []).map(String);
        const isUserMatch = targetUserIds.includes(currentUserId);
        const isDeptMatch = targetDeptIds.length > 0 && (
          (userDeptId && targetDeptIds.includes(userDeptId)) ||
          userDeptIds.some((id) => targetDeptIds.includes(id))
        );
        if (!isUserMatch && !isDeptMatch) {
          continue;
        }
      }
    }

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
    (entry) => entry.userId.toString() === currentUser.id,
  );
  if (!seen) {
    message.seenBy.push({ userId: currentUser.id, at: new Date() });
    await message.save();
    await refreshConversationLastMessage(message.conversationId);
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

  const canDeleteAnyMessage = await userHasPermission(
    currentUser,
    "canDeleteMessages",
  );
  const isOwnMessage = message.senderId.toString() === currentUser.id;
  if (!isOwnMessage && !canDeleteAnyMessage) {
    throw new ApiError(403, "Permission denied.");
  }

  if (message.storedFilePath) {
    const isReferencedElsewhere = await Message.exists({
      _id: { $ne: message._id },
      storedFilePath: message.storedFilePath,
      isDeleted: { $ne: true },
    });
    if (!isReferencedElsewhere) {
      await deleteFileIfExists(message.storedFilePath);
    }
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

  const isOwnMessage = message.senderId.toString() === currentUser.id;
  if (!isOwnMessage) {
    throw new ApiError(403, "You can only edit your own messages.");
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
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
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
  const normalizedEmoji = String(emoji || "")
    .trim()
    .slice(0, 8);
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
  const reactions = {
    ...(metadata.reactions && typeof metadata.reactions === "object"
      ? metadata.reactions
      : {}),
  };
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
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
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
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
    )
    .exec();

  return serializeMessage(populated, populated.senderId);
}

async function updateConversationPreferences(
  currentUser,
  conversationId,
  payload,
) {
  const conversation = await getConversationById(conversationId);
  await assertConversationAccess(currentUser, conversation);

  await updateConversationState(currentUser.id, conversationId, payload);
  return getConversationDetailsForUser(currentUser, conversationId);
}

async function setConversationPinnedMessage(
  currentUser,
  conversationId,
  payload,
) {
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

  const systemMessage = await createSystemConversationMessage(
    conversation,
    currentUser,
    {
      content: `${currentUser.fullName || currentUser.username} updated the pinned message`,
      metadata: {
        eventType: "group.pinned_message.updated",
      },
    },
  );

  return {
    conversation: await getConversationDetailsForUser(
      currentUser,
      conversation._id,
    ),
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

  const systemMessage = await createSystemConversationMessage(
    conversation,
    currentUser,
    {
      content: `${currentUser.fullName || currentUser.username} removed the pinned message`,
      metadata: {
        eventType: "group.pinned_message.cleared",
      },
    },
  );

  return {
    conversation: await getConversationDetailsForUser(
      currentUser,
      conversation._id,
    ),
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
  if (conversation.type === "direct" || conversation.type === "department" || conversation.type === "broadcast") {
    throw new ApiError(400, "This conversation cannot be joined manually.");
  }

  const canCreateRooms = await userHasPermission(currentUser, "canCreateRooms");
  if (!canCreateRooms && currentUser.role !== "admin") {
    throw new ApiError(403, "Permission denied.");
  }

  const memberIds = new Set(
    (conversation.members || []).map((entry) => entry.toString()),
  );
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
    (entry) => entry.toString() !== currentUser.id,
  );
  conversation.admins = (conversation.admins || []).filter(
    (entry) => entry.toString() !== currentUser.id,
  );

  // Auto-promote first remaining member to admin if no admins left
  if (
    conversation.admins.length === 0 &&
    conversation.members.length > 0 &&
    conversation.type !== "direct"
  ) {
    const newAdminId = conversation.members[0];
    conversation.admins = [newAdminId];
  }

  await conversation.save();
  const leftAt = new Date();
  await markConversationMemberLeft(conversation._id, currentUser.id, leftAt);

  const systemMessage = await createSystemConversationMessage(
    conversation,
    currentUser,
    {
      content: `${currentUser.fullName || currentUser.username} غادر المجموعة`,
      metadata: {
        eventType: "group.member.left",
        userIds: [String(currentUser.id)],
      },
    },
  );

  await logAuditEvent({
    actorId: currentUser.id,
    action: "group.member.left",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { userId: String(currentUser.id) },
  });

  return {
    conversation: await getConversationDetailsForUser(currentUser, conversation._id),
    systemMessage,
    affectedUserIds: [String(currentUser.id)],
  };
}

async function listConversationMembers(currentUser, conversationId) {
  const conversation = await getConversationById(conversationId);
  await assertConversationAccess(currentUser, conversation);
  return (conversation.members || []).map((member) =>
    member._id ? serializeUserLite(member) : { id: member.toString() },
  );
}

async function addConversationMembers(currentUser, conversationId, userIds) {
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
    isActive: true,
  }).exec();
  assertGroupOwnerAccess(currentUser, conversation);

  const blocked = new Set(
    (conversation.blockedMembers || []).map((entry) => entry.toString()),
  );
  const nextUserIds = Array.from(new Set((userIds || []).map(String))).filter(
    (userId) => !blocked.has(userId),
  );
  if (nextUserIds.length === 0) {
    throw new ApiError(400, "No eligible users to add.");
  }

  const addedUsers = await User.find(
    { _id: { $in: nextUserIds }, isActive: true },
    "username fullName",
  ).lean();
  const addedNames = addedUsers.map(
    (entry) => entry.fullName || entry.username,
  );

  const nextMembers = Array.from(
    new Set([...(conversation.members || []).map(String), ...nextUserIds]),
  );
  conversation.members = nextMembers;
  await conversation.save();
  await syncConversationMemberStates(conversation._id, nextMembers);
  const channelTypeLabel = conversation.type === "broadcast" ? "قناة البث" : "المجموعة";
  const systemMessage = await createSystemConversationMessage(
    conversation,
    currentUser,
    {
      content: `${currentUser.fullName || currentUser.username} أضاف ${addedNames.join("، ")} إلى ${channelTypeLabel}`,
      metadata: {
        eventType: "group.members.added",
        userIds: nextUserIds,
      },
    },
  );
  await logAuditEvent({
    actorId: currentUser.id,
    action: "group.members.added",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { userIds: nextUserIds },
  });
  return {
    conversation: await getConversationDetailsForUser(
      currentUser,
      conversation._id,
    ),
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
  const creatorId = getObjectIdString(conversation.createdBy);
  if (String(userId) === creatorId) {
    throw new ApiError(403, "Cannot modify the original group creator.");
  }

  const memberIds = new Set(
    (conversation.members || []).map((entry) => entry.toString()),
  );
  if (!memberIds.has(String(userId))) {
    throw new ApiError(400, "User is not a member of this group.");
  }
  conversation.members = (conversation.members || []).filter(
    (entry) => entry.toString() !== String(userId),
  );
  conversation.admins = (conversation.admins || []).filter(
    (entry) => entry.toString() !== String(userId),
  );
  if (conversation.type === "broadcast") {
    conversation.broadcastPublisherIds = (
      conversation.broadcastPublisherIds || []
    ).filter((entry) => entry.toString() !== String(userId));
  }
  await conversation.save();
  const removedAt = new Date();
  await markConversationMemberRemoved(conversation._id, userId, removedAt);
  const target = await User.findById(userId, "username fullName").lean();
  const targetLabel = target?.fullName || target?.username || "عضو";
  const channelTypeLabel = conversation.type === "broadcast" ? "القناة" : "المجموعة";
  const systemMessage = await createSystemConversationMessage(
    conversation,
    currentUser,
    {
      content: `${currentUser.fullName || currentUser.username} أزال ${targetLabel} من ${channelTypeLabel}`,
      metadata: {
        eventType: "group.member.removed",
        userIds: [String(userId)],
      },
    },
  );
  await logAuditEvent({
    actorId: currentUser.id,
    action: "group.member.removed",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { userId: String(userId) },
  });
  return {
    conversation: await getConversationDetailsForUser(
      currentUser,
      conversation._id,
    ),
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

  const memberIds = new Set(
    (conversation.members || []).map((entry) => entry.toString()),
  );
  if (!memberIds.has(String(userId))) {
    throw new ApiError(400, "User must be a group member first.");
  }

  const adminIds = new Set(
    (conversation.admins || []).map((entry) => entry.toString()),
  );
  adminIds.add(String(userId));
  adminIds.add(currentUser.id);
  conversation.admins = [...adminIds];
  if (conversation.type === "broadcast") {
    const publisherIds = new Set(
      (conversation.broadcastPublisherIds || []).map((entry) =>
        entry.toString(),
      ),
    );
    publisherIds.add(String(userId));
    conversation.broadcastPublisherIds = [...publisherIds];
  }
  await conversation.save();
  const target = await User.findById(userId, "username fullName").lean();
  const targetLabel = target?.fullName || target?.username || "عضو";
  const roleLabel =
    conversation.type === "broadcast"
      ? "مشرفاً وناشراً في قناة البث"
      : "أدمن في المجموعة";
  const systemMessage = await createSystemConversationMessage(
    conversation,
    currentUser,
    {
      content: `${targetLabel} أصبح ${roleLabel}`,
      metadata: {
        eventType: "group.admin.promoted",
        userIds: [String(userId)],
      },
    },
  );
  await logAuditEvent({
    actorId: currentUser.id,
    action: "group.admin.promoted",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { userId: String(userId) },
  });
  return {
    conversation: await getConversationDetailsForUser(
      currentUser,
      conversation._id,
    ),
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
  const creatorIdDemote = getObjectIdString(conversation.createdBy);
  if (String(userId) === creatorIdDemote) {
    throw new ApiError(403, "Cannot demote the original group creator.");
  }

  conversation.admins = (conversation.admins || []).filter(
    (entry) => entry.toString() !== String(userId),
  );
  if (conversation.type === "broadcast") {
    conversation.broadcastPublisherIds = (
      conversation.broadcastPublisherIds || []
    ).filter((entry) => entry.toString() !== String(userId));
  }
  await conversation.save();
  const target = await User.findById(userId, "username fullName").lean();
  const targetLabel = target?.fullName || target?.username || "عضو";
  const roleLabel =
    conversation.type === "broadcast"
      ? "صلاحية الإشراف والنشر في قناة البث"
      : "صلاحية الأدمن في المجموعة";
  const systemMessage = await createSystemConversationMessage(
    conversation,
    currentUser,
    {
      content: `تمت إزالة ${roleLabel} من ${targetLabel}`,
      metadata: {
        eventType: "group.admin.demoted",
        userIds: [String(userId)],
      },
    },
  );
  await logAuditEvent({
    actorId: currentUser.id,
    action: "group.admin.demoted",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { userId: String(userId) },
  });
  return {
    conversation: await getConversationDetailsForUser(
      currentUser,
      conversation._id,
    ),
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
  const creatorIdBlock = getObjectIdString(conversation.createdBy);
  if (String(userId) === creatorIdBlock) {
    throw new ApiError(403, "Cannot block the original group creator.");
  }

  conversation.members = (conversation.members || []).filter(
    (entry) => entry.toString() !== String(userId),
  );
  conversation.admins = (conversation.admins || []).filter(
    (entry) => entry.toString() !== String(userId),
  );
  if (conversation.type === "broadcast") {
    conversation.broadcastPublisherIds = (
      conversation.broadcastPublisherIds || []
    ).filter((entry) => entry.toString() !== String(userId));
  }
  conversation.blockedMembers.addToSet(userId);
  await conversation.save();
  const blockedAt = new Date();
  await markConversationMemberBlocked(conversation._id, userId, blockedAt);
  const target = await User.findById(userId, "username fullName").lean();
  const targetLabel = target?.fullName || target?.username || "عضو";
  const channelTypeLabel = conversation.type === "broadcast" ? "القناة" : "المجموعة";
  const systemMessage = await createSystemConversationMessage(
    conversation,
    currentUser,
    {
      content: `${currentUser.fullName || currentUser.username} قام بحظر ${targetLabel} من ${channelTypeLabel}`,
      metadata: {
        eventType: "group.member.blocked",
        userIds: [String(userId)],
      },
    },
  );
  await logAuditEvent({
    actorId: currentUser.id,
    action: "group.member.blocked",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { userId: String(userId) },
  });
  return {
    conversation: await getConversationDetailsForUser(
      currentUser,
      conversation._id,
    ),
    systemMessage,
    affectedUserIds: [String(userId)],
  };
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
  const isMember = (conversation.members || []).some(
    (m) => getObjectIdString(m) === String(userId),
  );
  await markConversationMemberUnblocked(conversation._id, userId, isMember);
  await logAuditEvent({
    actorId: currentUser.id,
    action: "group.member.unblocked",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { userId: String(userId) },
  });
  return {
    conversation: await getConversationDetailsForUser(
      currentUser,
      conversation._id,
    ),
    affectedUserIds: [String(userId)],
  };
}

async function searchMessages(
  currentUser,
  { q = "", conversationId = null, cursor = null, limit = 30 } = {},
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
  let conversation = null;
  let memberState = null;
  if (conversationId) {
    conversation = await getConversationById(conversationId);
    await assertConversationAccess(currentUser, conversation);
    memberState = await getConversationState(
      currentUser.id,
      conversationId,
    );
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
    isScheduled: { $ne: true },
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

  if (conversationId && conversation) {
    const memberIdsList = (conversation.members || []).map(getObjectIdString).filter(Boolean);
    const isCurrentlyInMembers = memberIdsList.includes(currentUserId);
    const isBlocked = (conversation.blockedMembers || []).some((b) => getObjectIdString(b) === currentUserId);
    const isDept = conversation.type === "department";
    const isBcast = conversation.type === "broadcast";
    const isMemberOrValidAudience = isCurrentlyInMembers || isDept || isBcast;
    const effectiveStatus = memberState?.membershipStatus || (isMemberOrValidAudience ? "active" : "removed");
    const isCurrentlyActiveMember = (isMemberOrValidAudience || isCurrentlyInMembers) && effectiveStatus === "active" && !isBlocked;
    const isNonActive = !isCurrentlyActiveMember;

    const cutoffDate = isNonActive && (memberState?.removedAt || memberState?.leftAt || memberState?.blockedAt)
      ? new Date(memberState.removedAt || memberState.leftAt || memberState.blockedAt)
      : null;

    if (cutoffDate && clearHistoryAt) {
      query.createdAt = { $gt: clearHistoryAt, $lte: cutoffDate };
    } else if (cutoffDate) {
      query.createdAt = { $lte: cutoffDate };
    } else if (clearHistoryAt) {
      query.createdAt = { $gt: clearHistoryAt };
    }
  } else if (clearHistoryAt) {
    query.createdAt = { $gt: clearHistoryAt };
  }

  const pageSize = Math.max(1, Math.min(Number(limit || 30), 100));
  const messages = await Message.find(query)
    .sort({ _id: -1 })
    .limit(pageSize + 1)
    .populate(
      "senderId",
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
    )
    .exec();

  const hasMore = messages.length > pageSize;
  const sliced = hasMore ? messages.slice(0, pageSize) : messages;
  return {
    messages: sliced.map((message) =>
      serializeMessage(message, message.senderId),
    ),
    meta: {
      nextCursor: hasMore ? sliced[sliced.length - 1]._id.toString() : null,
      hasMore,
      limit: pageSize,
    },
  };
}

async function listFavoriteMessages(
  currentUser,
  { cursor = null, limit = 30 } = {},
) {
  const conversations = await listConversationsForUser(currentUser);
  const conversationById = new Map(
    conversations.map((conversation) => [conversation.id, conversation]),
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
      new Date(state.clearHistoryAt),
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
        "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
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
    presenceStatus:
      user.presenceStatus || (user.isOnline ? "online" : "offline"),
    avatarUrl: normalizeMediaUrl(user.avatarUrl),
    lastSeen: user.lastSeen || null,
    lastActiveAt: user.lastActiveAt || null,
  };
}

async function getMessageAttachment(
  currentUser,
  conversationId,
  storedName,
  { requireDownload = false } = {},
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
    throw new ApiError(
      409,
      "This attachment cannot be restored automatically.",
    );
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
    throw new ApiError(
      409,
      "This attachment cannot be restored automatically.",
    );
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
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
    )
    .exec();
  return serializeMessage(populated, populated.senderId);
}

async function votePollMessage(currentUser, messageId, optionIds) {
  const message = await Message.findById(messageId);
  if (
    !message ||
    message.isDeleted ||
    !["poll", "checklist"].includes(message.messageType)
  ) {
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
  const currentUserIdStr = String(currentUser.id || currentUser._id);
  for (const key of Object.keys(metadata.votes)) {
    metadata.votes[key] = (metadata.votes[key] || []).filter(
      (id) => String(id) !== currentUserIdStr,
    );
  }

  // Add the user to the selected options (deduplicate optionIds first)
  const uniqueOptionIds = [...new Set((optionIds || []).map(String))];
  for (const optId of uniqueOptionIds) {
    const optionExists = metadata.options.find(
      (o) => String(o.id) === String(optId),
    );
    if (optionExists) {
      if (!metadata.votes[String(optId)]) metadata.votes[String(optId)] = [];
      metadata.votes[String(optId)].push(currentUserIdStr);
    }
  }

  message.metadata = metadata;
  message.markModified("metadata");
  await message.save();

  const populated = await Message.findById(message._id)
    .populate(
      "senderId",
      "username fullName role jobTitle departmentId departmentIds branchCode isOnline presenceStatus avatarUrl isActive lastSeen lastActiveAt",
    )
    .exec();

  let audienceUserIds;
  if (conversation.type === "broadcast") {
    const publisherIds = extractIdArray(conversation.broadcastPublisherIds);
    audienceUserIds = Array.from(
      new Set([...extractIdArray(conversation.members), ...publisherIds]),
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
  if (
    !message ||
    message.isDeleted ||
    !["poll", "checklist"].includes(message.messageType)
  ) {
    throw new ApiError(404, "الاستطلاع غير موجود أو محذوف.");
  }
  const conversation = await getConversationById(message.conversationId);
  await assertConversationAccess(currentUser, conversation);

  const isAdmin =
    currentUser.role === "admin" || currentUser.role === "superadmin";
  const isManager = currentUser.role === "manager";
  const isPrivileged = isAdmin || isManager;
  const senderIdStr = message.senderId ? String(message.senderId._id || message.senderId) : "";
  const currentUserIdStr = String(currentUser._id || currentUser.id || "");
  const isCreator = Boolean(senderIdStr && senderIdStr === currentUserIdStr);

  if (!isPrivileged && !isCreator) {
    throw new ApiError(403, "ليس لديك صلاحية لتصدير نتائج هذا الاستطلاع.");
  }

  const metadata = message.metadata || {};
  const question = metadata.question || "استطلاع رأي";
  const options = metadata.options || [];
  const votes = metadata.votes || {};
  const isAnonymous = metadata.isAnonymous === true;
  const isMultipleChoice = metadata.isMultipleChoice === true;
  const isClosed = metadata.isClosed === true;

  // Collect all unique voter IDs
  const allVoterIdsSet = new Set();
  for (const opt of options) {
    const vIds = votes[String(opt.id)] || [];
    for (const vid of vIds) {
      if (vid) allVoterIdsSet.add(String(vid));
    }
  }
  const allVoterIds = Array.from(allVoterIdsSet);

  // Fetch full details of all voters including branch name
  const voters = await User.find({ _id: { $in: allVoterIds } })
    .populate("departmentId", "name")
    .populate("branchId", "name code")
    .select("fullName username jobTitle role departmentId branchId branchCode")
    .lean();

  const voterMap = new Map();
  voters.forEach((v) => {
    voterMap.set(String(v._id), v);
  });

  function formatRole(role) {
    if (role === "superadmin") return "مسؤول رئيسي";
    if (role === "admin") return "مسؤول النظام";
    if (role === "manager") return "مدير";
    return "موظف";
  }

  function formatDateTime(dt) {
    if (!dt) return "-";
    const d = new Date(dt);
    if (isNaN(d.getTime())) return "-";
    return d.toLocaleString("ar-EG", {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: true,
    });
  }

  function getBranchName(u) {
    if (u?.branchId?.name) return u.branchId.name;
    if (u?.branchCode) return u.branchCode;
    return "-";
  }

  function getDeptName(u) {
    if (u?.departmentId?.name) return u.departmentId.name;
    return "-";
  }

  // Color palette
  const C = {
    headerBg:    "FF1E3A8A", // Dark blue
    headerFont:  "FFFFFFFF",
    subHeaderBg: "FF2563EB", // Mid blue
    greenBg:     "FF065F46", // Dark green
    greenMid:    "FF059669", // Mid green
    rowAlt:      "FFF0F4FF", // Light blue alt row
    rowAlt2:     "FFF0FDF4", // Light green alt row
    totalBg:     "FFEFF6FF",
    totalFont:   "FF1E3A8A",
    labelFont:   "FF1E3A8A",
    valueFont:   "FF111827",
    mutedFont:   "FF6B7280",
    sectionBg:   "FFE0E7FF", // Section divider
    winnerBg:    "FFFBBF24", // Gold for winner
    winnerFont:  "FF78350F",
  };

  function applyHeaderStyle(cell, bgArgb, fontArgb, fontSize) {
    cell.font = { name: "Arial", size: fontSize || 11, bold: true, color: { argb: fontArgb } };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: bgArgb } };
    cell.alignment = { horizontal: "center", vertical: "middle", wrapText: true };
  }

  function applyLabelStyle(cell) {
    cell.font = { name: "Arial", bold: true, size: 10, color: { argb: C.labelFont } };
    cell.alignment = { horizontal: "right", vertical: "middle" };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFE8EDFD" } };
  }

  function applyValueStyle(cell) {
    cell.font = { name: "Arial", bold: false, size: 10, color: { argb: C.valueFont } };
    cell.alignment = { horizontal: "right", vertical: "middle", wrapText: true };
  }

  // Compute totals
  let totalVotes = 0;
  for (const opt of options) {
    totalVotes += (votes[String(opt.id)] || []).length;
  }

  // Find winner(s)
  let maxVotes = 0;
  for (const opt of options) {
    const cnt = (votes[String(opt.id)] || []).length;
    if (cnt > maxVotes) maxVotes = cnt;
  }

  // Safe filename from question
  const safeQuestion = question
    .replace(/[\/:*?"<>|]/g, "")
    .replace(/\s+/g, "_")
    .slice(0, 40);
  const exportDate = new Date();
  const dateStr = exportDate.toISOString().slice(0, 10);
  const filename = `استطلاع_${safeQuestion}_${dateStr}.xlsx`;

  // ============================================================
  const workbook = new exceljs.Workbook();
  workbook.creator = "iSmart Messenger";
  workbook.lastModifiedBy = currentUser.fullName || currentUser.username || "iSmart System";
  workbook.created = exportDate;
  workbook.modified = exportDate;

  // ============================================================
  // SHEET 1: معلومات الاستطلاع (Poll Info)
  // ============================================================
  const infoSheet = workbook.addWorksheet("معلومات الاستطلاع", {
    pageSetup: { orientation: "portrait", fitToPage: true },
  });
  infoSheet.views = [{ rightToLeft: true }];

  // === Big Title ===
  infoSheet.mergeCells("A1:D1");
  const t1 = infoSheet.getCell("A1");
  t1.value = "🗳️  تقرير استطلاع الرأي";
  applyHeaderStyle(t1, C.headerBg, C.headerFont, 16);
  infoSheet.getRow(1).height = 44;

  // Sub-title: system name
  infoSheet.mergeCells("A2:D2");
  const t2 = infoSheet.getCell("A2");
  t2.value = "iSmart Messenger — نظام المراسلات الذكية";
  t2.font = { name: "Arial", size: 10, italic: true, color: { argb: "FFFFFFFF" } };
  t2.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF1D4ED8" } };
  t2.alignment = { horizontal: "center", vertical: "middle" };
  infoSheet.getRow(2).height = 24;

  // Blank row
  infoSheet.addRow([]);

  // === Section: Poll Details ===
  infoSheet.mergeCells("A4:D4");
  const secPoll = infoSheet.getCell("A4");
  secPoll.value = "📋  تفاصيل الاستطلاع";
  applyHeaderStyle(secPoll, C.sectionBg, C.labelFont, 11);
  infoSheet.getRow(4).height = 28;

  const infoRows = [
    ["سؤال الاستطلاع", question],
    ["المحادثة / المجموعة", conversation?.title || conversation?.name || "محادثة"],
    ["أنشئ بواسطة", message.senderId?.fullName || message.senderId?.username || "غير محدد"],
    ["تاريخ الإنشاء", formatDateTime(message.createdAt)],
    ["نوع الاستطلاع", isMultipleChoice ? "✅ اختيارات متعددة" : "🔘 اختيار واحد فقط"],
    ["حالة الاستطلاع", isClosed ? "🔒 مغلق — انتهى التصويت" : "🟢 نشط — التصويت مفتوح"],
    ["طبيعة التصويت", isAnonymous
      ? (isPrivileged ? "🔐 مجهول (مكشوف للإدارة)" : "🔐 مجهول للجميع")
      : "👁️  علني — أسماء المصوتين ظاهرة"],
    ["عدد الخيارات", options.length],
    ["إجمالي المصوتين", allVoterIds.length],
    ["إجمالي أصوات المسجلة", totalVotes],
  ];

  infoRows.forEach(([label, value], i) => {
    const rowNum = 5 + i;
    const row = infoSheet.getRow(rowNum);
    row.height = 26;
    const lc = row.getCell(1);
    const vc = row.getCell(2);
    // Merge value across B-D
    infoSheet.mergeCells(`B${rowNum}:D${rowNum}`);
    lc.value = label;
    vc.value = value;
    applyLabelStyle(lc);
    applyValueStyle(vc);
    // Alternate row bg
    if (i % 2 === 0) {
      vc.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFAFBFF" } };
    }
  });

  // === Section: Export Info ===
  const exportSectionRow = 5 + infoRows.length + 1;
  infoSheet.mergeCells(`A${exportSectionRow}:D${exportSectionRow}`);
  const secExport = infoSheet.getCell(`A${exportSectionRow}`);
  secExport.value = "📤  معلومات التصدير";
  applyHeaderStyle(secExport, C.sectionBg, C.labelFont, 11);
  infoSheet.getRow(exportSectionRow).height = 28;

  const exportRows = [
    ["صدّره", `${currentUser.fullName || currentUser.username} — ${formatRole(currentUser.role)}`],
    ["تاريخ التصدير", formatDateTime(exportDate)],
    ["اسم الملف", filename],
  ];

  exportRows.forEach(([label, value], i) => {
    const rowNum = exportSectionRow + 1 + i;
    infoSheet.mergeCells(`B${rowNum}:D${rowNum}`);
    const row = infoSheet.getRow(rowNum);
    row.height = 24;
    const lc = row.getCell(1);
    const vc = row.getCell(2);
    lc.value = label;
    vc.value = value;
    applyLabelStyle(lc);
    applyValueStyle(vc);
  });

  infoSheet.columns = [
    { width: 26 },
    { width: 50 },
    { width: 10 },
    { width: 10 },
  ];

  // ============================================================
  // SHEET 2: نتائج التصويت (Voting Results)
  // ============================================================
  const resultsSheet = workbook.addWorksheet("نتائج التصويت", {
    pageSetup: { orientation: "landscape", fitToPage: true },
  });
  resultsSheet.views = [{ rightToLeft: true }];

  // Title
  resultsSheet.mergeCells("A1:F1");
  const rt = resultsSheet.getCell("A1");
  rt.value = "📊  نتائج الاستطلاع — توزيع الأصوات على الخيارات";
  applyHeaderStyle(rt, C.headerBg, C.headerFont, 14);
  resultsSheet.getRow(1).height = 40;

  // Question row
  resultsSheet.mergeCells("A2:F2");
  const rq = resultsSheet.getCell("A2");
  rq.value = `السؤال: ${question}`;
  rq.font = { name: "Arial", size: 11, bold: true, color: { argb: C.labelFont } };
  rq.fill = { type: "pattern", pattern: "solid", fgColor: { argb: C.sectionBg } };
  rq.alignment = { horizontal: "right", vertical: "middle", wrapText: true };
  resultsSheet.getRow(2).height = 32;

  resultsSheet.addRow([]);

  // Header row
  const rHeader = resultsSheet.addRow([
    "م",
    "خيار الاستطلاع",
    "عدد الأصوات",
    "النسبة المئوية",
    "شريط الأداء",
    "أسماء المصوتين",
  ]);
  rHeader.height = 30;
  rHeader.eachCell((cell) => {
    applyHeaderStyle(cell, C.subHeaderBg, C.headerFont, 11);
    cell.border = {
      bottom: { style: "medium", color: { argb: C.headerBg } },
    };
  });

  // Data rows
  options.forEach((opt, idx) => {
    const voterIds = votes[String(opt.id)] || [];
    const count = voterIds.length;
    const pct = totalVotes > 0 ? (count / totalVotes) * 100 : 0;
    const pctStr = pct.toFixed(1) + "%";
    const isWinner = maxVotes > 0 && count === maxVotes;

    // Build bar (▓ chars) max 20 chars wide
    const barLen = Math.round((pct / 100) * 20);
    const bar = "▓".repeat(barLen) + "░".repeat(20 - barLen) + `  ${pctStr}`;

    let voterNames = "-";
    if (!isAnonymous || isPrivileged) {
      const names = voterIds.map((vid) => {
        const u = voterMap.get(String(vid));
        return u ? (u.fullName || u.username) : "مستخدم";
      });
      voterNames = names.length > 0 ? names.join("،  ") : "لا يوجد مصوتين";
    } else {
      voterNames = "🔐 مجهول";
    }

    const row = resultsSheet.addRow([
      idx + 1,
      (isWinner && totalVotes > 0 ? "🥇 " : "") + opt.text,
      count,
      pctStr,
      bar,
      voterNames,
    ]);
    row.height = 28;

    // Winner gets gold background
    if (isWinner && totalVotes > 0) {
      row.eachCell((cell) => {
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: C.winnerBg } };
        cell.font = { name: "Arial", size: 10, bold: true, color: { argb: C.winnerFont } };
      });
    } else if (idx % 2 === 0) {
      row.eachCell((cell) => {
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: C.rowAlt } };
        cell.font = { name: "Arial", size: 10 };
      });
    } else {
      row.eachCell((cell) => {
        cell.font = { name: "Arial", size: 10 };
      });
    }

    row.getCell(1).alignment = { horizontal: "center", vertical: "middle" };
    row.getCell(2).alignment = { horizontal: "right", vertical: "middle", wrapText: true };
    row.getCell(3).alignment = { horizontal: "center", vertical: "middle" };
    row.getCell(4).alignment = { horizontal: "center", vertical: "middle" };
    row.getCell(5).alignment = { horizontal: "left", vertical: "middle" };
    row.getCell(5).font = { name: "Courier New", size: 9, color: { argb: "FF1E3A8A" } };
    row.getCell(6).alignment = { horizontal: "right", vertical: "middle", wrapText: true };
  });

  // Total row
  const totalRow = resultsSheet.addRow([
    "",
    "✅ الإجمالي الكلي",
    totalVotes,
    "100%",
    "",
    `${allVoterIds.length} مشارك`,
  ]);
  totalRow.height = 28;
  totalRow.eachCell((cell) => {
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: C.totalBg } };
    cell.font = { name: "Arial", size: 10, bold: true, color: { argb: C.totalFont } };
    cell.border = { top: { style: "medium", color: { argb: C.headerBg } } };
  });
  totalRow.getCell(2).alignment = { horizontal: "right", vertical: "middle" };
  totalRow.getCell(3).alignment = { horizontal: "center", vertical: "middle" };
  totalRow.getCell(4).alignment = { horizontal: "center", vertical: "middle" };
  totalRow.getCell(6).alignment = { horizontal: "center", vertical: "middle" };

  resultsSheet.columns = [
    { width: 6 },
    { width: 36 },
    { width: 14 },
    { width: 14 },
    { width: 28 },
    { width: 50 },
  ];

  // ============================================================
  // SHEET 3: سجل المصوتين (Detailed Voter Records) — privileged only
  // ============================================================
  if (isPrivileged || !isAnonymous) {
    const detailSheet = workbook.addWorksheet("سجل المصوتين التفصيلي", {
      pageSetup: { orientation: "landscape", fitToPage: true },
    });
    detailSheet.views = [{ rightToLeft: true }];

    // Title
    detailSheet.mergeCells("A1:I1");
    const dt = detailSheet.getCell("A1");
    dt.value = "👥  سجل المصوتين التفصيلي — من صوت وماذا اختار وبيانات كل مشارك";
    applyHeaderStyle(dt, C.greenBg, C.headerFont, 13);
    detailSheet.getRow(1).height = 40;

    // Sub header info
    detailSheet.mergeCells("A2:I2");
    const ds = detailSheet.getCell("A2");
    ds.value = isAnonymous
      ? "⚠️  هذا الاستطلاع مجهول — الأسماء مكشوفة لك فقط بصلاحيات الإدارة والمدراء"
      : "👁️  استطلاع علني — الأسماء ظاهرة لجميع الأعضاء";
    ds.font = { name: "Arial", size: 10, italic: true, color: { argb: "FFFFFFFF" } };
    ds.fill = { type: "pattern", pattern: "solid", fgColor: { argb: isAnonymous ? "FF7C3AED" : C.greenMid } };
    ds.alignment = { horizontal: "center", vertical: "middle" };
    detailSheet.getRow(2).height = 24;

    detailSheet.addRow([]);

    // Header
    const dHeader = detailSheet.addRow([
      "م",
      "الاسم الكامل",
      "اسم المستخدم",
      "الخيار الذي اختاره",
      "المسمى الوظيفي",
      "القسم / الإدارة",
      "الفرع",
      "الصلاحية",
      "ملاحظات",
    ]);
    dHeader.height = 30;
    dHeader.eachCell((cell) => {
      applyHeaderStyle(cell, C.greenMid, C.headerFont, 10);
      cell.border = {
        bottom: { style: "medium", color: { argb: C.greenBg } },
      };
    });

    // Build rows grouped by option
    let rowIdx = 1;
    for (const opt of options) {
      const vIds = votes[String(opt.id)] || [];
      if (vIds.length === 0) continue;

      // Option divider row
      const divRow = detailSheet.addRow([
        "", `◀ ${opt.text}`, `(${vIds.length} صوت)`, "", "", "", "", "", ""
      ]);
      detailSheet.mergeCells(`B${divRow.number}:C${divRow.number}`);
      divRow.height = 24;
      divRow.eachCell((cell, colNum) => {
        if (colNum >= 2) {
          cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFD1FAE5" } };
          cell.font = { name: "Arial", size: 10, bold: true, color: { argb: C.greenBg } };
          cell.alignment = { horizontal: "right", vertical: "middle" };
        }
      });
      divRow.getCell(3).alignment = { horizontal: "left", vertical: "middle" };

      for (const vid of vIds) {
        const u = voterMap.get(String(vid));
        const isCurrentExporter = String(vid) === currentUserIdStr;
        const note = isCurrentExporter ? "📤 مصدّر التقرير" : "";

        const row = detailSheet.addRow([
          rowIdx++,
          u?.fullName || "مستخدم غير مسجل",
          u?.username || "-",
          opt.text,
          u?.jobTitle || "-",
          getDeptName(u),
          getBranchName(u),
          formatRole(u?.role),
          note,
        ]);
        row.height = 24;

        const bg = rowIdx % 2 === 0 ? C.rowAlt2 : "FFFFFFFF";
        row.eachCell((cell, colNum) => {
          cell.font = { name: "Arial", size: 10, color: { argb: C.valueFont } };
          cell.alignment = { horizontal: "right", vertical: "middle", wrapText: true };
          if (bg !== "FFFFFFFF") {
            cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: bg } };
          }
        });
        row.getCell(1).alignment = { horizontal: "center", vertical: "middle" };
        row.getCell(3).alignment = { horizontal: "center", vertical: "middle" };
        row.getCell(7).alignment = { horizontal: "center", vertical: "middle" };
        row.getCell(8).alignment = { horizontal: "center", vertical: "middle" };
        row.getCell(9).alignment = { horizontal: "center", vertical: "middle" };
        row.getCell(9).font = { name: "Arial", size: 9, italic: true, color: { argb: "FF7C3AED" } };
      }
    }

    if (rowIdx === 1) {
      const emptyRow = detailSheet.addRow([
        "-",
        "لم يقم أي عضو بالتصويت في هذا الاستطلاع حتى الآن.",
        "", "", "", "", "", "", ""
      ]);
      detailSheet.mergeCells(`B${emptyRow.number}:I${emptyRow.number}`);
      emptyRow.getCell(2).font = { name: "Arial", italic: true, color: { argb: C.mutedFont } };
      emptyRow.getCell(2).alignment = { horizontal: "center", vertical: "middle" };
    }

    // Summary footer
    detailSheet.addRow([]);
    const footerRow = detailSheet.addRow([
      "", `إجمالي المصوتين: ${allVoterIds.length} مشارك`,
      `إجمالي الأصوات المسجلة: ${totalVotes}`,
      "", "", "", "", "", ""
    ]);
    detailSheet.mergeCells(`B${footerRow.number}:C${footerRow.number}`);
    footerRow.height = 26;
    footerRow.eachCell((cell, colNum) => {
      if (colNum >= 2) {
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: C.totalBg } };
        cell.font = { name: "Arial", size: 10, bold: true, color: { argb: C.totalFont } };
        cell.alignment = { horizontal: "right", vertical: "middle" };
        cell.border = { top: { style: "thin", color: { argb: C.headerBg } } };
      }
    });

    detailSheet.columns = [
      { width: 6 },
      { width: 28 },
      { width: 18 },
      { width: 32 },
      { width: 22 },
      { width: 22 },
      { width: 18 },
      { width: 14 },
      { width: 18 },
    ];
  }

  const buffer = await workbook.xlsx.writeBuffer();
  return {
    buffer,
    filename,
  };
}


async function updateConversationAvatar(currentUser, conversationId, file) {
  if (!file) {
    throw new ApiError(400, "صورة المحادثة مطلوبة.");
  }
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
  });
  if (!conversation) {
    throw new ApiError(404, "المحادثة غير موجودة.");
  }
  await assertConversationManagementAccess(currentUser, conversation);

  conversation.avatarUrl = `/api/chat/conversations/${conversationId}/avatar?v=${Date.now()}`;
  await conversation.save();

  const avatarDirectory = getConversationAvatarUploadsDir(conversationId);
  try {
    const entries = await fs.promises.readdir(avatarDirectory);
    for (const entry of entries) {
      const candidatePath = path.join(avatarDirectory, entry);
      if (candidatePath !== resolveStoredUploadPath(file.path)) {
        await deleteFileIfExists(candidatePath);
      }
    }
  } catch (_) {}

  await logAuditEvent({
    actorId: currentUser.id,
    action: "conversation.avatar.updated",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: { avatarUrl: conversation.avatarUrl },
  });

  return serializeConversation(conversation, currentUser.id);
}

async function removeConversationAvatar(currentUser, conversationId) {
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
  });
  if (!conversation) {
    throw new ApiError(404, "المحادثة غير موجودة.");
  }
  await assertConversationManagementAccess(currentUser, conversation);

  conversation.avatarUrl = null;
  await conversation.save();

  const avatarDirectory = getConversationAvatarUploadsDir(conversationId);
  try {
    const entries = await fs.promises.readdir(avatarDirectory);
    for (const entry of entries) {
      const candidatePath = path.join(avatarDirectory, entry);
      await deleteFileIfExists(candidatePath);
    }
  } catch (_) {}

  await logAuditEvent({
    actorId: currentUser.id,
    action: "conversation.avatar.removed",
    entityType: "Conversation",
    entityId: conversation._id,
    payload: {},
  });

  return serializeConversation(conversation, currentUser.id);
}

async function getConversationAvatarFilePath(conversationId) {
  const conversation = await Conversation.findOne({
    _id: conversationId,
    deletedAt: null,
  }).lean();
  if (!conversation) {
    throw new ApiError(404, "Avatar not found.");
  }

  const avatarDirectory = getConversationAvatarUploadsDir(conversationId);
  let entries = [];
  try {
    entries = await fs.promises.readdir(avatarDirectory);
  } catch (_) {
    throw new ApiError(404, "Avatar not found.");
  }
  if (!entries.length) {
    throw new ApiError(404, "Avatar not found.");
  }
  const latestEntry = entries
    .map((fileName) => ({
      fileName,
      filePath: path.join(avatarDirectory, fileName),
    }))
    .sort((a, b) => (a.fileName < b.fileName ? 1 : -1))[0];
  return latestEntry.filePath;
}


async function sanitizeBroadcastConversations() {
  try {
    const broadcastConversations = await Conversation.find({
      type: "broadcast",
      deletedAt: null,
    }).exec();

    let repairedCount = 0;
    for (const conv of broadcastConversations) {
      const creatorId = conv.createdBy ? conv.createdBy.toString() : null;
      const adminIds = new Set(
        (conv.admins || []).map((entry) => entry.toString()),
      );
      if (creatorId) {
        adminIds.add(creatorId);
      }

      const rawPublishers = (conv.broadcastPublisherIds || []).map((entry) =>
        entry.toString(),
      );
      const memberIds = new Set(
        (conv.members || []).map((entry) => entry.toString()),
      );

      let nextPublishers = rawPublishers;
      if (memberIds.size > 1 && rawPublishers.length >= memberIds.size) {
        nextPublishers = Array.from(adminIds);
      } else {
        nextPublishers = Array.from(new Set([...adminIds, ...rawPublishers]));
      }

      for (const pubId of nextPublishers) {
        memberIds.add(pubId);
      }

      const needsUpdate =
        conv.broadcastPublisherIds.length !== nextPublishers.length ||
        conv.admins.length !== adminIds.size ||
        conv.members.length !== memberIds.size;

      if (needsUpdate) {
        conv.broadcastPublisherIds = nextPublishers;
        conv.admins = Array.from(adminIds);
        conv.members = Array.from(memberIds);
        await conv.save();
        repairedCount++;
      }
    }
    if (repairedCount > 0) {
      logger.info(
        `[Broadcast Sanitization] Repaired ${repairedCount} broadcast channels in database.`
      );
    }
  } catch (err) {
    logger.error("[Broadcast Sanitization Error]:", err);
  }
}

module.exports = {
  updateConversationAvatar,
  removeConversationAvatar,
  getConversationAvatarFilePath,
  votePollMessage,
  exportPollToExcel,
  serializeUserLite,
  serializeConversation,
  serializeMessage,
  buildLastMessagePayload,
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
  markMessageDeliveredForUser,
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
  getMessageReadReceipts,
  sanitizeMessageContent,
  sanitizePinnedMessageContent,
  sanitizeBroadcastConversations,
};

async function getMessageReadReceipts(currentUser, messageId) {
  const message = await Message.findById(messageId)
    .populate("seenBy.userId", "username fullName avatarUrl")
    .populate("deliveredTo.userId", "username fullName avatarUrl")
    .exec();

  if (!message || message.isDeleted) {
    throw new ApiError(404, "Message not found.");
  }

  const conversation = await getConversationById(message.conversationId);
  await assertConversationAccess(currentUser, conversation);

  const senderIdStr = (message.senderId?._id || message.senderId)?.toString();

  const mapReceipt = (r) => {
    if (!r.userId) return null;
    const uid = (r.userId._id || r.userId).toString();
    // Exclude the sender so sender's authoring time is never mistaken for recipient reading it
    if (senderIdStr && uid === senderIdStr) return null;

    return {
      _id: r.userId._id,
      username: r.userId.username,
      fullName: r.userId.fullName,
      avatarUrl: r.userId.avatarUrl,
      displayName: r.userId.fullName || r.userId.username || "مستخدم",
      seenAt: r.at, // Frontend expects 'seenAt' for both read and delivery (or we can send at)
      deliveredAt: r.at,
    };
  };

  return {
    seenBy: message.seenBy.map(mapReceipt).filter(Boolean),
    deliveredTo: message.deliveredTo.map(mapReceipt).filter(Boolean),
  };
}

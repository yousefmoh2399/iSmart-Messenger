const express = require("express");
const rateLimit = require("express-rate-limit");
const { body, param, query } = require("express-validator");
const { chatUpload } = require("../utils/chat-upload");
const { chatTransferUpload } = require("../utils/chat-transfer-upload");
const {
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
  votePoll,
  exportPoll,
  postChatTransfer,
  downloadChatTransfer,
  getAuditLogs,
  getSystemErrors,
} = require("../controllers/chat.controller");
const { requireAuth } = require("../../middleware/auth.middleware");
const validateRequest = require("../../middleware/validate.middleware");

const router = express.Router();

const messageLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    message: "تم تجاوز عدد الرسائل المسموح في الدقيقة. حاول مرة أخرى بعد قليل.",
  },
});

router.use(requireAuth);

router.get("/users", getChatDirectoryUsers);
router.get("/roles", getChatRoles);
router.get("/conversations", getConversations);
router.get("/admin/conversations", getManageableConversations);
router.post("/transfers", chatTransferUpload.single("file"), postChatTransfer);
router.get(
  "/transfers/:id/download",
  [param("id").isString().trim().isLength({ min: 8, max: 64 })],
  validateRequest,
  downloadChatTransfer
);

router.post(
  "/conversations",
  [
    body("type")
      .isIn(["direct", "group", "department", "broadcast"])
      .withMessage("نوع المحادثة غير صالح."),
    body("name").optional().isString(),
    body("description").optional().isString(),
    body("memberIds").optional().isArray(),
    body("adminIds").optional().isArray(),
    body("departmentId").optional({ nullable: true }).isMongoId(),
  ],
  validateRequest,
  createChatConversation
);

router.get(
  "/conversations/:id",
  [param("id").isMongoId().withMessage("معرّف المحادثة غير صالح.")],
  validateRequest,
  getConversation
);

router.put(
  "/conversations/:id",
  [
    param("id").isMongoId().withMessage("معرّف المحادثة غير صالح."),
    body("name").optional().isString(),
    body("description").optional().isString(),
    body("memberIds").optional().isArray(),
    body("adminIds").optional().isArray(),
    body("isArchived").optional().isBoolean(),
    body("isActive").optional().isBoolean(),
  ],
  validateRequest,
  updateChatConversation
);

router.patch(
  "/conversations/:id/preferences",
  [
    param("id").isMongoId().withMessage("معرّف المحادثة غير صالح."),
    body("isMuted").optional().isBoolean(),
    body("isArchived").optional().isBoolean(),
    body("isPinned").optional().isBoolean(),
    body("isFavorite").optional().isBoolean(),
  ],
  validateRequest,
  updateChatConversationPreferences
);

router.patch(
  "/conversations/:id/pinned-message",
  [
    param("id").isMongoId().withMessage("معرّف المحادثة غير صالح."),
    body("content")
      .isString()
      .trim()
      .isLength({ min: 1, max: 2000 })
      .withMessage("محتوى الرسالة مطلوب."),
  ],
  validateRequest,
  setGroupPinnedMessage
);

router.delete(
  "/conversations/:id/pinned-message",
  [param("id").isMongoId().withMessage("معرّف المحادثة غير صالح.")],
  validateRequest,
  clearGroupPinnedMessage
);

router.delete(
  "/conversations/:id",
  [param("id").isMongoId().withMessage("معرّف المحادثة غير صالح.")],
  validateRequest,
  deleteChatConversation
);

router.post(
  "/conversations/:id/join",
  [param("id").isMongoId().withMessage("معرّف المحادثة غير صالح.")],
  validateRequest,
  joinChatConversation
);

router.post(
  "/conversations/:id/leave",
  [param("id").isMongoId().withMessage("معرّف المحادثة غير صالح.")],
  validateRequest,
  leaveChatConversation
);

router.get(
  "/conversations/:id/members",
  [param("id").isMongoId().withMessage("معرّف المحادثة غير صالح.")],
  validateRequest,
  getConversationMembers
);

router.post(
  "/conversations/:id/members",
  [
    param("id").isMongoId().withMessage("معرّف المحادثة غير صالح."),
    body("userIds").isArray({ min: 1 }).withMessage("قائمة الأعضاء مطلوبة."),
  ],
  validateRequest,
  addMembers
);

router.delete(
  "/conversations/:id/members/:userId",
  [
    param("id").isMongoId().withMessage("معرّف المحادثة غير صالح."),
    param("userId").isMongoId().withMessage("معرّف المستخدم غير صالح."),
  ],
  validateRequest,
  removeMember
);

router.post(
  "/conversations/:id/admins/:userId",
  [
    param("id").isMongoId().withMessage("معرّف المحادثة غير صالح."),
    param("userId").isMongoId().withMessage("معرّف المستخدم غير صالح."),
  ],
  validateRequest,
  promoteMemberAdmin
);

router.delete(
  "/conversations/:id/admins/:userId",
  [
    param("id").isMongoId().withMessage("معرّف المحادثة غير صالح."),
    param("userId").isMongoId().withMessage("معرّف المستخدم غير صالح."),
  ],
  validateRequest,
  demoteMemberAdmin
);

router.post(
  "/conversations/:id/blocked-members/:userId",
  [
    param("id").isMongoId().withMessage("معرّف المحادثة غير صالح."),
    param("userId").isMongoId().withMessage("معرّف المستخدم غير صالح."),
  ],
  validateRequest,
  blockMember
);

router.delete(
  "/conversations/:id/blocked-members/:userId",
  [
    param("id").isMongoId().withMessage("معرّف المحادثة غير صالح."),
    param("userId").isMongoId().withMessage("معرّف المستخدم غير صالح."),
  ],
  validateRequest,
  unblockMember
);

router.get(
  "/conversations/:id/messages",
  [
    param("id").isMongoId().withMessage("معرّف المحادثة غير صالح."),
    query("cursor").optional().isMongoId().withMessage("المؤشر غير صالح."),
    query("limit").optional().isInt({ min: 1, max: 100 }),
  ],
  validateRequest,
  getConversationMessages
);

router.post(
  "/messages",
  messageLimiter,
  chatUpload.single("file"),
  [
    body("conversationId")
      .isMongoId()
      .withMessage("معرّف المحادثة مطلوب."),
    body("content").optional().isString(),
    body("messageType")
      .optional()
      .isIn(["text", "file", "image", "pdf", "audio", "system", "poll", "gif"])
      .withMessage("نوع الرسالة غير صالح."),
    body("forwardFromMessageId").optional({ nullable: true }).isMongoId(),
    body("replyToMessageId").optional({ nullable: true }).isMongoId(),
    body("fileName").optional().isString().isLength({ min: 1, max: 255 }),
  ],
  validateRequest,
  postChatMessage
);

router.patch(
  "/messages/:id",
  [
    param("id").isMongoId().withMessage("معرّف الرسالة غير صالح."),
    body("content").isString().withMessage("محتوى الرسالة مطلوب."),
  ],
  validateRequest,
  patchChatMessage
);

router.patch(
  "/messages/:id/reactions",
  [
    param("id").isMongoId().withMessage("معرّف الرسالة غير صالح."),
    body("emoji").isString().notEmpty().withMessage("الإيموجي مطلوب."),
  ],
  validateRequest,
  reactToChatMessage
);

router.patch(
  "/messages/:id/favorite",
  toggleFavoriteChatMessage
);

router.patch(
  "/messages/:id/seen",
  [param("id").isMongoId().withMessage("معرّف الرسالة غير صالح.")],
  validateRequest,
  markSingleMessageSeen
);

router.post(
  "/messages/:id/poll/vote",
  [
    param("id").isMongoId().withMessage("معرّف الرسالة غير صالح."),
    body("optionIds").isArray().withMessage("يجب إرسال مصفوفة بالخيارات."),
  ],
  validateRequest,
  votePoll
);

router.get(
  "/messages/:id/poll/export",
  [param("id").isMongoId().withMessage("معرّف الرسالة غير صالح.")],
  validateRequest,
  exportPoll
);

router.delete(
  "/messages/:id",
  [param("id").isMongoId().withMessage("معرّف الرسالة غير صالح.")],
  validateRequest,
  removeMessage
);

router.post(
  "/conversations/:id/seen",
  [param("id").isMongoId().withMessage("معرّف المحادثة غير صالح.")],
  validateRequest,
  markSeen
);

router.get(
  "/admin/audit-logs",
  [
    query("departmentId").optional().isMongoId(),
    query("limit").optional().isInt({ min: 1, max: 200 }),
  ],
  validateRequest,
  getAuditLogs
);

router.get(
  "/admin/system-errors",
  [
    query("statusCode").optional().isInt({ min: 400, max: 599 }),
    query("limit").optional().isInt({ min: 1, max: 200 }),
  ],
  validateRequest,
  getSystemErrors
);

router.get(
  "/messages/favorites",
  [
    query("cursor").optional().isMongoId(),
    query("limit").optional().isInt({ min: 1, max: 100 }),
  ],
  validateRequest,
  getFavoriteChatMessages
);

router.get(
  "/search/messages",
  [
    query("q").optional().isString(),
    query("conversationId").optional().isMongoId(),
    query("cursor").optional().isMongoId(),
    query("limit").optional().isInt({ min: 1, max: 100 }),
  ],
  validateRequest,
  searchChatMessages
);

router.get(
  "/presence/:userId",
  [param("userId").isMongoId().withMessage("معرّف المستخدم غير صالح.")],
  validateRequest,
  getPresence
);

router.get(
  "/messages/:conversationId/:storedName/file",
  [param("conversationId").isMongoId().withMessage("معرّف المحادثة غير صالح.")],
  validateRequest,
  getAttachmentFile
);

router.get(
  "/messages/:conversationId/:storedName/download",
  [param("conversationId").isMongoId().withMessage("معرّف المحادثة غير صالح.")],
  validateRequest,
  downloadAttachment
);

router.post(
  "/messages/:id/rehydrate/request",
  [param("id").isMongoId().withMessage("Invalid message id.")],
  validateRequest,
  requestAttachmentRestore
);

router.post(
  "/messages/:id/rehydrate",
  chatUpload.single("file"),
  [param("id").isMongoId().withMessage("Invalid message id.")],
  validateRequest,
  restoreAttachment
);

module.exports = router;

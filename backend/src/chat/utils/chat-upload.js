const { maxFileSizeBytes } = require("../../config/env");
const {
  getChatUploadsDir,
  resolveUploadPath,
} = require("../../utils/storage-paths");
const {
  scheduleUploadRetentionCleanup,
} = require("../../utils/upload-retention");
const {
  buildTimestampedName,
  createBlocklistFilter,
  createDiskUpload,
} = require("../../utils/upload.util");

const TWO_HUNDRED_MB = 200 * 1024 * 1024;
const CHAT_MAX_FILE_SIZE_BYTES = Math.max(maxFileSizeBytes, 1024 * 1024 * 1024); // 1GB global limit, controller enforces precise limits
const CHAT_BLOCKED_FILE_MESSAGE =
  "هذا النوع من الملفات غير مسموح إرساله في الشات.";

const chatUpload = createDiskUpload({
  resolveDestination: (req) =>
    getChatUploadsDir(req.body.conversationId || "general"),
  resolveFilename: (req, file) => buildTimestampedName(file),
  fileFilter: createBlocklistFilter({ message: CHAT_BLOCKED_FILE_MESSAGE }),
  limits: {
    fileSize: CHAT_MAX_FILE_SIZE_BYTES,
  },
});


module.exports = {
  chatUpload,
};

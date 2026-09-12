const { maxFileSizeBytes } = require("../../config/env");
const { getChatTransferUploadsDir } = require("../../utils/storage-paths");
const {
  buildTimestampedName,
  createBlocklistFilter,
  createDiskUpload,
} = require("../../utils/upload.util");

const TWO_HUNDRED_MB = 200 * 1024 * 1024;
const TRANSFER_MAX_FILE_SIZE_BYTES = Math.min(maxFileSizeBytes, TWO_HUNDRED_MB);
const CHAT_BLOCKED_FILE_MESSAGE =
  "هذا النوع من الملفات غير مسموح إرساله في الشات.";

const chatTransferUpload = createDiskUpload({
  resolveDestination: (req) =>
    getChatTransferUploadsDir(String(req.user?.id || "anonymous")),
  resolveFilename: (req, file) => buildTimestampedName(file),
  fileFilter: createBlocklistFilter({ message: CHAT_BLOCKED_FILE_MESSAGE }),
  limits: {
    fileSize: TRANSFER_MAX_FILE_SIZE_BYTES,
  },
});

module.exports = {
  chatTransferUpload,
};

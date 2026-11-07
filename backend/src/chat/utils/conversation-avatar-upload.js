const { maxFileSizeBytes } = require("../../config/env");
const { getConversationAvatarUploadsDir } = require("../../utils/storage-paths");
const {
  buildTimestampedName,
  createAllowlistFilter,
  createDiskUpload,
} = require("../../utils/upload.util");

const conversationAvatarUpload = createDiskUpload({
  resolveDestination: (req) => getConversationAvatarUploadsDir(req.params.id),
  resolveFilename: (req, file) =>
    buildTimestampedName(file, { defaultExtension: ".jpg" }),
  fileFilter: createAllowlistFilter({
    allowedMimeTypes: ["image/png", "image/jpeg", "image/jpg", "image/webp"],
    message: "فقط ملفات الصور (PNG, JPG, JPEG, WEBP) مسموحة كصورة للمحادثة.",
  }),
  limits: {
    fileSize: Math.min(maxFileSizeBytes, 10 * 1024 * 1024),
  },
});

module.exports = {
  conversationAvatarUpload,
};

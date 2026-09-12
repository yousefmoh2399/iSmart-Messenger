const { maxFileSizeBytes } = require("../config/env");
const { getAvatarUploadsDir } = require("./storage-paths");
const {
  buildTimestampedName,
  createAllowlistFilter,
  createDiskUpload,
} = require("./upload.util");

const avatarUpload = createDiskUpload({
  resolveDestination: (req) => getAvatarUploadsDir(req.user.id),
  resolveFilename: (req, file) =>
    buildTimestampedName(file, { defaultExtension: ".jpg" }),
  fileFilter: createAllowlistFilter({
    allowedMimeTypes: ["image/png", "image/jpeg", "image/jpg", "image/webp"],
    message: "Only PNG, JPG, JPEG, and WEBP avatars are allowed.",
  }),
  limits: {
    fileSize: Math.min(maxFileSizeBytes, 5 * 1024 * 1024),
  },
});

module.exports = {
  avatarUpload,
};

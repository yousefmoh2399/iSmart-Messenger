const path = require("path");
const { getUploadsRoot } = require("../utils/storage-paths");
const {
  buildTimestampedName,
  createAllowlistFilter,
  createDiskUpload,
} = require("../utils/upload.util");

const allowedExtensions = [
  ".pdf", ".png", ".jpg", ".jpeg", ".webp", ".xlsx", ".xls", ".doc", ".docx", ".csv", ".txt",
];

const itAssetsUpload = createDiskUpload({
  resolveDestination: () => path.join(getUploadsRoot(), "it-assets"),
  resolveFilename: (req, file) => buildTimestampedName(file),
  fileFilter: createAllowlistFilter({
    allowedExtensions,
    message: "نوع المرفق غير مدعوم.",
  }),
  limits: { fileSize: 20 * 1024 * 1024 },
});

module.exports = { itAssetsUpload };

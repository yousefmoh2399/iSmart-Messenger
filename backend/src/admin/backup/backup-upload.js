const path = require("path");
const { getBackupsRoot } = require("../../utils/storage-paths");
const {
  randomToken,
  createAllowlistFilter,
  createDiskUpload,
} = require("../../utils/upload.util");

const ZIP_FILE_NAME_PATTERN = /^[a-zA-Z0-9._-]+\.zip$/;
const BACKUP_UPLOAD_MAX_BYTES =
  Number(process.env.BACKUP_UPLOAD_MAX_GB || 5) * 1024 * 1024 * 1024;

function sanitizeBackupFileName(originalName) {
  const base = path.basename(String(originalName || "")).trim();
  const timestamp = Date.now();
  const token = randomToken(6);
  if (ZIP_FILE_NAME_PATTERN.test(base)) {
    return `uploaded_${timestamp}_${token}_${base}`.slice(-220);
  }
  return `uploaded_backup_${timestamp}_${token}.zip`;
}

const backupUpload = createDiskUpload({
  resolveDestination: () => getBackupsRoot(),
  resolveFilename: (req, file) => sanitizeBackupFileName(file.originalname),
  fileFilter: createAllowlistFilter({
    allowedMimeTypes: ["application/zip"],
    allowedExtensions: [".zip"],
    message: "Only .zip backup files are allowed.",
  }),
  limits: {
    fileSize: BACKUP_UPLOAD_MAX_BYTES,
  },
});

module.exports = {
  backupUpload,
};

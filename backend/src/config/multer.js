const { maxFileSizeBytes } = require("./env");
const {
  getDocumentsUploadsDir,
  resolveUploadPath,
} = require("../utils/storage-paths");
const {
  scheduleUploadRetentionCleanup,
} = require("../utils/upload-retention");
const {
  buildTimestampedName,
  createAllowlistFilter,
  createDiskUpload,
} = require("../utils/upload.util");

const upload = createDiskUpload({
  resolveDestination: (req) => getDocumentsUploadsDir(req.user.id),
  resolveFilename: (req, file) =>
    buildTimestampedName(file, { extension: ".pdf" }),
  fileFilter: createAllowlistFilter({
    allowedMimeTypes: ["application/pdf"],
    allowedExtensions: [".pdf"],
    message: "Only PDF files are allowed.",
  }),
  limits: {
    fileSize: maxFileSizeBytes,
  },
});


module.exports = {
  upload,
};

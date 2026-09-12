const fs = require("fs");
const path = require("path");
const multer = require("multer");

const ApiError = require("./api-error");

// Executable / script file types that must never be accepted as user uploads.
const DANGEROUS_UPLOAD_EXTENSIONS = new Set([
  ".app",
  ".bat",
  ".cmd",
  ".com",
  ".cpl",
  ".dll",
  ".exe",
  ".hta",
  ".jar",
  ".js",
  ".jse",
  ".lnk",
  ".msi",
  ".msp",
  ".ps1",
  ".reg",
  ".scr",
  ".sh",
  ".vb",
  ".vbe",
  ".vbs",
  ".wsf",
]);

const DANGEROUS_UPLOAD_MIME_PREFIXES = [
  "application/x-ms",
  "application/x-dosexec",
  "application/x-msdownload",
  "application/x-sh",
];

function ensureDirectoryExists(directoryPath) {
  fs.mkdirSync(directoryPath, { recursive: true });
}

function randomToken(length = 8) {
  return Math.random()
    .toString(36)
    .slice(2, 2 + length);
}

function lowerExtension(originalName) {
  return path.extname(originalName || "").toLowerCase();
}

// Builds a collision-resistant `${timestamp}-${token}${ext}` name. Pass an
// explicit `extension` to force one (e.g. always ".pdf"), otherwise the
// original file extension is used, falling back to `defaultExtension`.
function buildTimestampedName(
  file,
  { extension, defaultExtension = "", tokenLength = 8 } = {},
) {
  const token = randomToken(tokenLength);
  let ext = extension;
  if (ext === undefined) {
    ext = lowerExtension(file && file.originalname) || defaultExtension;
  }
  return `${Date.now()}-${token}${ext}`;
}

// Filter that accepts a file when its mime type is in `allowedMimeTypes` OR
// its extension is in `allowedExtensions`. Pass only one to enforce a single
// dimension (e.g. mime-only for avatars, extension-only for artifacts).
function createAllowlistFilter({
  allowedMimeTypes,
  allowedExtensions,
  message,
}) {
  const mimeTypes = allowedMimeTypes ? new Set(allowedMimeTypes) : null;
  const extensions = allowedExtensions ? new Set(allowedExtensions) : null;

  return (req, file, cb) => {
    const mimeType = String(file.mimetype || "").toLowerCase();
    const ext = lowerExtension(file.originalname);
    const mimeOk = mimeTypes ? mimeTypes.has(mimeType) : false;
    const extOk = extensions ? extensions.has(ext) : false;

    if (mimeOk || extOk) {
      cb(null, true);
      return;
    }

    cb(new ApiError(400, message));
  };
}

// Filter that rejects files whose extension is in `blockedExtensions` or whose
// mime type starts with one of `blockedMimePrefixes`, accepting everything else.
function createBlocklistFilter({
  blockedExtensions = DANGEROUS_UPLOAD_EXTENSIONS,
  blockedMimePrefixes = DANGEROUS_UPLOAD_MIME_PREFIXES,
  message,
}) {
  return (req, file, cb) => {
    const ext = lowerExtension(file.originalname);
    const mimeType = String(file.mimetype || "").toLowerCase();

    if (
      blockedExtensions.has(ext) ||
      blockedMimePrefixes.some((prefix) => mimeType.startsWith(prefix))
    ) {
      cb(new ApiError(400, message));
      return;
    }

    cb(null, true);
  };
}

// Wraps the shared multer disk-storage pattern: resolve a destination
// directory (created if missing) and a stored file name per request.
function createDiskUpload({
  resolveDestination,
  resolveFilename,
  fileFilter,
  limits,
}) {
  const storage = multer.diskStorage({
    destination: (req, file, cb) => {
      const targetDirectory = resolveDestination(req, file);
      ensureDirectoryExists(targetDirectory);
      cb(null, targetDirectory);
    },
    filename: (req, file, cb) => {
      cb(null, resolveFilename(req, file));
    },
  });

  return multer({ storage, fileFilter, limits });
}

module.exports = {
  DANGEROUS_UPLOAD_EXTENSIONS,
  DANGEROUS_UPLOAD_MIME_PREFIXES,
  ensureDirectoryExists,
  randomToken,
  buildTimestampedName,
  createAllowlistFilter,
  createBlocklistFilter,
  createDiskUpload,
};

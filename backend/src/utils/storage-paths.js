const fs = require("fs/promises");
const path = require("path");
const envConfig = require("../config/env");

// When bundled with pkg, __dirname points inside the frozen snapshot.
// Use the directory containing the actual executable so that mutable
// data (uploads, backups, releases) is written on real disk next to the EXE.
const BACKEND_ROOT = process.pkg
  ? path.dirname(process.execPath)
  : path.resolve(__dirname, "../..");


function getBackendRoot() {
  return BACKEND_ROOT;
}

function getUploadsRoot() {
  return envConfig.uploadDir;
}

function getBackupsRoot() {
  return envConfig.backupsDir;
}

function getUpdateReleasesRoot() {
  return envConfig.updateReleasesDir;
}

function resolveStorageRoot(configuredValue, fallbackDirectoryName) {
  // Not used directly for roots anymore, but kept for signature compatibility if needed
  return path.join(envConfig.DATA_DIR, fallbackDirectoryName);
}

function sanitizePathSegment(segment, fallback = "") {
  const value = String(segment ?? "")
    .replace(/\\/g, "/")
    .trim();
  if (!value) {
    return fallback;
  }

  const parts = value
    .split("/")
    .map((entry) => entry.trim())
    .filter(Boolean);

  const sanitizedParts = [];
  for (const part of parts) {
    if (part === "." || part === "..") {
      continue;
    }
    sanitizedParts.push(part.replace(/[<>:"|?*\x00-\x1F]/g, "_"));
  }

  return sanitizedParts.join(path.sep);
}

function isPathInsideRoot(rootPath, targetPath) {
  const root = path.resolve(rootPath);
  const target = path.resolve(targetPath);
  const relative = path.relative(root, target);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function resolveUploadPath(...segments) {
  const root = getUploadsRoot();
  const safeSegments = segments
    .map((segment) => sanitizePathSegment(segment))
    .filter(Boolean);
  const resolved = path.resolve(root, ...safeSegments);

  if (!isPathInsideRoot(root, resolved)) {
    throw new Error("Resolved path escapes uploads root.");
  }

  return resolved;
}

function getChatUploadsDir(scopeId) {
  return resolveUploadPath("chat", scopeId);
}

function getChatTransferUploadsDir(userId) {
  return resolveUploadPath("chat_transfers", userId);
}

function getAvatarUploadsDir(userId) {
  return resolveUploadPath("avatars", userId);
}

function getDocumentsUploadsDir(userId) {
  return resolveUploadPath(userId);
}

async function ensureDirectory(directoryPath) {
  await fs.mkdir(directoryPath, { recursive: true });
  return directoryPath;
}

async function fileExists(filePath) {
  if (!filePath) {
    return false;
  }
  try {
    await fs.access(filePath);
    return true;
  } catch (_) {
    return false;
  }
}

function toRelativeUploadPath(filePath) {
  if (!filePath) {
    return null;
  }
  const resolved = path.resolve(filePath);
  const uploadsRoot = getUploadsRoot();
  if (!isPathInsideRoot(uploadsRoot, resolved)) {
    throw new Error("File path is outside uploads root.");
  }
  return path.relative(uploadsRoot, resolved);
}

function normalizeStoredPathInput(storedPath) {
  return String(storedPath || "")
    .replace(/\\/g, "/")
    .trim();
}

function extractRelativePathFromLegacyAbsolute(storedPath) {
  const normalized = normalizeStoredPathInput(storedPath);
  const uploadsBaseName = path.basename(getUploadsRoot()).toLowerCase();
  const parts = normalized.split("/").filter(Boolean);
  const rootIndex = parts.findIndex(
    (part) => part.trim().toLowerCase() === uploadsBaseName,
  );

  if (rootIndex < 0) {
    return null;
  }

  const relativeParts = parts.slice(rootIndex + 1);
  if (!relativeParts.length) {
    return null;
  }

  return path.join(...relativeParts);
}

function resolveStoredUploadPath(storedPath) {
  const raw = String(storedPath || "").trim();
  if (!raw) {
    return null;
  }

  const uploadsRoot = getUploadsRoot();

  if (!path.isAbsolute(raw)) {
    const normalizedRelative = normalizeStoredPathInput(raw);
    const uploadsPrefix = `${path.basename(uploadsRoot).toLowerCase()}/`;
    const relativeWithoutPrefix = normalizedRelative.toLowerCase().startsWith(uploadsPrefix)
      ? normalizedRelative.slice(uploadsPrefix.length)
      : normalizedRelative;
    return resolveUploadPath(relativeWithoutPrefix);
  }

  const normalizedAbsolute = path.resolve(raw);
  if (isPathInsideRoot(uploadsRoot, normalizedAbsolute)) {
    return normalizedAbsolute;
  }

  const relativePath = extractRelativePathFromLegacyAbsolute(raw);
  if (!relativePath) {
    return null;
  }

  return resolveUploadPath(relativePath);
}

function resolveStoredUpdateReleasePath(storedPath) {
  return resolveStoredPathInRoot(storedPath, getUpdateReleasesRoot(), [
    "releases",
  ]);
}

function resolveStoredPathInRoot(storedPath, rootPath, legacyRootBaseNames = []) {
  const raw = String(storedPath || "").trim();
  if (!raw) {
    return null;
  }

  const root = path.resolve(rootPath);
  if (!path.isAbsolute(raw)) {
    const resolved = path.resolve(root, normalizeStoredPathInput(raw));
    return isPathInsideRoot(root, resolved) ? resolved : null;
  }

  const normalizedAbsolute = path.resolve(raw);
  if (isPathInsideRoot(root, normalizedAbsolute)) {
    return normalizedAbsolute;
  }

  const normalized = normalizeStoredPathInput(raw);
  const rootBaseNames = new Set(
    [path.basename(root), ...legacyRootBaseNames]
      .map((entry) => String(entry || "").trim().toLowerCase())
      .filter(Boolean),
  );
  const parts = normalized.split("/").filter(Boolean);
  const rootIndex = parts.findIndex(
    (part) => rootBaseNames.has(part.trim().toLowerCase()),
  );
  if (rootIndex < 0 || rootIndex >= parts.length - 1) {
    return normalizedAbsolute;
  }

  return path.resolve(root, ...parts.slice(rootIndex + 1));
}

module.exports = {
  getBackendRoot,
  getUploadsRoot,
  getBackupsRoot,
  getUpdateReleasesRoot,
  resolveUploadPath,
  getChatUploadsDir,
  getChatTransferUploadsDir,
  getAvatarUploadsDir,
  getDocumentsUploadsDir,
  ensureDirectory,
  fileExists,
  toRelativeUploadPath,
  resolveStoredUploadPath,
  resolveStoredUpdateReleasePath,
  isPathInsideRoot,
  sanitizePathSegment,
};

const fs = require("fs");
const crypto = require("crypto");
const path = require("path");
const ApiError = require("../../utils/api-error");
const {
  fileExists,
  resolveStoredUploadPath,
  resolveUploadPath,
  toRelativeUploadPath,
} = require("../../utils/storage-paths");

const transferStore = new Map();
const TRANSFER_TTL_MS = 30 * 60 * 1000;

function sanitizeFileName(input, fallback = "file") {
  const cleaned = String(input || "")
    .replace(/[\\/:*?"<>|]/g, "_")
    .trim();
  return cleaned || fallback;
}

function normalizeMimeType(value) {
  const mimeType = String(value || "")
    .trim()
    .slice(0, 160);
  return mimeType || null;
}

function cleanupExpiredTransfers() {
  const now = Date.now();
  for (const [transferId, transfer] of transferStore.entries()) {
    if (transfer.expiresAtMs > now) {
      continue;
    }
    deleteTransferArtifacts(transfer);
  }
}

const cleanupInterval = setInterval(cleanupExpiredTransfers, 5 * 60 * 1000);
if (typeof cleanupInterval.unref === "function") {
  cleanupInterval.unref();
}

function buildTransferDownloadUrl(transferId) {
  return `/api/chat/transfers/${transferId}/download`;
}

function getTransferMetaPath(userId, transferId) {
  return resolveUploadPath(
    "chat_transfers_meta",
    String(userId || "anonymous"),
    `${String(transferId || "transfer").trim()}.json`,
  );
}

function persistTransferMetadata(transfer) {
  const metaPath = getTransferMetaPath(transfer.ownerUserId, transfer.id);
  fs.mkdirSync(path.dirname(metaPath), { recursive: true });
  fs.writeFileSync(metaPath, JSON.stringify(transfer, null, 2));
}

function loadTransferMetadata(userId, transferId) {
  try {
    const metaPath = getTransferMetaPath(userId, transferId);
    if (!fs.existsSync(metaPath)) {
      return null;
    }
    const raw = fs.readFileSync(metaPath, "utf8");
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch (_) {
    return null;
  }
}

function deleteTransferMetadata(transfer) {
  try {
    const metaPath = getTransferMetaPath(transfer.ownerUserId, transfer.id);
    if (fs.existsSync(metaPath)) {
      fs.unlinkSync(metaPath);
    }
  } catch (_) {}
}

function deleteTransferArtifacts(transfer) {
  transferStore.delete(transfer.id);
  deleteTransferMetadata(transfer);
  try {
    const resolvedPath = resolveStoredUploadPath(transfer.storedFilePath);
    if (resolvedPath) {
      fs.unlinkSync(resolvedPath);
    }
  } catch (_) {}
}

function serializeTransfer(transfer) {
  return {
    id: transfer.id,
    fileName: transfer.fileName,
    mimeType: transfer.mimeType,
    fileSize: transfer.fileSize,
    source: transfer.source,
    createdAt: transfer.createdAt,
    expiresAt: transfer.expiresAt,
    downloadUrl: buildTransferDownloadUrl(transfer.id),
  };
}

function createChatTransfer(actor, file, payload = {}) {
  cleanupExpiredTransfers();

  if (!file?.path) {
    throw new ApiError(400, "A transfer file is required.");
  }

  const id = crypto.randomBytes(18).toString("hex");
  const fileName = sanitizeFileName(
    payload.fileName || file.originalname,
    "file"
  );
  const mimeType = normalizeMimeType(payload.mimeType || file.mimetype);
  const source =
    String(payload.source || "unknown")
      .trim()
      .slice(0, 64) || "unknown";
  const createdAt = new Date();
  const expiresAtMs = createdAt.getTime() + TRANSFER_TTL_MS;

  const transfer = {
    id,
    ownerUserId: String(actor.id),
    storedFilePath: toRelativeUploadPath(file.path),
    fileName,
    mimeType,
    fileSize: Number(file.size || 0),
    source,
    createdAt: createdAt.toISOString(),
    expiresAt: new Date(expiresAtMs).toISOString(),
    expiresAtMs,
  };

  transferStore.set(id, transfer);
  persistTransferMetadata(transfer);
  return serializeTransfer(transfer);
}

async function getChatTransferForUser(actor, transferId) {
  cleanupExpiredTransfers();
  const id = String(transferId || "").trim();
  if (!id) {
    throw new ApiError(400, "Transfer id is required.");
  }

  let transfer = transferStore.get(id);
  if (!transfer) {
    transfer = loadTransferMetadata(actor.id, id);
    if (transfer) {
      transferStore.set(id, transfer);
    }
  }
  if (!transfer) {
    throw new ApiError(404, "Transfer not found or expired.");
  }

  if (transfer.ownerUserId !== String(actor.id)) {
    throw new ApiError(403, "You are not allowed to access this transfer.");
  }

  if (Number(transfer.expiresAtMs || 0) <= Date.now()) {
    deleteTransferArtifacts(transfer);
    throw new ApiError(404, "Transfer not found or expired.");
  }

  const resolvedPath = resolveStoredUploadPath(transfer.storedFilePath);
  if (!resolvedPath || !(await fileExists(resolvedPath))) {
    deleteTransferMetadata(transfer);
    transferStore.delete(id);
    throw new ApiError(404, "Transfer file is no longer available.");
  }

  return transfer;
}

module.exports = {
  buildTransferDownloadUrl,
  createChatTransfer,
  getChatTransferForUser,
};

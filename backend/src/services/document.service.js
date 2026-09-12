const path = require("path");
const Document = require("../models/document.model");
const ApiError = require("../utils/api-error");
const { baseUrl } = require("../config/env");
const { deleteFileIfExists } = require("../utils/file.util");
const { toRelativeUploadPath } = require("../utils/storage-paths");

function normalizeDocumentName(fileName) {
  const trimmed = String(fileName || "").trim();
  if (!trimmed) {
    throw new ApiError(400, "Document name is required.");
  }

  return trimmed.toLowerCase().endsWith(".pdf") ? trimmed : `${trimmed}.pdf`;
}

function serializeDocument(document) {
  const owner =
    document.userId && typeof document.userId === "object"
      ? document.userId
      : null;

  return {
    id: document._id.toString(),
    fileName: document.fileName,
    originalName: document.originalName,
    storedName: document.storedName,
    mimeType: document.mimeType,
    pageCount: document.pageCount,
    fileSize: document.fileSize,
    createdAt: document.createdAt,
    updatedAt: document.updatedAt,
    ownerId: owner?._id?.toString?.() || document.userId?.toString?.() || null,
    ownerUsername: owner?.username || null,
    ownerFullName: owner?.fullName || null,
    localSyncStatus: document.localSyncStatus || "none",
    localSyncedAt: document.localSyncedAt || null,
    localSyncRequestedAt: document.localSyncRequestedAt || null,
    downloadUrl: `${baseUrl}/api/documents/${document._id.toString()}/download`,
  };
}

async function listDocumentsPage(query, options = {}) {
  const page = Math.max(1, Math.min(Number(options.page || 1), 100000));
  const limit = Math.max(1, Math.min(Number(options.limit || 40), 100));
  const skip = (page - 1) * limit;
  const [documents, total] = await Promise.all([
    Document.find(query)
      .populate("userId", "username fullName")
      .sort({ createdAt: -1, _id: -1 })
      .skip(skip)
      .limit(limit)
      .lean(),
    Document.countDocuments(query),
  ]);
  return {
    documents: documents.map(serializeDocument),
    pagination: {
      page,
      limit,
      total,
      hasMore: page * limit < total,
    },
  };
}

async function listUserDocuments(userId, options = {}) {
  return listDocumentsPage({ userId }, options);
}

async function listManageableDocuments(actor, options = {}) {
  if (actor?.role !== "admin") {
    throw new ApiError(403, "Admin access required.");
  }

  return listDocumentsPage({}, options);
}

async function getAccessibleDocument(actor, documentId) {
  const query =
    actor?.role === "admin"
      ? { _id: documentId }
      : { _id: documentId, userId: actor?.id || actor };

  const document = await Document.findOne(query)
    .populate("userId", "username fullName")
    .exec();

  if (!document) {
    throw new ApiError(404, "Document not found.");
  }

  return document;
}

async function getOwnedDocument(userId, documentId) {
  return getAccessibleDocument(userId, documentId);
}

async function createDocumentForUser(userId, file, payload) {
  if (!file) {
    throw new ApiError(400, "PDF file is required.");
  }

  const fileName = normalizeDocumentName(payload.fileName || file.originalname);
  const pageCount = Number(payload.pageCount || 1);

  if (!Number.isFinite(pageCount) || pageCount < 1) {
    throw new ApiError(400, "Page count must be a positive number.");
  }

  const localSyncTarget = String(payload.localSyncTarget || "").trim();
  const localSyncStatus = localSyncTarget === "desktop" ? "pending" : "none";

  const document = await Document.create({
    userId,
    fileName,
    originalName: file.originalname,
    storedName: path.basename(file.path),
    filePath: toRelativeUploadPath(file.path),
    mimeType: file.mimetype || "application/pdf",
    pageCount,
    fileSize: file.size,
    localSyncStatus,
    localSyncRequestedAt: localSyncStatus === "pending" ? new Date() : null,
  });

  return serializeDocument(document);
}

async function listPendingLocalSyncDocuments(actor) {
  const documents = await Document.find({
    userId: actor.id || actor,
    localSyncStatus: "pending",
  })
    .sort({ createdAt: 1 })
    .lean();
  return documents.map(serializeDocument);
}

async function markDocumentLocalSynced(actor, documentId) {
  const document = await getAccessibleDocument(actor, documentId);
  if (document.localSyncStatus !== "pending") {
    return serializeDocument(document);
  }
  await deleteFileIfExists(document.filePath);
  document.filePath = `local-only:${document._id.toString()}`;
  document.localSyncStatus = "synced";
  document.localSyncedAt = new Date();
  await document.save();
  return serializeDocument(document);
}

async function getDocumentDetails(actor, documentId) {
  const document = await getAccessibleDocument(actor, documentId);
  return serializeDocument(document);
}

async function renameDocument(actor, documentId, nextName) {
  const document = await getAccessibleDocument(actor, documentId);
  document.fileName = normalizeDocumentName(nextName);
  await document.save();
  return serializeDocument(document);
}

async function deleteDocument(actor, documentId) {
  const document = await getAccessibleDocument(actor, documentId);
  await deleteFileIfExists(document.filePath);
  await document.deleteOne();
}

module.exports = {
  listUserDocuments,
  listManageableDocuments,
  getAccessibleDocument,
  getOwnedDocument,
  createDocumentForUser,
  getDocumentDetails,
  renameDocument,
  deleteDocument,
  listPendingLocalSyncDocuments,
  markDocumentLocalSynced,
  serializeDocument,
};

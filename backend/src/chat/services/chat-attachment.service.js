const path = require("path");

const imageExtensions = new Set([
  ".png",
  ".jpg",
  ".jpeg",
  ".webp",
  ".gif",
  ".bmp",
]);

const audioExtensions = new Set([
  ".aac",
  ".m4a",
  ".mp3",
  ".wav",
  ".ogg",
  ".webm",
  ".opus",
]);

function sanitizeMetadataValue(value, maxLength = 255) {
  return String(value || "").trim().slice(0, maxLength);
}

function classifyAttachment(file) {
  if (!file) {
    return { messageType: "text", fileUrl: null, fileName: null, fileSize: null, mimeType: null };
  }

  const mimeType = sanitizeMetadataValue(file.mimetype, 120);
  const fileName = sanitizeMetadataValue(file.originalname, 255);
  const extension = path.extname(fileName || file.path || "").toLowerCase();
  let messageType = "file";

  if (mimeType.startsWith("image/") || imageExtensions.has(extension)) {
    messageType = "image";
  } else if (mimeType === "application/pdf" || extension === ".pdf") {
    messageType = "pdf";
  } else if (mimeType.startsWith("audio/") || audioExtensions.has(extension)) {
    messageType = "audio";
  }

  return {
    messageType,
    fileUrl: `/api/chat/messages/${file.conversationId}/${path.basename(file.path)}/file`,
    fileName,
    fileSize: Number(file.size || 0),
    mimeType,
  };
}

module.exports = {
  classifyAttachment,
};

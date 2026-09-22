const path = require("path");
const fs = require("fs").promises;

const { fileExists, resolveStoredUploadPath } = require("./storage-paths");

async function sendUploadFile(
  res,
  storedPath,
  {
    contentType,
    disposition,
    fileName,
    cacheControl,
    notFoundMessage = "File not found.",
    logLabel = "upload-file",
  } = {},
) {
  const resolvedPath = resolveStoredUploadPath(storedPath);
  if (!resolvedPath || !(await fileExists(resolvedPath))) {
    console.warn(`[${logLabel}] Missing file`, {
      storedPath,
      resolvedPath,
    });
    res.status(404).json({ message: notFoundMessage });
    return;
  }

  if (cacheControl) {
    res.setHeader("Cache-Control", cacheControl);
  }

  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Cross-Origin-Resource-Policy", "cross-origin");
  res.setHeader("Timing-Allow-Origin", "*");

  // Set Content-Length so clients can show accurate download progress
  try {
    const { size } = await fs.stat(resolvedPath);
    if (size > 0) {
      res.setHeader("Content-Length", String(size));
    }
  } catch (_) {}

  const resolvedContentType = contentType || inferContentType(resolvedPath);
  if (resolvedContentType) {
    res.setHeader("Content-Type", resolvedContentType);
  }
  if (disposition) {
    const resolvedFileName = String(fileName || path.basename(resolvedPath)).trim() || "file";
    res.setHeader(
      "Content-Disposition",
      `${disposition}; filename="${encodeURIComponent(resolvedFileName)}"`,
    );
  }

  res.sendFile(resolvedPath, (error) => {
    if (!error) {
      return;
    }

    console.warn(`[${logLabel}] sendFile failed`, {
      storedPath,
      resolvedPath,
      code: error.code,
      message: error.message,
    });

    if (res.headersSent) {
      return;
    }

    if (error.code === "ENOENT") {
      res.status(404).json({ message: notFoundMessage });
      return;
    }

    res.status(500).json({ message: "Failed to read file." });
  });
}

module.exports = {
  sendUploadFile,
};

function inferContentType(filePath) {
  switch (path.extname(filePath || "").toLowerCase()) {
    case ".png":
      return "image/png";
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".webp":
      return "image/webp";
    case ".gif":
      return "image/gif";
    case ".bmp":
      return "image/bmp";
    case ".pdf":
      return "application/pdf";
    case ".mp3":
      return "audio/mpeg";
    case ".wav":
      return "audio/wav";
    case ".ogg":
      return "audio/ogg";
    case ".webm":
      return "audio/webm";
    default:
      return null;
  }
}

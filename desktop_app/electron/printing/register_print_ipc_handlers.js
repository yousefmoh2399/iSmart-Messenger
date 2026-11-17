const fs = require("fs");
const path = require("path");

function registerPrintIpcHandlers({
  ipcMain,
  pdfPrintService,
  htmlPrintService,
  app,
  downloadFileAndValidate,
  fsOverride,
  pathOverride,
  loggerOverride
}) {
  const _fs = fsOverride || fs;
  const _path = pathOverride || path;
  const _logger = loggerOverride || {
    info: console.log,
    warn: console.warn,
    error: console.error
  };

  function uniqueOutputPath(directory, fileName) {
    const ext = _path.extname(fileName || "") || ".pdf";
    const base = _path.basename(fileName || "print_job", ext);
    // Sanitize base name to remove problematic characters
    const cleanBase = base.replace(/[/\\?%*:|"<>]/g, "_").trim() || "print_job";
    const timestamp = Date.now();
    const nonce = Math.random().toString(36).slice(2, 8);
    // Unique name incorporating timestamp and random nonce ensures zero collisions with locked or delete-pending files
    const uniqueFileName = `${cleanBase}_${timestamp}_${nonce}${ext}`;
    return _path.join(directory, uniqueFileName);
  }

  function getSafePrintTempDir() {
    const primary = _path.join(app.getPath("temp"), "iSmart Messenger", "print_jobs");
    try {
      _fs.mkdirSync(primary, { recursive: true });
      return primary;
    } catch (_) {
      try {
        const fallback = _path.join(app.getPath("userData"), "print_jobs");
        _fs.mkdirSync(fallback, { recursive: true });
        return fallback;
      } catch (_) {
        return primary;
      }
    }
  }

  function writeBufferSafely(primaryDir, fileName, buffer) {
    let outputPath = uniqueOutputPath(primaryDir, fileName);
    try {
      _fs.writeFileSync(outputPath, buffer);
      return outputPath;
    } catch (primaryErr) {
      _logger.warn(`[Print] writeFileSync failed in primary temp dir: ${primaryErr.message}. Trying fallback dir...`);
      try {
        const fallbackDir = _path.join(app.getPath("userData"), "print_jobs");
        _fs.mkdirSync(fallbackDir, { recursive: true });
        outputPath = uniqueOutputPath(fallbackDir, fileName);
        _fs.writeFileSync(outputPath, buffer);
        return outputPath;
      } catch (_) {
        throw primaryErr;
      }
    }
  }

  function safeUnlink(filePath) {
    if (!filePath) return;
    try {
      if (_fs.existsSync(filePath)) {
        _fs.unlinkSync(filePath);
      }
    } catch (_) {
      // On Windows, if a process (e.g. Acrobat/Sumatra) still holds the handle,
      // retry unlinking after a short delay so we don't throw an unhandled exception.
      setTimeout(() => {
        try {
          if (_fs.existsSync(filePath)) {
            _fs.unlinkSync(filePath);
          }
        } catch (_) {}
      }, 5000);
    }
  }

  function isImageFile(filePath, buffer) {
    const ext = _path.extname(filePath || "").toLowerCase();
    const imageExtensions = [".png", ".jpg", ".jpeg", ".bmp", ".gif", ".webp", ".svg"];
    if (imageExtensions.includes(ext)) {
      return true;
    }
    if (buffer && buffer.length >= 4) {
      if (buffer.length >= 8 && buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47) return true; // PNG
      if (buffer.length >= 2 && buffer[0] === 0xff && buffer[1] === 0xd8) return true; // JPEG
      if (buffer.length >= 6 && buffer.slice(0, 6).toString("ascii").startsWith("GIF")) return true; // GIF
      if (buffer.length >= 2 && buffer[0] === 0x42 && buffer[1] === 0x4d) return true; // BMP
      if (buffer.length >= 12 && buffer.slice(8, 12).toString("ascii") === "WEBP") return true; // WEBP
    }
    return false;
  }

  async function printImageFile(imagePath, printerName, jobId, tempDirectory) {
    const htmlPath = _path.join(tempDirectory, `print_img_${Date.now()}_${Math.random().toString(36).slice(2, 7)}.html`);
    const normalizedImgPath = imagePath.replace(/\\/g, "/");
    const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><style>@page{margin:0;}html,body{margin:0;padding:0;width:100%;height:100%;display:flex;justify-content:center;align-items:center;background:#fff;}img{max-width:100%;max-height:100vh;object-fit:contain;}</style></head><body><img src="file://${normalizedImgPath}" /></body></html>`;
    _fs.writeFileSync(htmlPath, html, "utf8");
    try {
      const result = await htmlPrintService(
        `file://${htmlPath.replace(/\\/g, "/")}`,
        printerName || null,
        { jobId: jobId || "image-job" }
      );
      return { success: true, executionState: "submitted", ...result };
    } finally {
      try {
        _fs.unlinkSync(htmlPath);
      } catch (_) {}
    }
  }

  ipcMain.handle("print:base64", async (_event, payload = {}) => {
    let outputPath = null;
    try {
      const tempDir = getSafePrintTempDir();

      let base64Data = String(payload.base64 || payload.inlineFileBase64 || "");
      const dataUrlPrefix = /^data:application\/pdf;base64,/i;
      if (dataUrlPrefix.test(base64Data)) {
        base64Data = base64Data.replace(dataUrlPrefix, "");
      }

      const buffer = Buffer.from(base64Data, "base64");
      const fileName = payload.fileName || "print_file.pdf";
      outputPath = writeBufferSafely(tempDir, fileName, buffer);

      const isPdf = buffer.length >= 5 && buffer.slice(0, 5).toString("utf8") === "%PDF-";
      if (!isPdf) {
        const mime = String(payload.mimeType || payload.contentType || "").trim().toLowerCase();
        if (mime === "application/pdf" || mime.includes("application/pdf")) {
          const err = new Error("INVALID_PDF_SIGNATURE");
          err.code = "INVALID_PDF_SIGNATURE";
          throw err;
        }

        const isImg = isImageFile(fileName, buffer) || isImageFile(outputPath, buffer) || mime.startsWith("image/");
        if (isImg) {
          const result = await printImageFile(
            outputPath,
            payload.printerName || null,
            payload.jobId,
            tempDir
          );
          safeUnlink(outputPath);
          return { success: true, executionState: "submitted", savedPath: outputPath, ...result };
        }

        const text = buffer.toString("utf8");
        if (text.includes("<html") || text.includes("<body")) {
          const result = await htmlPrintService(
            `file://${outputPath.replace(/\\/g, "/")}`,
            payload.printerName || null,
            { jobId: payload.jobId }
          );
          safeUnlink(outputPath);
          return { success: true, executionState: "submitted", savedPath: outputPath, ...result };
        } else {
          throw new Error("Unsupported format (only PDF and HTML are printable).");
        }
      }

      const result = await pdfPrintService.printPdfNative({
        filePath: outputPath,
        printerName: payload.printerName || null,
        jobId: payload.jobId || "base64-job",
        disableAdobeFallback: payload.disableAdobeFallback === true
      });

      safeUnlink(outputPath);

      return { success: true, savedPath: outputPath, ...result };
    } catch (error) {
      _logger.error(`event=electron_print_base64_failed jobId=${payload.jobId} error=${error.message}`);
      if (payload.enableDiagnostics !== true) {
        safeUnlink(outputPath);
      }
      return { success: false, message: error.message, code: error.code || "PRINT_FAILED" };
    }
  });

  ipcMain.handle("print:url", async (_event, payload = {}) => {
    const url = String(payload.url || payload.downloadUrl || "").trim();
    if (!url) {
      return { success: false, message: "URL is required.", code: "URL_REQUIRED" };
    }

    let outputPath = null;
    try {
      const tempDir = getSafePrintTempDir();

      const parsedUrl = new URL(url);
      const ext = _path.extname(parsedUrl.pathname) || ".pdf";
      const fileName = payload.fileName || `downloaded_file${ext}`;
      outputPath = uniqueOutputPath(tempDir, fileName);

      const token = payload.requestAuthToken || payload.token || null;
      const printerName = payload.printerName || null;

      await downloadFileAndValidate(url, outputPath, token);

      const exists = _fs.existsSync(outputPath);
      const stat = exists ? _fs.statSync(outputPath) : null;
      const fileBuffer = exists && stat && stat.size > 0 ? _fs.readFileSync(outputPath) : Buffer.alloc(0);

      const isPdf = fileBuffer.length >= 5 && fileBuffer.slice(0, 5).toString("utf8") === "%PDF-";

      if (!isPdf) {
        const mime = String(payload.mimeType || payload.contentType || "").trim().toLowerCase();
        const isImg = isImageFile(fileName, fileBuffer) || isImageFile(outputPath, fileBuffer) || mime.startsWith("image/");
        if (isImg) {
          const result = await printImageFile(outputPath, printerName, payload.jobId, tempDir);
          safeUnlink(outputPath);
          return { success: true, savedPath: outputPath, ...result };
        }

        const text = fileBuffer.toString("utf8");
        if (text.includes("<html") || text.includes("<body")) {
          const result = await htmlPrintService(
            `file://${outputPath.replace(/\\/g, "/")}`,
            printerName,
            { jobId: payload.jobId }
          );
          safeUnlink(outputPath);
          return { success: true, savedPath: outputPath, ...result };
        }

        const err = new Error("INVALID_PDF_SIGNATURE");
        err.code = "INVALID_PDF_SIGNATURE";
        throw err;
      }

      const result = await pdfPrintService.printPdfNative({
        filePath: outputPath,
        printerName,
        jobId: payload.jobId || "url-job",
        disableAdobeFallback: payload.disableAdobeFallback === true
      });

      safeUnlink(outputPath);

      return { success: true, savedPath: outputPath, ...result };
    } catch (error) {
      _logger.error(`event=electron_print_url_failed jobId=${payload.jobId} error=${error.message}`);
      safeUnlink(outputPath);
      return { success: false, message: error.message, code: error.code || "PRINT_FAILED" };
    }
  });
}

module.exports = {
  registerPrintIpcHandlers
};

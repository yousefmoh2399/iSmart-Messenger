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
    const ext = _path.extname(fileName);
    const base = _path.basename(fileName, ext);
    let candidate = _path.join(directory, fileName);
    let counter = 1;
    while (_fs.existsSync(candidate)) {
      candidate = _path.join(directory, `${base}_${counter}${ext}`);
      counter++;
    }
    return candidate;
  }

  ipcMain.handle("print:base64", async (_event, payload = {}) => {
    const tempDir = _path.join(app.getPath("temp"), "iSmart Messenger", "print_jobs");
    _fs.mkdirSync(tempDir, { recursive: true });

    let base64Data = String(payload.base64 || payload.inlineFileBase64 || "");
    const dataUrlPrefix = /^data:application\/pdf;base64,/i;
    if (dataUrlPrefix.test(base64Data)) {
      base64Data = base64Data.replace(dataUrlPrefix, "");
    }

    const buffer = Buffer.from(base64Data, "base64");
    const fileName = payload.fileName || "print_file.pdf";
    const outputPath = uniqueOutputPath(tempDir, fileName);
    _fs.writeFileSync(outputPath, buffer);
    try {
      const isPdf = buffer.length >= 5 && buffer.slice(0, 5).toString("utf8") === "%PDF-";
      if (!isPdf) {
        const mime = String(payload.mimeType || payload.contentType || "").trim().toLowerCase();
        if (mime === "application/pdf" || mime.includes("application/pdf")) {
          const err = new Error("INVALID_PDF_SIGNATURE");
          err.code = "INVALID_PDF_SIGNATURE";
          throw err;
        }
        const text = buffer.toString("utf8");
        if (text.includes("<html") || text.includes("<body")) {
          const result = await htmlPrintService(
            `file://${outputPath.replace(/\\/g, "/")}`,
            payload.printerName || null,
            { jobId: payload.jobId }
          );
          try {
            _fs.unlinkSync(outputPath);
          } catch (_) {}
          return { success: true, executionState: "submitted", ...result };
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

      try {
        _fs.unlinkSync(outputPath);
      } catch (_) {}

      return { success: true, ...result };
    } catch (error) {
      _logger.error(`event=electron_print_base64_failed jobId=${payload.jobId} error=${error.message}`);
      if (payload.enableDiagnostics !== true) {
        try {
          _fs.unlinkSync(outputPath);
        } catch (_) {}
      }
      return { success: false, message: error.message, code: error.code || "PRINT_FAILED" };
    }
  });

  ipcMain.handle("print:url", async (_event, payload = {}) => {
    const url = String(payload.url || payload.downloadUrl || "").trim();
    if (!url) {
      return { success: false, message: "URL is required.", code: "URL_REQUIRED" };
    }

    const tempDir = _path.join(app.getPath("temp"), "iSmart Messenger", "print_jobs");
    _fs.mkdirSync(tempDir, { recursive: true });

    const parsedUrl = new URL(url);
    const ext = _path.extname(parsedUrl.pathname) || ".pdf";
    const fileName = payload.fileName || `downloaded_file${ext}`;
    const outputPath = uniqueOutputPath(tempDir, fileName);

    const token = payload.requestAuthToken || payload.token || null;
    const printerName = payload.printerName || null;

    try {
      await downloadFileAndValidate(url, outputPath, token);

      const isPdf = _fs.existsSync(outputPath) && 
                    _fs.statSync(outputPath).size >= 5 && 
                    _fs.readFileSync(outputPath).slice(0, 5).toString("utf8") === "%PDF-";

      if (!isPdf) {
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

      try {
        _fs.unlinkSync(outputPath);
      } catch (_) {}

      return { success: true, ...result };
    } catch (error) {
      _logger.error(`event=electron_print_url_failed jobId=${payload.jobId} error=${error.message}`);
      try {
        _fs.unlinkSync(outputPath);
      } catch (_) {}
      return { success: false, message: error.message, code: error.code || "PRINT_FAILED" };
    }
  });
}

module.exports = {
  registerPrintIpcHandlers
};

const fs = require("fs");
const path = require("path");
const { execFile } = require("child_process");
const { createPrintToolResolver } = require("./print_tool_resolver");

function createPdfPrintService({
  fsOverride,
  pathOverride,
  execFileOverride,
  resolverOverride,
  loggerOverride,
  appResourcesPath
} = {}) {
  const _fs = fsOverride || fs;
  const _path = pathOverride || path;
  const _execFile = execFileOverride || execFile;
  const _logger = loggerOverride || {
    info: console.log,
    warn: console.warn,
    error: console.error
  };

  const resolver = resolverOverride || createPrintToolResolver({
    fsOverride: _fs,
    pathOverride: _path,
    execOverride: null,
    appResourcesPath
  });

  function validatePdfFile(filePath) {
    if (!_fs.existsSync(filePath)) {
      const err = new Error(`File not found: ${filePath}`);
      err.code = "PDF_FILE_NOT_FOUND";
      throw err;
    }

    const stats = _fs.statSync(filePath);
    if (!stats.isFile()) {
      const err = new Error(`Path is a directory, not a file: ${filePath}`);
      err.code = "PDF_FILE_NOT_FILE";
      throw err;
    }

    if (stats.size === 0) {
      const err = new Error(`PDF file is empty: ${filePath}`);
      err.code = "PDF_FILE_EMPTY";
      throw err;
    }

    const fd = _fs.openSync(filePath, "r");
    const buffer = Buffer.alloc(5);
    _fs.readSync(fd, buffer, 0, 5, 0);
    _fs.closeSync(fd);

    if (buffer.toString("utf8") !== "%PDF-") {
      const err = new Error(`File is not a valid PDF: ${filePath}`);
      err.code = "INVALID_PDF_SIGNATURE";
      throw err;
    }

    return stats.size;
  }

  async function printPdfNative({ filePath, printerName, jobId, disableAdobeFallback }) {
    const printExecutionId = `exec_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const fileSize = validatePdfFile(filePath);

    const resolved = await resolver.resolvePdfPrintTool({ disableAdobeFallback });
    if (!resolved) {
      const err = new Error("No print tool resolved.");
      err.code = "PRINT_TOOL_NOT_FOUND";
      throw err;
    }

    const { tool, path: exePath } = resolved;

    _logger.info(`event=native_pdf_print_started jobId=${jobId} printExecutionId=${printExecutionId} tool=${tool} printerName=${printerName || "default"} fileSize=${fileSize}`);

    const isDefault = !printerName;
    let args = [];
    if (tool === "SumatraPDF") {
      args = [
        "-silent",
        "-print-settings", "fit",
        isDefault ? "-print-to-default" : "-print-to",
        ...(isDefault ? [] : [printerName]),
        filePath
      ];
    } else if (tool === "AdobeReader") {
      const targetPrinter = printerName || "default";
      args = ["/s", "/o", "/h", "/t", filePath, targetPrinter];
    }

    const startTime = Date.now();
    return new Promise((resolve, reject) => {
      _execFile(exePath, args, { timeout: 30000 }, (error, stdout, stderr) => {
        const durationMs = Date.now() - startTime;
        const exitCode = error ? (error.code || 1) : 0;

        if (error && error.killed) {
          const timeoutErr = new Error("Print process timed out.");
          timeoutErr.code = "PRINT_PROCESS_TIMEOUT";
          _logger.error(`event=native_pdf_print_finished jobId=${jobId} printExecutionId=${printExecutionId} executionState=failed exitCode=${exitCode} durationMs=${durationMs}`);
          reject(timeoutErr);
          return;
        }

        if (error && tool === "SumatraPDF") {
          const failErr = new Error(`SumatraPDF failed: ${stderr || error.message}`);
          failErr.code = "PRINT_PROCESS_FAILED";
          _logger.error(`event=native_pdf_print_finished jobId=${jobId} printExecutionId=${printExecutionId} executionState=failed exitCode=${exitCode} durationMs=${durationMs}`);
          reject(failErr);
          return;
        }

        _logger.info(`event=native_pdf_print_finished jobId=${jobId} printExecutionId=${printExecutionId} executionState=submitted exitCode=${exitCode} durationMs=${durationMs}`);
        resolve({
          success: true,
          executionState: "submitted",
          tool,
          executable: exePath,
          exitCode,
          durationMs
        });
      });
    });
  }

  return {
    validatePdfFile,
    printPdfNative
  };
}

module.exports = {
  createPdfPrintService
};

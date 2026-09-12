const assert = require("assert");

// Mock dependencies
const mockFs = {
  _files: {},
  existsSync(p) {
    const exists = !!this._files[p];
    return exists;
  },
  statSync(p) {
    if (!this._files[p]) throw new Error("not found: " + p);
    return {
      isFile: () => !this._files[p].isDir,
      size: this._files[p].content.length
    };
  },
  openSync(p) {
    return p;
  },
  readSync(fd, buf) {
    const file = this._files[fd];
    const data = Buffer.from(file.content);
    data.copy(buf, 0, 0, buf.length);
  },
  closeSync() {},
  writeFileSync(p, content) {
    this._files[p] = { content: Buffer.isBuffer(content) ? content : Buffer.from(content), isDir: false };
  },
  unlinkSync(p) {
    delete this._files[p];
  },
  readFileSync(p) {
    if (!this._files[p]) throw new Error("not found: " + p);
    return this._files[p].content;
  },
  mkdirSync() {}
};

const mockPath = {
  join(...args) {
    return args.join("/");
  },
  extname(p) {
    const idx = p.lastIndexOf(".");
    return idx === -1 ? "" : p.slice(idx);
  },
  basename(p, ext) {
    let name = p.split("/").pop();
    if (ext && name.endsWith(ext)) {
      name = name.slice(0, -ext.length);
    }
    return name;
  }
};

let execFileCalled = 0;
let execFileArgs = null;
let execFileExe = null;
let execFileCallback = null;
let execFileTimeout = null;

function mockExecFile(exe, args, opts, callback) {
  execFileCalled++;
  execFileExe = exe;
  execFileArgs = args;
  execFileTimeout = opts.timeout;
  execFileCallback = callback;
}

function waitForExecFile() {
  return new Promise((resolve) => {
    const check = () => {
      if (execFileCalled > 0) {
        resolve();
      } else {
        setTimeout(check, 5);
      }
    };
    check();
  });
}

const mockLogger = {
  info(msg) { console.log("[INFO]", msg); },
  warn(msg) { console.warn("[WARN]", msg); },
  error(msg) { console.error("[ERROR]", msg); }
};

const resolverModule = require("./printing/print_tool_resolver");
const pdfServiceModule = require("./printing/pdf_print_service");
const handlerModule = require("./printing/register_print_ipc_handlers");

async function runTests() {
  console.log("Running Electron native print unit tests on platform:", process.platform);

  console.log("Starting Test 1: Resolver ranking...");
  const resolver = resolverModule.createPrintToolResolver({
    fsOverride: mockFs,
    pathOverride: mockPath,
    execOverride: (cmd, cb) => {
      console.log("Mock exec called for cmd:", cmd);
      cb(null, "C:\\Path\\To\\SumatraPDF.exe\r\n");
    },
    appResourcesPath: "resources",
    envOverride: {
      ProgramFiles: "C:\\Program Files",
      LOCALAPPDATA: "C:\\Users\\Mock\\AppData\\Local"
    }
  });

  // If resources has bundled SumatraPDF
  mockFs._files["resources/tools/sumatra/SumatraPDF.exe"] = { content: Buffer.from("%PDF-"), isDir: false };
  let resolved = await resolver.resolvePdfPrintTool();
  assert.strictEqual(resolved.tool, "SumatraPDF");
  assert.strictEqual(resolved.path, "resources/tools/sumatra/SumatraPDF.exe");

  // If bundled doesn't exist, check ProgramFiles candidate
  delete mockFs._files["resources/tools/sumatra/SumatraPDF.exe"];
  mockFs._files["C:\\Program Files/SumatraPDF/SumatraPDF.exe"] = { content: Buffer.from("exe"), isDir: false };
  resolved = await resolver.resolvePdfPrintTool();
  assert.strictEqual(resolved.tool, "SumatraPDF");
  assert.strictEqual(resolved.path, "C:\\Program Files/SumatraPDF/SumatraPDF.exe");

  delete mockFs._files["C:\\Program Files/SumatraPDF/SumatraPDF.exe"];
  console.log("Test 1 passed.");

  console.log("Starting Test 2: PDF Validation checks...");
  const pdfService = pdfServiceModule.createPdfPrintService({
    fsOverride: mockFs,
    pathOverride: mockPath,
    execFileOverride: mockExecFile,
    resolverOverride: {
      resolvePdfPrintTool: () => Promise.resolve({ tool: "SumatraPDF", path: "sumatra.exe" })
    },
    loggerOverride: mockLogger
  });

  mockFs._files["empty.pdf"] = { content: Buffer.from(""), isDir: false };
  assert.throws(() => pdfService.validatePdfFile("empty.pdf"), /PDF file is empty/);

  mockFs._files["invalid.pdf"] = { content: Buffer.from("HELLO"), isDir: false };
  assert.throws(() => pdfService.validatePdfFile("invalid.pdf"), /File is not a valid PDF/);

  mockFs._files["valid.pdf"] = { content: Buffer.from("%PDF-1.4"), isDir: false };
  const size = pdfService.validatePdfFile("valid.pdf");
  assert.strictEqual(size, 8);
  console.log("Test 2 passed.");

  console.log("Starting Test 3: printPdfNative execution...");
  execFileCalled = 0;
  const printPromise = pdfService.printPdfNative({
    filePath: "valid.pdf",
    printerName: "MyPrinter",
    jobId: "test-job-1"
  });

  await waitForExecFile();
  assert.strictEqual(execFileCalled, 1);
  assert.strictEqual(execFileExe, "sumatra.exe");
  assert.deepStrictEqual(execFileArgs, [
    "-silent",
    "-print-settings", "fit",
    "-print-to", "MyPrinter",
    "valid.pdf"
  ]);
  assert.strictEqual(execFileTimeout, 30000);

  execFileCallback(null, "stdout", "");
  const printResult = await printPromise;
  assert.strictEqual(printResult.success, true);
  assert.strictEqual(printResult.executionState, "submitted");
  console.log("Test 3 passed.");

  console.log("Starting Test 4: printPdfNative timeout...");
  execFileCalled = 0;
  const timeoutPromise = pdfService.printPdfNative({
    filePath: "valid.pdf",
    printerName: null,
    jobId: "test-job-2"
  });
  await waitForExecFile();
  const timeoutError = new Error("timeout");
  timeoutError.killed = true;
  execFileCallback(timeoutError, "", "");
  await assert.rejects(timeoutPromise, /Print process timed out/);
  console.log("Test 4 passed.");

  console.log("Starting Test 5: printPdfNative failure...");
  execFileCalled = 0;
  const failPromise = pdfService.printPdfNative({
    filePath: "valid.pdf",
    printerName: null,
    jobId: "test-job-3"
  });
  await waitForExecFile();
  execFileCallback(new Error("failed"), "", "spooler error");
  await assert.rejects(failPromise, /SumatraPDF failed/);
  console.log("Test 5 passed.");

  console.log("Starting Test 6: registerPrintIpcHandlers integration...");
  const ipcHandlers = {};
  const mockIpcMain = {
    handle(channel, cb) {
      ipcHandlers[channel] = cb;
    }
  };
  const mockApp = {
    getPath(name) {
      return `/temp/${name}`;
    }
  };

  let htmlPrintCalled = 0;
  handlerModule.registerPrintIpcHandlers({
    ipcMain: mockIpcMain,
    pdfPrintService: pdfService,
    htmlPrintService: async (target, printer, options) => {
      htmlPrintCalled++;
      return { success: true };
    },
    app: mockApp,
    downloadFileAndValidate: async (url, dest, token) => {
      mockFs._files[dest] = { content: Buffer.from("%PDF-url"), isDir: false };
    },
    fsOverride: mockFs,
    pathOverride: mockPath,
    loggerOverride: mockLogger
  });

  assert.ok(ipcHandlers["print:base64"]);
  assert.ok(ipcHandlers["print:url"]);

  console.log("Testing print:base64 PDF signature success & temp cleanup...");
  execFileCalled = 0;
  const pdfBase64 = Buffer.from("%PDF-valid").toString("base64");
  const base64Promise = ipcHandlers["print:base64"](null, {
    base64: pdfBase64,
    fileName: "file.pdf",
    printerName: "MyPrinter",
    jobId: "b64-job-1"
  });

  await waitForExecFile();
  assert.strictEqual(execFileCalled, 1);
  execFileCallback(null, "", "");

  const base64Finished = await base64Promise;
  assert.strictEqual(base64Finished.success, true);
  assert.strictEqual(mockFs.existsSync(base64Finished.savedPath), false);

  console.log("Testing print:base64 HTML printing support...");
  const htmlBase64 = Buffer.from("<html><body>Test</body></html>").toString("base64");
  htmlPrintCalled = 0;
  const htmlRes = await ipcHandlers["print:base64"](null, {
    base64: htmlBase64,
    fileName: "file.html",
    jobId: "html-job-1"
  });
  assert.strictEqual(htmlPrintCalled, 1);
  assert.strictEqual(htmlRes.success, true);

  console.log("Testing print:url downloading & printing PDF...");
  execFileCalled = 0;
  const urlPromise = ipcHandlers["print:url"](null, {
    url: "https://example.com/test.pdf",
    printerName: "MyPrinter",
    jobId: "url-job-1"
  });

  await waitForExecFile();
  assert.strictEqual(execFileCalled, 1);
  execFileCallback(null, "", "");

  const urlFinished = await urlPromise;
  assert.strictEqual(urlFinished.success, true);
  assert.strictEqual(mockFs.existsSync(urlFinished.savedPath), false);

  console.log("Starting Test 7: Chromium PDF Print Bypass Assertions...");

  // 7.1 Base64 PDF Bypass
  execFileCalled = 0;
  htmlPrintCalled = 0;
  const pdfB64Data = Buffer.from("%PDF-valid").toString("base64");
  const p1 = ipcHandlers["print:base64"](null, {
    base64: pdfB64Data,
    fileName: "doc.pdf",
    jobId: "bypass-1"
  });
  await waitForExecFile();
  assert.strictEqual(execFileCalled, 1, "nativePdfPrint calls must be 1 for Base64 PDF");
  assert.strictEqual(htmlPrintCalled, 0, "htmlPrint calls must be 0 for Base64 PDF");
  execFileCallback(null, "", "");
  await p1;
  console.log("Assertion passed: Base64 PDF bypasses Chromium.");

  // 7.2 URL PDF Bypass
  execFileCalled = 0;
  htmlPrintCalled = 0;
  mockFs._files["/temp/downloaded_file.pdf"] = { content: Buffer.from("%PDF-url"), isDir: false };
  const p2 = ipcHandlers["print:url"](null, {
    url: "https://example.com/test.pdf",
    jobId: "bypass-2"
  });
  await waitForExecFile();
  assert.strictEqual(execFileCalled, 1, "nativePdfPrint calls must be 1 for URL PDF");
  assert.strictEqual(htmlPrintCalled, 0, "htmlPrint calls must be 0 for URL PDF");
  execFileCallback(null, "", "");
  await p2;
  console.log("Assertion passed: URL PDF bypasses Chromium.");

  // 7.3 HTML URL
  execFileCalled = 0;
  htmlPrintCalled = 0;
  const htmlB64Data = Buffer.from("<html><body>HTML CONTENT</body></html>").toString("base64");
  const p3 = await ipcHandlers["print:base64"](null, {
    base64: htmlB64Data,
    fileName: "doc.html",
    jobId: "bypass-3"
  });
  assert.strictEqual(htmlPrintCalled, 1, "htmlPrint calls must be 1 for Base64 HTML");
  assert.strictEqual(execFileCalled, 0, "nativePdfPrint calls must be 0 for Base64 HTML");
  assert.strictEqual(p3.success, true);
  console.log("Assertion passed: HTML uses Electron/Chromium print.");

  // 7.4 JSON response (rejected as unsupported format)
  execFileCalled = 0;
  htmlPrintCalled = 0;
  const jsonB64Data = Buffer.from('{"status":"error"}').toString("base64");
  const p4 = await ipcHandlers["print:base64"](null, {
    base64: jsonB64Data,
    fileName: "doc.json",
    jobId: "bypass-4"
  });
  assert.strictEqual(p4.success, false, "JSON must be rejected");
  assert.strictEqual(p4.message.includes("Unsupported format"), true, "JSON rejection message check");
  assert.strictEqual(execFileCalled, 0, "nativePdfPrint calls must be 0 for JSON");
  assert.strictEqual(htmlPrintCalled, 0, "htmlPrint calls must be 0 for JSON");
  console.log("Assertion passed: JSON is rejected.");

  // 7.5 Misleading Content Type / Signature validation checks
  
  // Case A: declared application/pdf, but starts with html => INVALID_PDF_SIGNATURE
  execFileCalled = 0;
  htmlPrintCalled = 0;
  const misleadingHtmlB64 = Buffer.from("<html>misleading</html>").toString("base64");
  const p5 = await ipcHandlers["print:base64"](null, {
    base64: misleadingHtmlB64,
    fileName: "misleading.pdf",
    mimeType: "application/pdf",
    jobId: "bypass-5"
  });
  assert.strictEqual(p5.success, false, "Must fail validation");
  assert.strictEqual(p5.message, "INVALID_PDF_SIGNATURE", "Error must be INVALID_PDF_SIGNATURE");
  assert.strictEqual(htmlPrintCalled, 0, "nativePdfPrint calls = 0");
  assert.strictEqual(execFileCalled, 0, "htmlPrint calls = 0");
  console.log("Assertion passed: Content-Type: application/pdf with HTML body returns INVALID_PDF_SIGNATURE.");

  // Case B: Content-Type: text/html + HTML body => HTML print
  execFileCalled = 0;
  htmlPrintCalled = 0;
  const htmlBodyB64 = Buffer.from("<html><body>HTML Content</body></html>").toString("base64");
  const p5b = await ipcHandlers["print:base64"](null, {
    base64: htmlBodyB64,
    fileName: "doc.html",
    mimeType: "text/html",
    jobId: "bypass-5b"
  });
  assert.strictEqual(htmlPrintCalled, 1, "HTML print called");
  assert.strictEqual(execFileCalled, 0, "Native PDF print not called");
  assert.strictEqual(p5b.success, true);
  console.log("Assertion passed: Content-Type: text/html + HTML body => HTML print.");

  // Case C: Content-Type: text/html + %PDF- signature => Native PDF print
  execFileCalled = 0;
  htmlPrintCalled = 0;
  const misleadingPdfB64 = Buffer.from("%PDF-misleading").toString("base64");
  const p6 = ipcHandlers["print:base64"](null, {
    base64: misleadingPdfB64,
    fileName: "misleading.html",
    mimeType: "text/html",
    jobId: "bypass-6"
  });
  await waitForExecFile();
  assert.strictEqual(execFileCalled, 1, "Treated as PDF based on file signature");
  assert.strictEqual(htmlPrintCalled, 0, "Not treated as HTML despite text/html type");
  execFileCallback(null, "", "");
  await p6;
  console.log("Assertion passed: Content-Type: text/html + %PDF- signature => Native PDF print.");

  console.log("All Electron native print unit tests passed successfully!");
}

runTests().catch(err => {
  console.error("Test suite failed:", err);
  throw err;
});

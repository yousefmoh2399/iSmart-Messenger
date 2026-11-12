process.env['ELECTRON_DISABLE_SECURITY_WARNINGS'] = 'true';
process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";

const {
  app,
  BrowserWindow,
  Notification,
  Tray,
  dialog,
  ipcMain,
  shell,
  Menu,
  nativeImage,
  nativeTheme,
  safeStorage,
} = require("electron");
const { execFile, spawn } = require("child_process");
const fs = require("fs");
const http = require("http");
const https = require("https");
const os = require("os");
const path = require("path");

// Windows 7 / Electron 22 compatibility: Apply GPU/sandbox flags early (before app 'ready').
// These prevent crashes on Windows 7 which lacks modern GPU compositing APIs.
if (process.platform === 'win32') {
  const release = os.release(); // e.g. "6.1.7601" for Win7, "6.2.xxxx" for Win8+
  const major = parseInt(release.split('.')[0], 10);
  const minor = parseInt(release.split('.')[1], 10);
  const isWin7OrOlder = major < 6 || (major === 6 && minor < 2);
  const forceSoftwareGpu = process.argv.includes('--disable-gpu') || process.env.ISMART_DISABLE_GPU === '1';
  if (forceSoftwareGpu) {
    app.disableHardwareAcceleration();
  } else if (isWin7OrOlder) {
    // Disable GPU sandbox — Windows 7 sandbox layer is incompatible with Chromium 108+
    app.commandLine.appendSwitch('disable-gpu-sandbox');


    // Disable Direct2D font rendering (uses GDI fallback on Win7)
    app.commandLine.appendSwitch('disable-directwrite-for-ui');
    // Force hardware rasterization with D3D9 ANGLE backend (fast 60fps on Win7 legacy drivers)
    app.commandLine.appendSwitch('enable-gpu-rasterization');
    app.commandLine.appendSwitch('enable-zero-copy');
    app.commandLine.appendSwitch('ignore-gpu-blocklist');
    // Disable DX12 (not available on Win7)
    app.commandLine.appendSwitch('use-angle', 'd3d9');
  } else {
    app.commandLine.appendSwitch('enable-gpu-rasterization');
    app.commandLine.appendSwitch('enable-zero-copy');
  }
}

const { createPrintToolResolver } = require("./printing/print_tool_resolver");
const { createPdfPrintService } = require("./printing/pdf_print_service");
const { registerPrintIpcHandlers } = require("./printing/register_print_ipc_handlers");

const pdfPrintService = createPdfPrintService();

const LAN_TRANSFER_PORT = 27861;
const WEB_APP_PORT = 27862;
const APP_NAME = "iSmart Messenger";
const STARTUP_REG_KEY =
  "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run";
const STARTUP_VALUE_NAME = "iSmart Messenger";
let mainWindow = null;
let lanServer = null;
let webAppServer = null;
let tray = null;
let lastStartUrl = null;
let isQuitting = false;
let startupEnabled = true;
let hasShownTrayHint = false;
let lanReceiveReminderTimer = null;
let currentWindowTheme = nativeTheme.shouldUseDarkColors ? "dark" : "light";
const pendingLanTransfers = new Map();
const pendingLanReceiveRequests = new Map();
const MAX_ELECTRON_FETCH_BYTES = 512 * 1024 * 1024;
const LAN_DISCOVERY_TIMEOUT_MS = 750;
const LAN_DISCOVERY_BATCH_SIZE = 20;
const DEFAULT_TRANSFER_POLICY = {
  maxFileSizeBytes: 500 * 1024 * 1024,
  allowedExtensions: [],
  allowedBranchCodes: [],
  autoAcceptTrustedDevices: false,
};

function titleBarPalette(mode = currentWindowTheme) {
  const dark = mode === "dark";
  return dark
    ? {
        color: "#0F172A",
        symbolColor: "#F8FAFC",
      }
    : {
        color: "#F8FAFC",
        symbolColor: "#111827",
      };
}

function applyWindowTheme(mode = currentWindowTheme) {
  const newTheme = mode === "dark" ? "dark" : "light";
  const themeChanged = newTheme !== currentWindowTheme;
  currentWindowTheme = newTheme;
  nativeTheme.themeSource = currentWindowTheme;
  if (!mainWindow || mainWindow.isDestroyed()) {
    return;
  }
  const palette = titleBarPalette(currentWindowTheme);
  mainWindow.setBackgroundColor(palette.color);
  // Only call setTitleBarOverlay when the theme actually changed.
  // Calling it repeatedly causes Windows to destroy and recreate the native
  // caption buttons, leaving behind stale hover states that accumulate
  // visually each time the mouse passes over minimize/maximize/close.
  if (themeChanged && typeof mainWindow.setTitleBarOverlay === "function") {
    mainWindow.setTitleBarOverlay({
      color: palette.color,
      symbolColor: palette.symbolColor,
      height: 34,
    });
  }
}

function transferStorePath() {
  return path.join(app.getPath("userData"), "lan-transfer-store.json");
}

function secureStorePath() {
  return path.join(app.getPath("userData"), "secure-store.json");
}

function debugLogPath() {
  return path.join(app.getPath("userData"), "auth-debug.log");
}

const _DEBUG_LOG_MAX_BYTES = 2 * 1024 * 1024;
let _debugLogDirReady = false;
let _debugLogWriteCount = 0;
let _debugLogChain = Promise.resolve();

function appendDebugLog(scope, message, details) {
  try {
    const line = JSON.stringify({
      at: new Date().toISOString(),
      scope: String(scope || "app"),
      message: String(message || ""),
      details: details == null ? null : details,
    });
    const logFile = debugLogPath();
    _debugLogChain = _debugLogChain
      .then(async () => {
        if (!_debugLogDirReady) {
          await fs.promises.mkdir(path.dirname(logFile), { recursive: true });
          _debugLogDirReady = true;
        }
        _debugLogWriteCount += 1;
        if (_debugLogWriteCount % 100 === 0) {
          try {
            const st = await fs.promises.stat(logFile);
            if (st.size > _DEBUG_LOG_MAX_BYTES) {
              await fs.promises.truncate(logFile, 0);
            }
          } catch (_) {}
        }
        await fs.promises.appendFile(logFile, `${line}\n`, "utf8");
      })
      .catch(() => {});
  } catch (_) {}
}

function localStorageRootPath(preferredPath) {
  const customPath = String(preferredPath || "").trim();
  if (customPath) {
    return customPath;
  }
  const localAppData =
    String(process.env.LOCALAPPDATA || "").trim() ||
    (() => {
      try {
        return app.getPath("appData");
      } catch (error) {
        appendDebugLog("storage", "appData fallback failed", {
          error: error.message,
        });
        return os.homedir();
      }
    })();
  return path.join(localAppData, APP_NAME, "Storage");
}

const _ensuredStorageDirs = new Set();

function localStorageChildPath(name, preferredPath) {
  const directory = path.join(localStorageRootPath(preferredPath), name);
  if (!_ensuredStorageDirs.has(directory)) {
    fs.mkdirSync(directory, { recursive: true });
    _ensuredStorageDirs.add(directory);
  }
  return directory;
}

function ensureLocalStorageTree(preferredPath) {
  for (const name of ["Chat", path.join("Chat", "sent"), path.join("Chat", "cache"), "Documents", "Scans", "Incoming"]) {
    localStorageChildPath(name, preferredPath);
  }
}

function chatArchivePath(messageId, sha256Hex, fileName, preferredPath) {
  const safeMessageId = String(messageId || "").replace(/[^\w.-]+/g, "_");
  const safeHash = String(sha256Hex || "").toLowerCase().replace(/[^a-f0-9]/g, "");
  const ext = path.extname(String(fileName || "")) || ".bin";
  return path.join(
    localStorageChildPath(path.join("Chat", "sent"), preferredPath),
    `${safeMessageId}_${safeHash}${ext}`,
  );
}

function safeStorageFileName(value, fallback = "attachment") {
  const baseName = path.basename(String(value || "").trim() || fallback);
  const cleaned = baseName
    .replace(/[<>:"/\\|?*\x00-\x1F]/g, "_")
    .replace(/\s+/g, " ")
    .trim();
  return cleaned || fallback;
}

function chatAttachmentCachePath(messageId, fileName, preferredPath) {
  const safeMessageId = safeStorageFileName(messageId, "message");
  const safeName = safeStorageFileName(fileName, "attachment");
  return path.join(
    localStorageChildPath(path.join("Chat", "cache"), preferredPath),
    `${safeMessageId}_${safeName}`,
  );
}

function readSecureStore() {
  try {
    const filePath = secureStorePath();
    if (!fs.existsSync(filePath)) {
      return {};
    }
    const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed
      : {};
  } catch (_) {
    return {};
  }
}

function writeSecureStore(store) {
  const filePath = secureStorePath();
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(store, null, 2));
}

function normalizeSecureKey(key) {
  return String(key || "")
    .trim()
    .replace(/[^\w.-]+/g, "_")
    .slice(0, 120);
}

function normalizeTransferPolicy(value = {}) {
  const maxFileSizeBytes = Number(value.maxFileSizeBytes || 0);
  const allowedExtensions = Array.isArray(value.allowedExtensions)
    ? value.allowedExtensions
        .map((entry) =>
          String(entry || "")
            .trim()
            .toLowerCase()
            .replace(/^\./, ""),
        )
        .filter(Boolean)
    : [];
  const allowedBranchCodes = Array.isArray(value.allowedBranchCodes)
    ? value.allowedBranchCodes
        .map((entry) => String(entry || "").trim().toUpperCase())
        .filter(Boolean)
    : [];
  return {
    maxFileSizeBytes:
      Number.isFinite(maxFileSizeBytes) && maxFileSizeBytes > 0
        ? Math.min(maxFileSizeBytes, 2 * 1024 * 1024 * 1024)
        : DEFAULT_TRANSFER_POLICY.maxFileSizeBytes,
    allowedExtensions: [...new Set(allowedExtensions)],
    allowedBranchCodes: [...new Set(allowedBranchCodes)],
    autoAcceptTrustedDevices: value.autoAcceptTrustedDevices === true,
  };
}

function defaultTransferStore() {
  return {
    version: 1,
    policy: { ...DEFAULT_TRANSFER_POLICY },
    transfers: [],
    inbox: [],
    auditLogs: [],
    notifications: [],
  };
}

function isExternalHttpUrl(targetUrl, appUrl) {
  try {
    const target = new URL(String(targetUrl || ""));
    if (target.protocol !== "http:" && target.protocol !== "https:") {
      return false;
    }
    const appOrigin = new URL(String(appUrl || lastStartUrl || "")).origin;
    return target.origin !== appOrigin;
  } catch (_) {
    return false;
  }
}

function readTransferStore() {
  try {
    const filePath = transferStorePath();
    if (!fs.existsSync(filePath)) {
      return defaultTransferStore();
    }
    const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
    return {
      ...defaultTransferStore(),
      ...parsed,
      policy: normalizeTransferPolicy(parsed.policy),
      transfers: Array.isArray(parsed.transfers) ? parsed.transfers : [],
      inbox: Array.isArray(parsed.inbox) ? parsed.inbox : [],
      auditLogs: Array.isArray(parsed.auditLogs) ? parsed.auditLogs : [],
      notifications: Array.isArray(parsed.notifications)
        ? parsed.notifications
        : [],
    };
  } catch (error) {
    console.warn(`Failed to read transfer store: ${error.message}`);
    return defaultTransferStore();
  }
}

function writeTransferStore(nextStore) {
  const filePath = transferStorePath();
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(
    filePath,
    JSON.stringify(
      {
        ...defaultTransferStore(),
        ...nextStore,
        policy: normalizeTransferPolicy(nextStore.policy),
      },
      null,
      2,
    ),
    "utf8",
  );
}

function mutateTransferStore(mutator) {
  const store = readTransferStore();
  const result = mutator(store) || store;
  result.transfers = (result.transfers || []).slice(-300);
  result.inbox = (result.inbox || []).slice(-300);
  result.auditLogs = (result.auditLogs || []).slice(-500);
  result.notifications = (result.notifications || []).slice(-300);
  writeTransferStore(result);
  return result;
}

function randomTransferRecordId(prefix = "transfer") {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

function addTransferRecord(record) {
  const item = {
    id: record.id || randomTransferRecordId("transfer"),
    direction: record.direction || "outgoing",
    status: record.status || "pending",
    fileName: record.fileName || "file",
    fileSizeBytes: Number(record.fileSizeBytes || 0),
    peerName: record.peerName || record.peerLabel || null,
    peerIp: record.peerIp || null,
    senderName: record.senderName || null,
    receiverName: record.receiverName || null,
    senderBranchCode: record.senderBranchCode || null,
    receiverBranchCode: record.receiverBranchCode || null,
    savedPath: record.savedPath || null,
    message: record.message || null,
    createdAt: record.createdAt || new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  mutateTransferStore((store) => {
    store.transfers.push(item);
    return store;
  });
  return item;
}

function updateTransferRecord(id, patch) {
  if (!id) return null;
  let updated = null;
  mutateTransferStore((store) => {
    store.transfers = store.transfers.map((entry) => {
      if (entry.id !== id) return entry;
      updated = { ...entry, ...patch, updatedAt: new Date().toISOString() };
      return updated;
    });
    return store;
  });
  return updated;
}

function addAuditLog(event) {
  const item = {
    id: randomTransferRecordId("audit"),
    type: event.type || "transfer_event",
    actorName: event.actorName || null,
    peerName: event.peerName || null,
    fileName: event.fileName || null,
    fileSizeBytes: Number(event.fileSizeBytes || 0),
    status: event.status || null,
    message: event.message || null,
    createdAt: new Date().toISOString(),
  };
  mutateTransferStore((store) => {
    store.auditLogs.push(item);
    return store;
  });
  return item;
}

function addNotificationRecord(notification) {
  const item = {
    id: randomTransferRecordId("notif"),
    category: notification.category || "files",
    title: notification.title || "إشعار",
    body: notification.body || "",
    read: false,
    createdAt: new Date().toISOString(),
  };
  mutateTransferStore((store) => {
    store.notifications.push(item);
    return store;
  });
  return item;
}

function addInboxRecord(record) {
  const item = {
    id: randomTransferRecordId("inbox"),
    fileName: record.fileName || "file",
    fileSizeBytes: Number(record.fileSizeBytes || 0),
    senderName: record.senderName || null,
    senderIp: record.senderIp || null,
    savedPath: record.savedPath || null,
    receivedAt: new Date().toISOString(),
    category: record.category || "received",
  };
  mutateTransferStore((store) => {
    store.inbox.push(item);
    return store;
  });
  return item;
}

function validateTransferPolicy({ fileName, fileSizeBytes, senderBranchCode, receiverBranchCode }) {
  const policy = readTransferStore().policy;
  const size = Number(fileSizeBytes || 0);
  if (size > policy.maxFileSizeBytes) {
    return {
      allowed: false,
      message: `حجم الملف أكبر من الحد المسموح (${formatBytes(policy.maxFileSizeBytes)}).`,
    };
  }
  const extension = path.extname(String(fileName || "")).replace(/^\./, "").toLowerCase();
  if (
    policy.allowedExtensions.length > 0 &&
    extension &&
    !policy.allowedExtensions.includes(extension)
  ) {
    return {
      allowed: false,
      message: `نوع الملف .${extension} غير مسموح حسب سياسة الإدارة.`,
    };
  }
  const branches = policy.allowedBranchCodes;
  const senderBranch = String(senderBranchCode || "").trim().toUpperCase();
  const receiverBranch = String(receiverBranchCode || "").trim().toUpperCase();
  if (
    branches.length > 0 &&
    ((senderBranch && !branches.includes(senderBranch)) ||
      (receiverBranch && !branches.includes(receiverBranch)))
  ) {
    return {
      allowed: false,
      message: "هذا الفرع غير مسموح له بتبادل الملفات حسب سياسة الإدارة.",
    };
  }
  return { allowed: true, message: null };
}

// Enable single-instance lock to prevent multiple app instances
const gotTheLock = app.requestSingleInstanceLock();
if (!gotTheLock) {
  app.quit();
  process.exit(0);
}

app.on("second-instance", () => {
  if (mainWindow) {
    showMainWindow();
  }
});

app.commandLine.appendSwitch("disable-dev-shm-usage");
app.commandLine.appendSwitch("no-sandbox");
app.commandLine.appendSwitch("ignore-certificate-errors");
app.commandLine.appendSwitch("proxy-bypass-list", "<-loopback>,127.0.0.1,localhost");


app.commandLine.appendSwitch("renderer-process-limit", "3");

// V8 32-bit Memory Optimization: constrain heap to 512MB to trigger fast, non-blocking GC pauses
// preventing memory fragmentation and 1-2 second freezes on low-RAM branch PCs.
app.commandLine.appendSwitch("js-flags", "--max-old-space-size=512");

// Limit disk cache to prevent thrashing slow mechanical 5400rpm hard drives
app.commandLine.appendSwitch("disk-cache-size", "67108864");
app.commandLine.appendSwitch("font-render-hinting", "medium");
app.commandLine.appendSwitch("autoplay-policy", "no-user-gesture-required");

// Graphics Performance Tuning:
// On Windows 7 (NT 6.1), disabling hardware acceleration forces CPU software emulation (SwiftShader),
// which pegs dual-core CPUs at 100% and freezes the app when scrolling or typing.
// Instead, we force the mature DirectX 9 ANGLE backend with GPU rasterization,
// which runs at 60fps on virtually all legacy Intel/AMD/Nvidia drivers on Windows 7.
/* Graphics tuning configured in early init
if (os.release().startsWith("6.1")) {
  const forceSoftware = process.argv.includes("--disable-gpu") || process.env.ISMART_DISABLE_GPU === "1";
  if (forceSoftware) {
    app.disableHardwareAcceleration();
  } else {
    app.commandLine.appendSwitch("use-angle", "d3d9");
    app.commandLine.appendSwitch("ignore-gpu-blocklist");
    app.commandLine.appendSwitch("enable-gpu-rasterization");
    app.commandLine.appendSwitch("enable-zero-copy");
  }
} else {
  app.commandLine.appendSwitch("enable-gpu-rasterization");
  app.commandLine.appendSwitch("enable-zero-copy");
}

*/

app.on("certificate-error", (event, webContents, url, error, certificate, callback) => {
  event.preventDefault();
  callback(true);
});

function webRoot() {
  return app.isPackaged
    ? path.join(process.resourcesPath, "app.asar", "web")
    : path.resolve(__dirname, "..", "build", "web");
}

function appIconPath() {
  const candidates = [
    path.join(__dirname, "build", "icon.ico"),
    path.join(__dirname, "icon.ico"),
    path.join(process.resourcesPath || "", "build", "icon.ico"),
    path.join(process.resourcesPath || "", "app.asar", "build", "icon.ico"),
    path.resolve(__dirname, "..", "build", "icon.ico"),
  ];
  for (const candidate of candidates) {
    if (candidate && fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return null;
}

const mimeTypes = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".mjs": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".wasm": "application/wasm",
  ".otf": "font/otf",
  ".ttf": "font/ttf",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".wav": "audio/wav",
  ".mp3": "audio/mpeg",
  ".ogg": "audio/ogg",
  ".webm": "audio/webm",
};

function resolveWebFile(root, requestUrl) {
  const parsed = new URL(requestUrl || "/", "http://127.0.0.1");
  const cleanPath = decodeURIComponent(parsed.pathname).replace(/^\/+/, "");
  const requested = path.resolve(root, cleanPath || "index.html");
  if (!requested.startsWith(root)) {
    return null;
  }
  return requested;
}

const _staticWebCache = new Map();
let _staticWebCacheBytes = 0;
const MAX_STATIC_WEB_CACHE_BYTES = 48 * 1024 * 1024;
const MAX_STATIC_WEB_CACHE_ENTRY_BYTES = 16 * 1024 * 1024;

function _shouldCacheStaticWebAsset(filePath, ext) {
  const base = path.basename(filePath).toLowerCase();
  if (
    ext === ".html" ||
    base === "flutter_service_worker.js" ||
    base === "version.json"
  ) {
    return false;
  }
  return true;
}

function _cacheStaticWebAsset(filePath, ext, data) {
  if (
    !_shouldCacheStaticWebAsset(filePath, ext) ||
    !data ||
    data.length > MAX_STATIC_WEB_CACHE_ENTRY_BYTES ||
    _staticWebCache.has(filePath)
  ) {
    return;
  }
  while (
    _staticWebCacheBytes + data.length > MAX_STATIC_WEB_CACHE_BYTES &&
    _staticWebCache.size > 0
  ) {
    const oldestKey = _staticWebCache.keys().next().value;
    const oldest = _staticWebCache.get(oldestKey);
    _staticWebCache.delete(oldestKey);
    if (oldest) {
      _staticWebCacheBytes -= oldest.data.length;
    }
  }
  _staticWebCache.set(filePath, {
    contentType: mimeTypes[ext] || "application/octet-stream",
    data,
  });
  _staticWebCacheBytes += data.length;
}

function startWebAppServer() {
  if (webAppServer) {
    const address = webAppServer.address();
    return Promise.resolve(`http://127.0.0.1:${address.port}/`);
  }

  const root = webRoot();
  webAppServer = http.createServer(async (request, response) => {
    if (request.method !== "GET" && request.method !== "HEAD") {
      response.writeHead(405);
      response.end("Method not allowed");
      return;
    }

    let filePath = resolveWebFile(root, request.url);
    if (!filePath) {
      response.writeHead(403);
      response.end("Forbidden");
      return;
    }

    try {
      const cached = _staticWebCache.get(filePath);
      if (cached) {
        response.writeHead(200, {
          "Content-Type": cached.contentType,
          "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
          Pragma: "no-cache",
          Expires: "0",
        });
        if (request.method === "HEAD") {
          response.end();
          return;
        }
        response.end(cached.data);
        return;
      }

      const stat = await fs.promises.stat(filePath).catch(() => null);
      if (!stat || stat.isDirectory()) {
        filePath = path.join(root, "index.html");
      }
      const ext = path.extname(filePath).toLowerCase();
      const data = await fs.promises.readFile(filePath);
      _cacheStaticWebAsset(filePath, ext, data);
      response.writeHead(200, {
        "Content-Type": mimeTypes[ext] || "application/octet-stream",
        "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
        Pragma: "no-cache",
        Expires: "0",
      });
      if (request.method === "HEAD") {
        response.end();
        return;
      }
      response.end(data);
    } catch (error) {
      response.writeHead(404);
      response.end("Not found");
    }
  });

  return new Promise((resolve, reject) => {
    webAppServer.once("error", (err) => {
      if (err && err.code === "EADDRINUSE") {
        console.warn(`[WebServer] Port ${WEB_APP_PORT} in use, retrying on dynamic port 0...`);
        webAppServer.once("error", reject);
        webAppServer.listen(0, "127.0.0.1", () => {
          const address = webAppServer.address();
          console.log(`[WebServer] Web app listening on dynamic port http://127.0.0.1:${address.port}/`);
          resolve(`http://127.0.0.1:${address.port}/`);
        });
        return;
      }
      reject(err);
    });
    webAppServer.listen(WEB_APP_PORT, "127.0.0.1", () => {
      const address = webAppServer.address();
      resolve(`http://127.0.0.1:${address.port}/`);
    });
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function normalizeLanIp(value) {
  const ip = String(value || "").trim();
  if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(ip)) {
    return "";
  }
  const parts = ip.split(".").map((part) => Number(part));
  if (parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) {
    return "";
  }
  return parts.join(".");
}

const VIRTUAL_ADAPTER_REGEX =
  /(vmware|virtualbox|vbox|vethernet|hyper-v|wsl|loopback|npcap|pcap|tap|tun|tailscale|zerotier|hamachi|wireguard|nordlynx|anyconnect|fortinet|pulse|cisco|vpn|bluetooth)/i;
const PHYSICAL_ADAPTER_REGEX =
  /(ethernet|wi-fi|wifi|wlan|eth|local area connection|شبكة)/i;
const VIRTUAL_MAC_PREFIXES = [
  "00:50:56",
  "00:0c:29",
  "00:05:69",
  "08:00:27",
  "00:15:5d",
];

function getRankedIpv4Addresses() {
  const ifaces = os.networkInterfaces();
  const candidates = [];

  for (const [name, entries] of Object.entries(ifaces)) {
    for (const entry of entries || []) {
      const isIpv4 = entry.family === "IPv4" || entry.family === 4;
      if (!isIpv4 || entry.internal) {
        continue;
      }
      const rawIp = String(entry.address || "").trim();
      const ip = normalizeLanIp(rawIp);
      if (
        !ip ||
        ip.startsWith("127.") ||
        ip.startsWith("169.254.") ||
        ip === "0.0.0.0"
      ) {
        continue;
      }

      let score = 100;
      const lowerName = name.toLowerCase();
      const mac = (entry.mac || "").toLowerCase();
      const isVirtual =
        VIRTUAL_ADAPTER_REGEX.test(lowerName) ||
        VIRTUAL_MAC_PREFIXES.some((prefix) => mac.startsWith(prefix));

      if (isVirtual) {
        score -= 90;
      }
      if (PHYSICAL_ADAPTER_REGEX.test(lowerName)) {
        score += 60;
      }

      // Priority for standard private branch / office subnets
      if (/^172\.(1[6-9]|2[0-9]|3[0-1])\./.test(ip)) {
        score += 30;
      } else if (ip.startsWith("192.168.")) {
        score += 20;
      } else if (ip.startsWith("10.")) {
        score += 15;
      }

      candidates.push({ name, ip, mac, score, isVirtual });
    }
  }

  candidates.sort((a, b) => b.score - a.score);
  return candidates;
}

function localPhysicalLanIpv4s() {
  const ranked = getRankedIpv4Addresses();
  const seen = new Set();
  const result = [];
  for (const c of ranked) {
    if (c.isVirtual) {
      continue;
    }
    if (!seen.has(c.ip)) {
      seen.add(c.ip);
      result.push(c.ip);
    }
  }
  return result;
}

function localIpv4s() {
  const ranked = getRankedIpv4Addresses();
  const seen = new Set();
  const result = [];
  for (const c of ranked) {
    if (!seen.has(c.ip)) {
      seen.add(c.ip);
      result.push(c.ip);
    }
  }
  if (result.length === 0) {
    for (const entries of Object.values(os.networkInterfaces())) {
      for (const entry of entries || []) {
        const isIpv4 = entry.family === "IPv4" || entry.family === 4;
        if (isIpv4 && !entry.internal) {
          const ip = normalizeLanIp(entry.address);
          if (ip && !ip.startsWith("127.") && !seen.has(ip)) {
            seen.add(ip);
            result.push(ip);
          }
        }
      }
    }
  }
  return result;
}

function getBestLocalIpv4() {
  const ips = localIpv4s();
  return ips.length > 0 ? ips[0] : null;
}

function lanSubnetKey(value) {
  const ip = normalizeLanIp(value);
  if (!ip) {
    return "";
  }
  return ip.split(".").slice(0, 3).join(".");
}

function uniqueLanIps(values) {
  const seen = new Set();
  const result = [];
  for (const value of values || []) {
    const ip = normalizeLanIp(value);
    if (ip && !seen.has(ip)) {
      seen.add(ip);
      result.push(ip);
    }
  }
  return result;
}

async function probeLanPeerAtIp(targetIp, timeoutMs = 2500) {
  const ip = normalizeLanIp(targetIp);
  if (!ip) {
    return { success: false, peerIp: "", message: "Invalid IP address." };
  }
  const data = await requestLanJson(ip, "/lan-transfer/info", { timeoutMs });
  return {
    ...data,
    success: data.success === true,
    peerIp: ip,
    ips: uniqueLanIps(data.ips || []),
  };
}

async function probeLanPeerWithRetry(targetIp, { attempts = 3, timeoutMs = 2500 } = {}) {
  let lastError = null;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const result = await probeLanPeerAtIp(targetIp, timeoutMs);
      if (result.success === true) {
        return result;
      }
      lastError = new Error(result.message || "LAN peer is not ready.");
    } catch (error) {
      lastError = error;
    }
    if (attempt + 1 < attempts) {
      await sleep(250);
    }
  }
  throw lastError || new Error("LAN peer was not reachable.");
}

async function discoverLanPeersOnLocalNetworks() {
  // Never scan VPN TAP/TUN or VM virtual adapter subnets with /24 probes.
  const ownIps = uniqueLanIps(localPhysicalLanIpv4s());
  if (ownIps.length === 0) {
    return [];
  }
  const ownIpSet = new Set(ownIps);
  const subnets = Array.from(new Set(ownIps.map(lanSubnetKey).filter(Boolean))).sort();
  const candidates = [];
  for (const subnet of subnets) {
    for (let host = 1; host <= 254; host += 1) {
      const candidate = `${subnet}.${host}`;
      if (!ownIpSet.has(candidate)) {
        candidates.push(candidate);
      }
    }
  }

  const discovered = new Map();
  for (let index = 0; index < candidates.length; index += LAN_DISCOVERY_BATCH_SIZE) {
    const batch = candidates.slice(index, index + LAN_DISCOVERY_BATCH_SIZE);
    const results = await Promise.allSettled(
      batch.map((ip) => probeLanPeerAtIp(ip, LAN_DISCOVERY_TIMEOUT_MS)),
    );
    for (const result of results) {
      if (result.status !== "fulfilled" || result.value.success !== true) {
        continue;
      }
      const peerIp = normalizeLanIp(result.value.peerIp);
      if (!peerIp) {
        continue;
      }
      discovered.set(peerIp, {
        success: true,
        ip: peerIp,
        peerIp,
        ips: uniqueLanIps(result.value.ips || []),
        app: result.value.app || APP_NAME,
        port: result.value.port || LAN_TRANSFER_PORT,
      });
    }
  }
  return Array.from(discovered.values()).sort((a, b) => a.ip.localeCompare(b.ip));
}

function ensureStartup(enabled = true) {
  if (process.platform !== "win32") {
    return;
  }
  startupEnabled = enabled === true;
  app.setLoginItemSettings({
    openAtLogin: startupEnabled,
    openAsHidden: false,
    path: process.execPath,
  });
  const args = startupEnabled
    ? [
        "add",
        STARTUP_REG_KEY,
        "/v",
        STARTUP_VALUE_NAME,
        "/t",
        "REG_SZ",
        "/d",
        `"${process.execPath}"`,
        "/f",
      ]
    : ["delete", STARTUP_REG_KEY, "/v", STARTUP_VALUE_NAME, "/f"];
  execFile("reg.exe", args, { windowsHide: true }, () => {});
}

function cleanLegacyInstallation() {
  if (process.platform !== "win32") {
    return;
  }
  try {
    // Only clean legacy Public desktop shortcut if it exists so employees don't see duplicate/old icons
    const publicDesktop = process.env.PUBLIC
      ? path.join(process.env.PUBLIC, "Desktop")
      : "C:\\Users\\Public\\Desktop";
    const legacyPublicLnk = path.join(publicDesktop, "iSmart Messenger.lnk");
    if (fs.existsSync(legacyPublicLnk)) {
      try { fs.unlinkSync(legacyPublicLnk); } catch (_) {}
    }
    const legacyPublicLnk2 = path.join(publicDesktop, "ismart-messenger.lnk");
    if (fs.existsSync(legacyPublicLnk2)) {
      try { fs.unlinkSync(legacyPublicLnk2); } catch (_) {}
    }

    // Delete legacy uninstaller file from Program Files (x86) if present WITHOUT EVER executing it
    const pf32 = process.env["ProgramFiles(x86)"] || "C:\\Program Files (x86)";
    const legacyUninstaller = path.join(pf32, "iSmart Messenger", "Uninstall iSmart Messenger.exe");
    if (fs.existsSync(legacyUninstaller)) {
      try { fs.unlinkSync(legacyUninstaller); } catch (_) {}
      try { fs.rmdirSync(path.join(pf32, "iSmart Messenger")); } catch (_) {}
    }
  } catch (err) {
    if (typeof writeLog === "function") {
      writeLog(`cleanLegacyInstallation error: ${err.message}`);
    }
  }
}

function showMainWindow() {
  if (!mainWindow && lastStartUrl) {
    createWindow(lastStartUrl);
  }
  if (!mainWindow) {
    return;
  }
  if (!mainWindow.isVisible()) {
    mainWindow.show();
    mainWindow.setSkipTaskbar(false);
  }
  if (mainWindow.isMinimized()) {
    mainWindow.restore();
  }
  mainWindow.focus();
  mainWindow.flashFrame(false);
}

function openInternalBrowserWindow(targetUrl) {
  const url = String(targetUrl || "").trim();
  if (!url) {
    return;
  }
  let parsedUrl;
  try {
    parsedUrl = new URL(url);
  } catch (_) {
    return;
  }
  if (!["http:", "https:"].includes(parsedUrl.protocol)) {
    return;
  }
  const browserWindow = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 900,
    minHeight: 600,
    title: APP_NAME,
    autoHideMenuBar: true,
    icon: appIconPath(),
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  browserWindow.setMenuBarVisibility(false);
  browserWindow.loadURL(url);
}

function sendTrayAction(action) {
  showMainWindow();
  if (mainWindow && !mainWindow.webContents.isDestroyed()) {
    mainWindow.webContents.send("tray-action", action);
  }
}

function createTray() {
  const menu = Menu.buildFromTemplate([
    { label: "Open", click: showMainWindow },
    {
      label: "Start with Windows",
      type: "checkbox",
      checked: startupEnabled,
      click: (item) => {
        ensureStartup(item.checked === true);
        createTray();
        sendTrayAction(`startup_enabled:${startupEnabled}`);
      },
    },
    { type: "separator" },
    { label: "Sign out", click: () => sendTrayAction("signout") },
    { type: "separator" },
    {
      label: "Exit",
      click: () => {
        isQuitting = true;
        app.quit();
      },
    },
  ]);

  if (!tray) {
    try {
      const iconPath = appIconPath();
      if (iconPath && fs.existsSync(iconPath)) {
        tray = new Tray(iconPath);
      } else {
        tray = new Tray(nativeImage.createEmpty());
      }
      tray.setToolTip(APP_NAME);
      tray.on("click", showMainWindow);
      tray.on("double-click", showMainWindow);
      tray.on("right-click", () => {
        tray.popUpContextMenu(menu);
      });
    } catch (error) {
      console.error("Failed to create tray:", error);
      return;
    }
  }
  tray.setContextMenu(menu);
}

function createWindow(startUrl) {
  lastStartUrl = startUrl || lastStartUrl;
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 980,
    minHeight: 640,
    show: false,
    title: APP_NAME,
    autoHideMenuBar: true,
    icon: appIconPath(),
    backgroundColor: titleBarPalette().color,
    titleBarStyle: "hidden",
    titleBarOverlay: {
      ...titleBarPalette(),
      height: 34,
    },
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      backgroundThrottling: true,
      webSecurity: false,
      allowRunningInsecureContent: true,
      defaultFontFamily: {
        standard: "NotoSansArabic",
        serif: "NotoSansArabic",
        sansSerif: "NotoSansArabic",
        monospace: "Consolas",
      },
      defaultEncoding: "UTF-8",
    },
  });
  applyWindowTheme(currentWindowTheme);

  mainWindow.once("ready-to-show", () => mainWindow.show());
  mainWindow.setMenuBarVisibility(false);
  mainWindow.on("close", (event) => {
    // Hide to system tray instead of quitting unless user explicitly quits
    if (!isQuitting) {
      event.preventDefault();
      mainWindow.hide();
      if (tray && !hasShownTrayHint) {
        hasShownTrayHint = true;
        tray.displayBalloon({
          title: APP_NAME,
          content: "Still running. Right-click the tray icon for Open or Exit.",
        });
      }
    }
  });
  mainWindow.on("closed", () => {
    mainWindow = null;
  });
  mainWindow.on("focus", () => mainWindow.flashFrame(false));
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (isExternalHttpUrl(url, startUrl || lastStartUrl)) {
      shell.openExternal(url);
      return { action: "deny" };
    }
    return { action: "allow" };
  });
  mainWindow.webContents.on("will-navigate", (event, url) => {
    if (isExternalHttpUrl(url, startUrl || lastStartUrl)) {
      event.preventDefault();
      shell.openExternal(url);
    }
  });
  mainWindow.webContents.on("console-message", (_event, level, message) => {
    if (level >= 2 || message.includes("Electron image fetch failed")) {
      console.warn(`[renderer:${level}] ${message}`);
    }
  });
  mainWindow.webContents.on("render-process-gone", (_event, details) => {
    console.error(`[renderer] Render process gone: ${details.reason}`);
    if (details.reason !== "clean-exit") {
      setTimeout(() => {
        if (mainWindow && !mainWindow.isDestroyed()) {
          console.log("[renderer] Reloading after unexpected exit...");
          mainWindow.loadURL(startUrl || lastStartUrl);
        }
      }, 1000);
    }
  });
  mainWindow.webContents.on("did-fail-load", (_event, errorCode, errorDescription) => {
    console.warn(`[renderer] Load failed (${errorCode}): ${errorDescription}`);
    if (errorCode === -102 || errorCode === -105 || errorCode === -106) {
      setTimeout(() => {
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.loadURL(startUrl || lastStartUrl);
        }
      }, 1500);
    }
  });

  // Limit memory usage
  mainWindow.webContents.session.setMaxListeners(10);
  const session = mainWindow.webContents.session;
  session.webRequest.onCompleted({ urls: ["http://*/*", "https://*/*"] }, (details) => {
    if (details.url.includes("/api/auth/") || details.url.includes("/api/users/me")) {
      appendDebugLog("electron-webrequest", `${details.method} ${details.url}`, {
        statusCode: details.statusCode,
        fromCache: details.fromCache,
      });
    }
  });
  session.webRequest.onErrorOccurred({ urls: ["http://*/*", "https://*/*"] }, (details) => {
    if (details.url.includes("/api/auth/") || details.url.includes("/api/users/me")) {
      appendDebugLog("electron-webrequest-error", `${details.method} ${details.url}`, {
        error: details.error,
      });
    }
  });
  const load = () => mainWindow.loadURL(startUrl || lastStartUrl);
  session
    .clearStorageData({
      storages: ["serviceworkers"],
    })
    .then(() => { /* preserve disk cache */ })
    .catch((error) => {
      console.warn(`Failed to clear Electron serviceworkers: ${error.message}`);
    })
    .finally(load);
}

function sendJson(response, status, payload) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "content-type,accept,x-lan-transfer-token",
    "Access-Control-Allow-Private-Network": "true",
  });
  response.end(JSON.stringify(payload));
}

function emitLanTransferProgress(payload) {
  if (mainWindow && !mainWindow.webContents.isDestroyed()) {
    mainWindow.webContents.send("lan-transfer-progress", {
      ...payload,
      timestamp: new Date().toISOString(),
    });
  }
}

function parseJsonRequest(request) {
  return new Promise((resolve, reject) => {
    let body = "";
    request.setEncoding("utf8");
    request.on("data", (chunk) => {
      body += chunk;
      if (body.length > 1024 * 1024) {
        reject(new Error("Request body is too large."));
        request.destroy();
      }
    });
    request.on("end", () => {
      try {
        resolve(body.trim() ? JSON.parse(body) : {});
      } catch (error) {
        reject(error);
      }
    });
    request.on("error", reject);
  });
}

function requestLanJson(targetIp, routePath, { method = "GET", payload, timeoutMs = 8000 } = {}) {
  return new Promise((resolve, reject) => {
    const body = payload == null ? null : Buffer.from(JSON.stringify(payload), "utf8");
    const request = http.request(
      {
        host: String(targetIp || "").trim(),
        port: LAN_TRANSFER_PORT,
        path: routePath,
        method,
        headers: body
          ? {
              "Content-Type": "application/json",
              "Content-Length": body.length,
            }
          : undefined,
      },
      (response) => {
        let text = "";
        response.setEncoding("utf8");
        response.on("data", (chunk) => {
          text += chunk;
          if (text.length > 1024 * 1024) {
            request.destroy(new Error("LAN response is too large."));
          }
        });
        response.on("end", () => {
          try {
            const data = text.trim() ? JSON.parse(text) : {};
            if ((response.statusCode || 0) >= 500) {
              reject(new Error(data.message || `LAN request failed with status ${response.statusCode}.`));
              return;
            }
            resolve(data);
          } catch (error) {
            reject(error);
          }
        });
      },
    );
    if (timeoutMs && timeoutMs > 0) {
      request.setTimeout(timeoutMs, () =>
        request.destroy(new Error("LAN request timed out.")),
      );
    }
    request.on("error", reject);
    if (body) {
      request.write(body);
    }
    request.end();
  });
}

function toBuffer(value) {
  if (Buffer.isBuffer(value)) {
    return value;
  }
  if (value instanceof ArrayBuffer) {
    return Buffer.from(value);
  }
  if (ArrayBuffer.isView(value)) {
    return Buffer.from(value.buffer, value.byteOffset, value.byteLength);
  }
  if (Array.isArray(value)) {
    return Buffer.from(value);
  }
  return Buffer.alloc(0);
}

function guessMimeType(fileName) {
  switch (path.extname(String(fileName || "")).toLowerCase()) {
    case ".pdf":
      return "application/pdf";
    case ".png":
      return "image/png";
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".webp":
      return "image/webp";
    case ".gif":
      return "image/gif";
    case ".mp3":
      return "audio/mpeg";
    case ".wav":
      return "audio/wav";
    case ".mp4":
      return "video/mp4";
    case ".zip":
      return "application/zip";
    default:
      return "application/octet-stream";
  }
}

function uploadLanBuffer(targetIp, transferId, bytes, uploadToken = "", timeoutMs = 20 * 60 * 1000) {
  return new Promise((resolve, reject) => {
    const buffer = toBuffer(bytes);
    const request = http.request(
      {
        host: String(targetIp || "").trim(),
        port: LAN_TRANSFER_PORT,
        path: `/lan-transfer/upload/${encodeURIComponent(String(transferId || ""))}`,
        method: "POST",
        timeout: timeoutMs,
        headers: {
          "Content-Type": "application/octet-stream",
          "Content-Length": buffer.length,
          "X-LAN-Transfer-Token": String(uploadToken || ""),
        },
      },
      (response) => {
        let text = "";
        response.setEncoding("utf8");
        response.on("data", (chunk) => {
          text += chunk;
        });
        response.on("end", () => {
          try {
            const data = text.trim() ? JSON.parse(text) : {};
            if ((response.statusCode || 0) >= 500) {
              reject(new Error(data.message || `LAN upload failed with status ${response.statusCode}.`));
              return;
            }
            resolve(data);
          } catch (error) {
            reject(error);
          }
        });
      },
    );
    request.on("timeout", () => request.destroy(new Error("LAN upload timed out.")));
    request.on("error", reject);
    request.end(buffer);
  });
}

function uploadLanFile(
  targetIp,
  transferId,
  filePath,
  {
    timeoutMs = 20 * 60 * 1000,
    progressToken = null,
    uploadToken = "",
    fileName = path.basename(filePath),
    targetLabel = targetIp,
  } = {},
) {
  return new Promise((resolve, reject) => {
    const stat = fs.statSync(filePath);
    let sentBytes = 0;
    let lastPercent = -1;
    const request = http.request(
      {
        host: String(targetIp || "").trim(),
        port: LAN_TRANSFER_PORT,
        path: `/lan-transfer/upload/${encodeURIComponent(String(transferId || ""))}`,
        method: "POST",
        headers: {
          "Content-Type": "application/octet-stream",
          "Content-Length": stat.size,
          "X-LAN-Transfer-Token": String(uploadToken || ""),
        },
      },
      (response) => {
        let text = "";
        response.setEncoding("utf8");
        response.on("data", (chunk) => {
          text += chunk;
        });
        response.on("end", () => {
          try {
            const data = text.trim() ? JSON.parse(text) : {};
            if ((response.statusCode || 0) >= 500) {
              reject(new Error(data.message || `LAN upload failed with status ${response.statusCode}.`));
              return;
            }
            resolve(data);
          } catch (error) {
            reject(error);
          }
        });
      },
    );
    if (timeoutMs && timeoutMs > 0) {
      request.setTimeout(timeoutMs, () =>
        request.destroy(new Error("LAN upload timed out.")),
      );
    }
    request.on("error", reject);
    const stream = fs.createReadStream(filePath);
    stream.on("data", (chunk) => {
      sentBytes += chunk.length;
      const progress = stat.size <= 0 ? 1 : Math.min(sentBytes / stat.size, 1);
      const percent = Math.floor(progress * 100);
      if (percent !== lastPercent) {
        lastPercent = percent;
        emitLanTransferProgress({
          token: progressToken,
          direction: "outgoing",
          stage: "uploading",
          fileName,
          peerLabel: targetLabel,
          progress,
          sentBytes,
          totalBytes: stat.size,
          message: `جاري إرسال الملف ${percent}%`,
        });
      }
    });
    stream.on("error", reject);
    stream.pipe(request);
  });
}

async function pickAndSendLanFile(payload = {}) {
  const picker = await dialog.showOpenDialog(mainWindow || undefined, {
    title: "Choose file to send",
    properties: ["openFile"],
  });
  if (picker.canceled || !picker.filePaths.length) {
    return { success: false, canceled: true, message: "تم إلغاء اختيار الملف." };
  }

  const filePath = picker.filePaths[0];
  const stat = fs.statSync(filePath);
  const maxBytes = Number(payload.maxBytes || 0);
  const policyCheck = validateTransferPolicy({
    fileName: path.basename(filePath),
    fileSizeBytes: stat.size,
    senderBranchCode: payload.senderBranchCode,
    receiverBranchCode: payload.receiverBranchCode,
  });
  const effectiveMaxBytes =
    maxBytes > 0
      ? Math.min(maxBytes, readTransferStore().policy.maxFileSizeBytes)
      : readTransferStore().policy.maxFileSizeBytes;
  if (!policyCheck.allowed) {
    addAuditLog({
      type: "send_blocked_by_policy",
      actorName: payload.senderName,
      peerName: payload.targetIp,
      fileName: path.basename(filePath),
      fileSizeBytes: stat.size,
      status: "blocked",
      message: policyCheck.message,
    });
    addNotificationRecord({
      category: "files",
      title: "تم منع إرسال ملف",
      body: policyCheck.message,
    });
    return { success: false, message: policyCheck.message };
  }
  if (effectiveMaxBytes > 0 && stat.size > effectiveMaxBytes) {
    return {
      success: false,
      message: `حجم الملف أكبر من الحد المسموح للنقل المحلي (${formatBytes(effectiveMaxBytes)}).`,
    };
  }

  const fileName = path.basename(filePath);
  let targetIp = normalizeLanIp(payload.targetIp);
  if (!targetIp) {
    return { success: false, message: "Invalid target IP address." };
  }
  let targetInfo = null;
  try {
    targetInfo = await probeLanPeerWithRetry(targetIp, {
      attempts: 3,
      timeoutMs: 2500,
    });
    targetIp = targetInfo.peerIp || targetIp;
  } catch (error) {
    return {
      success: false,
      message: `LAN device ${targetIp} was not reachable on port ${LAN_TRANSFER_PORT}. ${error.message || error}`,
    };
  }
  const transferRecord = addTransferRecord({
    direction: "outgoing",
    status: "waiting_acceptance",
    fileName,
    fileSizeBytes: stat.size,
    peerName: targetIp,
    peerIp: targetIp,
    senderName: payload.senderName,
    senderBranchCode: payload.senderBranchCode || null,
    receiverBranchCode: payload.receiverBranchCode || null,
    message: "بانتظار قبول الجهاز الآخر.",
  });
  addAuditLog({
    type: "send_requested",
    actorName: payload.senderName,
    peerName: targetIp,
    fileName,
    fileSizeBytes: stat.size,
    status: "requested",
    message: "تم إرسال طلب استقبال ملف.",
  });
  const requestResponse = await requestLanJson(targetIp, "/lan-transfer/request", {
    method: "POST",
    timeoutMs: 60 * 60 * 1000,
    payload: {
      fileName,
      fileSizeBytes: stat.size,
      senderName: payload.senderName,
      mimeType: guessMimeType(fileName),
      senderBranchCode: payload.senderBranchCode,
    },
  });
  if (requestResponse.accepted !== true) {
    updateTransferRecord(transferRecord.id, {
      status: "rejected",
      message: requestResponse.message || "تم رفض استلام الملف.",
    });
    addAuditLog({
      type: "send_rejected",
      actorName: payload.senderName,
      peerName: targetIp,
      fileName,
      fileSizeBytes: stat.size,
      status: "rejected",
      message: requestResponse.message || "تم رفض استلام الملف.",
    });
    return {
      success: false,
      fileName,
      message: requestResponse.message || "تم رفض استلام الملف.",
    };
  }

  const transferId = String(requestResponse.transferId || "").trim();
  const uploadToken = String(requestResponse.uploadToken || "").trim();
  if (!transferId) {
    updateTransferRecord(transferRecord.id, {
      status: "failed",
      message: "الجهاز الآخر لم يرجع معرّف نقل صالح.",
    });
    return {
      success: false,
      fileName,
      message: "الجهاز الآخر لم يرجع معرّف نقل صالح.",
    };
  }

  const progressToken = String(payload.progressToken || "").trim() || null;
  emitLanTransferProgress({
    token: progressToken,
    direction: "outgoing",
    stage: "accepted",
    fileName,
    peerLabel: targetIp,
    progress: 0.12,
    sentBytes: 0,
    totalBytes: stat.size,
    message: "وافق الجهاز الآخر. جاري إرسال الملف...",
  });
  const uploadResponse = await uploadLanFile(targetIp, transferId, filePath, {
    progressToken,
    uploadToken,
    fileName,
    targetLabel: targetIp,
  });
  updateTransferRecord(transferRecord.id, {
    status: uploadResponse.success === true ? "completed" : "failed",
    savedPath: uploadResponse.savedPath || null,
    message:
      uploadResponse.message ||
      (uploadResponse.success === true
        ? "تم إرسال الملف بنجاح عبر الشبكة المحلية."
        : "فشل إرسال الملف عبر الشبكة المحلية."),
  });
  addAuditLog({
    type: uploadResponse.success === true ? "send_completed" : "send_failed",
    actorName: payload.senderName,
    peerName: targetIp,
    fileName,
    fileSizeBytes: stat.size,
    status: uploadResponse.success === true ? "completed" : "failed",
    message: uploadResponse.message,
  });
  emitLanTransferProgress({
    token: progressToken,
    direction: "outgoing",
    stage: uploadResponse.success === true ? "completed" : "failed",
    fileName,
    peerLabel: targetIp,
    progress: 1,
    sentBytes: stat.size,
    totalBytes: stat.size,
    message:
      uploadResponse.success === true
        ? "تم إرسال الملف بنجاح عبر الشبكة المحلية."
        : uploadResponse.message || "فشل إرسال الملف عبر الشبكة المحلية.",
  });
  return {
    ...uploadResponse,
    peerIp: targetIp,
    peerIps: targetInfo?.ips || [],
    fileName,
    fileSizeBytes: stat.size,
    savedPath: uploadResponse.savedPath || null,
  };
}

function safeFileName(value) {
  const clean = String(value || "file")
    .replace(/[<>:"/\\|?*\x00-\x1F]/g, "_")
    .trim();
  return clean || "file";
}

function uniqueOutputPath(directory, fileName) {
  const parsed = path.parse(safeFileName(fileName));
  let candidate = path.join(directory, `${parsed.name}${parsed.ext}`);
  let index = 1;
  while (fs.existsSync(candidate)) {
    candidate = path.join(directory, `${parsed.name} (${index})${parsed.ext}`);
    index += 1;
  }
  return candidate;
}

const _resolvedWebAssetCache = new Map();
const _extractedAudioPathCache = new Map();
const AUDIO_WORKER_IDLE_TIMEOUT_MS = 45000;
const AUDIO_WORKER_PLAY_TIMEOUT_MS = 10000;
const AUDIO_WORKER_MAX_QUEUE = 6;
let _audioWorkerState = null;
const _audioPlayQueue = [];
let _audioQueueActive = false;

function resolveWebAssetPath(assetPath) {
  const rawKey = String(assetPath || "").trim();
  if (_resolvedWebAssetCache.has(rawKey)) {
    return _resolvedWebAssetCache.get(rawKey);
  }
  const normalized = rawKey
    .replace(/\\/g, "/")
    .replace(/^\/+/, "");
  if (!normalized || normalized.includes("..")) {
    return null;
  }

  const root = webRoot();
  const projectRoot = path.resolve(__dirname, "..");
  const resourceRoot = process.resourcesPath || "";
  const candidates = [];
  const pushCandidate = (...parts) => {
    const candidate = path.resolve(...parts);
    if (!candidates.includes(candidate)) {
      candidates.push(candidate);
    }
  };

  pushCandidate(root, normalized);
  if (!normalized.startsWith("assets/")) {
    pushCandidate(root, "assets", normalized);
  }
  pushCandidate(root, "assets", normalized);
  pushCandidate(projectRoot, normalized);
  pushCandidate(projectRoot, "assets", normalized.replace(/^assets\//, ""));
  pushCandidate(projectRoot, "build", "flutter_assets", normalized);
  pushCandidate(projectRoot, "build", "flutter_assets", normalized.replace(/^assets\//, ""));
  pushCandidate(projectRoot, "build", "web", normalized);
  pushCandidate(projectRoot, "build", "web", "assets", normalized);
  if (resourceRoot) {
    pushCandidate(resourceRoot, "app.asar", "web", normalized);
    pushCandidate(resourceRoot, "app.asar", "web", "assets", normalized);
    pushCandidate(resourceRoot, "app.asar.unpacked", "web", normalized);
    pushCandidate(resourceRoot, "app.asar.unpacked", "web", "assets", normalized);
  }

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      if (_resolvedWebAssetCache.size > 200) {
        _resolvedWebAssetCache.clear();
      }
      _resolvedWebAssetCache.set(rawKey, candidate);
      return candidate;
    }
  }
  if (_resolvedWebAssetCache.size > 200) {
    _resolvedWebAssetCache.clear();
  }
  _resolvedWebAssetCache.set(rawKey, null);
  console.warn("[electron] asset not found", { assetPath, candidates });
  return null;
}

async function resolvePlayableAudioPath(filePath) {
  if (!filePath || !filePath.includes("app.asar")) {
    return filePath;
  }
  const cached = _extractedAudioPathCache.get(filePath);
  if (cached) {
    return cached;
  }
  const tempDir = path.join(app.getPath("temp"), APP_NAME, "sounds");
  await fs.promises.mkdir(tempDir, { recursive: true });
  let pathHash = 2166136261;
  for (let i = 0; i < filePath.length; i += 1) {
    pathHash ^= filePath.charCodeAt(i);
    pathHash = Math.imul(pathHash, 16777619) >>> 0;
  }
  const tempFilePath = path.join(tempDir, `${pathHash.toString(16)}_${path.basename(filePath)}`);
  const alreadyExists = await fs.promises
    .access(tempFilePath)
    .then(() => true)
    .catch(() => false);
  if (!alreadyExists) {
    const buffer = await fs.promises.readFile(filePath);
    await fs.promises.writeFile(tempFilePath, buffer);
  }
  _extractedAudioPathCache.set(filePath, tempFilePath);
  return tempFilePath;
}

function destroyAudioWorker(reason) {
  const state = _audioWorkerState;
  _audioWorkerState = null;
  if (!state) {
    return;
  }
  if (state.idleTimer) {
    clearTimeout(state.idleTimer);
    state.idleTimer = null;
  }
  if (state.itemTimer) {
    clearTimeout(state.itemTimer);
    state.itemTimer = null;
  }
  if (state.currentItem) {
    const item = state.currentItem;
    state.currentItem = null;
    item.reject(new Error(reason || "Audio worker stopped."));
  }
  try {
    state.proc.stdin.end();
  } catch (_) {}
  try {
    state.proc.kill();
  } catch (_) {}
}

function _scheduleAudioWorkerIdleShutdown(state) {
  if (state.idleTimer) {
    clearTimeout(state.idleTimer);
  }
  state.idleTimer = setTimeout(() => {
    if (_audioWorkerState === state && !state.currentItem && _audioPlayQueue.length === 0) {
      destroyAudioWorker("Idle audio worker shutdown.");
    }
  }, AUDIO_WORKER_IDLE_TIMEOUT_MS);
  if (typeof state.idleTimer.unref === "function") {
    state.idleTimer.unref();
  }
}

function _ensureAudioWorker() {
  if (_audioWorkerState) {
    return _audioWorkerState;
  }
  const psScript = [
    "[Console]::InputEncoding = [System.Text.Encoding]::UTF8;",
    "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8;",
    "$ErrorActionPreference = 'Stop';",
    "Add-Type -AssemblyName System.Windows.Forms;",
    "while (($b64 = [Console]::In.ReadLine()) -ne $null) {",
    "  if ([string]::IsNullOrWhiteSpace($b64)) { continue }",
    "  try {",
    "    $p = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64));",
    "    $player = New-Object System.Media.SoundPlayer($p);",
    "    try {",
    "      $player.Load();",
    "      $player.PlaySync();",
    "    } finally {",
    "      $player.Dispose();",
    "    }",
    "    [Console]::Out.WriteLine('OK');",
    "  } catch {",
    "    [Console]::Out.WriteLine('ERR:' + $_.Exception.Message);",
    "  }",
    "  [Console]::Out.Flush();",
    "}",
  ].join(" ");

  const proc = spawn(
    "powershell.exe",
    ["-NoProfile", "-NonInteractive", "-Command", psScript],
    { windowsHide: true, stdio: ["pipe", "pipe", "pipe"] },
  );

  const state = {
    proc,
    stdoutBuffer: "",
    currentItem: null,
    itemTimer: null,
    idleTimer: null,
  };
  _audioWorkerState = state;

  proc.stdout.setEncoding("utf8");
  proc.stdout.on("data", (chunk) => {
    state.stdoutBuffer += chunk;
    let newlineIndex = state.stdoutBuffer.indexOf("\n");
    while (newlineIndex !== -1) {
      const line = state.stdoutBuffer.slice(0, newlineIndex).trim();
      state.stdoutBuffer = state.stdoutBuffer.slice(newlineIndex + 1);
      newlineIndex = state.stdoutBuffer.indexOf("\n");
      if (!line || !state.currentItem) {
        continue;
      }
      if (state.itemTimer) {
        clearTimeout(state.itemTimer);
        state.itemTimer = null;
      }
      const item = state.currentItem;
      state.currentItem = null;
      if (line.startsWith("ERR:")) {
        item.reject(new Error(line.slice(4) || "PowerShell SoundPlayer error"));
      } else {
        item.resolve();
      }
    }
  });

  proc.once("error", (err) => {
    if (_audioWorkerState === state) {
      destroyAudioWorker(err.message);
    }
  });

  proc.once("exit", (code) => {
    if (_audioWorkerState === state) {
      destroyAudioWorker(`Audio worker exited (${code}).`);
    }
  });

  return state;
}

async function _drainAudioQueue() {
  if (_audioQueueActive) {
    return;
  }
  _audioQueueActive = true;
  try {
    while (_audioPlayQueue.length > 0 && !isQuitting) {
      const next = _audioPlayQueue.shift();
      let state;
      try {
        state = _ensureAudioWorker();
      } catch (err) {
        next.reject(err);
        continue;
      }
      if (state.idleTimer) {
        clearTimeout(state.idleTimer);
        state.idleTimer = null;
      }
      try {
        await new Promise((resolve, reject) => {
          state.currentItem = { resolve, reject };
          state.itemTimer = setTimeout(() => {
            if (_audioWorkerState === state && state.currentItem) {
              destroyAudioWorker("Audio worker playback timed out.");
            }
          }, AUDIO_WORKER_PLAY_TIMEOUT_MS);
          const encodedPath = Buffer.from(String(next.playPath || ""), "utf8").toString("base64");
          state.proc.stdin.write(`${encodedPath}\n`, "utf8");
        });
        next.resolve();
      } catch (err) {
        next.reject(err);
      }
    }
  } finally {
    _audioQueueActive = false;
    if (_audioWorkerState && !_audioWorkerState.currentItem && _audioPlayQueue.length === 0) {
      _scheduleAudioWorkerIdleShutdown(_audioWorkerState);
    }
  }
}

async function _tryPlayAudioInRenderer(filePath) {
  if (
    !mainWindow ||
    mainWindow.isDestroyed() ||
    !mainWindow.isVisible() ||
    mainWindow.isMinimized() ||
    mainWindow.webContents.isDestroyed()
  ) {
    return false;
  }
  const root = webRoot();
  const rel = path.relative(root, filePath).replace(/\\/g, "/");
  if (!rel || rel.startsWith("..") || path.isAbsolute(rel)) {
    return false;
  }
  try {
    const js = `(() => {
      try {
        const audio = new Audio(${JSON.stringify(`/${rel}`)});
        audio.volume = 1.0;
        const p = audio.play();
        if (p && typeof p.then === 'function') {
          return Promise.race([
            p.then(() => true).catch(() => false),
            new Promise((r) => setTimeout(() => r(false), 600)),
          ]);
        }
        return true;
      } catch (_) {
        return false;
      }
    })()`;
    const played = await mainWindow.webContents.executeJavaScript(js, true);
    return played === true;
  } catch (_) {
    return false;
  }
}

async function playWavFile(filePath, { fromNotification = false } = {}) {
  if (process.platform !== "win32") {
    throw new Error("Audio preview is only implemented for Windows.");
  }
  if (await _tryPlayAudioInRenderer(filePath)) {
    return;
  }
  const playPath = await resolvePlayableAudioPath(filePath);
  if (fromNotification && _audioPlayQueue.length >= 2) {
    return;
  }
  while (_audioPlayQueue.length >= AUDIO_WORKER_MAX_QUEUE) {
    const dropped = _audioPlayQueue.shift();
    dropped?.resolve();
  }
  return new Promise((resolve, reject) => {
    _audioPlayQueue.push({ playPath, resolve, reject });
    unawaitedDrainAudioQueue();
  });
}

function unawaitedDrainAudioQueue() {
  _drainAudioQueue().catch(() => {});
}

const _httpAgentKeepAlive = new http.Agent({
  keepAlive: true,
  keepAliveMsecs: 30000,
  maxSockets: 6,
});
const _httpsAgentNoVerify = new https.Agent({
  rejectUnauthorized: false,
  keepAlive: true,
  keepAliveMsecs: 30000,
  maxSockets: 6,
});

function _doFetchOnce(targetUrl, headers, redirectCount) {
  return new Promise((resolve, reject) => {
    if (redirectCount > 5) {
      reject(new Error("Too many redirects."));
      return;
    }

    let parsed;
    try {
      parsed = new URL(String(targetUrl || ""));
    } catch (_) {
      reject(new Error("Invalid URL."));
      return;
    }

    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      reject(new Error("Only HTTP URLs can be fetched."));
      return;
    }

    const isHttps = parsed.protocol === "https:";
    const transport = isHttps ? https : http;
    const requestOptions = {
      method: "GET",
      headers: {
        Accept: "image/*,*/*;q=0.8",
        ...headers,
      },
      timeout: 12000, // reduced from 30s to 12s to avoid blocking main thread on slow VPN
      agent: isHttps ? _httpsAgentNoVerify : _httpAgentKeepAlive,
    };

    const request = transport.request(
      parsed,
      requestOptions,
      (response) => {
        const statusCode = response.statusCode || 0;
        const location = response.headers.location;
        if ([301, 302, 303, 307, 308].includes(statusCode) && location) {
          response.resume();
          const nextUrl = new URL(location, parsed).toString();
          _doFetchOnce(nextUrl, headers, redirectCount + 1)
            .then(resolve)
            .catch(reject);
          return;
        }

        if (statusCode < 200 || statusCode >= 300) {
          response.resume();
          const error = new Error(
            `Image request failed with status ${statusCode}.`,
          );
          error.statusCode = statusCode;
          reject(error);
          return;
        }

        const chunks = [];
        let total = 0;
        response.on("data", (chunk) => {
          total += chunk.length;
          if (total > MAX_ELECTRON_FETCH_BYTES) {
            request.destroy(new Error("Image is too large."));
            return;
          }
          chunks.push(chunk);
        });
        response.on("end", () => {
          resolve({
            buffer: Buffer.concat(chunks),
            contentType: response.headers["content-type"] || null,
          });
        });
      },
    );

    request.on("timeout", () =>
      request.destroy(new Error("Image request timed out.")),
    );
    request.on("error", reject);
    request.end();
  });
}

// Concurrency semaphore + in-flight deduplication + bounded LRU cache:
// prevents duplicate avatar/image downloads from flooding slow branch VPNs.
let _fetchUrlBufferActive = 0;
const _fetchUrlBufferQueue = [];
const _FETCH_URL_BUFFER_CONCURRENCY = 4;
const _fetchUrlBufferInFlight = new Map();
const _fetchUrlBufferCache = new Map();
const _FETCH_URL_BUFFER_CACHE_MAX_ENTRIES = 64;
const _FETCH_URL_BUFFER_CACHE_MAX_ITEM_BYTES = 512 * 1024;
const _FETCH_URL_BUFFER_CACHE_TTL_MS = 5 * 60 * 1000;

function _rememberFetchedBuffer(cacheKey, result) {
  if (
    !result ||
    !Buffer.isBuffer(result.buffer) ||
    result.buffer.length === 0 ||
    result.buffer.length > _FETCH_URL_BUFFER_CACHE_MAX_ITEM_BYTES
  ) {
    return;
  }
  const contentType = String(result.contentType || "").toLowerCase();
  if (!contentType.startsWith("image/")) {
    return;
  }
  _fetchUrlBufferCache.delete(cacheKey);
  while (_fetchUrlBufferCache.size >= _FETCH_URL_BUFFER_CACHE_MAX_ENTRIES) {
    const oldestKey = _fetchUrlBufferCache.keys().next().value;
    _fetchUrlBufferCache.delete(oldestKey);
  }
  _fetchUrlBufferCache.set(cacheKey, {
    buffer: result.buffer,
    contentType: result.contentType,
    cachedAt: Date.now(),
  });
}

function _runNextFetch() {
  while (_fetchUrlBufferActive < _FETCH_URL_BUFFER_CONCURRENCY && _fetchUrlBufferQueue.length > 0) {
    const { task, resolve, reject } = _fetchUrlBufferQueue.shift();
    _fetchUrlBufferActive++;
    task().then(resolve, reject).finally(() => {
      _fetchUrlBufferActive--;
      _runNextFetch();
    });
  }
}

async function fetchUrlBuffer(targetUrl, headers = {}) {
  const authHeader = String(headers?.Authorization || headers?.authorization || "").trim();
  const fetchKey = `${targetUrl}\n${authHeader}`;

  const cached = _fetchUrlBufferCache.get(fetchKey);
  if (cached) {
    if (Date.now() - cached.cachedAt < _FETCH_URL_BUFFER_CACHE_TTL_MS) {
      _fetchUrlBufferCache.delete(fetchKey);
      _fetchUrlBufferCache.set(fetchKey, cached);
      return { buffer: cached.buffer, contentType: cached.contentType };
    }
    _fetchUrlBufferCache.delete(fetchKey);
  }

  const existingPromise = _fetchUrlBufferInFlight.get(fetchKey);
  if (existingPromise) {
    return existingPromise;
  }

  const promise = new Promise((resolve, reject) => {
    _fetchUrlBufferQueue.push({
      task: () => _fetchUrlBufferCore(targetUrl, headers),
      resolve,
      reject,
    });
    _runNextFetch();
  }).then((result) => {
    _rememberFetchedBuffer(fetchKey, result);
    return result;
  }).finally(() => {
    _fetchUrlBufferInFlight.delete(fetchKey);
  });

  _fetchUrlBufferInFlight.set(fetchKey, promise);
  return promise;
}

async function _fetchUrlBufferCore(targetUrl, headers = {}) {
  const MAX_ATTEMPTS = 2; // reduced from 3 to 2 retries on slow VPN
  let lastError;
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    try {
      return await _doFetchOnce(targetUrl, headers, 0);
    } catch (err) {
      lastError = err;
      const statusCode = err.statusCode || 0;
      // Do not retry on 4xx client errors (auth/not-found) — only on network/5xx
      if (statusCode >= 400 && statusCode < 500) {
        break;
      }
      if (attempt < MAX_ATTEMPTS - 1) {
        await new Promise((r) => setTimeout(r, 150)); // fixed 150ms delay, was 200*(attempt+1)
      }
    }
  }
  throw lastError;
}

// ─── PowerShell screenshot helpers ──────────────────────────────────────────

function _runPowerShell(command, timeoutMs = 30000) {
  return new Promise((resolve, reject) => {
    const os = require('os');
    const path = require('path');
    const fs = require('fs');
    const tmpFile = path.join(os.tmpdir(), `ps_${Date.now()}_${Math.random().toString(36).substr(2)}.ps1`);
    fs.writeFileSync(tmpFile, command, 'utf8');

    execFile(
      "powershell.exe",
      ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", tmpFile],
      { windowsHide: true, timeout: timeoutMs },
      (error, stdout, stderr) => {
        try { fs.unlinkSync(tmpFile); } catch(e){}
        if (error) {
          // Only reject on real PowerShell errors, not PSReadLine profile warnings
          const stderrClean = (stderr || "")
            .split("\n")
            .filter((l) => !l.includes("PSReadLine") && l.trim())
            .join("\n")
            .trim();
          reject(new Error(stderrClean || error.message));
          return;
        }
        resolve(stdout.trim());
      },
    );
  });
}

async function listOpenWindowsPS() {
  // Keep the PowerShell-to-Node protocol ASCII-only. Windows PowerShell writes
  // pipeline output using the active console code page, which turns Arabic (and
  // other Unicode) window titles into question marks before Node receives them.
  // Each textual field is sent as UTF-16LE Base64 and decoded below.
  // Uses Get-Process — no Add-Type needed, no backtick/template-literal issues.
  const script = [
    "$ErrorActionPreference = 'SilentlyContinue'",
    "$out = @()",
    "Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -ne '' } | ForEach-Object {",
    "  $id = $_.MainWindowHandle.ToInt64()",
    "  $title = $_.MainWindowTitle.Trim()",
    "  $proc = $_.ProcessName",
    "  $title64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($title))",
    "  $proc64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($proc))",
    "  if ($id -gt 0 -and $title -ne '') { $out += \"$id|$title64|$proc64\" }",
    "}",
    "$out -join [char]10",
  ].join("\n");
  const raw = await _runPowerShell(script);
  if (!raw) return [];
  return raw
    .split("\n")
    .map((line) => line.trim().replace(/\r$/, ""))
    .filter(Boolean)
    .map((line) => {
      const parts = line.split("|");
      const windowId = parseInt(parts[0] || "0", 10);
      const decodeUnicodeField = (value) => {
        try {
          return Buffer.from(value || "", "base64").toString("utf16le").trim();
        } catch (_) {
          return "";
        }
      };
      const title = decodeUnicodeField(parts[1]);
      const appName = decodeUnicodeField(parts[2]);
      return windowId > 0 && title ? { windowId, title, appName } : null;
    })
    .filter(Boolean);
}

async function captureWindowPS(windowId, imagePath) {
  const escapedPath = imagePath.replace(/'/g, "''");
  const script = `
$ErrorActionPreference = 'Stop'
if (-not ([System.Management.Automation.PSTypeName]'_ScreenCapW').Type) {
  Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms -TypeDefinition @"
  using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
  public class _ScreenCapW {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    public static bool Capture(long id, string p) {
      var hwnd = new IntPtr(id);
      if (IsIconic(hwnd)) ShowWindow(hwnd, 9);
      SetForegroundWindow(hwnd);
      System.Threading.Thread.Sleep(200);
      RECT r; if (!GetWindowRect(hwnd, out r)) return false;
      int w = r.R - r.L, h = r.B - r.T; if (w<=0||h<=0) return false;
      using (var bmp = new Bitmap(w,h)) using (var g = Graphics.FromImage(bmp)) {
        g.CopyFromScreen(r.L, r.T, 0, 0, new System.Drawing.Size(w,h));
        bmp.Save(p, ImageFormat.Png); }
      return true; }
  }
"@
}
[_ScreenCapW]::Capture(${windowId}L, '${escapedPath}')
  `.trim();
  const result = await _runPowerShell(script);
  return result.trim().toLowerCase() === "true";
}

async function captureScreenPS(imagePath) {
  const escapedPath = imagePath.replace(/'/g, "''");
  const script = `
$ErrorActionPreference = 'Stop'
if (-not ([System.Management.Automation.PSTypeName]'_ScreenCapS').Type) {
  Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms -TypeDefinition @"
  using System; using System.Drawing; using System.Drawing.Imaging; using System.Windows.Forms;
  public class _ScreenCapS {
    public static bool Capture(string p) {
      var s = Screen.PrimaryScreen.Bounds;
      using (var bmp = new Bitmap(s.Width, s.Height)) using (var g = Graphics.FromImage(bmp)) {
        g.CopyFromScreen(s.X, s.Y, 0, 0, bmp.Size);
        bmp.Save(p, ImageFormat.Png); }
      return true; }
  }
"@
}
[_ScreenCapS]::Capture('${escapedPath}')
  `.trim();
  const result = await _runPowerShell(script);
  return result.trim().toLowerCase() === "true";
}

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function formatBytes(bytes) {
  const size = Number(bytes || 0);
  if (!Number.isFinite(size) || size <= 0) return "غير معروف";
  const units = ["B", "KB", "MB", "GB"];
  let value = size;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return `${value.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`;
}

function pendingLanReceiveSummaries() {
  return [...pendingLanReceiveRequests.values()].map((entry) => ({
    requestId: entry.requestId,
    fileName: entry.fileName,
    fileSizeBytes: entry.fileSizeBytes,
    senderName: entry.senderName,
    senderIp: entry.senderIp,
    createdAt: entry.createdAt,
  }));
}

function notifyRendererPendingLanReceive() {
  if (mainWindow && !mainWindow.webContents.isDestroyed()) {
    mainWindow.webContents.send(
      "lan-receive-pending",
      pendingLanReceiveSummaries(),
    );
  }
}

function showLanReceiveNotification(entry) {
  try {
    const notification = new Notification({
      title: "طلب استقبال ملف",
      body: `${entry.senderName} يريد إرسال ${entry.fileName} (${formatBytes(entry.fileSizeBytes)})`,
      silent: false,
      timeoutType: "default",
    });
    const autoCloseTimer = setTimeout(() => {
      try {
        notification.close();
      } catch (_) {}
    }, 6000);
    notification.on("click", () => {
      clearTimeout(autoCloseTimer);
      try {
        if (mainWindow) {
          if (mainWindow.isMinimized()) mainWindow.restore();
          mainWindow.show();
          mainWindow.focus();
        }
        notification.close();
      } catch (_) {}
      openPendingLanReceiveDialog(entry.requestId);
    });
    notification.on("close", () => {
      clearTimeout(autoCloseTimer);
    });
    notification.show();
  } catch (error) {
    console.warn(`LAN receive notification failed: ${error.message}`);
  }
  if (mainWindow && !mainWindow.isFocused()) {
    mainWindow.flashFrame(true);
  }
}

function scheduleLanReceiveReminder() {
  if (lanReceiveReminderTimer) {
    return;
  }
  lanReceiveReminderTimer = setInterval(() => {
    const first = pendingLanReceiveRequests.values().next().value;
    if (!first) {
      clearInterval(lanReceiveReminderTimer);
      lanReceiveReminderTimer = null;
      return;
    }
    showLanReceiveNotification(first);
  }, 2 * 60 * 1000);
}

function createPendingLanReceiveRequest({
  fileName,
  fileSizeBytes,
  senderName,
  senderIp,
  transferRecordId = null,
}) {
  const requestId = `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
  let resolveDecision;
  const decision = new Promise((resolve) => {
    resolveDecision = resolve;
  });
  const entry = {
    requestId,
    fileName,
    fileSizeBytes,
    senderName,
    senderIp,
    transferRecordId,
    createdAt: new Date().toISOString(),
    window: null,
    decision,
    resolveDecision,
  };
  pendingLanReceiveRequests.set(requestId, entry);
  notifyRendererPendingLanReceive();
  showLanReceiveNotification(entry);
  scheduleLanReceiveReminder();
  setTimeout(() => openPendingLanReceiveDialog(requestId), 250);
  return entry;
}

function settlePendingLanReceiveRequest(entry, result) {
  if (!entry || !pendingLanReceiveRequests.has(entry.requestId)) {
    return;
  }
  pendingLanReceiveRequests.delete(entry.requestId);
  if (pendingLanReceiveRequests.size === 0 && lanReceiveReminderTimer) {
    clearInterval(lanReceiveReminderTimer);
    lanReceiveReminderTimer = null;
  }
  if (entry.window && !entry.window.isDestroyed()) {
    entry.window.removeAllListeners("closed");
    entry.window.close();
  }
  entry.window = null;
  entry.resolveDecision(result || { accepted: false, directoryPath: null });
  notifyRendererPendingLanReceive();
}

async function handlePendingLanReceiveDecision(entry, decision, ownerWindow) {
  const value = String(decision || "");
  if (value === "choose") {
    const picker = await dialog.showOpenDialog(ownerWindow || mainWindow || undefined, {
      title: "اختر مكان حفظ الملف",
      properties: ["openDirectory", "createDirectory"],
      defaultPath: localStorageChildPath("Incoming"),
    });
    if (picker.canceled || !picker.filePaths.length) {
      return;
    }
    settlePendingLanReceiveRequest(entry, {
      accepted: true,
      directoryPath: picker.filePaths[0],
    });
    return;
  }
  if (value === "accept") {
    settlePendingLanReceiveRequest(entry, {
      accepted: true,
      directoryPath: null,
    });
    return;
  }
  if (value === "reject") {
    settlePendingLanReceiveRequest(entry, {
      accepted: false,
      directoryPath: null,
    });
  }
}

function openPendingLanReceiveDialog(requestId) {
  const entry =
    pendingLanReceiveRequests.get(String(requestId || "")) ||
    pendingLanReceiveRequests.values().next().value;
  if (!entry) {
    showMainWindow();
    return { success: false, message: "No pending LAN receive requests." };
  }
  showMainWindow();
  if (entry.window && !entry.window.isDestroyed()) {
    entry.window.show();
    entry.window.focus();
    return { success: true, alreadyOpen: true, requestId: entry.requestId };
  }

  try {
    const receiveWindow = new BrowserWindow({
      width: 440,
      height: 340,
      resizable: false,
      minimizable: false,
      maximizable: false,
      fullscreenable: false,
      title: "استقبال ملف",
      parent: mainWindow || undefined,
      modal: false,
      autoHideMenuBar: true,
      show: false,
      icon: appIconPath(),
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: false,
        preload: path.join(__dirname, "receive-preload.js"),
      },
    });
    entry.window = receiveWindow;
    const channel = `lan-receive-decision:${entry.requestId}:${Math.random()
      .toString(36)
      .slice(2)}`;
    ipcMain.on(channel, async (_event, decision) => {
      await handlePendingLanReceiveDecision(entry, decision, receiveWindow);
    });
    receiveWindow.on("closed", () => {
      ipcMain.removeAllListeners(channel);
      if (entry.window === receiveWindow) {
        entry.window = null;
      }
      notifyRendererPendingLanReceive();
    });
    receiveWindow.once("ready-to-show", () => receiveWindow.show());

    const html = `<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8" />
<style>
*{box-sizing:border-box}body{margin:0;font-family:"NotoSansArabic","NotoSans","Segoe UI",Tahoma,Arial,sans-serif;background:#0e1621;color:#f4f7fb}
.wrap{height:100vh;padding:22px;background:linear-gradient(135deg,#111b26,#182533)}
.head{display:flex;gap:14px;align-items:center;margin-bottom:18px}.icon{width:46px;height:46px;border-radius:14px;background:#2f8cff;display:grid;place-items:center;font-size:24px}
h1{font-size:18px;margin:0 0 4px}.sub{font-size:13px;color:#a8b3c1;line-height:1.5}.file{background:#223142;border:1px solid #37516b;border-radius:10px;padding:12px;margin:14px 0;color:#dce8f5;direction:ltr;text-align:left;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.meta{font-size:13px;color:#8fb4d8;margin-bottom:18px}.hint{font-size:12px;color:#96a8ba;margin-bottom:14px}.actions{display:grid;grid-template-columns:1fr 1fr;gap:10px}.btn{border:0;border-radius:8px;padding:11px 12px;font-weight:700;cursor:pointer;min-width:0}.accept{background:#3390ec;color:white}.choose{background:#1f6fb8;color:white}.reject{background:#263544;color:#d7e4f2;grid-column:1/3}.btn:focus{outline:2px solid #7bbcff;outline-offset:2px}
</style>
</head>
<body>
<div class="wrap">
  <div class="head"><div class="icon">↓</div><div><h1>طلب استقبال ملف</h1><div class="sub">يريد ${escapeHtml(entry.senderName)} إرسال ملف إلى هذا الجهاز.</div></div></div>
  <div class="file">${escapeHtml(entry.fileName)}</div>
  <div class="meta">الحجم: ${escapeHtml(formatBytes(entry.fileSizeBytes))}</div>
  <div class="hint">يمكنك إغلاق هذه النافذة وفتحها لاحقا من صفحة الملفات طالما الطلب ما زال معلقا.</div>
  <div class="actions"><button class="btn accept" id="accept">حفظ في الافتراضي</button><button class="btn choose" id="choose">اختيار المكان</button><button class="btn reject" id="reject">رفض</button></div>
</div>
<script>
document.getElementById("accept").onclick = () => window.receiveBridge.decide("${channel}", "accept");
document.getElementById("choose").onclick = () => window.receiveBridge.decide("${channel}", "choose");
document.getElementById("reject").onclick = () => window.receiveBridge.decide("${channel}", "reject");
document.addEventListener("keydown", e => { if (e.key === "Escape") window.close(); });
</script>
</body></html>`;
    receiveWindow.loadURL(
      `data:text/html;charset=utf-8,${encodeURIComponent(html)}`,
    );
    return { success: true, requestId: entry.requestId };
  } catch (error) {
    console.warn(`Failed to open LAN receive dialog: ${error.message}`);
    return { success: false, message: error.message };
  }
}

function showLanReceiveDialog({ fileName, fileSizeBytes, senderName }) {
  return new Promise((resolve) => {
    const receiveWindow = new BrowserWindow({
      width: 420,
      height: 330,
      resizable: false,
      minimizable: false,
      maximizable: false,
      fullscreenable: false,
      title: "استقبال ملف",
      parent: mainWindow || undefined,
      modal: Boolean(mainWindow),
      autoHideMenuBar: true,
      show: false,
      icon: appIconPath(),
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: false,
        preload: path.join(__dirname, "receive-preload.js"),
      },
    });

    const channel = `lan-receive-decision:${Date.now()}:${Math.random()
      .toString(36)
      .slice(2)}`;
    let settled = false;
    const settle = (result) => {
      if (settled) return;
      settled = true;
      ipcMain.removeAllListeners(channel);
      if (!receiveWindow.isDestroyed()) receiveWindow.close();
      resolve(result || { accepted: false, directoryPath: null });
    };
    ipcMain.on(channel, async (_event, decision) => {
      const value = String(decision || "");
      if (value === "choose") {
        const picker = await dialog.showOpenDialog(receiveWindow, {
          title: "اختر مكان حفظ الملف",
          properties: ["openDirectory", "createDirectory"],
          defaultPath: app.getPath("downloads"),
        });
        if (picker.canceled || !picker.filePaths.length) {
          return;
        }
        settle({ accepted: true, directoryPath: picker.filePaths[0] });
        return;
      }
      settle({ accepted: value === "accept", directoryPath: null });
    });
    receiveWindow.on("closed", () =>
      settle({ accepted: false, directoryPath: null }),
    );
    receiveWindow.once("ready-to-show", () => receiveWindow.show());

    const html = `<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8" />
<style>
*{box-sizing:border-box}body{margin:0;font-family:"NotoSansArabic","NotoSans","Segoe UI",Tahoma,Arial,sans-serif;background:#0e1621;color:#f4f7fb}
.wrap{height:100vh;padding:22px;background:linear-gradient(135deg,#111b26,#182533)}
.head{display:flex;gap:14px;align-items:center;margin-bottom:18px}.icon{width:46px;height:46px;border-radius:14px;background:#2f8cff;display:grid;place-items:center;font-size:24px}
h1{font-size:18px;margin:0 0 4px}.sub{font-size:13px;color:#a8b3c1;line-height:1.5}.file{background:#223142;border:1px solid #37516b;border-radius:10px;padding:12px;margin:14px 0;color:#dce8f5;direction:ltr;text-align:left;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.meta{font-size:13px;color:#8fb4d8;margin-bottom:18px}.actions{display:grid;grid-template-columns:1fr 1fr;gap:10px}.btn{border:0;border-radius:8px;padding:11px 12px;font-weight:700;cursor:pointer;min-width:0}.accept{background:#3390ec;color:white}.choose{background:#1f6fb8;color:white}.reject{background:#263544;color:#d7e4f2;grid-column:1/3}.btn:focus{outline:2px solid #7bbcff;outline-offset:2px}
</style>
</head>
<body>
<div class="wrap">
  <div class="head"><div class="icon">↓</div><div><h1>طلب استقبال ملف</h1><div class="sub">يريد ${escapeHtml(senderName)} إرسال ملف إلى هذا الجهاز.</div></div></div>
  <div class="file">${escapeHtml(fileName)}</div>
  <div class="meta">الحجم: ${escapeHtml(formatBytes(fileSizeBytes))}</div>
  <div class="actions"><button class="btn accept" id="accept">حفظ في الافتراضي</button><button class="btn choose" id="choose">اختيار المكان</button><button class="btn reject" id="reject">رفض</button></div>
</div>
<script>
document.getElementById("accept").onclick = () => window.receiveBridge.decide("${channel}", "accept");
document.getElementById("choose").onclick = () => window.receiveBridge.decide("${channel}", "choose");
document.getElementById("reject").onclick = () => window.receiveBridge.decide("${channel}", "reject");
document.addEventListener("keydown", e => { if (e.key === "Escape") window.receiveBridge.decide("${channel}", "reject"); });
</script>
</body></html>`;
    receiveWindow.loadURL(
      `data:text/html;charset=utf-8,${encodeURIComponent(html)}`,
    );
  });
}

function startLanTransferServer() {
  if (lanServer) {
    return;
  }
  lanServer = http.createServer(async (request, response) => {
    if (request.method === "OPTIONS") {
      sendJson(response, 204, {});
      return;
    }

    if (request.method === "GET" && request.url === "/lan-transfer/info") {
      sendJson(response, 200, {
        success: true,
        app: APP_NAME,
        port: LAN_TRANSFER_PORT,
        ips: localIpv4s(),
      });
      return;
    }

    if (request.method === "POST" && request.url === "/lan-transfer/request") {
      try {
        const payload = await parseJsonRequest(request);
        const fileName = safeFileName(payload.fileName);
        const fileSizeBytes = Number(payload.fileSizeBytes || 0);
        const senderName =
          String(payload.senderName || "User").trim() || "User";
        const senderBranchCode = String(payload.senderBranchCode || "")
          .trim()
          .toUpperCase();
        const policyCheck = validateTransferPolicy({
          fileName,
          fileSizeBytes,
          senderBranchCode,
          receiverBranchCode: null,
        });
        if (!policyCheck.allowed) {
          addAuditLog({
            type: "receive_blocked_by_policy",
            actorName: "هذا الجهاز",
            peerName: senderName,
            fileName,
            fileSizeBytes,
            status: "blocked",
            message: policyCheck.message,
          });
          addNotificationRecord({
            category: "files",
            title: "تم منع استقبال ملف",
            body: policyCheck.message,
          });
          sendJson(response, 200, {
            accepted: false,
            message: policyCheck.message,
          });
          return;
        }
        const incomingRecord = addTransferRecord({
          direction: "incoming",
          status: "waiting_acceptance",
          fileName,
          fileSizeBytes,
          senderName,
          senderBranchCode,
          peerName: senderName,
          peerIp: request.socket?.remoteAddress || "unknown",
          message: "بانتظار قبول الاستقبال.",
        });
        const pendingReceive = createPendingLanReceiveRequest({
          fileName,
          fileSizeBytes,
          senderName,
          senderIp: request.socket?.remoteAddress || "unknown",
          transferRecordId: incomingRecord.id,
        });
        const receiveDecision = await pendingReceive.decision;
        if (!receiveDecision.accepted) {
          updateTransferRecord(incomingRecord.id, {
            status: "rejected",
            message: "تم رفض استلام الملف.",
          });
          addAuditLog({
            type: "receive_rejected",
            actorName: "هذا الجهاز",
            peerName: senderName,
            fileName,
            fileSizeBytes,
            status: "rejected",
            message: "تم رفض استلام الملف.",
          });
          sendJson(response, 200, {
            accepted: false,
            message: "تم رفض استلام الملف.",
          });
          return;
        }
        const transferId = `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
        const uploadToken = crypto.randomBytes(32).toString("hex");
        const downloads = receiveDecision.directoryPath
          ? String(receiveDecision.directoryPath)
          : localStorageChildPath("Incoming");
        fs.mkdirSync(downloads, { recursive: true });
        pendingLanTransfers.set(transferId, {
          outputPath: uniqueOutputPath(downloads, fileName),
          fileName,
          fileSizeBytes,
          senderName,
          senderIp: request.socket?.remoteAddress || "unknown",
          transferRecordId: incomingRecord.id,
          uploadToken,
        });
        updateTransferRecord(incomingRecord.id, {
          status: "accepted",
          savedPath: pendingLanTransfers.get(transferId)?.outputPath || null,
          message: "تم قبول استلام الملف.",
        });
        addAuditLog({
          type: "receive_accepted",
          actorName: "هذا الجهاز",
          peerName: senderName,
          fileName,
          fileSizeBytes,
          status: "accepted",
          message: "تم قبول استلام الملف.",
        });
        sendJson(response, 200, {
          accepted: true,
          transferId,
          uploadToken,
          message: "تم قبول استلام الملف.",
        });
      } catch (error) {
        sendJson(response, 400, { accepted: false, message: error.message });
      }
      return;
    }

    if (
      request.method === "POST" &&
      request.url.startsWith("/lan-transfer/upload/")
    ) {
      const transferId = decodeURIComponent(request.url.split("/").pop() || "");
      const pending = pendingLanTransfers.get(transferId);
      if (!pending) {
        sendJson(response, 404, {
          success: false,
          message: "Invalid transfer id.",
        });
        return;
      }
      const uploadToken = String(request.headers["x-lan-transfer-token"] || "").trim();
      if (!pending.uploadToken || uploadToken !== pending.uploadToken) {
        sendJson(response, 403, {
          success: false,
          message: "Invalid transfer token.",
        });
        return;
      }
      const declaredBytes = Number(request.headers["content-length"] || 0) || 0;
      if (
        pending.fileSizeBytes > 0 &&
        declaredBytes > 0 &&
        declaredBytes !== pending.fileSizeBytes
      ) {
        sendJson(response, 400, {
          success: false,
          message: "Transfer size does not match the accepted request.",
        });
        return;
      }
      const output = fs.createWriteStream(pending.outputPath);
      const totalBytes =
        declaredBytes || Number(pending.fileSizeBytes || 0) || 0;
      let receivedBytes = 0;
      let lastPercent = -1;
      request.on("data", (chunk) => {
        receivedBytes += chunk.length;
        const progress = totalBytes <= 0 ? 0 : Math.min(receivedBytes / totalBytes, 1);
        const percent = Math.floor(progress * 100);
        if (percent !== lastPercent) {
          lastPercent = percent;
          emitLanTransferProgress({
            direction: "incoming",
            stage: "receiving",
            fileName: pending.fileName || path.basename(pending.outputPath),
            peerLabel: pending.senderName || pending.senderIp || "جهاز على الشبكة",
            progress,
            receivedBytes,
            totalBytes,
            savedPath: pending.outputPath,
            message: `جاري استقبال الملف ${percent}%`,
          });
        }
      });
      request.pipe(output);
      output.on("finish", () => {
        pendingLanTransfers.delete(transferId);
        if (pending.transferRecordId) {
          updateTransferRecord(pending.transferRecordId, {
            status: "completed",
            savedPath: pending.outputPath,
            message: "تم حفظ الملف على هذا الجهاز بنجاح.",
          });
        }
        addInboxRecord({
          fileName: pending.fileName || path.basename(pending.outputPath),
          fileSizeBytes: totalBytes || receivedBytes,
          senderName: pending.senderName || null,
          senderIp: pending.senderIp || null,
          savedPath: pending.outputPath,
        });
        addNotificationRecord({
          category: "files",
          title: "تم استلام ملف",
          body: `تم حفظ ${pending.fileName || path.basename(pending.outputPath)} بنجاح.`,
        });
        addAuditLog({
          type: "receive_completed",
          actorName: "هذا الجهاز",
          peerName: pending.senderName || pending.senderIp || null,
          fileName: pending.fileName || path.basename(pending.outputPath),
          fileSizeBytes: totalBytes || receivedBytes,
          status: "completed",
          message: "تم حفظ الملف على هذا الجهاز بنجاح.",
        });
        emitLanTransferProgress({
          direction: "incoming",
          stage: "completed",
          fileName: pending.fileName || path.basename(pending.outputPath),
          peerLabel: pending.senderName || pending.senderIp || "جهاز على الشبكة",
          progress: 1,
          receivedBytes: totalBytes || receivedBytes,
          totalBytes: totalBytes || receivedBytes,
          savedPath: pending.outputPath,
          message: "تم استلام الملف بنجاح.",
        });
        sendJson(response, 200, {
          success: true,
          message: "تم حفظ الملف على هذا الجهاز بنجاح.",
          savedPath: pending.outputPath,
        });
        shell.showItemInFolder(pending.outputPath);
      });
      output.on("error", (error) => {
        pendingLanTransfers.delete(transferId);
        if (pending.transferRecordId) {
          updateTransferRecord(pending.transferRecordId, {
            status: "failed",
            message: `فشل حفظ الملف: ${error.message}`,
          });
        }
        addAuditLog({
          type: "receive_failed",
          actorName: "هذا الجهاز",
          peerName: pending.senderName || pending.senderIp || null,
          fileName: pending.fileName || path.basename(pending.outputPath),
          fileSizeBytes: totalBytes || receivedBytes,
          status: "failed",
          message: `فشل حفظ الملف: ${error.message}`,
        });
        emitLanTransferProgress({
          direction: "incoming",
          stage: "failed",
          fileName: pending.fileName || path.basename(pending.outputPath),
          peerLabel: pending.senderName || pending.senderIp || "جهاز على الشبكة",
          progress: 1,
          receivedBytes,
          totalBytes,
          savedPath: pending.outputPath,
          message: `فشل استلام الملف: ${error.message}`,
        });
        sendJson(response, 500, {
          success: false,
          message: `فشل حفظ الملف: ${error.message}`,
        });
      });
      return;
    }

    sendJson(response, 404, { success: false, message: "Not found" });
  });
  lanServer.on("error", (error) => {
    console.warn(`LAN transfer server was not started: ${error.message}`);
  });
  lanServer.listen(LAN_TRANSFER_PORT, "0.0.0.0");
}

async function printFile(target, printerName) {
  const printWindow = new BrowserWindow({
    show: false,
    width: 900,
    height: 1200,
    webPreferences: { sandbox: true, plugins: true },
  });
  try {
    await printWindow.loadURL(target);

    // Chromium's PDF viewer can spool blank pages if printed while the
    // BrowserWindow is still hidden. Briefly showing it lets the plugin paint.
    printWindow.showInactive();
    await new Promise((resolve) => setTimeout(resolve, 3500));

    await new Promise((resolve, reject) => {
      printWindow.webContents.print(
        {
          silent: Boolean(printerName),
          deviceName: printerName || undefined,
          printBackground: true,
          margins: { marginType: "printableArea" },
        },
        (success, failureReason) => {
          if (success) resolve();
          else reject(new Error(failureReason || "Print failed."));
        },
      );
    });
    return { success: true, printerName: printerName || null };
  } finally {
    printWindow.close();
  }
}

ipcMain.handle("app:get-device-info", async () => {
  const ranked = getRankedIpv4Addresses();
  const seenIps = new Set();
  const allIps = [];
  for (const item of ranked) {
    if (!seenIps.has(item.ip)) {
      seenIps.add(item.ip);
      allIps.push(item.ip);
    }
  }
  const bestPhysical = ranked.find((item) => !item.isVirtual);
  const bestIp = bestPhysical ? bestPhysical.ip : (allIps[0] || null);
  return {
    hostName: os.hostname(),
    localIp: bestIp,
    localIps: allIps,
    osName: process.platform,
    osVersion: os.release(),
    architecture: process.arch,
    appVersion: app.getVersion(),
  };
});

ipcMain.handle("debug:log", async (_event, payload = {}) => {
  appendDebugLog(payload.scope, payload.message, payload.details);
  return { success: true, path: debugLogPath() };
});

ipcMain.handle("secure-store:set", async (_event, payload = {}) => {
  appendDebugLog("secure-store", "set", {
    key: normalizeSecureKey(payload.key),
    encryptionAvailable: safeStorage.isEncryptionAvailable(),
  });
  if (!safeStorage.isEncryptionAvailable()) {
    return { success: false, message: "Secure storage is not available." };
  }
  const key = normalizeSecureKey(payload.key);
  if (!key) {
    return { success: false, message: "Secure storage key is required." };
  }
  const encrypted = safeStorage.encryptString(String(payload.value || ""));
  const store = readSecureStore();
  store[key] = encrypted.toString("base64");
  writeSecureStore(store);
  return { success: true };
});

ipcMain.handle("secure-store:get", async (_event, keyValue) => {
  appendDebugLog("secure-store", "get", {
    key: normalizeSecureKey(keyValue),
    encryptionAvailable: safeStorage.isEncryptionAvailable(),
  });
  if (!safeStorage.isEncryptionAvailable()) {
    return { success: false, value: null };
  }
  const key = normalizeSecureKey(keyValue);
  if (!key) {
    return { success: false, value: null };
  }
  const encrypted = readSecureStore()[key];
  if (!encrypted) {
    return { success: true, value: null };
  }
  try {
    const value = safeStorage.decryptString(Buffer.from(encrypted, "base64"));
    return { success: true, value };
  } catch (_) {
    return { success: false, value: null };
  }
});

ipcMain.handle("secure-store:delete", async (_event, keyValue) => {
  const key = normalizeSecureKey(keyValue);
  if (!key) {
    return { success: false };
  }
  const store = readSecureStore();
  delete store[key];
  writeSecureStore(store);
  return { success: true };
});

ipcMain.handle("lan:probe-peer", async (_event, targetIp) =>
  probeLanPeerWithRetry(targetIp),
);

ipcMain.handle("lan:discover-peers", async () => discoverLanPeersOnLocalNetworks());

ipcMain.handle("lan:request-transfer", async (_event, payload = {}) =>
  requestLanJson(payload.targetIp, "/lan-transfer/request", {
    method: "POST",
    timeoutMs: 60 * 60 * 1000,
    payload: {
      fileName: payload.fileName,
      fileSizeBytes: payload.fileSizeBytes,
      senderName: payload.senderName,
      mimeType: payload.mimeType,
    },
  }),
);

ipcMain.handle("lan:upload-transfer", async (_event, payload = {}) =>
  uploadLanBuffer(
    payload.targetIp,
    payload.transferId,
    payload.bytes,
    payload.uploadToken,
  ),
);

ipcMain.handle("lan:pick-and-send-file", async (_event, payload = {}) =>
  pickAndSendLanFile(payload),
);

ipcMain.handle("lan:get-pending-receive-requests", async () =>
  pendingLanReceiveSummaries(),
);

ipcMain.handle("lan:open-pending-receive-dialog", async (_event, requestId) =>
  openPendingLanReceiveDialog(requestId),
);

ipcMain.handle("lan:get-transfer-center-state", async () => readTransferStore());

ipcMain.handle("lan:update-transfer-policy", async (_event, policy = {}) => {
  const nextPolicy = normalizeTransferPolicy(policy);
  const updated = mutateTransferStore((store) => {
    store.policy = nextPolicy;
    return store;
  });
  addAuditLog({
    type: "policy_updated",
    actorName: "admin",
    status: "updated",
    message: "تم تحديث سياسة نقل الملفات.",
  });
  addNotificationRecord({
    category: "admin",
    title: "تم تحديث سياسة نقل الملفات",
    body: "تم حفظ إعدادات سياسة نقل الملفات المحلية.",
  });
  return updated;
});

ipcMain.handle("lan:mark-notifications-read", async () =>
  mutateTransferStore((store) => {
    store.notifications = store.notifications.map((entry) => ({
      ...entry,
      read: true,
    }));
    return store;
  }),
);

ipcMain.handle("lan:open-inbox-file-location", async (_event, filePath) => {
  const target = String(filePath || "").trim();
  if (!target || !fs.existsSync(target)) {
    return { success: false, message: "الملف غير موجود على هذا الجهاز." };
  }
  const resolvedTarget = path.resolve(target);
  const store = readTransferStore();
  const isKnownInboxFile = (store.inbox || []).some(
    (entry) =>
      entry?.savedPath && path.resolve(String(entry.savedPath)) === resolvedTarget,
  );
  if (!isKnownInboxFile) {
    return { success: false, message: "لا يمكن فتح هذا المسار من صندوق الوارد." };
  }
  shell.showItemInFolder(target);
  return { success: true };
});

ipcMain.handle("printers:list", async () => {
  const printers = mainWindow
    ? await mainWindow.webContents.getPrintersAsync()
    : [];
  return printers.map((printer) => ({
    name: printer.name,
    isDefault: printer.isDefault === true,
    status: printer.status,
  }));
});

const NOTIFICATION_AUDIO_COOLDOWN_MS = 750;
let _lastNotificationAudioAt = 0;

ipcMain.handle("notifications:show", async (_event, payload = {}) => {
  const title = String(payload.title || APP_NAME);
  const body = String(payload.body || "");
  const soundAssetPath = String(payload.soundAssetPath || "").trim();
  const silent = true;
  try {
    if (soundAssetPath) {
      const now = Date.now();
      if (now - _lastNotificationAudioAt >= NOTIFICATION_AUDIO_COOLDOWN_MS) {
        const filePath = resolveWebAssetPath(soundAssetPath);
        if (filePath) {
          _lastNotificationAudioAt = now;
          playWavFile(filePath, { fromNotification: true }).catch((error) =>
            console.error("[electron] notification sound failed", error),
          );
        }
      }
    }
    if (Notification.isSupported()) {
      const notif = new Notification({
        title,
        body,
        silent,
        timeoutType: "default",
      });
      const autoCloseTimer = setTimeout(() => {
        try {
          notif.close();
        } catch (_) {}
      }, 5000);
      try {
        notif.on("click", () => {
          clearTimeout(autoCloseTimer);
          try {
            if (mainWindow) {
              if (mainWindow.isMinimized()) mainWindow.restore();
              mainWindow.show();
              mainWindow.focus();
            }
            notif.close();
          } catch (_) {}
        });
        notif.on("close", () => {
          clearTimeout(autoCloseTimer);
        });
      } catch (e) {}
      notif.show();
    }
    if (mainWindow && !mainWindow.isFocused()) {
      mainWindow.flashFrame(true);
    }
    return { success: true };
  } catch (err) {
    console.error("[electron] notifications:show error", err);
    return { success: false, error: String(err) };
  }
});

ipcMain.handle("audio:play-asset", async (_event, payload = {}) => {
  const assetPath = String(payload.assetPath || "").trim();
  try {
    const filePath = resolveWebAssetPath(assetPath);
    if (!filePath) {
      return {
        success: false,
        error: `Audio asset was not found: ${assetPath}`,
      };
    }
    await playWavFile(filePath);
    return { success: true, filePath };
  } catch (error) {
    console.error("[electron] audio:play-asset error", error);
    return { success: false, error: String(error.message || error) };
  }
});

ipcMain.handle("window:request-attention", async () => {
  if (mainWindow) {
    mainWindow.flashFrame(true);
  }
  return { success: true };
});

ipcMain.handle("window:get-state", async () => ({
  isVisible: mainWindow ? mainWindow.isVisible() : false,
  isMinimized: mainWindow ? mainWindow.isMinimized() : false,
  isForeground: mainWindow ? mainWindow.isFocused() : false,
}));

ipcMain.handle("window:set-theme", async (_event, payload = {}) => {
  const mode =
    String(payload.mode || "").toLowerCase() === "dark" ? "dark" : "light";
  applyWindowTheme(mode);
  return { success: true, mode: currentWindowTheme };
});

let currentBadgeCount = 0;

function updateAppBadge(count, dataUrl) {
  const validCount = Number.isFinite(count) ? Math.max(0, Math.floor(count)) : 0;
  currentBadgeCount = validCount;

  if (!mainWindow || mainWindow.isDestroyed()) {
    return;
  }

  // 1. Windows Taskbar Overlay Icon (16x16 crisp red badge)
  if (process.platform === "win32") {
    try {
      if (validCount <= 0 || !dataUrl) {
        mainWindow.setOverlayIcon(null, "");
      } else {
        const badgeImage = nativeImage.createFromDataURL(dataUrl);
        if (!badgeImage.isEmpty()) {
          const desc = validCount === 1 ? "رسالة جديدة واحدة" : `${validCount} رسائل غير مقروءة`;
          mainWindow.setOverlayIcon(badgeImage, desc);
        } else {
          mainWindow.setOverlayIcon(null, "");
        }
      }
    } catch (e) {
      console.warn("[Badge] Failed to set overlay icon:", e.message);
    }
  }

  // 2. Window Title
  try {
    const titlePrefix = validCount > 0 ? `(${validCount}) ` : "";
    mainWindow.setTitle(`${titlePrefix}${APP_NAME}`);
  } catch (_) {}

  // 3. System Tray Tooltip
  if (tray && !tray.isDestroyed()) {
    try {
      const tooltip = validCount > 0
        ? `${APP_NAME} (${validCount} غير مقروء)`
        : APP_NAME;
      tray.setToolTip(tooltip);
    } catch (_) {}
  }

  // 4. macOS / Linux Dock Badge
  // CRITICAL: NEVER call app.setBadgeCount on Windows. On Windows, Chromium implements
  // app.setBadgeCount by setting its own default dark charcoal overlay icon, which
  // immediately overwrites and destroys our custom 16x16 vibrant red overlay badge!
  if (process.platform === "darwin" && app.dock && typeof app.dock.setBadge === "function") {
    try {
      app.dock.setBadge(validCount > 0 ? String(validCount) : "");
    } catch (_) {}
  } else if (process.platform === "linux" && typeof app.setBadgeCount === "function") {
    try {
      app.setBadgeCount(validCount);
    } catch (_) {}
  }
}

ipcMain.handle("window:set-badge", async (_event, payload = {}) => {
  const count = typeof payload === "number" ? payload : (payload?.count || 0);
  const dataUrl = payload?.dataUrl || payload?.badgedIconUrl || null;
  updateAppBadge(count, dataUrl);
  return { success: true, count: currentBadgeCount };
});


const STORAGE_IMAGE_EXTS = new Set([".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".heic", ".ico"]);
const STORAGE_AUDIO_EXTS = new Set([".m4a", ".aac", ".mp3", ".wav", ".ogg", ".opus", ".flac"]);
const STORAGE_DOC_EXTS = new Set([".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".txt", ".csv", ".zip", ".rar"]);

function parseWindowsHdrop(buf) {
  if (!buf || buf.length < 20) return [];
  try {
    const pFiles = buf.readUInt32LE(0);
    const fWide = buf.readUInt32LE(16);
    if (pFiles >= buf.length) return [];
    if (fWide) {
      const text = buf.subarray(pFiles).toString("utf16le");
      return text.split("\0").map((s) => s.trim()).filter((p) => p.length > 0 && fs.existsSync(p));
    } else {
      const text = buf.subarray(pFiles).toString("utf8");
      return text.split("\0").map((s) => s.trim()).filter((p) => p.length > 0 && fs.existsSync(p));
    }
  } catch (_) {
    return [];
  }
}

function getClipHelperPath() {
  const devPath = path.join(__dirname, "clip_helper.exe");
  if (fs.existsSync(devPath)) return devPath;
  const unpackedPath = path.join(process.resourcesPath, "app.asar.unpacked", "clip_helper.exe");
  if (fs.existsSync(unpackedPath)) return unpackedPath;
  const resPath = path.join(process.resourcesPath, "clip_helper.exe");
  if (fs.existsSync(resPath)) return resPath;
  return null;
}

function getWindowsClipboardFilePathsHelper() {
  const helperPath = getClipHelperPath();
  if (!helperPath) return Promise.resolve(null);
  return new Promise((resolve) => {
    execFile(
      helperPath,
      [],
      { windowsHide: true, timeout: 2000, maxBuffer: 4 * 1024 * 1024 },
      (err, stdout) => {
        if (err) return resolve(null);
        const raw = String(stdout || "").trim();
        if (!raw || raw === "null") return resolve(null);
        try {
          const parsed = JSON.parse(raw);
          if (Array.isArray(parsed) && parsed.length > 0) {
            resolve(parsed.map((p) => String(p || "").trim()).filter(Boolean));
          } else {
            resolve(null);
          }
        } catch (_) {
          resolve(null);
        }
      }
    );
  });
}

async function getWindowsClipboardFilePaths() {
  if (process.platform !== "win32") {
    return [];
  }
  try {
    const { clipboard } = require("electron");

    // Fast check 1: Can we read FileNameW buffer directly? (< 0.1ms)
    // When files are copied in Windows Explorer, FileNameW buffer contains the first file path.
    const fnBuf = clipboard.readBuffer("FileNameW");
    let hasFileName = false;
    let singleFile = "";
    if (fnBuf && fnBuf.length > 2) {
      const raw = fnBuf.toString("utf16le").replace(/\0.*$/, "").trim();
      if (raw && fs.existsSync(raw)) {
        hasFileName = true;
        singleFile = raw;
      }
    }

    // Fast check 2: Check CF_HDROP buffer (< 0.1ms)
    const hdropBuf = clipboard.readBuffer("CF_HDROP");
    const hdropPaths = parseWindowsHdrop(hdropBuf);
    if (hdropPaths && hdropPaths.length > 0) {
      return hdropPaths;
    }

    // Fast check 3: availableFormats
    const formats = clipboard.availableFormats();
    const hasFileFormats = formats.some((f) => {
      const lower = f.toLowerCase();
      return lower.includes("hdrop") || lower.includes("filename") || lower === "text/uri-list";
    });

    if (!hasFileName && !hasFileFormats) {
      // Fast path: No file formats in clipboard at all — return immediately (0ms).
      // Prevents running helper or PowerShell when user pastes plain text or empty clipboard.
      return [];
    }

    // If files are present, call our instant 4KB C# helper (40-70ms) to get ALL files if multiple were copied
    const helperPaths = await getWindowsClipboardFilePathsHelper();
    if (helperPaths && helperPaths.length > 0) {
      return helperPaths;
    }

    // If helper didn't return but we had singleFile from FileNameW:
    if (singleFile) {
      return [singleFile];
    }
  } catch (_) {}

  // Last resort fallback: PowerShell if helper not available and native format didn't return
  return getWindowsClipboardFilePathsPS();
}

function getWindowsClipboardFilePathsPS() {
  return new Promise((resolve) => {
    if (process.platform !== "win32") {
      resolve([]);
      return;
    }
    const psCommand = [
      "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8;",
      "Add-Type -AssemblyName System.Windows.Forms;",
      "if ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) {",
      "  $files = [System.Windows.Forms.Clipboard]::GetFileDropList();",
      "  @($files) | ConvertTo-Json -Compress",
      "} else {",
      "  '[]'",
      "}"
    ].join(" ");

    execFile(
      "powershell.exe",
      ["-NoProfile", "-NonInteractive", "-STA", "-Command", psCommand],
      { windowsHide: true, timeout: 4000, maxBuffer: 4 * 1024 * 1024 },
      (err, stdout) => {
        if (err) {
          resolve([]);
          return;
        }
        const raw = String(stdout || "").trim();
        if (!raw || raw === "null") {
          resolve([]);
          return;
        }
        try {
          const parsed = JSON.parse(raw);
          if (Array.isArray(parsed)) {
            resolve(parsed.map((p) => String(p || "").trim()).filter(Boolean));
          } else if (typeof parsed === "string" && parsed.trim()) {
            resolve([parsed.trim()]);
          } else {
            resolve([]);
          }
        } catch (_) {
          resolve([]);
        }
      },
    );
  });
}

ipcMain.handle("clipboard:read-files", async () => {
  try {
    const { clipboard } = require("electron");
    const files = [];

    // 1. Check for copied files from Windows Explorer (CF_HDROP / FileDropList)
    const droppedPaths = await getWindowsClipboardFilePaths();
    if (droppedPaths.length > 0) {
      for (const filePath of droppedPaths) {
        try {
          const stat = await fs.promises.stat(filePath).catch(() => null);
          if (!stat || !stat.isFile()) continue;
          const fileName = path.basename(filePath);
          const ext = path.extname(fileName).toLowerCase();
          const isImage = STORAGE_IMAGE_EXTS.has(ext);

          // PERFORMANCE FIX:
          // Do NOT read gigantic Base64 strings for large files or documents!
          // Only read Base64 for small images (<= 4MB) for instant thumbnail rendering.
          // For all documents, archives, videos, or images > 4MB:
          // Returning base64: "" completely eliminates Dart/V8 UI thread freezing.
          let base64 = "";
          if (isImage && stat.size <= 4 * 1024 * 1024) {
            const buffer = await fs.promises.readFile(filePath);
            base64 = buffer.toString("base64");
          }

          files.push({
            name: fileName,
            path: filePath,
            size: stat.size,
            base64,
            isImage,
          });
        } catch (fileErr) {
          console.warn("[electron] clipboard file read error:", fileErr);
        }
      }
      if (files.length > 0) {
        return { success: true, hasFiles: true, files };
      }
    }

    // 2. Check for copied bitmap/screenshot image in clipboard
    const clipImage = clipboard.readImage();
    if (clipImage && !clipImage.isEmpty()) {
      const pngBuffer = clipImage.toPNG();
      if (pngBuffer && pngBuffer.length > 0) {
        const fileName = `clipboard_${Date.now()}.png`;
        files.push({
          name: fileName,
          path: fileName,
          size: pngBuffer.length,
          base64: pngBuffer.toString("base64"),
          isImage: true,
        });
        return { success: true, hasFiles: true, files };
      }
    }
    return { success: true, hasFiles: false, files: [] };
  } catch (error) {
    console.error("[electron] clipboard:read-files error", error);
    return {
      success: false,
      hasFiles: false,
      files: [],
      error: String(error.message || error),
    };
  }
});

ipcMain.handle("window:list-open-windows", async () => {
  try {
    if (process.platform !== "win32") {
      return { success: true, windows: [] };
    }
    const windows = await listOpenWindowsPS();
    return { success: true, windows };
  } catch (error) {
    console.error("[electron] window:list-open-windows error", error);
    return { success: false, windows: [], error: String(error.message || error) };
  }
});

ipcMain.handle("window:capture-window", async (_event, payload = {}) => {
  try {
    if (process.platform !== "win32") {
      return { success: false, error: "Only supported on Windows." };
    }
    const windowId = Number(payload.windowId || 0);
    if (!windowId) {
      return { success: false, error: "Invalid windowId." };
    }
    // Generate temp path in main process — Flutter Web cannot access filesystem
    const tmpPath = path.join(
      app.getPath("temp"),
      `capture_win_${windowId}_${Date.now()}.png`,
    );
    const captured = await captureWindowPS(windowId, tmpPath);
    if (!captured) {
      return { success: false, error: "Capture returned false." };
    }
    const base64 = fs.readFileSync(tmpPath).toString("base64");
    try { fs.unlinkSync(tmpPath); } catch (_) {}
    return { success: true, base64, mimeType: "image/png" };
  } catch (error) {
    console.error("[electron] window:capture-window error", error);
    return { success: false, error: String(error.message || error) };
  }
});

ipcMain.handle("window:capture-screen", async (_event, _payload) => {
  try {
    if (process.platform !== "win32") {
      return { success: false, error: "Only supported on Windows." };
    }
    // Generate temp path in main process — Flutter Web cannot access filesystem
    const tmpPath = path.join(
      app.getPath("temp"),
      `capture_screen_${Date.now()}.png`,
    );
    const captured = await captureScreenPS(tmpPath);
    if (!captured) {
      return { success: false, error: "Screen capture returned false." };
    }
    const base64 = fs.readFileSync(tmpPath).toString("base64");
    try { fs.unlinkSync(tmpPath); } catch (_) {}
    return { success: true, base64, mimeType: "image/png" };
  } catch (error) {
    console.error("[electron] window:capture-screen error", error);
    return { success: false, error: String(error.message || error) };
  }
});

ipcMain.handle("shell:open-rdp", async (_event, payload = {}) => {
  try {
    const ip = String(payload.ip || "").trim();
    if (!ip) {
      return { success: false, error: "No IP provided." };
    }
    const { exec } = require("child_process");
    exec(`mstsc.exe /v:${ip}`, (err) => {
      if (err) console.warn("[electron] mstsc.exe error", err.message);
    });
    return { success: true };
  } catch (error) {
    console.error("[electron] shell:open-rdp error", error);
    return { success: false, error: String(error.message || error) };
  }
});

ipcMain.handle("shell:open-ping", async (_event, payload = {}) => {
  try {
    const ip = String(payload.ip || "").trim();
    if (!ip) {
      return { success: false, error: "No IP provided." };
    }
    const { exec } = require("child_process");
    exec(`start cmd.exe /k ping ${ip}`, (err) => {
      if (err) console.warn("[electron] ping error", err.message);
    });
    return { success: true };
  } catch (error) {
    console.error("[electron] shell:open-ping error", error);
    return { success: false, error: String(error.message || error) };
  }
});

ipcMain.handle("net:probe-peer-status", async (_event, payload = {}) => {
  const targetIp = normalizeLanIp(payload.ip || payload.targetIp);
  if (!targetIp) {
    return {
      success: false,
      ip: "",
      message: "عنوان IP غير صالح أو غير محدد.",
    };
  }

  const { exec } = require("child_process");
  const net = require("net");

  // 1. ICMP Ping check (Windows ping -n 1 -w 1200)
  const pingPromise = new Promise((resolve) => {
    exec(`ping -n 1 -w 1200 ${targetIp}`, (err, stdout) => {
      if (err) {
        resolve({ reachable: false, latency: null });
        return;
      }
      const text = String(stdout || "");
      const match = text.match(/time[=<](\d+ms)/i) || text.match(/الوقت[=<](\d+ms)/i);
      resolve({ reachable: true, latency: match ? match[1] : "<10ms" });
    });
  });

  // 2. TCP RDP port check (3389)
  const rdpPromise = new Promise((resolve) => {
    const socket = new net.Socket();
    socket.setTimeout(1200);
    socket.on("connect", () => {
      socket.destroy();
      resolve(true);
    });
    socket.on("timeout", () => {
      socket.destroy();
      resolve(false);
    });
    socket.on("error", () => {
      socket.destroy();
      resolve(false);
    });
    socket.connect(3389, targetIp);
  });

  // 3. LAN App check (iSmart Messenger HTTP port)
  const lanAppPromise = probeLanPeerAtIp(targetIp, 1200).catch(() => ({ success: false }));

  const [pingRes, rdpOpen, lanRes] = await Promise.all([pingPromise, rdpPromise, lanAppPromise]);

  const isReachable = pingRes.reachable || rdpOpen || lanRes.success === true;
  let summary = "";
  if (isReachable) {
    const parts = [];
    if (pingRes.reachable) {
      parts.push(`Ping: متاح (${pingRes.latency || '<10ms'})`);
    }
    if (rdpOpen) {
      parts.push("Remote Desktop: جاهز (بورت 3389 مفتوح)");
    } else {
      parts.push("Remote Desktop: بورت 3389 مغلق");
    }
    if (lanRes.success === true) {
      parts.push("تطبيق المراسلة: متصل ونشط");
    }
    summary = parts.join(" | ");
  } else {
    summary = "الجهاز لا يستجيب في الشبكة المحلية (Ping أو RDP غير متاح). تأكد من تشغيل الجهاز واتصاله بنفس الشبكة.";
  }

  return {
    success: isReachable,
    ip: targetIp,
    pingReachable: pingRes.reachable,
    latency: pingRes.latency,
    rdpAvailable: rdpOpen,
    lanAppActive: lanRes.success === true,
    message: summary,
  };
});

ipcMain.handle("http:fetch-base64", async (_event, payload = {}) => {
  const url = String(payload.url || "").trim();
  const rawHeaders = payload.headers || {};
  const headers = {};
  if (rawHeaders && typeof rawHeaders === "object") {
    for (const [key, value] of Object.entries(rawHeaders)) {
      if (value != null && String(value).trim()) {
        headers[key] = String(value);
      }
    }
  }
  try {
    const result = await fetchUrlBuffer(url, headers);
    return {
      success: true,
      base64: result.buffer.toString("base64"),
      contentType: result.contentType,
    };
  } catch (error) {
    console.warn(`Electron media fetch failed for ${url}: ${error.message}`);
    return {
      success: false,
      message: error.message,
      statusCode: error.statusCode || null,
    };
  }
});

ipcMain.handle("files:save-base64", async (event, payload = {}) => {
  const explicitPath = String(payload.filePath || "").trim();
  const requestedDirectory = String(payload.directoryPath || "").trim();
  let outputPath;

  if (explicitPath) {
    await fs.promises.mkdir(path.dirname(explicitPath), { recursive: true });
    outputPath = explicitPath;
  } else if (requestedDirectory) {
    await fs.promises.mkdir(requestedDirectory, { recursive: true });
    outputPath = uniqueOutputPath(
      requestedDirectory,
      payload.fileName || "file",
    );
  } else {
    const browserWindow = BrowserWindow.fromWebContents(event.sender) || mainWindow;
    if (browserWindow && !browserWindow.isDestroyed()) {
      if (browserWindow.isMinimized()) {
        browserWindow.restore();
      }
      browserWindow.show();
      browserWindow.focus();
      browserWindow.setAlwaysOnTop(true);
      browserWindow.setAlwaysOnTop(false);
    }
    const defaultPath = path.join(app.getPath("downloads"), payload.fileName || "file");
    
    let result;
    try {
      result = await dialog.showSaveDialog(browserWindow, {
        title: "حفظ الملف",
        defaultPath: defaultPath,
      });
    } catch (dialogErr) {
      return { success: false, message: `Save dialog error: ${dialogErr.message}` };
    }

    if (!result || result.canceled || !result.filePath) {
      return { success: false, message: "تم إلغاء الحفظ بواسطة المستخدم." };
    }
    outputPath = result.filePath;
  }

  const buffer = Buffer.from(String(payload.base64 || ""), "base64");
  if (buffer.length > MAX_ELECTRON_FETCH_BYTES) {
    return { success: false, message: "File is too large to save from memory." };
  }
  await fs.promises.writeFile(outputPath, buffer);
  return { success: true, savedPath: outputPath };
});

ipcMain.handle("files:exists", async (_event, payload = {}) => {
  const filePath = String(payload.path || "").trim();
  const exists = !!filePath && (await fs.promises.access(filePath).then(() => true).catch(() => false));
  return { success: true, exists };
});

ipcMain.handle("files:open-local", async (_event, payload = {}) => {
  const filePath = String(payload.path || "").trim();
  if (!filePath || !fs.existsSync(filePath)) {
    return { success: false, message: "File not found." };
  }
  const errorMessage = await shell.openPath(filePath);
  return {
    success: !errorMessage,
    message: errorMessage || "Opened.",
    path: filePath,
  };
});

ipcMain.handle("files:get-storage-root", async () => ({
  success: true,
  path: localStorageRootPath(),
}));

ipcMain.handle("files:initialize-storage", async (_event, payload = {}) => {
  ensureLocalStorageTree(payload.directoryPath);
  return { success: true, path: localStorageRootPath(payload.directoryPath) };
});

ipcMain.handle("files:append-error-log", async (_event, payload = {}) => {
  const root = localStorageRootPath(payload.directoryPath);
  fs.mkdirSync(root, { recursive: true });
  const entry = String(payload.entry || "");
  if (!entry) {
    return { success: false, message: "Log entry is empty." };
  }
  const logPath = path.join(root, "log error.txt");
  fs.appendFileSync(logPath, entry, "utf8");
  return { success: true, path: logPath };
});

ipcMain.handle("files:archive-chat-attachment", async (_event, payload = {}) => {
  const outputPath = chatArchivePath(
    payload.messageId,
    payload.sha256Hex,
    payload.fileName || "attachment",
    payload.directoryPath,
  );
  try {
    const dir = path.dirname(outputPath);
    if (!fs.existsSync(dir)) {
      await fs.promises.mkdir(dir, { recursive: true });
    }
    const exists = await fs.promises.access(outputPath).then(() => true).catch(() => false);
    if (!exists) {
      if (payload.sourcePath && fs.existsSync(payload.sourcePath)) {
        await fs.promises.copyFile(payload.sourcePath, outputPath);
      } else if (payload.base64) {
        await fs.promises.writeFile(outputPath, Buffer.from(String(payload.base64 || ""), "base64"));
      }
    }
    return { success: true, path: outputPath };
  } catch (err) {
    return { success: false, error: err.message || String(err) };
  }
});

const activeUploadRequests = new Map();

ipcMain.handle("chat:cancel-upload", async (_event, transferId) => {
  if (!transferId) return { success: false, message: "Missing transferId" };
  const key = String(transferId).trim();
  const active = activeUploadRequests.get(key);
  if (active) {
    try {
      active.aborted = true;
      if (active.fileStream) {
        try { active.fileStream.destroy(); } catch (_) {}
      }
      if (active.req) {
        try { active.req.destroy(new Error("Upload cancelled by user.")); } catch (_) {}
      }
    } catch (_) {}
    activeUploadRequests.delete(key);
    return { success: true, canceled: true };
  }
  return { success: false, message: "Upload not found or already finished." };
});

ipcMain.handle("chat:upload-attachment", async (_event, payload = {}) => {
  const {
    url,
    filePath,
    token,
    conversationId,
    content,
    replyToMessageId,
    fileName,
    clientMessageId,
    metadata,
    transferId,
  } = payload;

  if (!url || !filePath || !fs.existsSync(filePath)) {
    return { success: false, error: "Missing upload parameters or file does not exist." };
  }

  const uploadKey = transferId ? String(transferId).trim() : null;
  const activeRecord = {
    req: null,
    fileStream: null,
    aborted: false,
  };
  if (uploadKey) {
    activeUploadRequests.set(uploadKey, activeRecord);
  }

  const maxAttempts = 3;
  let lastError = "Upload failed.";

  try {
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      if (activeRecord.aborted) {
        return { success: false, error: "تم إلغاء الرفع من قبل المستخدم.", isCancelled: true };
      }
    try {
      const stat = await fs.promises.stat(filePath);
      const boundary = "----iSmartUploadBoundary" + Date.now().toString(16) + Math.random().toString(16);
      const resolvedFileName = fileName || path.basename(filePath);

      // Build multipart preamble
      const fields = {
        conversationId: String(conversationId || ""),
      };
      if (content) fields.content = String(content);
      if (replyToMessageId) fields.replyToMessageId = String(replyToMessageId);
      if (fileName) fields.fileName = String(fileName);

      let parsedMeta = null;
      if (metadata) {
        if (typeof metadata === "string") {
          try { parsedMeta = JSON.parse(metadata); } catch (_) {}
          fields.metadata = metadata;
        } else {
          parsedMeta = metadata;
          fields.metadata = JSON.stringify(metadata);
        }
      }

      const cId = clientMessageId || parsedMeta?.clientMessageId;
      if (cId) fields.clientMessageId = String(cId);

      let head = "";
      for (const [k, v] of Object.entries(fields)) {
        head += `--${boundary}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`;
      }
      head += `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${resolvedFileName}"\r\nContent-Type: application/octet-stream\r\n\r\n`;

      const headBuf = Buffer.from(head, "utf8");
      const tailBuf = Buffer.from(`\r\n--${boundary}--\r\n`, "utf8");
      const totalLength = headBuf.length + stat.size + tailBuf.length;

      const parsedUrl = new URL(url);
      const protocol = parsedUrl.protocol === "https:" ? https : http;

      const result = await new Promise((resolve) => {
        let isSettled = false;
        const safeResolve = (val) => {
          if (!isSettled) {
            isSettled = true;
            resolve(val);
          }
        };

        const req = protocol.request(
          parsedUrl,
          {
            method: "POST",
            headers: {
              "Content-Type": `multipart/form-data; boundary=${boundary}`,
              "Content-Length": totalLength,
              ...(token ? { Authorization: `Bearer ${token}` } : {}),
            },
          },
          (res) => {
            let responseBody = "";
            res.on("data", (chunk) => {
              responseBody += chunk;
            });
            res.on("end", () => {
              const statusCode = res.statusCode || 0;
              if (statusCode >= 200 && statusCode < 300) {
                let parsedData = null;
                try {
                  parsedData = JSON.parse(responseBody);
                } catch (_) {}
                safeResolve({
                  success: true,
                  statusCode,
                  responseJson: responseBody,
                  data: parsedData,
                });
              } else {
                try {
                  const errJson = JSON.parse(responseBody);
                  safeResolve({
                    success: false,
                    statusCode,
                    error: errJson.message || `Upload failed with status ${statusCode}`,
                  });
                } catch (_) {
                  safeResolve({
                    success: false,
                    statusCode,
                    error: responseBody || `Upload failed with status ${statusCode}`,
                  });
                }
              }
            });
          }
        );

        req.on("socket", (socket) => {
          socket.setKeepAlive(true, 5000);
          socket.setNoDelay(true);
          socket.setTimeout(600000);
          socket.on("timeout", () => {
            console.warn("[Upload] Socket idle timeout reached");
          });
        });

        req.on("error", (err) => {
          if (activeRecord.aborted) {
            safeResolve({ success: false, error: "تم إلغاء الرفع من قبل المستخدم.", isCancelled: true });
          } else {
            safeResolve({ success: false, error: err.message || String(err), isNetworkError: true });
          }
        });

        activeRecord.req = req;

        // Write preamble
        req.write(headBuf);

        // Stream file with backpressure handling (crucial for slow branch VPN networks)
        const fileStream = fs.createReadStream(filePath, { highWaterMark: 64 * 1024 });
        activeRecord.fileStream = fileStream;
        let sentBytes = headBuf.length;
        let lastUploadProgressAt = 0;

        fileStream.on("data", (chunk) => {
          sentBytes += chunk.length;
          const ok = req.write(chunk);
          if (!ok) {
            fileStream.pause();
          }
          const now = Date.now();
          if (
            mainWindow &&
            !mainWindow.isDestroyed() &&
            transferId &&
            (sentBytes >= totalLength || now - lastUploadProgressAt >= 150)
          ) {
            lastUploadProgressAt = now;
            mainWindow.webContents.send("upload-progress", {
              transferId,
              sent: sentBytes,
              total: totalLength,
            });
          }
        });

        req.on("drain", () => {
          fileStream.resume();
        });

        fileStream.on("end", () => {
          if (mainWindow && !mainWindow.isDestroyed() && transferId) {
            mainWindow.webContents.send("upload-progress", {
              transferId,
              sent: totalLength,
              total: totalLength,
            });
          }
          req.write(tailBuf);
          req.end();
        });

        fileStream.on("error", (err) => {
          req.destroy();
          safeResolve({ success: false, error: err.message || String(err) });
        });
      });

      if (result.success) {
        return result;
      }

      lastError = result.error || "Upload failed.";
      // Don't retry if client error (4xx) like file too large or unauthorized
      if (result.statusCode && result.statusCode >= 400 && result.statusCode < 500) {
        return result;
      }

      if (attempt < maxAttempts) {
        console.warn(`[Upload] Attempt ${attempt} failed: ${lastError}. Retrying in ${attempt * 1.5}s...`);
        await sleep(attempt * 1500);
      }
    } catch (err) {
      lastError = err.message || String(err);
      if (attempt < maxAttempts && !activeRecord.aborted) {
        await sleep(attempt * 1500);
      }
    }
  }
} finally {
    if (uploadKey) {
      activeUploadRequests.delete(uploadKey);
    }
  }

  if (activeRecord.aborted) {
    return { success: false, error: "تم إلغاء الرفع من قبل المستخدم.", isCancelled: true };
  }

  return { success: false, error: lastError };
});

const activeDownloadRequests = new Map();

ipcMain.handle("files:download-chat-attachment", async (_event, payload = {}) => {
  const { url, destinationPath, token, transferId } = payload;
  if (!url || !destinationPath) {
    return { success: false, error: "Missing url or destinationPath" };
  }
  try {
    const dir = path.dirname(destinationPath);
    if (!fs.existsSync(dir)) {
      await fs.promises.mkdir(dir, { recursive: true });
    }
    let lastDownloadProgressAt = 0;
    await downloadFile(url, destinationPath, token, (received, total) => {
      const now = Date.now();
      if (
        mainWindow &&
        !mainWindow.isDestroyed() &&
        transferId &&
        ((total > 0 && received >= total) || now - lastDownloadProgressAt >= 150)
      ) {
        lastDownloadProgressAt = now;
        mainWindow.webContents.send("download-progress", {
          transferId,
          received,
          total,
        });
      }
    }, transferId);
    return { success: true, path: destinationPath };
  } catch (err) {
    return { success: false, error: String(err && err.message ? err.message : err) };
  }
});

ipcMain.handle("files:cancel-download", async (_event, transferId) => {
  if (!transferId) return { success: false, message: "Missing transferId" };
  const key = String(transferId).trim();
  const active = activeDownloadRequests.get(key);
  if (active) {
    try {
      if (active.request) active.request.destroy();
    } catch (_) {}
    try {
      if (active.fileStream) active.fileStream.close();
    } catch (_) {}
    try {
      if (active.destinationPath && fs.existsSync(active.destinationPath)) {
        fs.unlinkSync(active.destinationPath);
      }
    } catch (_) {}
    activeDownloadRequests.delete(key);
    return { success: true, canceled: true };
  }
  return { success: false, message: "Download not found or already finished." };
});

ipcMain.handle("files:copy-file", async (_event, payload = {}) => {
  const { sourcePath, destinationPath } = payload || {};
  if (!sourcePath || !destinationPath || !fs.existsSync(sourcePath)) {
    return { success: false, message: "Source file not found" };
  }
  try {
    const dir = path.dirname(destinationPath);
    if (!fs.existsSync(dir)) {
      await fs.promises.mkdir(dir, { recursive: true });
    }
    await fs.promises.copyFile(sourcePath, destinationPath);
    return { success: true, path: destinationPath };
  } catch (err) {
    return { success: false, error: String(err && err.message ? err.message : err) };
  }
});

ipcMain.handle("files:calculate-sha256", async (_event, payload = {}) => {
  const filePath = payload.filePath;
  if (!filePath || !fs.existsSync(filePath)) {
    return { success: false, sha256: "" };
  }
  return new Promise((resolve) => {
    const hash = crypto.createHash("sha256");
    const stream = fs.createReadStream(filePath);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolve({ success: true, sha256: hash.digest("hex") }));
    stream.on("error", (err) => resolve({ success: false, error: err.message, sha256: "" }));
  });
});

async function scanDirectoryStorage(dirPath) {
  let appCache = 0;
  let media = 0;
  let audio = 0;
  let docs = 0;
  let scannedCount = 0;

  const rootExists = await fs.promises
    .access(dirPath)
    .then(() => true)
    .catch(() => false);
  if (!rootExists) {
    return { appCache, media, audio, docs };
  }

  async function walk(current) {
    let entries;
    try {
      entries = await fs.promises.readdir(current, { withFileTypes: true });
    } catch (_) {
      return;
    }
    for (const entry of entries) {
      scannedCount += 1;
      if (scannedCount % 64 === 0) {
        await new Promise((r) => setImmediate(r));
      }
      const full = path.join(current, entry.name);
      try {
        if (entry.isDirectory()) {
          await walk(full);
        } else if (entry.isFile()) {
          const stat = await fs.promises.stat(full);
          const size = stat.size;
          const ext = path.extname(entry.name).toLowerCase();
          if (STORAGE_IMAGE_EXTS.has(ext)) {
            media += size;
          } else if (STORAGE_AUDIO_EXTS.has(ext)) {
            audio += size;
          } else if (STORAGE_DOC_EXTS.has(ext)) {
            docs += size;
          } else {
            appCache += size;
          }
        }
      } catch (_) {}
    }
  }

  await walk(dirPath);
  return { appCache, media, audio, docs };
}

ipcMain.handle("storage:get-breakdown", async (_event, payload = {}) => {
  try {
    const cacheDir = localStorageChildPath(path.join("Chat", "cache"), payload.directoryPath);
    const tempDir = path.join(app.getPath("temp"), APP_NAME);

    const [s1, s2] = await Promise.all([
      scanDirectoryStorage(cacheDir),
      scanDirectoryStorage(tempDir),
    ]);

    const appCacheBytes = s1.appCache + s2.appCache;
    const mediaBytes = s1.media + s2.media;
    const audioBytes = s1.audio + s2.audio;
    const documentsBytes = s1.docs + s2.docs;

    return {
      success: true,
      appCacheBytes,
      mediaBytes,
      audioBytes,
      documentsBytes,
      totalBytes: appCacheBytes + mediaBytes + audioBytes + documentsBytes,
    };
  } catch (err) {
    console.error("[electron] storage:get-breakdown error", err);
    return {
      success: false,
      appCacheBytes: 0,
      mediaBytes: 0,
      audioBytes: 0,
      documentsBytes: 0,
      totalBytes: 0,
    };
  }
});

ipcMain.handle("storage:clear-cache", async (_event, payload = {}) => {
  try {
    const category = String(payload.category || "all").toLowerCase();
    const cacheDir = localStorageChildPath(path.join("Chat", "cache"), payload.directoryPath);
    const tempDir = path.join(app.getPath("temp"), APP_NAME);

    async function cleanDir(dirPath) {
      const exists = await fs.promises
        .access(dirPath)
        .then(() => true)
        .catch(() => false);
      if (!exists) return;
      let processedCount = 0;

      async function walkDelete(current) {
        let entries;
        try {
          entries = await fs.promises.readdir(current, { withFileTypes: true });
        } catch (_) {
          return;
        }
        for (const entry of entries) {
          processedCount += 1;
          if (processedCount % 64 === 0) {
            await new Promise((r) => setImmediate(r));
          }
          const full = path.join(current, entry.name);
          try {
            if (entry.isDirectory()) {
              await walkDelete(full);
              try {
                await fs.promises.rmdir(full);
              } catch (_) {}
            } else if (entry.isFile()) {
              const ext = path.extname(entry.name).toLowerCase();
              let del = false;
              if (category === "all") del = true;
              else if (category === "appcache" && !STORAGE_IMAGE_EXTS.has(ext) && !STORAGE_AUDIO_EXTS.has(ext) && !STORAGE_DOC_EXTS.has(ext)) del = true;
              else if (category === "media" && STORAGE_IMAGE_EXTS.has(ext)) del = true;
              else if (category === "audio" && STORAGE_AUDIO_EXTS.has(ext)) del = true;
              else if (category === "documents" && STORAGE_DOC_EXTS.has(ext)) del = true;
              if (del) {
                await fs.promises.unlink(full);
              }
            }
          } catch (_) {}
        }
      }
      await walkDelete(dirPath);
    }

    await cleanDir(cacheDir);
    await cleanDir(tempDir);
    _ensuredStorageDirs.clear();

    if (category === "all" || category === "appcache") {
      try {
        const { session } = require("electron");
        if (session && session.defaultSession) {
          await session.defaultSession.clearCache();
        }
      } catch (_) {}
    }

    return { success: true };
  } catch (err) {
    console.error("[electron] storage:clear-cache error", err);
    return { success: false, error: String(err.message || err) };
  }
});

ipcMain.handle("files:get-chat-attachment-path", async (_event, payload = {}) => {
  const filePath = chatAttachmentCachePath(
    payload.messageId,
    payload.fileName || "attachment",
    payload.directoryPath,
  );
  const exists = fs.existsSync(filePath);
  return { success: true, exists: exists, path: exists ? filePath : null };
});

ipcMain.handle("files:cache-chat-attachment", async (_event, payload = {}) => {
  const outputPath = chatAttachmentCachePath(
    payload.messageId,
    payload.fileName || "attachment",
    payload.directoryPath,
  );
  const exists = await fs.promises.access(outputPath).then(() => true).catch(() => false);
  if (!exists) {
    await fs.promises.writeFile(outputPath, Buffer.from(String(payload.base64 || ""), "base64"));
  }
  return { success: true, path: outputPath };
});

ipcMain.handle("files:read-chat-attachment-cache", async (_event, payload = {}) => {
  const filePath = chatAttachmentCachePath(
    payload.messageId,
    payload.fileName || "attachment",
    payload.directoryPath,
  );
  const exists = await fs.promises.access(filePath).then(() => true).catch(() => false);
  if (!exists) {
    return { success: false, message: "Cached attachment not found." };
  }
  const buffer = await fs.promises.readFile(filePath);
  return {
    success: true,
    fileName: path.basename(filePath),
    base64: buffer.toString("base64"),
  };
});

ipcMain.handle("files:read-chat-archive", async (_event, payload = {}) => {
  const directory = localStorageChildPath(path.join("Chat", "sent"), payload.directoryPath);
  const safeMessageId = String(payload.messageId || "").replace(/[^\w.-]+/g, "_").toLowerCase();
  const safeHash = String(payload.sha256Hex || "").toLowerCase().replace(/[^a-f0-9]/g, "");
  if (!safeMessageId || !safeHash) {
    return { success: false, message: "Archive not found." };
  }
  const entries = await fs.promises.readdir(directory).catch(() => []);
  for (const name of entries) {
    const lower = name.toLowerCase();
    if (lower.startsWith(`${safeMessageId}_`) && lower.includes(safeHash)) {
      const filePath = path.join(directory, name);
      const buffer = await fs.promises.readFile(filePath);
      return {
        success: true,
        fileName: name,
        base64: buffer.toString("base64"),
      };
    }
  }
  return { success: false, message: "Archive not found." };
});

function downloadFileAndValidate(url, destinationPath, token) {
  return new Promise((resolve, reject) => {
    const fileStream = fs.createWriteStream(destinationPath);
    let request;

    const startDownload = (targetUrl) => {
      const parsedUrl = new URL(targetUrl);
      const protocol = parsedUrl.protocol === "https:" ? https : http;

      const headers = {
        "Accept": "*/*",
      };
      if (token) {
        headers["Authorization"] = `Bearer ${token}`;
      }

      request = protocol.get(parsedUrl, { headers, timeout: 30000 }, (response) => {
        const statusCode = response.statusCode || 0;

        if ([301, 302, 303, 307, 308].includes(statusCode) && response.headers.location) {
          response.resume();
          fileStream.close();
          try { fs.unlinkSync(destinationPath); } catch (_) {}
          
          const redirectUrl = new URL(response.headers.location, parsedUrl).toString();
          downloadFileAndValidate(redirectUrl, destinationPath, token).then(resolve).catch(reject);
          return;
        }

        if (statusCode !== 200) {
          response.resume();
          fileStream.close();
          try { fs.unlinkSync(destinationPath); } catch (_) {}
          reject(new Error(`Failed to download. Status code: ${statusCode}`));
          return;
        }

        const contentType = response.headers["content-type"] || "";
        if (contentType.includes("application/json") || contentType.includes("text/html")) {
          response.resume();
          fileStream.close();
          try { fs.unlinkSync(destinationPath); } catch (_) {}
          reject(new Error(`Invalid Content-Type: ${contentType}. Expected PDF/binary.`));
          return;
        }

        response.on("data", (chunk) => {
          fileStream.write(chunk);
        });

        response.on("end", () => {
          fileStream.end();
        });

        response.on("error", (err) => {
          fileStream.close();
          try { fs.unlinkSync(destinationPath); } catch (_) {}
          reject(err);
        });
      });

      request.setTimeout(30000, () => {
        request.destroy(new Error("Download request timed out after 30s."));
      });
      request.on("error", (err) => {
        fileStream.close();
        try { fs.unlinkSync(destinationPath); } catch (_) {}
        reject(err);
      });
    };

    fileStream.on("finish", () => {
      resolve();
    });

    fileStream.on("error", (err) => {
      fileStream.close();
      try { fs.unlinkSync(destinationPath); } catch (_) {}
      reject(err);
    });

    startDownload(url);
  });
}

async function printHtmlWithElectron(target, printerName, options = {}) {
  if (target.toLowerCase().endsWith(".pdf") || target.toLowerCase().includes("application/pdf")) {
    throw new Error("PDF files cannot be printed using Electron's Chromium print.");
  }
  return printFile(target, printerName);
}

registerPrintIpcHandlers({
  ipcMain,
  pdfPrintService,
  htmlPrintService: printHtmlWithElectron,
  app,
  downloadFileAndValidate
});

ipcMain.handle("shell:open-url", async (_event, url) => {
  const parsedUrl = (() => {
    try {
      return new URL(String(url || "").trim());
    } catch (_) {
      return null;
    }
  })();
  if (!parsedUrl || !["http:", "https:"].includes(parsedUrl.protocol)) {
    return { success: false, message: "Invalid URL." };
  }
  openInternalBrowserWindow(url);
  return { success: true };
});

ipcMain.handle("dialog:pick-directory", async (_event, payload = {}) => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: String(payload.title || "Select folder"),
    properties: ["openDirectory", "createDirectory"],
    defaultPath: String(payload.defaultPath || "") || undefined,
  });
  if (result.canceled || !result.filePaths.length) {
    return { success: false, canceled: true, path: null };
  }
  return { success: true, canceled: false, path: result.filePaths[0] };
});

ipcMain.handle("dialog:pick-files", async (_event, payload = {}) => {
  const allowMultiple = payload.allowMultiple !== false;
  const isImageOnly = payload.isImageOnly === true;
  const filters = isImageOnly
    ? [{ name: "Images", extensions: ["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg"] }]
    : undefined;

  const result = await dialog.showOpenDialog(mainWindow || undefined, {
    title: String(payload.title || (isImageOnly ? "Select images" : "Select files")),
    properties: allowMultiple ? ["openFile", "multiSelections"] : ["openFile"],
    filters,
  });

  if (result.canceled || !result.filePaths.length) {
    return { success: false, canceled: true, files: [] };
  }

  const files = [];
  for (const fp of result.filePaths) {
    try {
      const stat = await fs.promises.stat(fp);
      files.push({
        path: fp,
        name: require('path').basename(fp),
        size: stat.size,
      });
    } catch (_) {
      files.push({
        path: fp,
        name: require('path').basename(fp),
        size: 0,
      });
    }
  }

  return { success: true, canceled: false, files };
});

ipcMain.handle("dialog:show-save-dialog", async (event, payload = {}) => {
  const browserWindow = BrowserWindow.fromWebContents(event.sender) || mainWindow;
  if (browserWindow && !browserWindow.isDestroyed()) {
    if (browserWindow.isMinimized()) {
      browserWindow.restore();
    }
    browserWindow.show();
    browserWindow.focus();
    browserWindow.setAlwaysOnTop(true);
    browserWindow.setAlwaysOnTop(false);
  }
  const defaultPath = path.join(app.getPath("downloads"), payload.fileName || "file");

  try {
    const result = await dialog.showSaveDialog(browserWindow, {
      title: String(payload.title || "نقل أو حفظ الملف في..."),
      defaultPath: String(payload.defaultPath || defaultPath),
    });

    if (!result || result.canceled || !result.filePath) {
      return { success: false, canceled: true, path: null };
    }
    return { success: true, canceled: false, path: result.filePath };
  } catch (err) {
    return { success: false, canceled: true, path: null, error: err.message };
  }
});

ipcMain.handle("startup:set", async (_event, enabled) => {
  ensureStartup(enabled === true);
  return { success: true, enabled: enabled === true };
});

ipcMain.handle("startup:get", async () => app.getLoginItemSettings());

const crypto = require("crypto");

function calculateFileSha256(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash("sha256");
    const stream = fs.createReadStream(filePath);
    stream.on("data", (data) => hash.update(data));
    stream.on("end", () => resolve(hash.digest("hex")));
    stream.on("error", (err) => reject(err));
  });
}

function downloadFile(url, destinationPath, token, onProgress, transferId, options = {}) {
  return new Promise((resolve, reject) => {
    const downloadKey = transferId ? String(transferId).trim() : null;
    const partPath = destinationPath + ".part";
    const partMetaPath = destinationPath + ".part.meta.json";
    const expectedChecksum = options && options.checksumSha256 ? String(options.checksumSha256).trim().toLowerCase() : "";
    const branchCodeHeader = options && options.branchCode ? String(options.branchCode).trim().toUpperCase() : "";
    const deviceUidHeader = options && options.deviceUid ? String(options.deviceUid).trim() : "";
    let isCancelled = false;
    let isSettled = false;
    let currentRequest = null;
    let currentStream = null;
    let retryTimer = null;
    let attempt = 0;
    let busyWaitCount = 0;
    const maxAttempts = 10;
    const maxBusyWaits = 20;

    const settleResolve = (value) => {
      if (isSettled) return;
      isSettled = true;
      resolve(value);
    };
    const settleReject = (err) => {
      if (isSettled) return;
      isSettled = true;
      reject(err);
    };

    const getUrlKey = (u) => {
      try {
        const p = new URL(u);
        return p.origin + p.pathname;
      } catch (_) {
        return String(u || "");
      }
    };
    const baseUrlKey = getUrlKey(url);

    const readPartMeta = () => {
      try {
        if (fs.existsSync(partMetaPath)) {
          return JSON.parse(fs.readFileSync(partMetaPath, "utf8"));
        }
      } catch (_) {}
      return null;
    };

    const writePartMeta = (meta) => {
      try {
        fs.writeFileSync(partMetaPath, JSON.stringify(meta), "utf8");
      } catch (_) {}
    };

    const clearPartialArtifacts = () => {
      try { if (fs.existsSync(partPath)) fs.unlinkSync(partPath); } catch (_) {}
      try { if (fs.existsSync(partMetaPath)) fs.unlinkSync(partMetaPath); } catch (_) {}
    };

    // Guard against stale or mismatched .part files from a previous version or failed run
    if (fs.existsSync(partPath)) {
      const savedMeta = readPartMeta();
      const urlMatches = savedMeta && savedMeta.urlKey === baseUrlKey;
      const checksumMatches = !expectedChecksum || !savedMeta || !savedMeta.checksumSha256 || savedMeta.checksumSha256.toLowerCase() === expectedChecksum;
      if (!savedMeta || !urlMatches || !checksumMatches) {
        clearPartialArtifacts();
      }
    }

    if (downloadKey) {
      activeDownloadRequests.set(downloadKey, {
        get request() { return currentRequest; },
        get fileStream() { return currentStream; },
        destinationPath,
        partPath,
        cancel: () => {
          isCancelled = true;
          if (retryTimer) {
            clearTimeout(retryTimer);
            retryTimer = null;
          }
          try { if (currentRequest) currentRequest.destroy(); } catch (_) {}
          try { if (currentStream) currentStream.destroy(); } catch (_) {}
          clearPartialArtifacts();
          try { if (fs.existsSync(destinationPath)) fs.unlinkSync(destinationPath); } catch (_) {}
          settleReject(new Error("Download cancelled by user."));
        }
      });
    }

    const runAttempt = (targetUrl) => {
      if (isCancelled) {
        return settleReject(new Error("Download cancelled by user."));
      }

      let attemptSettled = false;
      let responseEndedNormally = false;
      let timeoutTimer = null;

      let existingBytes = 0;
      try {
        if (fs.existsSync(partPath)) {
          existingBytes = fs.statSync(partPath).size;
        }
      } catch (_) {
        existingBytes = 0;
      }

      const savedMeta = readPartMeta();
      const parsedUrl = new URL(targetUrl);
      const protocol = parsedUrl.protocol === "https:" ? https : http;

      const headers = {
        "Accept": "*/*",
        "Cache-Control": "no-cache",
      };
      if (token) {
        headers["Authorization"] = "Bearer " + token;
      }
      if (branchCodeHeader) {
        headers["X-Branch-Code"] = branchCodeHeader;
      }
      if (deviceUidHeader) {
        headers["X-Device-Uid"] = deviceUidHeader;
      }
      if (existingBytes > 0) {
        headers["Range"] = "bytes=" + existingBytes + "-";
        if (savedMeta && savedMeta.etag) {
          headers["If-Range"] = savedMeta.etag;
        }
      }

      const failAttempt = (err, { resetPartial = false } = {}) => {
        if (attemptSettled) return;
        attemptSettled = true;
        if (timeoutTimer) {
          clearTimeout(timeoutTimer);
          timeoutTimer = null;
        }
        const streamToClose = currentStream;
        currentStream = null;
        try { if (currentRequest) currentRequest.destroy(); } catch (_) {}
        currentRequest = null;
        if (streamToClose) {
          try { streamToClose.destroy(); } catch (_) {}
        }
        if (resetPartial) {
          clearPartialArtifacts();
        }
        handleRetryOrReject(err, url);
      };

      const resetInactivityTimer = () => {
        if (timeoutTimer) clearTimeout(timeoutTimer);
        timeoutTimer = setTimeout(() => {
          if (!isCancelled && !attemptSettled) {
            console.warn("[downloadFile] Inactivity timeout (45s no data) on VPN link, retrying...");
            failAttempt(new Error("ETIMEDOUT: Connection inactive on VPN link"));
          }
        }, 45000);
      };

      resetInactivityTimer();

      currentRequest = protocol.get(parsedUrl, { headers, timeout: 30000 }, (response) => {
        if (attemptSettled) {
          response.resume();
          return;
        }

        const statusCode = response.statusCode || 0;

        // Handle redirects (e.g. 301, 302, 303, 307, 308)
        if ([301, 302, 303, 307, 308].includes(statusCode) && response.headers.location) {
          attemptSettled = true;
          if (timeoutTimer) clearTimeout(timeoutTimer);
          response.resume();
          const redirectUrl = new URL(response.headers.location, parsedUrl).toString();
          return runAttempt(redirectUrl);
        }

        // Handle 429 / 503 update download admission queue without burning fatal retries or deleting .part
        if (statusCode === 429 || statusCode === 503) {
          attemptSettled = true;
          if (timeoutTimer) {
            clearTimeout(timeoutTimer);
            timeoutTimer = null;
          }
          response.resume();
          busyWaitCount += 1;
          if (busyWaitCount > maxBusyWaits) {
            attemptSettled = false;
            return failAttempt(
              new Error("Download server busy too long. Status code: " + statusCode),
            );
          }
          const rawRetryAfter = parseInt(String(response.headers["retry-after"] || ""), 10);
          const baseWaitSec =
            Number.isFinite(rawRetryAfter) && rawRetryAfter > 0
              ? Math.min(Math.max(rawRetryAfter, 5), 90)
              : 15;
          const jitterMs = Math.floor(Math.random() * 9000) + 1000;
          const waitMs = baseWaitSec * 1000 + jitterMs;
          console.warn(
            `[downloadFile] Server busy (HTTP ${statusCode}), keeping partial file and retrying in ${waitMs}ms (wait ${busyWaitCount}/${maxBusyWaits})...`,
          );
          if (retryTimer) {
            clearTimeout(retryTimer);
          }
          retryTimer = setTimeout(() => {
            retryTimer = null;
            if (!isCancelled) {
              runAttempt(url);
            }
          }, waitMs);
          return;
        }

        // Handle 416 Range Not Satisfiable (file size changed on server or corrupted .part)
        if (statusCode === 416) {
          attemptSettled = true;
          if (timeoutTimer) clearTimeout(timeoutTimer);
          response.resume();
          clearPartialArtifacts();
          return runAttempt(url);
        }

        const isPartial = statusCode === 206;
        if (statusCode !== 200 && !isPartial) {
          response.resume();
          return failAttempt(new Error("Failed to download. Status code: " + statusCode));
        }

        let totalBytes = 0;
        let receivedBytes = 0;

        if (isPartial) {
          const contentRange = response.headers["content-range"] || "";
          const rangeMatch = contentRange.match(/^bytes\s+(\d+)-(\d+)\/(\d+|\*)$/i);
          if (!rangeMatch) {
            response.resume();
            return failAttempt(new Error("Invalid Content-Range header on 206 response"), { resetPartial: true });
          }
          const rangeStart = parseInt(rangeMatch[1], 10);
          if (rangeStart !== existingBytes) {
            response.resume();
            return failAttempt(
              new Error("Range offset mismatch: requested " + existingBytes + ", server sent " + rangeStart),
              { resetPartial: true }
            );
          }
          if (rangeMatch[3] !== "*") {
            totalBytes = parseInt(rangeMatch[3], 10);
          } else if (response.headers["content-length"]) {
            totalBytes = existingBytes + parseInt(response.headers["content-length"], 10);
          }
          receivedBytes = existingBytes;
        } else {
          totalBytes = parseInt(response.headers["content-length"] || response.headers["x-file-size"] || "0", 10);
          receivedBytes = 0;
        }

        if (!totalBytes && response.headers["x-file-size"]) {
          totalBytes = parseInt(response.headers["x-file-size"], 10) || 0;
        }

        const serverChecksum = response.headers["x-checksum-sha256"]
          ? String(response.headers["x-checksum-sha256"]).trim().toLowerCase()
          : null;
        if (expectedChecksum && serverChecksum && serverChecksum !== expectedChecksum) {
          response.resume();
          return failAttempt(new Error("Server checksum header mismatch"), { resetPartial: true });
        }

        writePartMeta({
          urlKey: baseUrlKey,
          etag: response.headers["etag"] || null,
          totalBytes: totalBytes || 0,
          checksumSha256: expectedChecksum || serverChecksum || null,
        });

        // Write mode: append only when verified 206 matches existingBytes, otherwise overwrite from 0
        const writeMode = isPartial ? "a" : "w";

        try {
          currentStream = fs.createWriteStream(partPath, { flags: writeMode });
        } catch (streamErr) {
          response.resume();
          return failAttempt(streamErr);
        }

        resetInactivityTimer();

        response.on("data", (chunk) => {
          if (isCancelled || attemptSettled) {
            response.resume();
            return;
          }
          receivedBytes += chunk.length;
          if (currentStream) {
            currentStream.write(chunk);
          }
          resetInactivityTimer();
          if (onProgress) {
            onProgress(receivedBytes, totalBytes);
          }
        });

        response.on("end", () => {
          if (timeoutTimer) clearTimeout(timeoutTimer);
          if (isCancelled || attemptSettled) return;
          if (!response.complete) {
            return failAttempt(new Error("HTTP response ended prematurely before EOF"));
          }
          responseEndedNormally = true;
          if (currentStream) {
            currentStream.end();
          }
        });

        response.on("aborted", () => {
          failAttempt(new Error("Download connection aborted by peer/VPN"));
        });

        response.on("close", () => {
          if (!responseEndedNormally && !attemptSettled && !isCancelled) {
            failAttempt(new Error("Download connection closed before EOF"));
          }
        });

        response.on("error", (err) => {
          failAttempt(err);
        });

        currentStream.on("finish", () => {
          if (timeoutTimer) clearTimeout(timeoutTimer);
          if (isCancelled || attemptSettled) return;
          if (!responseEndedNormally) {
            return failAttempt(new Error("Stream finished before response completed"));
          }

          let actualSize = 0;
          try {
            actualSize = fs.existsSync(partPath) ? fs.statSync(partPath).size : 0;
          } catch (_) {
            actualSize = 0;
          }

          if (actualSize <= 0) {
            return failAttempt(new Error("Downloaded file is empty (0 bytes)"), { resetPartial: true });
          }

          if (totalBytes > 0) {
            if (actualSize > totalBytes) {
              return failAttempt(
                new Error("Corrupted download: file size (" + actualSize + ") exceeds expected (" + totalBytes + ")"),
                { resetPartial: true }
              );
            }
            if (actualSize < totalBytes || receivedBytes !== totalBytes) {
              return failAttempt(
                new Error("Incomplete download: received " + actualSize + " of " + totalBytes + " bytes")
              );
            }
          }

          attemptSettled = true;
          currentStream = null;
          currentRequest = null;

          try {
            if (fs.existsSync(destinationPath)) {
              try { fs.unlinkSync(destinationPath); } catch (_) {}
            }
            fs.renameSync(partPath, destinationPath);
            try { if (fs.existsSync(partMetaPath)) fs.unlinkSync(partMetaPath); } catch (_) {}
            if (downloadKey) activeDownloadRequests.delete(downloadKey);
            settleResolve({
              filePath: destinationPath,
              totalBytes: totalBytes || actualSize,
              actualSize,
              checksumHeader: serverChecksum,
            });
          } catch (renameErr) {
            settleReject(renameErr);
          }
        });

        currentStream.on("error", (err) => {
          failAttempt(err);
        });
      });

      currentRequest.setTimeout(30000, () => {
        failAttempt(new Error("Download request socket timed out"));
      });

      currentRequest.on("error", (err) => {
        failAttempt(err);
      });
    };

    const handleRetryOrReject = (err, targetUrl) => {
      if (isCancelled) {
        return settleReject(new Error("Download cancelled by user."));
      }

      attempt++;
      if (attempt < maxAttempts) {
        const delay = Math.min(1000 * Math.pow(1.5, attempt - 1), 10000);
        console.warn("[downloadFile] Download attempt " + attempt + "/" + maxAttempts + " failed (" + err.message + "). Resuming in " + delay + "ms...");
        if (retryTimer) {
          clearTimeout(retryTimer);
        }
        retryTimer = setTimeout(() => {
          retryTimer = null;
          if (!isCancelled) {
            runAttempt(targetUrl);
          }
        }, delay);
      } else {
        console.error("[downloadFile] Download permanently failed after " + maxAttempts + " attempts:", err);
        clearPartialArtifacts();
        if (downloadKey) activeDownloadRequests.delete(downloadKey);
        settleReject(err);
      }
    };

    runAttempt(url);
  });
}

function detectFileType(filePath) {
  try {
    if (!fs.existsSync(filePath)) return "none";
    const stat = fs.statSync(filePath);
    if (stat.size < 4) return "unknown";
    const fd = fs.openSync(filePath, "r");
    const buffer = Buffer.alloc(4);
    fs.readSync(fd, buffer, 0, 4, 0);
    fs.closeSync(fd);
    
    // Check for MZ (0x4D, 0x5A) -> Windows Executable (.exe)
    if (buffer[0] === 0x4d && buffer[1] === 0x5a) {
      return "exe";
    }
    // Check for PK (0x50, 0x4B) -> Zip Archive (.zip)
    if (buffer[0] === 0x50 && buffer[1] === 0x4b) {
      return "zip";
    }
    // Check for MSI compound document (0xD0, 0xCF, 0x11, 0xE0)
    if (buffer[0] === 0xd0 && buffer[1] === 0xcf && buffer[2] === 0x11 && buffer[3] === 0xe0) {
      return "msi";
    }
  } catch (err) {
    console.error("detectFileType error:", err);
  }
  return "unknown";
}

ipcMain.handle("updater:start-update", async (event, payload = {}) => {
  const {
    downloadUrl,
    token,
    checksumSha256,
    fileName,
    silentInstallArgs,
    installerKind,
    branchCode,
    deviceUid,
  } = payload;
  if (!downloadUrl) {
    throw new Error("Missing download URL");
  }

  const tempDir = path.join(app.getPath("temp"), APP_NAME);
  fs.mkdirSync(tempDir, { recursive: true });

  const tempDownloadPath = path.join(tempDir, "update-download.tmp");

  try {
    let lastProgressEventAt = 0;
    let lastProgressValue = -1;
    const sendUpdaterProgress = (payload, { force = false } = {}) => {
      if (!mainWindow || mainWindow.webContents.isDestroyed()) {
        return;
      }
      const progress = Number(payload.progress || 0);
      const now = Date.now();
      if (
        !force &&
        payload.status === "downloading" &&
        progress !== 0 &&
        progress !== 100 &&
        progress === lastProgressValue &&
        now - lastProgressEventAt < 150
      ) {
        return;
      }
      lastProgressValue = progress;
      lastProgressEventAt = now;
      mainWindow.webContents.send("updater-progress", payload);
    };

    // Reuse an already-downloaded and cryptographically verified update package if present
    const reuseCheck = await updaterHelpers.validatePreparedPackage({
      tempDir,
      downloadUrl,
      checksumSha256,
      fileName,
      detectFileType,
      calculateFileSha256,
      requireMatchForReuse: true,
    });
    if (reuseCheck.prepared) {
      try {
        const refreshedMeta = {
          ...(reuseCheck.meta || {}),
          packagePath: reuseCheck.packagePath,
          packageType: reuseCheck.packageType,
          fileName:
            fileName ||
            (reuseCheck.meta && reuseCheck.meta.fileName) ||
            path.basename(reuseCheck.packagePath),
          downloadUrl:
            downloadUrl || (reuseCheck.meta && reuseCheck.meta.downloadUrl) || "",
          checksumSha256:
            reuseCheck.checksumSha256 ||
            (reuseCheck.meta && reuseCheck.meta.checksumSha256) ||
            null,
          expectedSize: reuseCheck.fileSize,
          silentInstallArgs:
            silentInstallArgs ||
            (reuseCheck.meta && reuseCheck.meta.silentInstallArgs) ||
            "",
          installerKind:
            installerKind || (reuseCheck.meta && reuseCheck.meta.installerKind) || "",
          previousVersion: app.getVersion(),
        };
        fs.writeFileSync(
          path.join(tempDir, "update-meta.json"),
          JSON.stringify(refreshedMeta, null, 2),
          "utf8"
        );
        updaterHelpers.clearUpdateResult(tempDir);
      } catch (_) {}

      sendUpdaterProgress({
        status: "downloaded",
        progress: 100,
        message: "حزمة التحديث محملة ومفحوصة مسبقاً وجاهزة للتثبيت.",
      }, { force: true });

      return {
        success: true,
        reused: true,
        filePath: reuseCheck.packagePath,
        packageType: reuseCheck.packageType,
      };
    }

    // Clean up previous mismatched/incomplete update output artifacts (keep matching .part ONLY if verified in downloadFile)
    const cleanups = [
      "update-download.tmp",
      "update-installer.exe",
      "update-installer.msi",
      "update-package.zip",
      "app-update.zip",
      "update-meta.json",
      "update-result.json",
    ];
    for (const c of cleanups) {
      try {
        const p = path.join(tempDir, c);
        if (fs.existsSync(p)) fs.unlinkSync(p);
      } catch (_) {}
    }

    sendUpdaterProgress({
      status: "downloading",
      progress: 0,
      message: "جاري بدء تحميل التحديث...",
    }, { force: true });

    const downloadResult = await downloadFile(
      downloadUrl,
      tempDownloadPath,
      token,
      (received, total) => {
        let progress = 0;
        let message = "";
        if (total > 0) {
          progress = Math.min(95, Math.round((received / total) * 100));
          const receivedMb = (received / (1024 * 1024)).toFixed(1);
          const totalMb = (total / (1024 * 1024)).toFixed(1);
          message = `جاري تحميل التحديث: ${progress}% (${receivedMb} / ${totalMb} MB)`;
        } else {
          const receivedMb = (received / (1024 * 1024)).toFixed(1);
          progress = Math.min(90, Math.round((received / (60 * 1024 * 1024)) * 100));
          message = `جاري تحميل التحديث: ${receivedMb} MB`;
        }
        sendUpdaterProgress({
          status: "downloading",
          progress: progress,
          message: message,
        });
      },
      null,
      { checksumSha256, branchCode, deviceUid }
    );

    const effectiveChecksum =
      (checksumSha256 && checksumSha256.trim()) ||
      (downloadResult && downloadResult.checksumHeader) ||
      "";

    if (effectiveChecksum) {
      sendUpdaterProgress({
        status: "downloading",
        progress: 96,
        message: "جاري التحقق من سلامة وبصمة ملف التحديث...",
      }, { force: true });
      const calculatedHash = await calculateFileSha256(tempDownloadPath);
      if (calculatedHash.toLowerCase() !== effectiveChecksum.trim().toLowerCase()) {
        // Delete corrupted artifact + partials immediately so next run downloads fresh
        try { if (fs.existsSync(tempDownloadPath)) fs.unlinkSync(tempDownloadPath); } catch (_) {}
        try { if (fs.existsSync(tempDownloadPath + ".part")) fs.unlinkSync(tempDownloadPath + ".part"); } catch (_) {}
        try { if (fs.existsSync(tempDownloadPath + ".part.meta.json")) fs.unlinkSync(tempDownloadPath + ".part.meta.json"); } catch (_) {}
        throw new Error(`بصمة ملف التحديث غير مطابقة (الملف تالف أو غير مكتمل)! المتوقع: ${effectiveChecksum.trim().toLowerCase()}، المحسوب: ${calculatedHash.toLowerCase()}`);
      }
    }

    // Inspect file magic bytes to determine real file type and reject non-binary/HTML error responses
    const detectedType = detectFileType(tempDownloadPath);
    const lowerTarget = (fileName || downloadUrl || "").toLowerCase();
    const expectsExe = lowerTarget.endsWith(".exe") || (installerKind || "").toLowerCase() === "exe";
    if (expectsExe && detectedType !== "exe") {
      try { if (fs.existsSync(tempDownloadPath)) fs.unlinkSync(tempDownloadPath); } catch (_) {}
      try { if (fs.existsSync(tempDownloadPath + ".part")) fs.unlinkSync(tempDownloadPath + ".part"); } catch (_) {}
      try { if (fs.existsSync(tempDownloadPath + ".part.meta.json")) fs.unlinkSync(tempDownloadPath + ".part.meta.json"); } catch (_) {}
      throw new Error("الملف المحمل ليس ملف تثبيت Windows صالح (.exe). قد يكون التحميل تالفاً بسبب الشبكة.");
    }

    let finalPackagePath = "";
    if (detectedType === "exe") {
      finalPackagePath = path.join(tempDir, "update-installer.exe");
    } else if (detectedType === "msi") {
      finalPackagePath = path.join(tempDir, "update-installer.msi");
    } else if (detectedType === "zip") {
      finalPackagePath = path.join(tempDir, "update-package.zip");
    } else {
      if (lowerTarget.includes(".msi")) {
        finalPackagePath = path.join(tempDir, "update-installer.msi");
      } else if (lowerTarget.includes(".zip")) {
        finalPackagePath = path.join(tempDir, "update-package.zip");
      } else {
        finalPackagePath = path.join(tempDir, "update-installer.exe");
      }
    }

    if (fs.existsSync(finalPackagePath)) {
      try { fs.unlinkSync(finalPackagePath); } catch (_) {}
    }
    fs.renameSync(tempDownloadPath, finalPackagePath);
    const finalStats = fs.statSync(finalPackagePath);

    // Save update metadata for pre-launch integrity verification in updater:apply-update
    const meta = {
      packagePath: finalPackagePath,
      packageType: detectedType,
      fileName: fileName || path.basename(finalPackagePath),
      downloadUrl: downloadUrl,
      checksumSha256: effectiveChecksum || null,
      expectedSize: finalStats.size,
      silentInstallArgs: silentInstallArgs || "",
      installerKind: installerKind || "",
      previousVersion: app.getVersion(),
      downloadedAt: new Date().toISOString(),
    };
    fs.writeFileSync(path.join(tempDir, "update-meta.json"), JSON.stringify(meta, null, 2), "utf8");
    updaterHelpers.clearUpdateResult(tempDir);

    sendUpdaterProgress({
      status: "downloaded",
      progress: 100,
      message: "تم تحميل التحديث بنجاح والتحقق من سلامته بالكامل.",
    }, { force: true });

    return { success: true, filePath: finalPackagePath, packageType: detectedType };
  } catch (error) {
    console.error("Update download failed:", error);
    try { if (fs.existsSync(tempDownloadPath)) fs.unlinkSync(tempDownloadPath); } catch (_) {}
    if (mainWindow && !mainWindow.webContents.isDestroyed()) {
      mainWindow.webContents.send("updater-progress", {
        status: "failed",
        progress: 100,
        message: `فشل التحديث: ${error.message || error}`,
      });
    }
    return { success: false, error: String(error.message || error) };
  }
});

const updaterHelpers = require("./updater_helpers");

ipcMain.handle("updater:get-prepared-update", async (_event, payload = {}) => {
  const tempDir = path.join(app.getPath("temp"), APP_NAME);
  if (!fs.existsSync(tempDir)) {
    return { prepared: false, reason: "missing", lastInstallResult: null };
  }
  const check = await updaterHelpers.validatePreparedPackage({
    tempDir,
    checksumSha256: payload && payload.checksumSha256 ? String(payload.checksumSha256) : "",
    fileName: payload && payload.fileName ? String(payload.fileName) : "",
    version: payload && (payload.targetVersion || payload.version) ? String(payload.targetVersion || payload.version) : "",
    detectFileType,
    calculateFileSha256,
    requireMatchForReuse: false,
  });
  return {
    prepared: Boolean(check.prepared),
    reason: check.reason || null,
    filePath: check.packagePath || null,
    packageType: check.packageType || null,
    fileSize: check.fileSize || 0,
    checksumSha256: check.checksumSha256 || null,
    version: check.version || null,
    fileName: check.fileName || null,
    silentInstallArgs: check.silentInstallArgs || "",
    lastInstallResult: check.lastInstallResult || null,
  };
});

ipcMain.handle("updater:apply-update", async (event, payload = {}) => {
  const tempDir = path.join(app.getPath("temp"), APP_NAME);
  fs.mkdirSync(tempDir, { recursive: true });
  
  const writeLog = (msg) => {
    try {
      const timestamp = new Date().toISOString().replace('T', ' ').substring(0, 19);
      fs.appendFileSync(path.join(tempDir, "update_log.txt"), `[JS ${timestamp}] ${msg}\n`, "utf8");
    } catch (_) {}
  };

  writeLog("=== Starting JS apply-update handler ===");

  // Read metadata if available
  let meta = updaterHelpers.readUpdateMeta(tempDir) || {};
  const metaPath = path.join(tempDir, "update-meta.json");

  // Merge any runtime payload options
  if (payload && typeof payload === "object") {
    meta = { ...meta, ...payload };
  }

  const check = await updaterHelpers.validatePreparedPackage({
    tempDir,
    checksumSha256: meta.checksumSha256 || "",
    fileName: meta.fileName || "",
    version: meta.targetVersion || meta.version || "",
    detectFileType,
    calculateFileSha256,
    requireMatchForReuse: false,
  });

  if (!check.prepared) {
    if (check.reason === "missing") {
      writeLog("ERROR: update package file does not exist in tempDir!");
      throw new Error("ملف التحديث غير موجود! يرجى تحميله أولاً.");
    }
    writeLog(`FATAL INTEGRITY ERROR (${check.reason}). Removing damaged package so updater can re-download cleanly.`);
    try { if (check.packagePath && fs.existsSync(check.packagePath)) fs.unlinkSync(check.packagePath); } catch (_) {}
    try { if (fs.existsSync(metaPath)) fs.unlinkSync(metaPath); } catch (_) {}
    updaterHelpers.clearUpdateResult(tempDir);
    return {
      success: false,
      error: "ملف التحديث تالف أو غير مكتمل. تم حذفه بأمان لمنع خطأ NSIS، يرجى إعادة المحاولة.",
    };
  }

  const packagePath = check.packagePath;
  const detectedType = check.packageType;
  const isExe = detectedType === "exe" || packagePath.toLowerCase().endsWith(".exe");
  const isMsi = detectedType === "msi" || packagePath.toLowerCase().endsWith(".msi");

  const appDir = path.dirname(process.execPath);
  const exePath = process.execPath;
  const procName = path.basename(exePath, path.extname(exePath));
  const parentPid = process.pid;

  writeLog(`Found update package: ${packagePath} (type: ${detectedType}, isExe: ${isExe}, isMsi: ${isMsi})`);
  writeLog(`appDir: ${appDir}, exePath: ${exePath}, procName: ${procName}, PID: ${parentPid}`);

  const silentArgs = (meta.silentInstallArgs || (payload && payload.silentInstallArgs) || "/S").trim();
  const targetVersion = String(meta.targetVersion || meta.version || "").trim();
  const previousVersion = String(app.getVersion() || meta.previousVersion || "").trim();
  const resultPath = path.join(tempDir, "update-result.json");
  const psScriptPath = path.join(tempDir, "apply_update.ps1");

  try {
    const updatedMeta = {
      ...meta,
      packagePath,
      packageType: detectedType,
      targetVersion: targetVersion || meta.targetVersion || null,
      previousVersion: previousVersion || meta.previousVersion || null,
      lastApplyStartedAt: new Date().toISOString(),
    };
    fs.writeFileSync(metaPath, JSON.stringify(updatedMeta, null, 2), "utf8");
  } catch (_) {}
  updaterHelpers.clearUpdateResult(tempDir);

  const psScriptContent = updaterHelpers.buildApplyUpdatePsScript({
    packageType: isExe ? "exe" : isMsi ? "msi" : "zip",
    packagePath,
    appDir,
    exePath,
    procName,
    parentPid,
    logPath: path.join(tempDir, "update_log.txt"),
    metaPath,
    resultPath,
    silentArgs,
    targetVersion,
    previousVersion,
    tempDir,
  });
  writeLog(`Generated PowerShell updater script (type=${isExe ? "exe" : isMsi ? "msi" : "zip"}, target=${targetVersion || "unknown"}).`);

  writeLog(`Writing psScriptPath: ${psScriptPath}...`);
  fs.writeFileSync(psScriptPath, psScriptContent, "utf8");
  writeLog("psScriptPath written successfully.");

  if (mainWindow && !mainWindow.isDestroyed() && mainWindow.webContents && !mainWindow.webContents.isDestroyed()) {
    try {
      if (typeof mainWindow.webContents.session.flushStorageData === "function") {
        await Promise.race([
          Promise.resolve(mainWindow.webContents.session.flushStorageData()),
          new Promise((resolve) => setTimeout(resolve, 600)),
        ]);
      }
      await new Promise((resolve) => setTimeout(resolve, 150));
    } catch (_) {}
  }

  const { spawn } = require("child_process");
  const psExecutable = updaterHelpers.resolvePowerShellExecutable();
  try {
    writeLog(`Spawning PowerShell updater directly (${psExecutable})...`);
    const child = spawn(
      psExecutable,
      [
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-WindowStyle",
        "Hidden",
        "-File",
        psScriptPath,
      ],
      {
        detached: true,
        stdio: "ignore",
        windowsHide: true,
      }
    );
    if (!child || !child.pid) {
      throw new Error("PowerShell process failed to start (no PID).");
    }
    child.on("error", (spawnErr) => {
      writeLog(`WARNING: PowerShell child error event: ${spawnErr.message}`);
    });
    writeLog(`PowerShell updater process spawned successfully (PID: ${child.pid}).`);
    child.unref();
  } catch (err) {
    writeLog(`ERROR: Exception spawning updater process: ${err.message}`);
    return {
      success: false,
      error: `تعذر بدء برنامج التثبيت تلقائياً: ${err.message}`,
    };
  }

  writeLog("Quitting application so installer can proceed...");
  setTimeout(() => {
    writeLog("Quitting Electron app now...");
    isQuitting = true;
    try {
      if (webAppServer && typeof webAppServer.closeAllConnections === "function") {
        webAppServer.closeAllConnections();
      }
    } catch (_) {}
    try {
      if (lanServer && typeof lanServer.closeAllConnections === "function") {
        lanServer.closeAllConnections();
      }
    } catch (_) {}
    if (mainWindow && !mainWindow.isDestroyed()) {
      try { mainWindow.destroy(); } catch (_) {}
    }
    app.quit();
    const forceExitTimer = setTimeout(() => {
      try { app.exit(0); } catch (_) {}
    }, 600);
    if (typeof forceExitTimer.unref === "function") {
      forceExitTimer.unref();
    }
  }, 300);

  return { success: true };
});

app.whenReady().then(async () => {
  app.setAppUserModelId("com.ismart.messenger.webwrapper");
  Menu.setApplicationMenu(null);
  ensureStartup(true);
  cleanLegacyInstallation();
  const locale = app.getLocale();
  const startUrl = await startWebAppServer();
  const localizedUrl = `${startUrl}?lang=${locale}`;
  createWindow(localizedUrl);
  createTray();
  startLanTransferServer();
});

app.on("before-quit", () => {
  isQuitting = true;

  destroyAudioWorker("Application quitting.");
  try { _httpAgentKeepAlive.destroy(); } catch (_) {}
  try { _httpsAgentNoVerify.destroy(); } catch (_) {}

  // Cleanup window resources without clearing Chromium storage/cache.
  if (mainWindow) {
    mainWindow.destroy();
    mainWindow = null;
  }

  if (tray) {
    tray.destroy();
    tray = null;
  }

  if (lanServer) {
    lanServer.close();
    lanServer = null;
  }

  if (webAppServer) {
    webAppServer.close();
    webAppServer = null;
  }
});

app.on("window-all-closed", () => {
  if (process.platform === "darwin") {
    app.quit();
  }
});

app.on("activate", () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow(lastStartUrl);
  } else {
    showMainWindow();
  }
});

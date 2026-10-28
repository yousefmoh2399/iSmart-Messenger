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
const { execFile } = require("child_process");
const fs = require("fs");
const http = require("http");
const https = require("https");
const os = require("os");
const path = require("path");

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
const LAN_DISCOVERY_BATCH_SIZE = 96;
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

function appendDebugLog(scope, message, details) {
  try {
    const line = JSON.stringify({
      at: new Date().toISOString(),
      scope: String(scope || "app"),
      message: String(message || ""),
      details: details == null ? null : details,
    });
    fs.mkdirSync(path.dirname(debugLogPath()), { recursive: true });
    fs.appendFileSync(debugLogPath(), `${line}\n`, "utf8");
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

function localStorageChildPath(name, preferredPath) {
  const directory = path.join(localStorageRootPath(preferredPath), name);
  fs.mkdirSync(directory, { recursive: true });
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
app.commandLine.appendSwitch("disable-background-timer-throttling");
app.commandLine.appendSwitch("disable-renderer-backgrounding");
app.commandLine.appendSwitch("renderer-process-limit", "3");

// V8 32-bit Memory Optimization: constrain heap to 512MB to trigger fast, non-blocking GC pauses
// preventing memory fragmentation and 1-2 second freezes on low-RAM branch PCs.
app.commandLine.appendSwitch("js-flags", "--max-old-space-size=512");

// Limit disk cache to prevent thrashing slow mechanical 5400rpm hard drives
app.commandLine.appendSwitch("disk-cache-size", "67108864");
app.commandLine.appendSwitch("font-render-hinting", "medium");

// Graphics Performance Tuning:
// On Windows 7 (NT 6.1), disabling hardware acceleration forces CPU software emulation (SwiftShader),
// which pegs dual-core CPUs at 100% and freezes the app when scrolling or typing.
// Instead, we force the mature DirectX 9 ANGLE backend with GPU rasterization,
// which runs at 60fps on virtually all legacy Intel/AMD/Nvidia drivers on Windows 7.
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

function startWebAppServer() {
  if (webAppServer) {
    const address = webAppServer.address();
    return Promise.resolve(`http://127.0.0.1:${address.port}/`);
  }

  const root = webRoot();
  webAppServer = http.createServer((request, response) => {
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
      if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
        filePath = path.join(root, "index.html");
      }
      const ext = path.extname(filePath).toLowerCase();
      const data = fs.readFileSync(filePath);
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
    webAppServer.once("error", reject);
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

      if (VIRTUAL_ADAPTER_REGEX.test(lowerName)) {
        score -= 90;
      }
      if (VIRTUAL_MAC_PREFIXES.some((prefix) => mac.startsWith(prefix))) {
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

      candidates.push({ name, ip, mac, score });
    }
  }

  candidates.sort((a, b) => b.score - a.score);
  return candidates;
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
  const ownIps = uniqueLanIps(localIpv4s());
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
      storages: ["serviceworkers", "cachestorage"],
    })
    .then(() => session.clearCache())
    .catch((error) => {
      console.warn(`Failed to clear Electron web cache: ${error.message}`);
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

function resolveWebAssetPath(assetPath) {
  const normalized = String(assetPath || "")
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
      return candidate;
    }
  }
  console.warn("[electron] asset not found", { assetPath, candidates });
  return null;
}

function playWavFile(filePath) {
  return new Promise((resolve, reject) => {
    if (process.platform !== "win32") {
      reject(new Error("Audio preview is only implemented for Windows."));
      return;
    }

    let playPath = filePath;
    let isTemp = false;

    if (filePath && filePath.includes("app.asar")) {
      try {
        const tempDir = path.join(app.getPath("temp"), APP_NAME, "sounds");
        fs.mkdirSync(tempDir, { recursive: true });
        const tempFilePath = path.join(tempDir, path.basename(filePath));
        fs.writeFileSync(tempFilePath, fs.readFileSync(filePath));
        playPath = tempFilePath;
        isTemp = true;
      } catch (err) {
        console.error("[electron] failed to extract sound from asar", err);
      }
    }

    const escapedPath = String(playPath || "").replace(/'/g, "''");
    execFile(
      "powershell.exe",
      [
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        `$ErrorActionPreference = 'Stop'; Add-Type -AssemblyName System.Windows.Forms; $player = New-Object System.Media.SoundPlayer('${escapedPath}'); $player.Load(); $player.PlaySync();`,
      ],
      { windowsHide: true },
      (error) => {
        if (isTemp) {
          try {
            fs.unlinkSync(playPath);
          } catch (_) {}
        }
        if (error) {
          reject(error);
          return;
        }
        resolve();
      },
    );
  });
}

const _httpsAgentNoVerify = new https.Agent({ rejectUnauthorized: false });

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
      timeout: 30000,
    };
    if (isHttps) {
      requestOptions.agent = _httpsAgentNoVerify;
    }

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

async function fetchUrlBuffer(targetUrl, headers = {}) {
  const MAX_ATTEMPTS = 3;
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
        await new Promise((r) => setTimeout(r, 200 * (attempt + 1)));
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
    });
    notification.on("click", () => openPendingLanReceiveDialog(entry.requestId));
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
  const bestIp = getBestLocalIpv4();
  const allIps = localIpv4s();
  return {
    hostName: os.hostname(),
    localIp: bestIp || (allIps.length > 0 ? allIps[0] : null),
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

ipcMain.handle("notifications:show", async (_event, payload = {}) => {
  const title = String(payload.title || APP_NAME);
  const body = String(payload.body || "");
  const soundAssetPath = String(payload.soundAssetPath || "").trim();
  const silent = true;
  try {
    console.log("[electron] notifications:show", {
      title,
      body,
      silent,
      rawSilent: payload.silent,
      soundAssetPath,
    });
    if (soundAssetPath) {
      const filePath = resolveWebAssetPath(soundAssetPath);
      if (filePath) {
        playWavFile(filePath).catch((error) =>
          console.error("[electron] notification sound failed", error),
        );
      } else {
        console.warn(
          `[electron] notification sound asset was not found: ${soundAssetPath}`,
        );
      }
    }
    console.log(
      `[electron] Notification.isSupported=${Notification.isSupported()} platform=${process.platform}`,
    );
    if (Notification.isSupported()) {
      const notif = new Notification({ title, body, silent });
      try {
        notif.on("show", () =>
          console.log("[electron] native notification shown"),
        );
        notif.on("click", () =>
          console.log("[electron] native notification clicked"),
        );
      } catch (e) {}
      notif.show();
      console.log("[electron] native notification created and show() called");
    } else {
      console.log(
        "[electron] native Notification not supported on this platform",
      );
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
  const requestedDirectory = String(payload.directoryPath || "").trim();
  let outputPath;

  if (requestedDirectory) {
    fs.mkdirSync(requestedDirectory, { recursive: true });
    outputPath = uniqueOutputPath(
      requestedDirectory,
      payload.fileName || "file",
    );
  } else {
    const browserWindow = BrowserWindow.fromWebContents(event.sender);
    const defaultPath = path.join(app.getPath("downloads"), payload.fileName || "file");
    
    const { canceled, filePath } = await dialog.showSaveDialog(browserWindow, {
      title: "حفظ الملف",
      defaultPath: defaultPath,
    });

    if (canceled || !filePath) {
      return { success: false, message: "User canceled." };
    }
    outputPath = filePath;
  }

  const buffer = Buffer.from(String(payload.base64 || ""), "base64");
  if (buffer.length > MAX_ELECTRON_FETCH_BYTES) {
    return { success: false, message: "File is too large to save from memory." };
  }
  fs.writeFileSync(
    outputPath,
    buffer,
  );
  return { success: true, savedPath: outputPath };
});

ipcMain.handle("files:exists", async (_event, payload = {}) => {
  const filePath = String(payload.path || "").trim();
  return { success: true, exists: !!filePath && fs.existsSync(filePath) };
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
  if (!fs.existsSync(outputPath)) {
    fs.writeFileSync(outputPath, Buffer.from(String(payload.base64 || ""), "base64"));
  }
  return { success: true, path: outputPath };
});


const STORAGE_IMAGE_EXTS = new Set([".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".heic", ".ico"]);
const STORAGE_AUDIO_EXTS = new Set([".m4a", ".aac", ".mp3", ".wav", ".ogg", ".opus", ".flac"]);
const STORAGE_DOC_EXTS = new Set([".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".txt", ".csv", ".zip", ".rar"]);

function scanDirectoryStorage(dirPath) {
  let appCache = 0;
  let media = 0;
  let audio = 0;
  let docs = 0;

  if (!fs.existsSync(dirPath)) {
    return { appCache, media, audio, docs };
  }

  function walk(current) {
    let entries;
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch (_) {
      return;
    }
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      try {
        if (entry.isDirectory()) {
          walk(full);
        } else if (entry.isFile()) {
          const size = fs.statSync(full).size;
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

  walk(dirPath);
  return { appCache, media, audio, docs };
}

ipcMain.handle("storage:get-breakdown", async (_event, payload = {}) => {
  try {
    const cacheDir = localStorageChildPath(path.join("Chat", "cache"), payload.directoryPath);
    const tempDir = path.join(app.getPath("temp"), APP_NAME);

    const s1 = scanDirectoryStorage(cacheDir);
    const s2 = scanDirectoryStorage(tempDir);

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

    function cleanDir(dirPath) {
      if (!fs.existsSync(dirPath)) return;
      function walkDelete(current) {
        let entries;
        try {
          entries = fs.readdirSync(current, { withFileTypes: true });
        } catch (_) {
          return;
        }
        for (const entry of entries) {
          const full = path.join(current, entry.name);
          try {
            if (entry.isDirectory()) {
              walkDelete(full);
              try { fs.rmdirSync(full); } catch (_) {}
            } else if (entry.isFile()) {
              const ext = path.extname(entry.name).toLowerCase();
              let del = false;
              if (category === "all") del = true;
              else if (category === "appcache" && !STORAGE_IMAGE_EXTS.has(ext) && !STORAGE_AUDIO_EXTS.has(ext) && !STORAGE_DOC_EXTS.has(ext)) del = true;
              else if (category === "media" && STORAGE_IMAGE_EXTS.has(ext)) del = true;
              else if (category === "audio" && STORAGE_AUDIO_EXTS.has(ext)) del = true;
              else if (category === "documents" && STORAGE_DOC_EXTS.has(ext)) del = true;
              if (del) {
                fs.unlinkSync(full);
              }
            }
          } catch (_) {}
        }
      }
      walkDelete(dirPath);
    }

    cleanDir(cacheDir);
    cleanDir(tempDir);

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
  if (!fs.existsSync(outputPath)) {
    fs.writeFileSync(outputPath, Buffer.from(String(payload.base64 || ""), "base64"));
  }
  return { success: true, path: outputPath };
});

ipcMain.handle("files:read-chat-attachment-cache", async (_event, payload = {}) => {
  const filePath = chatAttachmentCachePath(
    payload.messageId,
    payload.fileName || "attachment",
    payload.directoryPath,
  );
  if (!fs.existsSync(filePath)) {
    return { success: false, message: "Cached attachment not found." };
  }
  return {
    success: true,
    fileName: path.basename(filePath),
    base64: fs.readFileSync(filePath).toString("base64"),
  };
});

ipcMain.handle("files:read-chat-archive", async (_event, payload = {}) => {
  const directory = localStorageChildPath(path.join("Chat", "sent"), payload.directoryPath);
  const safeMessageId = String(payload.messageId || "").replace(/[^\w.-]+/g, "_").toLowerCase();
  const safeHash = String(payload.sha256Hex || "").toLowerCase().replace(/[^a-f0-9]/g, "");
  if (!safeMessageId || !safeHash || !fs.existsSync(directory)) {
    return { success: false, message: "Archive not found." };
  }
  for (const name of fs.readdirSync(directory)) {
    const lower = name.toLowerCase();
    if (lower.startsWith(`${safeMessageId}_`) && lower.includes(safeHash)) {
      const filePath = path.join(directory, name);
      return {
        success: true,
        fileName: name,
        base64: fs.readFileSync(filePath).toString("base64"),
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

      request = protocol.get(parsedUrl, { headers }, (response) => {
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

function downloadFile(url, destinationPath, token, onProgress) {
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

      request = protocol.get(parsedUrl, { headers }, (response) => {
        const statusCode = response.statusCode || 0;

        // Handle redirects (e.g. 302 Found)
        if ([301, 302, 303, 307, 308].includes(statusCode) && response.headers.location) {
          response.resume();
          fileStream.close();
          try { fs.unlinkSync(destinationPath); } catch (_) {}
          
          const redirectUrl = new URL(response.headers.location, parsedUrl).toString();
          downloadFile(redirectUrl, destinationPath, token, onProgress).then(resolve).catch(reject);
          return;
        }

        if (statusCode !== 200) {
          response.resume();
          fileStream.close();
          try { fs.unlinkSync(destinationPath); } catch (_) {}
          reject(new Error(`Failed to download. Status code: ${statusCode}`));
          return;
        }

        const totalHeader = response.headers["content-length"] || response.headers["x-file-size"];
        const totalBytes = totalHeader ? parseInt(totalHeader, 10) : 0;
        let receivedBytes = 0;

        response.on("data", (chunk) => {
          receivedBytes += chunk.length;
          fileStream.write(chunk);
          if (onProgress) {
            onProgress(receivedBytes, totalBytes);
          }
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
  const { downloadUrl, token, checksumSha256, fileName, silentInstallArgs, installerKind } = payload;
  if (!downloadUrl) {
    throw new Error("Missing download URL");
  }

  const tempDir = path.join(app.getPath("temp"), APP_NAME);
  fs.mkdirSync(tempDir, { recursive: true });

  // Clean up any previous update artifacts
  const cleanups = [
    "update-download.tmp",
    "update-installer.exe",
    "update-installer.msi",
    "update-package.zip",
    "app-update.zip",
  ];
  for (const c of cleanups) {
    try {
      const p = path.join(tempDir, c);
      if (fs.existsSync(p)) fs.unlinkSync(p);
    } catch (_) {}
  }

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

    sendUpdaterProgress({
      status: "downloading",
      progress: 0,
      message: "جاري بدء تحميل التحديث...",
    }, { force: true });

    await downloadFile(downloadUrl, tempDownloadPath, token, (received, total) => {
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
    });

    if (checksumSha256 && checksumSha256.trim()) {
      sendUpdaterProgress({
        status: "downloading",
        progress: 95,
        message: "جاري التحقق من سلامة ملف التحديث...",
      }, { force: true });
      const calculatedHash = await calculateFileSha256(tempDownloadPath);
      if (calculatedHash.toLowerCase() !== checksumSha256.trim().toLowerCase()) {
        throw new Error(`بصمة الملف غير مطابقة! المتوقع: ${checksumSha256.trim().toLowerCase()}، المحسوب: ${calculatedHash.toLowerCase()}`);
      }
    }

    // Inspect file magic bytes to determine real file type
    const detectedType = detectFileType(tempDownloadPath);
    let finalPackagePath = "";
    if (detectedType === "exe") {
      finalPackagePath = path.join(tempDir, "update-installer.exe");
    } else if (detectedType === "msi") {
      finalPackagePath = path.join(tempDir, "update-installer.msi");
    } else if (detectedType === "zip") {
      finalPackagePath = path.join(tempDir, "update-package.zip");
    } else {
      // Fallback based on fileName or downloadUrl
      const lower = (fileName || downloadUrl).toLowerCase();
      if (lower.includes(".msi")) {
        finalPackagePath = path.join(tempDir, "update-installer.msi");
      } else if (lower.includes(".zip")) {
        finalPackagePath = path.join(tempDir, "update-package.zip");
      } else {
        // Default to executable installer
        finalPackagePath = path.join(tempDir, "update-installer.exe");
      }
    }

    if (fs.existsSync(finalPackagePath)) {
      try { fs.unlinkSync(finalPackagePath); } catch (_) {}
    }
    fs.renameSync(tempDownloadPath, finalPackagePath);

    // Save update metadata for updater:apply-update
    const meta = {
      packagePath: finalPackagePath,
      packageType: detectedType,
      fileName: fileName || path.basename(finalPackagePath),
      downloadUrl: downloadUrl,
      silentInstallArgs: silentInstallArgs || "",
      installerKind: installerKind || "",
      downloadedAt: new Date().toISOString(),
    };
    fs.writeFileSync(path.join(tempDir, "update-meta.json"), JSON.stringify(meta, null, 2), "utf8");

    sendUpdaterProgress({
      status: "downloaded",
      progress: 100,
      message: "تم تحميل التحديث بنجاح وجاهز للتثبيت.",
    }, { force: true });

    return { success: true, filePath: finalPackagePath, packageType: detectedType };
  } catch (error) {
    console.error("Update download failed:", error);
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
  let meta = {};
  const metaPath = path.join(tempDir, "update-meta.json");
  if (fs.existsSync(metaPath)) {
    try {
      meta = JSON.parse(fs.readFileSync(metaPath, "utf8"));
    } catch (_) {}
  }

  // Merge any runtime payload options
  if (payload && typeof payload === "object") {
    meta = { ...meta, ...payload };
  }

  // Locate the update package file
  let packagePath = meta.packagePath;
  if (!packagePath || !fs.existsSync(packagePath)) {
    const candidates = [
      path.join(tempDir, "update-installer.exe"),
      path.join(tempDir, "update-installer.msi"),
      path.join(tempDir, "update-package.zip"),
      path.join(tempDir, "app-update.zip"),
    ];
    for (const c of candidates) {
      if (fs.existsSync(c)) {
        packagePath = c;
        break;
      }
    }
  }

  if (!packagePath || !fs.existsSync(packagePath)) {
    writeLog("ERROR: update package file does not exist in tempDir!");
    throw new Error("ملف التحديث غير موجود! يرجى تحميله أولاً.");
  }

  const detectedType = detectFileType(packagePath);
  const isExe = detectedType === "exe" || packagePath.toLowerCase().endsWith(".exe");
  const isMsi = detectedType === "msi" || packagePath.toLowerCase().endsWith(".msi");

  const appDir = path.dirname(process.execPath);
  const exePath = process.execPath;
  const procName = path.basename(exePath, path.extname(exePath));
  const parentPid = process.pid;

  writeLog(`Found update package: ${packagePath} (type: ${detectedType}, isExe: ${isExe}, isMsi: ${isMsi})`);
  writeLog(`appDir: ${appDir}, exePath: ${exePath}, procName: ${procName}, PID: ${parentPid}`);

  const packagePathNormalized = packagePath.replace(/\\/g, "/");
  const appDirNormalized = appDir.replace(/\\/g, "/");
  const exePathNormalized = exePath.replace(/\\/g, "/");
  const logPathNormalized = path.join(tempDir, "update_log.txt").replace(/\\/g, "/");

  const psScriptPath = path.join(app.getPath("temp"), "apply_update.ps1");
  let psScriptContent = "";

  if (isExe) {
    // -------------------------------------------------------------
    // Direct Executable Installer (.exe) - Electron NSIS setup
    // Requests Windows Administrator privileges (RunAs / UAC),
    // closes the application, installs into Program Files, and relaunches.
    // -------------------------------------------------------------
    writeLog("Generating PowerShell script for Executable Installer (RunAs / UAC elevation)...");
    psScriptContent = `
$logPath = "${logPathNormalized}"
$installerPath = "${packagePathNormalized}"
$procName = "${procName}"
$parentPid = ${parentPid}
$exePath = "${exePathNormalized}"

function Log-Msg($msg) {
    $logParent = [System.IO.Path]::GetDirectoryName($logPath)
    if (-not (Test-Path "$logParent")) {
        New-Item -ItemType Directory -Path "$logParent" -Force | Out-Null
    }
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "[$timestamp] $msg" | Out-File -FilePath $logPath -Append -Encoding UTF8
}

Log-Msg "=== Starting Electron Setup Installer Update ==="
Log-Msg "Installer path: $installerPath"
Log-Msg "Parent PID: $parentPid"
Log-Msg "Process Name: $procName"
Log-Msg "Exe Path: $exePath"

# 1. Wait for current Electron application to exit
Log-Msg "Waiting for parent process $parentPid to exit..."
$timeout = 25
while ((Get-Process -Id $parentPid -ErrorAction SilentlyContinue) -and ($timeout -gt 0)) {
    Start-Sleep -m 200
    $timeout--
}
if (Get-Process -Id $parentPid -ErrorAction SilentlyContinue) {
    Log-Msg "Terminating parent PID $parentPid forcefully..."
    Stop-Process -Id $parentPid -Force -ErrorAction SilentlyContinue
}

# Ensure all instances of the application are terminated so no files are locked
Log-Msg "Terminating any lingering instances of $procName or electron..."
Get-Process -Name "$procName" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -m 600

# 2. Launch the installer executable with Administrator rights (triggers Windows UAC prompt!)
Log-Msg "Launching installer with Administrator privileges (Verb: RunAs)..."
try {
    # Launching with -Verb RunAs prompts Windows UAC for administrator elevation
    $inst = Start-Process -FilePath "$installerPath" -Verb RunAs -PassThru -Wait
    Log-Msg "Installer process finished with exit code: $($inst.ExitCode)"
} catch {
    Log-Msg "Installer execution notice/exception (e.g. UAC prompt outcome): $($_.Exception.Message)"
}

# 3. Verify application launch and relaunch if not already started by installer
Start-Sleep -s 2
$running = Get-Process -Name "$procName" -ErrorAction SilentlyContinue
if (-not $running) {
    Log-Msg "Application not running yet. Searching for installed executable in Program Files..."
    $pf32 = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ProgramFilesX86)
    $pf64 = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ProgramFiles)
    $localApp = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)

    $candidates = @(
        (Join-Path $pf32 "iSmart Messenger\$procName.exe"),
        (Join-Path $pf64 "iSmart Messenger\$procName.exe"),
        (Join-Path $pf32 "$procName\$procName.exe"),
        (Join-Path $pf64 "$procName\$procName.exe"),
        (Join-Path $localApp "Programs\iSmart Messenger\$procName.exe"),
        "$exePath"
    )
    $launched = $false
    foreach ($cand in $candidates) {
        if ($cand -and (Test-Path "$cand")) {
            Log-Msg "Relaunching application from: $cand"
            Start-Process -FilePath "$cand"
            $launched = $true
            break
        }
    }
    if (-not $launched) {
        Log-Msg "Could not find Program Files executable, attempting original exePath: $exePath"
        if (Test-Path "$exePath") { Start-Process -FilePath "$exePath" }
    }
} else {
    Log-Msg "Application is already running after installer execution."
}

# 4. Clean up installer file
Start-Sleep -s 3
Remove-Item -Path "$installerPath" -Force -ErrorAction SilentlyContinue
Log-Msg "=== Installer update completed ==="

# Self-destruct script
Remove-Item -Path $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
`.trim();
  } else if (isMsi) {
    // -------------------------------------------------------------
    // MSI Package
    // -------------------------------------------------------------
    writeLog("Generating PowerShell script for MSI installer...");
    psScriptContent = `
$logPath = "${logPathNormalized}"
$installerPath = "${packagePathNormalized}"
$procName = "${procName}"
$parentPid = ${parentPid}
$exePath = "${exePathNormalized}"

function Log-Msg($msg) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "[$ts] $msg" | Out-File -FilePath $logPath -Append -Encoding UTF8
}

Log-Msg "=== Starting MSI Package Update ==="
$timeout = 25
while ((Get-Process -Id $parentPid -ErrorAction SilentlyContinue) -and ($timeout -gt 0)) {
    Start-Sleep -m 200
    $timeout--
}
Get-Process -Name "$procName" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -m 600

try {
    $inst = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i \`"$installerPath\`" /passive /norestart" -Verb RunAs -PassThru -Wait
    Log-Msg "msiexec finished with exit code: $($inst.ExitCode)"
} catch {
    Log-Msg "MSI install error: $($_.Exception.Message)"
}

Start-Sleep -s 2
$running = Get-Process -Name "$procName" -ErrorAction SilentlyContinue
if (-not $running) {
    if (Test-Path "$exePath") { Start-Process -FilePath "$exePath" }
}
Remove-Item -Path "$installerPath" -Force -ErrorAction SilentlyContinue
Remove-Item -Path $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
`.trim();
  } else {
    // -------------------------------------------------------------
    // Zip Archive Package (Portable / Loose files)
    // -------------------------------------------------------------
    writeLog("Generating PowerShell script for Zip Archive (clean extract without COM popups)...");
    const extractedPath = path.join(tempDir, "extracted");
    const extractedPathNormalized = extractedPath.replace(/\\/g, "/");

    psScriptContent = `
$logPath = "${logPathNormalized}"
$zipPath = "${packagePathNormalized}"
$extractedPath = "${extractedPathNormalized}"
$appDir = "${appDirNormalized}"
$exePath = "${exePathNormalized}"
$procName = "${procName}"
$parentPid = ${parentPid}

function Log-Msg($msg) {
    $logParent = [System.IO.Path]::GetDirectoryName($logPath)
    if (-not (Test-Path "$logParent")) {
        New-Item -ItemType Directory -Path "$logParent" -Force | Out-Null
    }
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "[$timestamp] $msg" | Out-File -FilePath $logPath -Append -Encoding UTF8
}

Log-Msg "=== Starting Zip Update Process ==="
$timeout = 25
while ((Get-Process -Id $parentPid -ErrorAction SilentlyContinue) -and ($timeout -gt 0)) {
    Start-Sleep -m 200
    $timeout--
}
Get-Process -Name "$procName" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -m 800

if (Test-Path "$extractedPath") {
    Remove-Item -Path "$extractedPath" -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path "$extractedPath" -Force | Out-Null

$extractedOk = $false
try {
    Add-Type -Assembly "System.IO.Compression.FileSystem"
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractedPath)
    $extractedOk = $true
    Log-Msg "Extraction completed via .NET ZipFile."
} catch {
    Log-Msg "Extraction via .NET failed: $($_.Exception.Message)."
}

if (-not $extractedOk) {
    try {
        Expand-Archive -Path "$zipPath" -DestinationPath "$extractedPath" -Force
        $extractedOk = $true
        Log-Msg "Extraction completed via Expand-Archive."
    } catch {
        Log-Msg "Expand-Archive failed: $($_.Exception.Message)"
    }
}

$sourceDir = "$extractedPath"
if (Test-Path "$extractedPath\\app") {
    $sourceDir = "$extractedPath\\app"
} elseif (Test-Path "$extractedPath\\resources") {
    $sourceDir = "$extractedPath"
}

Log-Msg "Copying updated files from $sourceDir to $appDir..."
$copied = $false
for ($i = 1; $i -le 10; $i++) {
    try {
        Get-Process -Name "$procName" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Copy-Item -Path "$sourceDir\\*" -Destination "$appDir" -Recurse -Force -ErrorAction Stop
        $copied = $true
        Log-Msg "Files copied successfully on attempt $i."
        break
    } catch {
        Log-Msg "Attempt $i failed: $($_.Exception.Message). Retrying..."
        Start-Sleep -s 1
    }
}

Start-Sleep -s 1
if (Test-Path "$exePath") {
    Start-Process "$exePath"
}
Remove-Item -Path "$zipPath" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$extractedPath" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
`.trim();
  }

  writeLog(`Writing psScriptPath: ${psScriptPath}...`);
  fs.writeFileSync(psScriptPath, psScriptContent, "utf8");
  writeLog("psScriptPath written successfully.");

  const { spawn } = require("child_process");
  try {
    writeLog("Spawning powershell.exe via cmd.exe start command...");
    const child = spawn(
      "cmd.exe",
      [
        "/c",
        "start",
        "",
        "/min",
        "powershell.exe",
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
    writeLog(`cmd.exe child process spawned successfully (PID: ${child.pid}).`);
    child.unref();
  } catch (err) {
    writeLog(`ERROR: Exception spawning child process: ${err.message}`);
  }

  writeLog("Quitting application so installer can proceed...");
  setTimeout(() => {
    writeLog("Quitting Electron app now...");
    isQuitting = true;
    if (mainWindow && !mainWindow.isDestroyed()) {
      try { mainWindow.destroy(); } catch (_) {}
    }
    app.quit();
  }, 1000);

  return { success: true };
});

app.whenReady().then(async () => {
  app.setAppUserModelId("com.ismart.messenger.webwrapper");
  Menu.setApplicationMenu(null);
  ensureStartup(true);
  const locale = app.getLocale();
  const startUrl = await startWebAppServer();
  const localizedUrl = `${startUrl}?lang=${locale}`;
  createWindow(localizedUrl);
  createTray();
  startLanTransferServer();
});

app.on("before-quit", () => {
  isQuitting = true;

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

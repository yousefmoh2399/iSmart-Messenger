const { contextBridge, ipcRenderer } = require("electron");

const TITLEBAR_HEIGHT = 34;

function applyTitlebarTheme(mode) {
  const dark = mode === "dark";
  const titlebar = document.getElementById("electron-titlebar");
  if (!titlebar) {
    return;
  }
  titlebar.style.background = dark ? "#0F172A" : "#F8FAFC";
  titlebar.style.color = dark ? "#F8FAFC" : "#111827";
  titlebar.style.borderBottomColor = dark ? "#1E293B" : "#E5E7EB";
}

function ensureElectronTitlebar() {
  if (document.getElementById("electron-titlebar")) {
    return;
  }

  const style = document.createElement("style");
  style.textContent = `
    html.electron-titlebar-enabled,
    html.electron-titlebar-enabled body {
      height: 100vh;
      overflow: hidden;
      margin: 0;
      padding: 0 !important;
      box-sizing: border-box;
    }

    #electron-titlebar {
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      height: ${TITLEBAR_HEIGHT}px;
      z-index: 2147483647;
      display: flex;
      align-items: center;
      direction: ltr;
      gap: 9px;
      padding: 0 142px 0 12px;
      box-sizing: border-box;
      border-bottom: 1px solid;
      font: 600 12px/1.2 "Segoe UI", Arial, sans-serif;
      letter-spacing: 0;
      user-select: none;
      -webkit-app-region: drag;
    }

    #electron-titlebar img {
      width: 18px;
      height: 18px;
      object-fit: contain;
      flex: 0 0 auto;
    }

    #electron-titlebar span {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  `;
  document.head.appendChild(style);

  const titlebar = document.createElement("div");
  titlebar.id = "electron-titlebar";

  const icon = document.createElement("img");
  icon.alt = "";
  icon.src = "assets/assets/images/logo.png";
  icon.onerror = () => icon.style.display = 'none';
  titlebar.appendChild(icon);

  const title = document.createElement("span");
  title.textContent = "iSmart Messenger";
  titlebar.appendChild(title);

  document.documentElement.classList.add("electron-titlebar-enabled");
  document.body.prepend(titlebar);
  applyTitlebarTheme("dark");
}

const BASE_APP_ICON_DATA_URL =
  "data:image/png;base64," +
  "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";

const baseAppIconImage = new Image();
baseAppIconImage.src = BASE_APP_ICON_DATA_URL;

function drawBadgeRoundRect(ctx, x, y, width, height, radius) {
  if (typeof ctx.roundRect === "function") {
    ctx.beginPath();
    ctx.roundRect(x, y, width, height, radius);
  } else {
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.lineTo(x + width - radius, y);
    ctx.quadraticCurveTo(x + width, y, x + width, y + radius);
    ctx.lineTo(x + width, y + height - radius);
    ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
    ctx.lineTo(x + radius, y + height);
    ctx.quadraticCurveTo(x, y + height, x, y + height - radius);
    ctx.lineTo(x + radius, y);
    ctx.quadraticCurveTo(x, y, x + radius, y);
    ctx.closePath();
  }
}

function createBadgeDataUrl(count) {
  if (!count || count <= 0) return null;
  try {
    const size = 64;
    const canvas = document.createElement("canvas");
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext("2d");
    if (!ctx) return null;

    ctx.clearRect(0, 0, size, size);

    // 1. Draw base application icon (inset to 56x56 so top-right badge fits cleanly)
    if (baseAppIconImage && baseAppIconImage.complete && baseAppIconImage.naturalWidth > 0) {
      ctx.drawImage(baseAppIconImage, 2, 4, 56, 56);
    } else {
      drawBadgeRoundRect(ctx, 4, 6, 52, 52, 12);
      ctx.fillStyle = "#2563EB";
      ctx.fill();
    }

    // 2. Draw Top-Right vibrant red notification bubble badge
    const label = count > 99 ? "99+" : String(count);
    const isSingle = label.length === 1;
    const isDouble = label.length === 2;

    ctx.save();
    // Drop shadow for crisp contrast over any taskbar background
    ctx.shadowColor = "rgba(0, 0, 0, 0.45)";
    ctx.shadowBlur = 3;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 1;

    // Pure vibrant red
    ctx.fillStyle = "#E53935";

    if (isSingle) {
      const cx = 49;
      const cy = 15;
      const r = 13;
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();

      // Sharp white border
      ctx.strokeStyle = "#FFFFFF";
      ctx.lineWidth = 2.5;
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.stroke();

      // Bold white number
      ctx.fillStyle = "#FFFFFF";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.font = 'bold 16px "Segoe UI", Arial, sans-serif';
      ctx.fillText(label, cx, cy + 1);
    } else {
      const badgeW = isDouble ? 34 : 40;
      const badgeH = 26;
      const badgeX = 62 - badgeW;
      const badgeY = 2;
      const radius = 13;

      drawBadgeRoundRect(ctx, badgeX, badgeY, badgeW, badgeH, radius);
      ctx.fill();
      ctx.restore();

      // Sharp white border
      ctx.strokeStyle = "#FFFFFF";
      ctx.lineWidth = 2.5;
      drawBadgeRoundRect(ctx, badgeX, badgeY, badgeW, badgeH, radius);
      ctx.stroke();

      // Bold white number
      ctx.fillStyle = "#FFFFFF";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      const fontSize = isDouble ? 14 : 12;
      ctx.font = `bold ${fontSize}px "Segoe UI", Arial, sans-serif`;
      ctx.fillText(label, badgeX + (badgeW / 2), badgeY + (badgeH / 2) + 1);
    }

    return canvas.toDataURL("image/png");
  } catch (_) {
    return null;
  }
}

window.addEventListener("DOMContentLoaded", ensureElectronTitlebar);

ipcRenderer.on("tray-action", (_event, action) => {
  window.dispatchEvent(
    new CustomEvent("electron-tray-action", { detail: String(action || "") }),
  );
});

ipcRenderer.on("updater-progress", (_event, payload) => {
  window.dispatchEvent(
    new CustomEvent("electron-updater-progress", { detail: JSON.stringify(payload || {}) }),
  );
});

ipcRenderer.on("lan-transfer-progress", (_event, payload) => {
  window.dispatchEvent(
    new CustomEvent("electron-lan-transfer-progress", { detail: JSON.stringify(payload || {}) }),
  );
});

ipcRenderer.on("lan-receive-pending", (_event, payload) => {
  window.dispatchEvent(
    new CustomEvent("electron-lan-receive-pending", { detail: JSON.stringify(payload || []) }),
  );
});

ipcRenderer.on("upload-progress", (_event, payload) => {
  window.dispatchEvent(
    new CustomEvent("electron-upload-progress", { detail: JSON.stringify(payload || {}) }),
  );
});

ipcRenderer.on("download-progress", (_event, payload) => {
  window.dispatchEvent(
    new CustomEvent("electron-download-progress", { detail: JSON.stringify(payload || {}) }),
  );
});

contextBridge.exposeInMainWorld("electronBridge", {
  isElectron: true,
  getDeviceInfo: () => ipcRenderer.invoke("app:get-device-info"),
  debugLog: (payload) => ipcRenderer.invoke("debug:log", payload),
  secureStoreSet: (payload) => ipcRenderer.invoke("secure-store:set", payload),
  secureStoreGet: (key) => ipcRenderer.invoke("secure-store:get", key),
  secureStoreDelete: (key) => ipcRenderer.invoke("secure-store:delete", key),
  getPrinters: () => ipcRenderer.invoke("printers:list"),
  notify: (payload) => {
    try {
      console.log("[preload] notify", payload);
    } catch (e) {}
    return (async () => {
      try {
        const res = await ipcRenderer.invoke("notifications:show", payload);
        try {
          console.log("[preload] notify result", res);
        } catch (e) {}
        return res;
      } catch (err) {
        try {
          console.error("[preload] notify error", err);
        } catch (e) {}
        throw err;
      }
    })();
  },
  playAudioAsset: (payload) => ipcRenderer.invoke("audio:play-asset", payload),
  requestAttention: () => ipcRenderer.invoke("window:request-attention"),
  getWindowState: () => ipcRenderer.invoke("window:get-state"),
  setTaskbarBadge: (count) => {
    const num = typeof count === "number" ? count : parseInt(count, 10) || 0;
    const dataUrl = num > 0 ? createBadgeDataUrl(num) : null;
    return ipcRenderer.invoke("window:set-badge", { count: num, dataUrl });
  },
  setWindowTheme: (payload) => {
    const mode = payload && payload.mode === "dark" ? "dark" : "light";
    applyTitlebarTheme(mode);
    return ipcRenderer.invoke("window:set-theme", { mode });
  },
  fetchBase64: (payload) => ipcRenderer.invoke("http:fetch-base64", payload),
  saveBase64: (payload) => ipcRenderer.invoke("files:save-base64", payload),
  fileExists: (payload) => ipcRenderer.invoke("files:exists", payload),
  openLocalFile: (payload) => ipcRenderer.invoke("files:open-local", payload),
  getStorageRoot: () => ipcRenderer.invoke("files:get-storage-root"),
  initializeStorage: (payload) => ipcRenderer.invoke("files:initialize-storage", payload),
  appendErrorLog: (payload) => ipcRenderer.invoke("files:append-error-log", payload),
  archiveChatAttachment: (payload) => ipcRenderer.invoke("files:archive-chat-attachment", payload),
  getChatAttachmentPath: (payload) => ipcRenderer.invoke("files:get-chat-attachment-path", payload),
  cacheChatAttachment: (payload) => ipcRenderer.invoke("files:cache-chat-attachment", payload),
  readChatAttachmentCache: (payload) => ipcRenderer.invoke("files:read-chat-attachment-cache", payload),
  readChatArchive: (payload) => ipcRenderer.invoke("files:read-chat-archive", payload),
  printBase64: (payload) => ipcRenderer.invoke("print:base64", payload),
  printUrl: (payload) => ipcRenderer.invoke("print:url", payload),
  openUrl: (url) => ipcRenderer.invoke("shell:open-url", url),
  probeLanPeer: (targetIp) => ipcRenderer.invoke("lan:probe-peer", targetIp),
  discoverLanPeers: () => ipcRenderer.invoke("lan:discover-peers"),
  requestLanTransfer: (payload) => ipcRenderer.invoke("lan:request-transfer", payload),
  uploadLanTransferBytes: (payload) => ipcRenderer.invoke("lan:upload-transfer", payload),
  pickAndSendLanFile: (payload) => ipcRenderer.invoke("lan:pick-and-send-file", payload),
  getPendingLanReceiveRequests: () => ipcRenderer.invoke("lan:get-pending-receive-requests"),
  openPendingLanReceiveDialog: (requestId) => ipcRenderer.invoke("lan:open-pending-receive-dialog", requestId),
  getTransferCenterState: () => ipcRenderer.invoke("lan:get-transfer-center-state"),
  updateTransferPolicy: (policy) => ipcRenderer.invoke("lan:update-transfer-policy", policy),
  markTransferNotificationsRead: () => ipcRenderer.invoke("lan:mark-notifications-read"),
  openInboxFileLocation: (filePath) => ipcRenderer.invoke("lan:open-inbox-file-location", filePath),
  pickDirectory: (payload) => ipcRenderer.invoke("dialog:pick-directory", payload),
  pickFiles: (payload) => ipcRenderer.invoke("dialog:pick-files", payload),
  setStartup: (enabled) => ipcRenderer.invoke("startup:set", enabled),
  getStartup: () => ipcRenderer.invoke("startup:get"),
  startUpdate: (payload) => ipcRenderer.invoke("updater:start-update", payload),
  applyUpdate: (payload) => ipcRenderer.invoke("updater:apply-update", payload),
  listOpenWindows: () => ipcRenderer.invoke("window:list-open-windows"),
  readClipboardFiles: () => ipcRenderer.invoke("clipboard:read-files"),
  captureWindow: (payload) => ipcRenderer.invoke("window:capture-window", payload),
  captureScreen: () => ipcRenderer.invoke("window:capture-screen"),
  openRdp: (payload) => ipcRenderer.invoke("shell:open-rdp", payload),
  openPing: (payload) => ipcRenderer.invoke("shell:open-ping", payload),
  getStorageBreakdown: (payload) => ipcRenderer.invoke("storage:get-breakdown", payload),
  clearStorageCache: (payload) => ipcRenderer.invoke("storage:clear-cache", payload),
  probePeerStatus: (payload) => ipcRenderer.invoke("net:probe-peer-status", payload),
  uploadChatAttachment: (payload) => ipcRenderer.invoke("chat:upload-attachment", payload),
  cancelUploadAttachment: (transferId) => ipcRenderer.invoke("chat:cancel-upload", transferId),
  downloadChatAttachment: (payload) => ipcRenderer.invoke("files:download-chat-attachment", payload),
  cancelDownloadAttachment: (transferId) => ipcRenderer.invoke("files:cancel-download", transferId),
  showSaveDialog: (payload) => ipcRenderer.invoke("dialog:show-save-dialog", payload),
  copyFile: (payload) => ipcRenderer.invoke("files:copy-file", payload),
  calculateFileSha256: (payload) => ipcRenderer.invoke("files:calculate-sha256", payload),
});
console.log("[preload] electronBridge exposed");

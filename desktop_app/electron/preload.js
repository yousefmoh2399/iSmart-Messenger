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
  setStartup: (enabled) => ipcRenderer.invoke("startup:set", enabled),
  getStartup: () => ipcRenderer.invoke("startup:get"),
  startUpdate: (payload) => ipcRenderer.invoke("updater:start-update", payload),
  applyUpdate: () => ipcRenderer.invoke("updater:apply-update"),
  listOpenWindows: () => ipcRenderer.invoke("window:list-open-windows"),
  captureWindow: (payload) => ipcRenderer.invoke("window:capture-window", payload),
  captureScreen: () => ipcRenderer.invoke("window:capture-screen"),
  openRdp: (payload) => ipcRenderer.invoke("shell:open-rdp", payload),
});
console.log("[preload] electronBridge exposed");

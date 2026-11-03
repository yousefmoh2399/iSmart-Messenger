/**
 * iSmart Dynamic Island Manager
 * Manages floating window lifecycle, multi-monitor alignment,
 * settings, API synchronization, and IPC communication.
 * Highly optimized for Windows 7 (32-bit), 10, and 11.
 */

const { BrowserWindow, screen, ipcMain, app, shell } = require("electron");
const path = require("path");
const fs = require("fs");
const http = require("http");
const https = require("https");

class DynamicIslandManager {
  constructor(options = {}) {
    this.mainWindow = null;
    this.islandWindow = null;
    this.cachedChats = [];
    this.activeUser = null;
    this.authToken = null;
    this.apiBaseUrl = null;
    this.conversationMessagesCache = new Map();
    this.getAuthToken = options.getAuthToken || (() => null);
    this.getActiveUser = options.getActiveUser || (() => null);
    this.getUserId = options.getUserId || (() => null);
    this.getApiBaseUrl = options.getApiBaseUrl || (() => "http://172.17.100.253:5000");
    this.fetchUrlBuffer = options.fetchUrlBuffer || null;
    this._mediaBase64Cache = new Map();
    this.onOpenConversation = options.onOpenConversation || (() => {});
    this.onShowMainWindow = options.onShowMainWindow || (() => {});
    this.onToggleMainWindow = options.onToggleMainWindow || (() => {});
    this.settings = this.loadSettings();
  }

  settingsFilePath() {
    return path.join(app.getPath("userData"), "island-settings.json");
  }

  loadSettings() {
    const defaults = {
      enabled: true,
      privacyMode: "full", // "full", "sender_only", "hidden"
      theme: "obsidian", // "obsidian", "midnight", "neon", "emerald", "crimson"
      soundEnabled: true,
      startMinimizedOnBoot: true,
      scale: 1.0,
      yOffset: 0,
    };
    try {
      const file = this.settingsFilePath();
      if (fs.existsSync(file)) {
        const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
        const isOurConfig = parsed.theme !== undefined || parsed.privacyMode !== undefined;
        const enabled = isOurConfig && typeof parsed.enabled === "boolean" ? parsed.enabled : true;
        const yOffset = typeof parsed.yOffset === "number" ? parsed.yOffset : 0;
        return { ...defaults, ...parsed, enabled, yOffset };
      }
    } catch (_) {}
    return defaults;
  }

  saveSettings(newSettings) {
    this.settings = { ...this.settings, ...newSettings };
    try {
      fs.writeFileSync(
        this.settingsFilePath(),
        JSON.stringify(this.settings, null, 2),
        "utf8",
      );
    } catch (_) {}

    if (this.settings.enabled) {
      if (!this.islandWindow || this.islandWindow.isDestroyed()) {
        this.createIslandWindow(false);
      } else if (!this.islandWindow.isVisible()) {
        this.islandWindow.show();
        this.islandWindow.moveTop();
      }
    } else {
      if (this.islandWindow && !this.islandWindow.isDestroyed()) {
        this.islandWindow.hide();
      }
    }

    if (this.islandWindow && !this.islandWindow.isDestroyed()) {
      this.islandWindow.webContents.send("island:settings-updated", this.settings);
      // Re-apply positioning
      this.resize(this.currentWidth || 440, this.currentHeight || 52);
    }
    if (this.mainWindow && !this.mainWindow.isDestroyed()) {
      this.mainWindow.webContents.send("island:settings-updated", this.settings);
    }
    return this.settings;
  }

  setMainWindow(win) {
    this.mainWindow = win;
    if (this.mainWindow && !this.mainWindow.isDestroyed()) {
      this.mainWindow.on("focus", () => {
        if (this.islandWindow && !this.islandWindow.isDestroyed() && this.islandWindow.isVisible()) {
          try {
            this.islandWindow.setAlwaysOnTop(true, "screen-saver");
          } catch (_) {
            try { this.islandWindow.setAlwaysOnTop(true); } catch (__) {}
          }
          this.islandWindow.moveTop();
        }
      });
    }
  }

  createIslandWindow(startHidden = false) {
    if (this.islandWindow && !this.islandWindow.isDestroyed()) {
      if (!startHidden && !this.islandWindow.isVisible()) {
        this.islandWindow.show();
      }
      return this.islandWindow;
    }

    if (!this.settings.enabled) {
      return null;
    }

    const primaryDisplay = screen.getPrimaryDisplay();
    const bounds = primaryDisplay.bounds;
    const initialWidth = 440;
    const initialHeight = 52;
    this.currentWidth = initialWidth;
    this.currentHeight = initialHeight;

    const x = Math.round(bounds.x + (bounds.width - initialWidth) / 2);
    const offset = typeof this.settings.yOffset === "number" ? this.settings.yOffset : 0;
    const y = Math.round(bounds.y + offset);

    this.islandWindow = new BrowserWindow({
      width: initialWidth,
      height: initialHeight,
      x,
      y,
      frame: false,
      transparent: true,
      alwaysOnTop: true,
      skipTaskbar: true,
      resizable: false,
      hasShadow: false,
      focusable: true,
      show: false,
      backgroundColor: "#00000000",
      webPreferences: {
        preload: path.join(__dirname, "island-preload.js"),
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: false,
        backgroundThrottling: false,
      },
    });

    // Make sure it sits on top of all windows
    try {
      this.islandWindow.setAlwaysOnTop(true, "screen-saver");
    } catch (_) {
      try {
        this.islandWindow.setAlwaysOnTop(true, "floating");
      } catch (__) {
        this.islandWindow.setAlwaysOnTop(true);
      }
    }

    try {
      this.islandWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
    } catch (_) {}

    const indexPath = path.join(__dirname, "index.html");
    this.islandWindow.loadFile(indexPath);


    const showIsland = () => {
      if (this.islandWindow && !this.islandWindow.isDestroyed() && !this.islandWindow.isVisible()) {
        this.islandWindow.show();
        try {
          this.islandWindow.setAlwaysOnTop(true, "screen-saver");
        } catch (_) {
          try { this.islandWindow.setAlwaysOnTop(true); } catch (__) {}
        }
        this.islandWindow.moveTop();
      }
    };

    this.islandWindow.once("ready-to-show", () => {
      if (!startHidden && this.settings.enabled) {
        showIsland();
      }
    });

    // Fail-safe timeout in case ready-to-show is delayed on some Windows themes
    setTimeout(() => {
      if (!startHidden && this.settings.enabled) {
        showIsland();
      }
    }, 400);

    this.islandWindow.webContents.on("did-finish-load", () => {
      if (this.activeUser) {
        this.islandWindow.webContents.send("island:user-updated", this.activeUser);
      }
      if (this.cachedChats && this.cachedChats.length > 0) {
        this.islandWindow.webContents.send("island:chats-updated", this.cachedChats);
      }
    });

    this.islandWindow.on("blur", () => {
      if (this.islandWindow && !this.islandWindow.isDestroyed()) {
        this.islandWindow.webContents.send("island:collapse");
      }
    });

    this.islandWindow.on("closed", () => {
      this.islandWindow = null;
    });

    return this.islandWindow;
  }

  resize(width, height) {
    if (!this.islandWindow || this.islandWindow.isDestroyed()) return;

    const WINDOW_CANVAS_WIDTH = 440;
    const targetWidth = WINDOW_CANVAS_WIDTH;
    const targetHeight = Math.max(Math.round(height || 52), 52);

    this.currentWidth = targetWidth;
    this.currentHeight = targetHeight;

    try {
      const primaryDisplay = screen.getPrimaryDisplay();
      const bounds = primaryDisplay.bounds;
      const fixedX = Math.round(bounds.x + (bounds.width - targetWidth) / 2);
      const offset = typeof this.settings.yOffset === "number" ? this.settings.yOffset : 0;
      const fixedY = Math.round(bounds.y + offset);

      const currentBounds = this.islandWindow.getBounds();
      // Only invoke OS setBounds if height, width, or position changed
      if (
        currentBounds.height !== targetHeight ||
        currentBounds.width !== targetWidth ||
        currentBounds.x !== fixedX ||
        currentBounds.y !== fixedY
      ) {
        this.islandWindow.setBounds({
          x: fixedX,
          y: fixedY,
          width: targetWidth,
          height: targetHeight,
        });
      }

      if (targetHeight > 60) {
        try {
          if (!this.islandWindow.isFocused()) {
            this.islandWindow.focus();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  setInteractive(interactive) {
    if (!this.islandWindow || this.islandWindow.isDestroyed()) return;
    try {
      if (interactive) {
        this.islandWindow.setIgnoreMouseEvents(false);
      } else {
        this.islandWindow.setIgnoreMouseEvents(true, { forward: true });
      }
    } catch (_) {}
  }

  showWelcome(userData = {}) {
    if (!this.settings.enabled) return;
    if (!this.islandWindow || this.islandWindow.isDestroyed()) {
      this.createIslandWindow(false);
    }
    if (this.islandWindow && !this.islandWindow.isDestroyed()) {
      if (!this.islandWindow.isVisible()) {
        this.islandWindow.show();
      }
      this.islandWindow.webContents.send(
        "island:welcome",
        userData || this.activeUser || (typeof this.getActiveUser === "function" ? this.getActiveUser() : null) || {},
      );
    }
  }

  showNotification(notificationData = {}) {
    if (!this.settings.enabled) return;
    const privacy = this.settings.privacyMode || "full";
    const safeData = { ...notificationData };

    if (privacy === "sender_only" || privacy === "hide_details") {
      safeData.body = "لديك رسالة جديدة";
    } else if (privacy === "hidden" || privacy === "sound_only") {
      safeData.senderName = "iSmart Messenger";
      safeData.title = "iSmart Messenger";
      safeData.body = "رسالة خاصة جديدة";
      safeData.avatarUrl = null;
    }

    if (safeData.conversationId && safeData.body) {
      if (!this.conversationMessagesCache) {
        this.conversationMessagesCache = new Map();
      }
      const convId = String(safeData.conversationId);
      const existing = this.conversationMessagesCache.get(convId) || [];
      const incomingMsg = {
        id: "notif_" + Date.now(),
        content: safeData.body,
        messageType: safeData.messageType || "text",
        fileName: safeData.fileName || null,
        fileUrl: safeData.fileUrl || null,
        fileSize: safeData.fileSize || null,
        senderId: safeData.senderId || "",
        senderName: safeData.senderName || safeData.title || "",
        senderAvatar: safeData.avatarUrl || null,
        createdAt: new Date().toISOString(),
        isOutgoing: false,
        isMine: false,
      };
      if (!existing.some((m) => m.content === incomingMsg.content && Math.abs(new Date(m.createdAt || 0) - new Date(incomingMsg.createdAt || 0)) < 30000)) {
        this.conversationMessagesCache.set(convId, [...existing, incomingMsg]);
      }
    }

    if (!this.islandWindow || this.islandWindow.isDestroyed()) {
      this.createIslandWindow(false);
    }
    if (this.islandWindow && !this.islandWindow.isDestroyed()) {
      if (!this.islandWindow.isVisible()) {
        this.islandWindow.show();
      }
      this.islandWindow.webContents.send("island:notification", safeData);
    }
  }

  syncAudioState(audioData = {}) {
    if (!this.settings.enabled) return;
    if (!this.islandWindow || this.islandWindow.isDestroyed()) {
      this.createIslandWindow(false);
    }
    if (this.islandWindow && !this.islandWindow.isDestroyed()) {
      if (!this.islandWindow.isVisible()) {
        this.islandWindow.show();
      }
      this.islandWindow.webContents.send("island:audio-state", audioData);
    }
  }

  syncCallState(callData = {}) {
    if (!this.settings.enabled) return;
    if (!this.islandWindow || this.islandWindow.isDestroyed()) {
      this.createIslandWindow(false);
    }
    if (this.islandWindow && !this.islandWindow.isDestroyed()) {
      if (!this.islandWindow.isVisible()) {
        this.islandWindow.show();
      }
      this.islandWindow.webContents.send("island:call-state", callData);
    }
  }

  showProgress(progressData = {}) {
    if (!this.settings.enabled) return;
    if (!this.islandWindow || this.islandWindow.isDestroyed()) {
      this.createIslandWindow(false);
    }
    if (this.islandWindow && !this.islandWindow.isDestroyed()) {
      if (!this.islandWindow.isVisible()) {
        this.islandWindow.show();
      }
      this.islandWindow.webContents.send("island:progress", progressData);
    }
  }

  syncChats(chats) {
    if (Array.isArray(chats)) {
      this.cachedChats = chats;
      if (!this.conversationMessagesCache) {
        this.conversationMessagesCache = new Map();
      }
      // Pre-seed conversation messages cache with last message for each chat
      chats.forEach((c) => {
        if (!c || !c.id) return;
        const convId = String(c.id);
        if (!this.conversationMessagesCache.has(convId) && (c.lastMessage || c.snippet)) {
          const content = c.lastMessage?.content || c.snippet || "";
          if (content) {
            this.conversationMessagesCache.set(convId, [{
              id: c.lastMessage?.id || "seed_" + (c.updatedAt || Date.now()),
              content,
              messageType: c.lastMessage?.messageType || "text",
              fileName: c.lastMessage?.fileName || null,
              fileUrl: c.lastMessage?.fileUrl || null,
              fileSize: c.lastMessage?.fileSize || null,
              senderId: c.lastMessage?.senderId || "",
              createdAt: c.lastMessage?.createdAt || c.updatedAt || new Date().toISOString(),
              isOutgoing: false,
              senderName: c.name || c.title || "",
            }]);
          }
        }
      });
      if (this.islandWindow && !this.islandWindow.isDestroyed()) {
        this.islandWindow.webContents.send("island:chats-updated", chats);
      }
    }
  }

  syncActiveUser(user) {
    if (user && typeof user === "object") {
      this.activeUser = user;
      if (user.apiBaseUrl) {
        this.apiBaseUrl = String(user.apiBaseUrl).trim().replace(/\/+$/, "");
      }
      if (user.token) {
        this.authToken = String(user.token).trim();
      }
      if (this.islandWindow && !this.islandWindow.isDestroyed()) {
        this.islandWindow.webContents.send("island:user-updated", user);
      }
    }
  }

  async fetchRecentChatsFromApi() {
    if (this.cachedChats && this.cachedChats.length > 0) {
      return this.cachedChats;
    }

    const token = this.authToken || (await this.getAuthToken());
    const baseUrl = this.apiBaseUrl || (typeof this.getApiBaseUrl === "function" ? this.getApiBaseUrl() : null);

    if (!token || !baseUrl) {
      return [];
    }

    const myId = String(
      this.activeUser?.id ||
      this.activeUser?._id ||
      this.activeUser?.userId ||
      (typeof this.getUserId === "function" ? this.getUserId() : "") ||
      ""
    );

    try {
      const parsedUrl = new URL("/api/chat/conversations", baseUrl);
      const isHttps = parsedUrl.protocol === "https:";
      const client = isHttps ? https : http;

      return await new Promise((resolve) => {
        const req = client.request(
          parsedUrl,
          {
            method: "GET",
            headers: {
              Accept: "application/json",
              Authorization: `Bearer ${token}`,
            },
            timeout: 6000,
          },
          (res) => {
            let body = "";
            res.on("data", (chunk) => (body += chunk));
            res.on("end", () => {
              try {
                const parsed = JSON.parse(body);
                const convs = parsed.data?.conversations || parsed.conversations || [];
                const formatted = convs.map((c) => {
                  let title = c.name || c.title || "";
                  let avatar = c.avatarUrl || "";
                  if (c.type === "direct" && Array.isArray(c.members)) {
                    const other = c.members.find((m) => String(m.id || m._id) !== myId) || c.members[0];
                    if (other) {
                      if (!title) title = other.displayName || other.fullName || other.name || other.username || "";
                      if (!avatar) avatar = other.avatarUrl || "";
                    }
                  }
                  if (!title) title = c.type === "direct" ? "محادثة خاصة" : (c.name || "محادثة جماعية");

                  if (avatar && !avatar.startsWith("http://") && !avatar.startsWith("https://") && !avatar.startsWith("data:")) {
                    try { avatar = new URL(avatar, baseUrl).href; } catch (_) {}
                  }

                  return {
                    ...c,
                    id: c._id || c.id,
                    name: title,
                    title: title,
                    avatarUrl: avatar,
                  };
                });
                this.cachedChats = formatted;
                resolve(formatted);
              } catch (_) {
                resolve([]);
              }
            });
          },
        );

        req.on("error", () => resolve([]));
        req.end();
      });
    } catch (_) {
      return [];
    }
  }

  async fetchConversationMessages(conversationId) {
    if (!conversationId) return [];
    const convId = String(conversationId);
    if (!this.conversationMessagesCache) {
      this.conversationMessagesCache = new Map();
    }
    const cachedMessages = this.conversationMessagesCache.get(convId) || [];

    const token = this.authToken || (await this.getAuthToken());
    const baseUrl = this.apiBaseUrl || (typeof this.getApiBaseUrl === "function" ? this.getApiBaseUrl() : null);
    if (!token || !baseUrl) return cachedMessages;

    const myId = String(
      this.activeUser?.id ||
      this.activeUser?._id ||
      this.activeUser?.userId ||
      (typeof this.getUserId === "function" ? this.getUserId() : "") ||
      ""
    );

    try {
      const parsedUrl = new URL(`/api/chat/conversations/${conversationId}/messages`, baseUrl);
      parsedUrl.searchParams.set("limit", "50");
      const isHttps = parsedUrl.protocol === "https:";
      const client = isHttps ? https : http;

      return await new Promise((resolve) => {
        const req = client.request(
          parsedUrl,
          {
            method: "GET",
            headers: {
              Accept: "application/json",
              Authorization: `Bearer ${token}`,
            },
            timeout: 8000,
          },
          (res) => {
            let body = "";
            res.on("data", (chunk) => (body += chunk));
            res.on("end", () => {
              try {
                if (res.statusCode < 200 || res.statusCode >= 300) {
                  return resolve(cachedMessages);
                }
                const parsed = JSON.parse(body);
                const msgs = parsed.data?.messages || parsed.messages || (Array.isArray(parsed.data) ? parsed.data : []);
                if (!Array.isArray(msgs) || msgs.length === 0) {
                  return resolve(cachedMessages);
                }
                const formatted = msgs.map((m) => {
                  const sId = String(m.senderId || m.sender?.id || m.sender?._id || "");
                  const isMine = Boolean(
                    m.isOutgoing ||
                    m.isMine ||
                    (myId && sId && sId === myId)
                  );

                  let fileUrl = m.fileUrl || null;
                  if (fileUrl && typeof fileUrl === "string" && !fileUrl.startsWith("http://") && !fileUrl.startsWith("https://") && !fileUrl.startsWith("data:")) {
                    try { fileUrl = new URL(fileUrl, baseUrl).href; } catch (_) {}
                  }

                  return {
                    id: m.id || m._id,
                    content: m.content || m.text || "",
                    messageType: m.messageType || "text",
                    fileName: m.fileName || null,
                    fileUrl: fileUrl,
                    fileSize: m.fileSize || 0,
                    mimeType: m.mimeType || null,
                    senderId: sId,
                    senderName: m.sender?.displayName || m.sender?.fullName || m.sender?.name || "",
                    senderAvatar: m.sender?.avatarUrl || null,
                    createdAt: m.createdAt,
                    isOutgoing: isMine,
                    isMine: isMine,
                  };
                });

                // Merge fetched messages with local pending/sent messages from cache
                const localPending = cachedMessages.filter((m) =>
                  String(m.id).startsWith("client_") || String(m.id).startsWith("temp_")
                );
                const merged = [...formatted];
                for (const pending of localPending) {
                  if (!merged.some((m) => m.content === pending.content && Math.abs(new Date(m.createdAt || 0) - new Date(pending.createdAt || 0)) < 60000)) {
                    merged.push(pending);
                  }
                }
                merged.sort((a, b) => new Date(a.createdAt || 0) - new Date(b.createdAt || 0));

                this.conversationMessagesCache.set(convId, merged);
                resolve(merged);
              } catch (_) {
                resolve(cachedMessages);
              }
            });
          },
        );

        req.on("error", () => resolve(cachedMessages));
        req.end();
      });
    } catch (_) {
      return cachedMessages;
    }
  }

  async sendReply(payload = {}) {
    const { conversationId, content } = payload;
    if (!conversationId || !content) {
      return { success: false, error: "بيانات الرد غير مكتملة." };
    }

    const convId = String(conversationId);
    if (!this.conversationMessagesCache) {
      this.conversationMessagesCache = new Map();
    }
    const myId = String(
      this.activeUser?.id ||
      this.activeUser?._id ||
      this.activeUser?.userId ||
      (typeof this.getUserId === "function" ? this.getUserId() : "") ||
      ""
    );
    const existing = this.conversationMessagesCache.get(convId) || [];
    const clientMsg = {
      id: "client_" + Date.now(),
      content: content,
      messageType: "text",
      fileName: null,
      fileUrl: null,
      fileSize: 0,
      mimeType: null,
      senderId: myId,
      senderName: this.activeUser?.displayName || this.activeUser?.fullName || this.activeUser?.name || "أنا",
      senderAvatar: this.activeUser?.avatarUrl || null,
      createdAt: new Date().toISOString(),
      isOutgoing: true,
      isMine: true,
    };
    this.conversationMessagesCache.set(convId, [...existing, clientMsg]);

    // Also update cachedChats snippet if exists
    if (Array.isArray(this.cachedChats)) {
      const targetChat = this.cachedChats.find((c) => String(c.id) === convId);
      if (targetChat) {
        targetChat.snippet = content;
        targetChat.lastMessage = {
          id: clientMsg.id,
          content: content,
          messageType: "text",
          createdAt: clientMsg.createdAt,
          isOutgoing: true,
        };
        targetChat.updatedAt = clientMsg.createdAt;
      }
    }

    // 1. Notify mainWindow to send message via live session
    if (this.mainWindow && !this.mainWindow.isDestroyed()) {
      this.mainWindow.webContents.send("island:quick-reply", {
        conversationId,
        content,
      });
    }

    // 2. Direct API request fallback
    const token = this.authToken || (await this.getAuthToken());
    const baseUrl = this.apiBaseUrl || (typeof this.getApiBaseUrl === "function" ? this.getApiBaseUrl() : null);

    if (token && baseUrl) {
      try {
        const postData = JSON.stringify({
          conversationId,
          content,
          messageType: "text",
        });

        const parsedUrl = new URL("/api/chat/messages", baseUrl);
        const isHttps = parsedUrl.protocol === "https:";
        const client = isHttps ? https : http;

        return await new Promise((resolve) => {
          const req = client.request(
            parsedUrl,
            {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                "Content-Length": Buffer.byteLength(postData),
                Authorization: `Bearer ${token}`,
              },
              timeout: 10000,
            },
            (res) => {
              let body = "";
              res.on("data", (chunk) => (body += chunk));
              res.on("end", () => {
                if (res.statusCode >= 200 && res.statusCode < 300) {
                  resolve({ success: true });
                } else {
                  resolve({
                    success: false,
                    error: `فشل الإرسال (${res.statusCode})`,
                  });
                }
              });
            },
          );

          req.on("error", (err) => {
            resolve({ success: false, error: err.message || "خطأ في الشبكة" });
          });

          req.write(postData);
          req.end();
        });
      } catch (err) {
        return { success: false, error: err.message };
      }
    }

    return { success: true, queued: true };
  }

  
  async fallbackFetchBuffer(targetUrl, headers = {}) {
    return await new Promise((resolve, reject) => {
      let parsed;
      try { parsed = new URL(targetUrl); } catch (e) { return reject(e); }
      const isHttps = parsed.protocol === "https:";
      const client = isHttps ? https : http;
      const req = client.request(
        parsed,
        {
          method: "GET",
          headers: {
            Accept: "image/*,*/*;q=0.8",
            ...headers,
          },
          timeout: 15000,
        },
        (res) => {
          if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
            const redirectUrl = new URL(res.headers.location, parsed).toString();
            return this.fallbackFetchBuffer(redirectUrl, headers).then(resolve).catch(reject);
          }
          if (res.statusCode < 200 || res.statusCode >= 300) {
            const err = new Error("Request failed with status " + res.statusCode);
            err.statusCode = res.statusCode;
            return reject(err);
          }
          const chunks = [];
          res.on("data", (c) => chunks.push(c));
          res.on("end", () => {
            resolve({
              buffer: Buffer.concat(chunks),
              contentType: res.headers["content-type"] || "image/png",
            });
          });
        }
      );
      req.on("error", reject);
      req.end();
    });
  }

  async fetchMediaBase64(targetUrl) {
    if (!targetUrl || typeof targetUrl !== "string") {
      return { success: false, message: "No URL" };
    }
    const token = this.authToken || (await this.getAuthToken());
    const baseUrl = this.apiBaseUrl || (typeof this.getApiBaseUrl === "function" ? this.getApiBaseUrl() : null);
    let fullUrl = targetUrl.trim();
    if (!fullUrl.startsWith("http://") && !fullUrl.startsWith("https://") && baseUrl) {
      try {
        fullUrl = new URL(fullUrl, baseUrl).href;
      } catch (_) {}
    }

    if (this._mediaBase64Cache && this._mediaBase64Cache.has(fullUrl)) {
      return this._mediaBase64Cache.get(fullUrl);
    }

    const headers = {};
    if (token) {
      headers["Authorization"] = "Bearer " + token;
    }

    try {
      let result;
      if (typeof this.fetchUrlBuffer === "function") {
        result = await this.fetchUrlBuffer(fullUrl, headers);
      } else {
        result = await this.fallbackFetchBuffer(fullUrl, headers);
      }

      if (result && result.buffer) {
        const mime = (result.contentType || "image/png").split(";")[0].trim();
        const b64 = result.buffer.toString("base64");
        const payload = {
          success: true,
          dataUri: "data:" + mime + ";base64," + b64,
          contentType: mime,
        };
        if (!this._mediaBase64Cache) this._mediaBase64Cache = new Map();
        if (this._mediaBase64Cache.size > 150) {
          const firstKey = this._mediaBase64Cache.keys().next().value;
          this._mediaBase64Cache.delete(firstKey);
        }
        this._mediaBase64Cache.set(fullUrl, payload);
        return payload;
      }
      return { success: false, message: "Empty result" };
    } catch (err) {
      return { success: false, message: err.message, statusCode: err.statusCode || 500 };
    }
  }

  async openMedia(payload) {
    const conversationId = payload?.conversationId;
    if (conversationId && typeof this.onOpenConversation === "function") {
      this.onOpenConversation(conversationId);
      return true;
    }
    if (typeof this.onShowMainWindow === "function") {
      this.onShowMainWindow();
      return true;
    }
    return true;
  }

  registerIpcHandlers() {
    ipcMain.handle("island:get-settings", () => this.settings);
    ipcMain.handle("island:save-settings", (_event, newSettings) =>
      this.saveSettings(newSettings),
    );
    ipcMain.handle("island:get-recent-chats", async () => {
      return this.fetchRecentChatsFromApi();
    });

    ipcMain.handle("island:fetch-media", async (_event, targetUrl) => {
      return await this.fetchMediaBase64(targetUrl);
    });

    ipcMain.handle("island:open-media", async (_event, payload) => {
      return await this.openMedia(payload);
    });

    ipcMain.handle("island:open-external", async (_event, url) => {
      if (url && typeof url === "string") {
        try {
          await shell.openExternal(url);
          return { success: true };
        } catch (e) {
          return { success: false, error: e.message };
        }
      }
      return { success: false };
    });

    ipcMain.handle("island:get-conversation-messages", async (_event, conversationId) => {
      return this.fetchConversationMessages(conversationId);
    });

    ipcMain.handle("island:sync-audio", (_event, audioData) => {
      this.syncAudioState(audioData);
      return { success: true };
    });

    ipcMain.handle("island:sync-call", (_event, callData) => {
      this.syncCallState(callData);
      return { success: true };
    });

    ipcMain.handle("island:toggle-audio", () => {
      if (this.mainWindow && !this.mainWindow.isDestroyed()) {
        this.mainWindow.webContents.send("island:toggle-audio");
      }
      return { success: true };
    });

    ipcMain.handle("island:stop-audio", () => {
      if (this.mainWindow && !this.mainWindow.isDestroyed()) {
        this.mainWindow.webContents.send("island:stop-audio");
      }
      return { success: true };
    });

    ipcMain.handle("island:set-audio-speed", (_event, speed) => {
      if (this.mainWindow && !this.mainWindow.isDestroyed()) {
        this.mainWindow.webContents.send("island:set-audio-speed", speed);
      }
      return { success: true };
    });

    ipcMain.handle("island:seek-audio", (_event, position) => {
      if (this.mainWindow && !this.mainWindow.isDestroyed()) {
        this.mainWindow.webContents.send("island:seek-audio", position);
      }
      return { success: true };
    });

    ipcMain.handle("island:accept-call", (_event, callId) => {
      if (this.mainWindow && !this.mainWindow.isDestroyed()) {
        this.mainWindow.webContents.send("island:accept-call", callId);
      }
      return { success: true };
    });

    ipcMain.handle("island:decline-call", (_event, callId) => {
      if (this.mainWindow && !this.mainWindow.isDestroyed()) {
        this.mainWindow.webContents.send("island:decline-call", callId);
      }
      return { success: true };
    });

    ipcMain.handle("island:resize", (_event, { width, height }) => {
      this.resize(width, height);
      return { success: true };
    });

    ipcMain.on("island:set-interactive", (_event, interactive) => {
      this.setInteractive(interactive);
    });

    ipcMain.handle("island:open-conversation", (_event, conversationId) => {
      this.onOpenConversation(conversationId);
      return { success: true };
    });

    ipcMain.handle("island:show-main-window", () => {
      this.onShowMainWindow();
      return { success: true };
    });

    ipcMain.handle("island:toggle-main-window", () => {
      this.onToggleMainWindow();
      return { success: true };
    });

    ipcMain.handle("island:send-reply", async (_event, payload) => {
      return this.sendReply(payload);
    });

    ipcMain.handle("island:test-notification", () => {
      this.showNotification({
        title: "مهندس يوسف (تجربة)",
        senderName: "مهندس يوسف",
        body: "السلام عليكم! الجزيرة التفاعلية تعمل الآن بنجاح على الويندوز ✨",
        conversationId: "test_conv",
      });
      return { success: true };
    });

    ipcMain.handle("island:close", () => {
      if (this.islandWindow && !this.islandWindow.isDestroyed()) {
        this.islandWindow.hide();
      }
      return { success: true };
    });

    // Renderer (Flutter / Web) can push chats or user to Island
    ipcMain.handle("island:sync-chats", (_event, chats) => {
      this.syncChats(chats);
      return { success: true };
    });

    ipcMain.handle("island:sync-user", (_event, user) => {
      this.syncActiveUser(user);
      return { success: true };
    });

    ipcMain.handle("island:get-active-user", () => {
      return this.activeUser || null;
    });

    ipcMain.handle("island:trigger-welcome", (_event, userData) => {
      this.showWelcome(userData);
      return { success: true };
    });

    ipcMain.handle("island:trigger-progress", (_event, progressData) => {
      this.showProgress(progressData);
      return { success: true };
    });
  }
}

module.exports = { DynamicIslandManager };

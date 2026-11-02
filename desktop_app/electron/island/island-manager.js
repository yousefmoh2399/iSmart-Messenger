/**
 * iSmart Dynamic Island Manager
 * Manages floating window lifecycle, multi-monitor alignment,
 * settings, API synchronization, and IPC communication.
 * Highly optimized for Windows 7 (32-bit), 10, and 11.
 */

const { BrowserWindow, screen, ipcMain, app } = require("electron");
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
    this.getAuthToken = options.getAuthToken || (() => null);
    this.getApiBaseUrl = options.getApiBaseUrl || (() => "http://127.0.0.1:3000");
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
      yOffset: 10,
    };
    try {
      const file = this.settingsFilePath();
      if (fs.existsSync(file)) {
        const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
        const isOurConfig = parsed.theme !== undefined || parsed.privacyMode !== undefined;
        const enabled = isOurConfig && typeof parsed.enabled === "boolean" ? parsed.enabled : true;
        return { ...defaults, ...parsed, enabled };
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
      this.resize(this.currentWidth || 260, this.currentHeight || 42);
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
    const initialWidth = 260;
    const initialHeight = 42;
    this.currentWidth = initialWidth;
    this.currentHeight = initialHeight;

    const x = Math.round(bounds.x + (bounds.width - initialWidth) / 2);
    const y = Math.round(bounds.y + (this.settings.yOffset || 10));

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

    this.islandWindow.on("closed", () => {
      this.islandWindow = null;
    });

    return this.islandWindow;
  }

  resize(width, height) {
    if (!this.islandWindow || this.islandWindow.isDestroyed()) return;

    this.currentWidth = width;
    this.currentHeight = height;

    try {
      const primaryDisplay = screen.getPrimaryDisplay();
      const bounds = primaryDisplay.bounds;
      const newX = Math.round(bounds.x + (bounds.width - width) / 2);
      const newY = Math.round(bounds.y + (this.settings.yOffset || 10));

      this.islandWindow.setBounds({
        x: newX,
        y: newY,
        width: Math.round(width),
        height: Math.round(height),
      });

      try {
        this.islandWindow.setAlwaysOnTop(true, "screen-saver");
      } catch (_) {
        try { this.islandWindow.setAlwaysOnTop(true); } catch (__) {}
      }
      this.islandWindow.moveTop();
    } catch (_) {}
  }

  setInteractive(_interactive) {
    // Window bounds strictly fit the capsule, so all clicks on the capsule
    // hit naturally, while clicks outside hit the desktop!
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
        userData || this.activeUser || {},
      );
    }
  }

  showNotification(notificationData = {}) {
    if (!this.settings.enabled) return;
    if (!this.islandWindow || this.islandWindow.isDestroyed()) {
      this.createIslandWindow(false);
    }
    if (this.islandWindow && !this.islandWindow.isDestroyed()) {
      if (!this.islandWindow.isVisible()) {
        this.islandWindow.show();
      }
      this.islandWindow.webContents.send("island:notification", notificationData);
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
      if (this.islandWindow && !this.islandWindow.isDestroyed()) {
        this.islandWindow.webContents.send("island:chats-updated", chats);
      }
    }
  }

  syncActiveUser(user) {
    if (user && typeof user === "object") {
      this.activeUser = user;
      if (this.islandWindow && !this.islandWindow.isDestroyed()) {
        this.islandWindow.webContents.send("island:user-updated", user);
      }
    }
  }

  async fetchRecentChatsFromApi() {
    if (this.cachedChats && this.cachedChats.length > 0) {
      return this.cachedChats;
    }

    const token = await this.getAuthToken();
    const baseUrl = this.getApiBaseUrl();

    if (!token || !baseUrl) {
      return [];
    }

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
                this.cachedChats = convs;
                resolve(convs);
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

  async sendReply(payload = {}) {
    const { conversationId, content } = payload;
    if (!conversationId || !content) {
      return { success: false, error: "بيانات الرد غير مكتملة." };
    }

    // 1. Notify mainWindow to send message via live session
    if (this.mainWindow && !this.mainWindow.isDestroyed()) {
      this.mainWindow.webContents.send("island:quick-reply", {
        conversationId,
        content,
      });
    }

    // 2. Direct API request fallback
    const token = await this.getAuthToken();
    const baseUrl = this.getApiBaseUrl();

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

    return { success: true };
  }

  registerIpcHandlers() {
    ipcMain.handle("island:get-settings", () => this.settings);
    ipcMain.handle("island:save-settings", (_event, newSettings) =>
      this.saveSettings(newSettings),
    );
    ipcMain.handle("island:get-recent-chats", async () => {
      return this.fetchRecentChatsFromApi();
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

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("islandBridge", {
  // Listeners from Main Process
  onNotification: (callback) => {
    const handler = (_event, data) => callback(data);
    ipcRenderer.on("island:notification", handler);
    return () => ipcRenderer.removeListener("island:notification", handler);
  },
  onWelcome: (callback) => {
    const handler = (_event, data) => callback(data);
    ipcRenderer.on("island:welcome", handler);
    return () => ipcRenderer.removeListener("island:welcome", handler);
  },
  onProgress: (callback) => {
    const handler = (_event, data) => callback(data);
    ipcRenderer.on("island:progress", handler);
    return () => ipcRenderer.removeListener("island:progress", handler);
  },
  onChatsUpdated: (callback) => {
    const handler = (_event, data) => callback(data);
    ipcRenderer.on("island:chats-updated", handler);
    return () => ipcRenderer.removeListener("island:chats-updated", handler);
  },
  onSettingsUpdated: (callback) => {
    const handler = (_event, data) => callback(data);
    ipcRenderer.on("island:settings-updated", handler);
    return () => ipcRenderer.removeListener("island:settings-updated", handler);
  },
  onActiveUserUpdated: (callback) => {
    const handler = (_event, data) => callback(data);
    ipcRenderer.on("island:user-updated", handler);
    return () => ipcRenderer.removeListener("island:user-updated", handler);
  },

  // Actions to Main Process
  sendReply: (payload) => ipcRenderer.invoke("island:send-reply", payload),
  openConversation: (conversationId) => ipcRenderer.invoke("island:open-conversation", conversationId),
  showMainWindow: () => ipcRenderer.invoke("island:show-main-window"),
  toggleMainWindow: () => ipcRenderer.invoke("island:toggle-main-window"),
  getRecentChats: () => ipcRenderer.invoke("island:get-recent-chats"),
  getSettings: () => ipcRenderer.invoke("island:get-settings"),
  saveSettings: (settings) => ipcRenderer.invoke("island:save-settings", settings),
  resizeWindow: (width, height) => ipcRenderer.invoke("island:resize", { width, height }),
  setInteractive: (interactive) => ipcRenderer.send("island:set-interactive", interactive),
  closeIsland: () => ipcRenderer.invoke("island:close"),
});

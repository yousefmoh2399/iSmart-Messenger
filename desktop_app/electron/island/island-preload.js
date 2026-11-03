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
  onAudioState: (callback) => {
    const handler = (_event, data) => callback(data);
    ipcRenderer.on("island:audio-state", handler);
    return () => ipcRenderer.removeListener("island:audio-state", handler);
  },
  onCallState: (callback) => {
    const handler = (_event, data) => callback(data);
    ipcRenderer.on("island:call-state", handler);
    return () => ipcRenderer.removeListener("island:call-state", handler);
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
  onCollapseRequested: (callback) => {
    const handler = () => callback();
    ipcRenderer.on("island:collapse", handler);
    return () => ipcRenderer.removeListener("island:collapse", handler);
  },

  // Actions to Main Process
  sendReply: (payload) => ipcRenderer.invoke("island:send-reply", payload),
  openConversation: (conversationId) => ipcRenderer.invoke("island:open-conversation", conversationId),
  showMainWindow: () => ipcRenderer.invoke("island:show-main-window"),
  toggleMainWindow: () => ipcRenderer.invoke("island:toggle-main-window"),
  getRecentChats: () => ipcRenderer.invoke("island:get-recent-chats"),
  getConversationMessages: (conversationId) => ipcRenderer.invoke("island:get-conversation-messages", conversationId),
  fetchMedia: (url) => ipcRenderer.invoke("island:fetch-media", url),
  openMedia: (payload) => ipcRenderer.invoke("island:open-media", payload),
  toggleAudio: () => ipcRenderer.invoke("island:toggle-audio"),
  stopAudio: () => ipcRenderer.invoke("island:stop-audio"),
  setAudioSpeed: (speed) => ipcRenderer.invoke("island:set-audio-speed", speed),
  seekAudio: (position) => ipcRenderer.invoke("island:seek-audio", position),
  acceptCall: (callId) => ipcRenderer.invoke("island:accept-call", callId),
  declineCall: (callId) => ipcRenderer.invoke("island:decline-call", callId),
  getSettings: () => ipcRenderer.invoke("island:get-settings"),
  saveSettings: (settings) => ipcRenderer.invoke("island:save-settings", settings),
  getActiveUser: () => ipcRenderer.invoke("island:get-active-user"),
  resizeWindow: (width, height) => ipcRenderer.invoke("island:resize", { width, height }),
  setInteractive: (interactive) => ipcRenderer.send("island:set-interactive", interactive),
  openExternal: (url) => ipcRenderer.invoke("island:open-external", url),
  closeIsland: () => ipcRenderer.invoke("island:close"),
});

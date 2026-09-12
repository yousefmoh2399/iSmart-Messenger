const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("receiveBridge", {
  decide: (channel, decision) => ipcRenderer.send(String(channel), String(decision || "")),
});

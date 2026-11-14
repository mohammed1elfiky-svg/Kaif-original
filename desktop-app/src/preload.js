'use strict';

// Gives the app's own pages (setup, offline) access to the settings. Pages of the server get nothing:
// the API is exposed only on file:// pages, and the main process also checks the sender.
const { contextBridge, ipcRenderer } = require('electron');

if (location.protocol === 'file:') {
  contextBridge.exposeInMainWorld('kaif', {
    getServer: () => ipcRenderer.invoke('kaif:get-server'),
    saveServer: (url, force) => ipcRenderer.invoke('kaif:save-server', url, !!force),
    retry: () => ipcRenderer.invoke('kaif:retry'),
    changeServer: () => ipcRenderer.invoke('kaif:change-server'),
  });
}

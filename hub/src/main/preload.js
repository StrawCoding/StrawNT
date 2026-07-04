const { contextBridge, ipcRenderer } = require('electron');

const IPC_CHANNELS = {
  GET_STATUS: 'runtime:get-status',
  GET_LOGS: 'runtime:get-logs',
  SET_UPDATE_CHANNEL: 'runtime:set-update-channel',
  GET_UPDATE_CHANNEL: 'runtime:get-update-channel',
  STATUS_UPDATE: 'runtime:status-update',
  LOG_ENTRY: 'runtime:log-entry',
};

contextBridge.exposeInMainWorld('strawwuHub', {
  getStatus: () => ipcRenderer.invoke(IPC_CHANNELS.GET_STATUS),
  getLogs: (subsystem) => ipcRenderer.invoke(IPC_CHANNELS.GET_LOGS, subsystem),
  getUpdateChannel: () => ipcRenderer.invoke(IPC_CHANNELS.GET_UPDATE_CHANNEL),
  setUpdateChannel: (ch) => ipcRenderer.invoke(IPC_CHANNELS.SET_UPDATE_CHANNEL, ch),

  onStatusUpdate: (callback) => {
    const handler = (_event, data) => callback(data);
    ipcRenderer.on(IPC_CHANNELS.STATUS_UPDATE, handler);
    return () => ipcRenderer.removeListener(IPC_CHANNELS.STATUS_UPDATE, handler);
  },

  onLogEntry: (callback) => {
    const handler = (_event, data) => callback(data);
    ipcRenderer.on(IPC_CHANNELS.LOG_ENTRY, handler);
    return () => ipcRenderer.removeListener(IPC_CHANNELS.LOG_ENTRY, handler);
  },
});

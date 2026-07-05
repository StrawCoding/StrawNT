const { contextBridge, ipcRenderer } = require('electron');

const IPC_CHANNELS = {
  GET_STATUS: 'runtime:get-status',
  GET_LOGS: 'runtime:get-logs',
  SET_UPDATE_CHANNEL: 'runtime:set-update-channel',
  GET_UPDATE_CHANNEL: 'runtime:get-update-channel',
  STATUS_UPDATE: 'runtime:status-update',
  LOG_ENTRY: 'runtime:log-entry',
  GET_I18N: 'i18n:get',
  SET_LOCALE: 'i18n:set-locale',
  GET_ABOUT: 'settings:get-about',
  GET_WINCOMPAT: 'settings:get-wincompat',
  GET_SYSTEM_SHORTCUTS: 'settings:get-system-shortcuts',
  OPEN_LEGAL: 'settings:open-legal',
  LAUNCH_BUG_REPORT: 'settings:launch-bug-report',
  OPEN_DESKTOP_SHORTCUT: 'settings:open-desktop-shortcut',
  GET_APPS: 'apps:get-list',
  PREVIEW_REMOVE_APP: 'apps:preview-remove',
  REMOVE_APP: 'apps:remove',
  SEARCH_FLATHUB: 'flathub:search',
  GET_FLATHUB_STATUS: 'flathub:get-status',
  INSTALL_FLATHUB: 'flathub:install',
};

contextBridge.exposeInMainWorld('strawwuHub', {
  getStatus: () => ipcRenderer.invoke(IPC_CHANNELS.GET_STATUS),
  getLogs: (subsystem) => ipcRenderer.invoke(IPC_CHANNELS.GET_LOGS, subsystem),
  getUpdateChannel: () => ipcRenderer.invoke(IPC_CHANNELS.GET_UPDATE_CHANNEL),
  setUpdateChannel: (ch) => ipcRenderer.invoke(IPC_CHANNELS.SET_UPDATE_CHANNEL, ch),
  getI18n: () => ipcRenderer.invoke(IPC_CHANNELS.GET_I18N),
  setLocale: (locale) => ipcRenderer.invoke(IPC_CHANNELS.SET_LOCALE, locale),
  getAbout: () => ipcRenderer.invoke(IPC_CHANNELS.GET_ABOUT),
  getWinCompat: () => ipcRenderer.invoke(IPC_CHANNELS.GET_WINCOMPAT),
  getSystemShortcuts: () => ipcRenderer.invoke(IPC_CHANNELS.GET_SYSTEM_SHORTCUTS),
  openLegal: (docId) => ipcRenderer.invoke(IPC_CHANNELS.OPEN_LEGAL, docId),
  launchBugReport: () => ipcRenderer.invoke(IPC_CHANNELS.LAUNCH_BUG_REPORT),
  openDesktopShortcut: (desktop) => ipcRenderer.invoke(IPC_CHANNELS.OPEN_DESKTOP_SHORTCUT, desktop),
  getApps: () => ipcRenderer.invoke(IPC_CHANNELS.GET_APPS),
  previewRemoveApp: (id) => ipcRenderer.invoke(IPC_CHANNELS.PREVIEW_REMOVE_APP, id),
  removeApp: (id) => ipcRenderer.invoke(IPC_CHANNELS.REMOVE_APP, id),
  searchFlathub: (query) => ipcRenderer.invoke(IPC_CHANNELS.SEARCH_FLATHUB, query),
  getFlathubStatus: () => ipcRenderer.invoke(IPC_CHANNELS.GET_FLATHUB_STATUS),
  installFlathub: (appId) => ipcRenderer.invoke(IPC_CHANNELS.INSTALL_FLATHUB, appId),

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

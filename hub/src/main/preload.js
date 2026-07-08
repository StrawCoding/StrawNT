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
  GET_DRIVERS_STATUS: 'drivers:get-status',
  LIST_DRIVERS: 'drivers:list',
  INSTALL_DRIVER: 'drivers:install',
  GET_DEVICE_PROXY_STATUS: 'device-proxy:get-status',
  GET_SOFTWARE_SOURCES_STATUS: 'software-sources:get-status',
  TOGGLE_SOFTWARE_SOURCE: 'software-sources:toggle',
  CHECK_SOFTWARE_UPDATES: 'software-sources:check-updates',
  GET_BACKUP_STATUS: 'backup:get-status',
  LIST_BACKUP_SNAPSHOTS: 'backup:list-snapshots',
  CREATE_BACKUP_SNAPSHOT: 'backup:create-snapshot',
  PREVIEW_BACKUP_RESTORE: 'backup:preview-restore',
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
  getDriversStatus: () => ipcRenderer.invoke(IPC_CHANNELS.GET_DRIVERS_STATUS),
  listDrivers: () => ipcRenderer.invoke(IPC_CHANNELS.LIST_DRIVERS),
  installDriver: (packageName) => ipcRenderer.invoke(IPC_CHANNELS.INSTALL_DRIVER, packageName),
  getDeviceProxyStatus: () => ipcRenderer.invoke(IPC_CHANNELS.GET_DEVICE_PROXY_STATUS),
  getSoftwareSourcesStatus: () => ipcRenderer.invoke(IPC_CHANNELS.GET_SOFTWARE_SOURCES_STATUS),
  toggleSoftwareSource: (sourceId, enabled) =>
    ipcRenderer.invoke(IPC_CHANNELS.TOGGLE_SOFTWARE_SOURCE, sourceId, enabled),
  checkSoftwareUpdates: () => ipcRenderer.invoke(IPC_CHANNELS.CHECK_SOFTWARE_UPDATES),
  getBackupStatus: () => ipcRenderer.invoke(IPC_CHANNELS.GET_BACKUP_STATUS),
  listBackupSnapshots: () => ipcRenderer.invoke(IPC_CHANNELS.LIST_BACKUP_SNAPSHOTS),
  createBackupSnapshot: (label) => ipcRenderer.invoke(IPC_CHANNELS.CREATE_BACKUP_SNAPSHOT, label),
  previewBackupRestore: (name) => ipcRenderer.invoke(IPC_CHANNELS.PREVIEW_BACKUP_RESTORE, name),

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

const { app, BrowserWindow, ipcMain, nativeTheme, shell } = require('electron');
const path = require('path');
const RuntimeClient = require('./runtime-client');
const settingsService = require('./settings-service');
const appRegistryService = require('./app-registry-service');
const flathubService = require('./flathub-service');
const driversService = require('./drivers-service');
const deviceProxyService = require('./device-proxy-service');
const softwareSourcesService = require('./software-sources-service');
const backupService = require('./backup-service');
const i18n = require('../common/i18n');
const { IPC_CHANNELS, UPDATE_CHANNELS } = require('../common/constants');

let mainWindow = null;
let runtimeClient = null;
let currentChannel = 'stable';

function createWindow(initialTab) {
  nativeTheme.themeSource = 'dark';

  mainWindow = new BrowserWindow({
    width: 960,
    height: 680,
    minWidth: 720,
    minHeight: 520,
    backgroundColor: '#0A0E14',
    title: 'StrawNT Hub',
    icon: path.join(__dirname, '..', '..', 'assets', 'icon.png'),
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      // Sandbox the renderer: the preload only requires 'electron', so it works
      // under the sandbox and gains OS-level process isolation.
      sandbox: true,
    },
  });

  const htmlPath = path.join(__dirname, '..', 'renderer', 'index.html');
  if (initialTab) {
    mainWindow.loadFile(htmlPath, { query: { tab: initialTab } });
  } else {
    mainWindow.loadFile(htmlPath);
  }

  // Navigation guards: this is a single local-file UI. Block any in-page
  // navigation away from the bundled renderer and route new-window requests to
  // the external browser instead of spawning uncontrolled Electron windows.
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (url !== mainWindow.webContents.getURL()) {
      event.preventDefault();
    }
  });
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:\/\//i.test(url)) {
      shell.openExternal(url);
    }
    return { action: 'deny' };
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

function setupRuntimeClient() {
  runtimeClient = new RuntimeClient();

  runtimeClient.on('message', (msg) => {
    if (!mainWindow) return;
    if (msg.topic === 'status') {
      mainWindow.webContents.send(IPC_CHANNELS.STATUS_UPDATE, msg.data);
    } else if (msg.topic === 'logs') {
      mainWindow.webContents.send(IPC_CHANNELS.LOG_ENTRY, msg.data);
    }
  });

  runtimeClient.on('error', () => {
    // Socket not available — use mock data mode
  });

  try {
    runtimeClient.connect();
  } catch {
    // runtime not running, mock mode
  }
}

// Validate a renderer-supplied string argument at the IPC boundary before it
// reaches services that shell out or touch the filesystem. Rejects non-strings,
// empty values, and absurdly long input.
function asString(value, name, { maxLen = 512 } = {}) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`invalid ${name}: expected non-empty string`);
  }
  if (value.length > maxLen) {
    throw new Error(`invalid ${name}: too long`);
  }
  return value;
}

function setupIpcHandlers() {
  ipcMain.handle(IPC_CHANNELS.GET_STATUS, async () => {
    if (runtimeClient && runtimeClient.connected) {
      runtimeClient.requestStatus();
      return null;
    }
    return runtimeClient.getMockStatus();
  });

  ipcMain.handle(IPC_CHANNELS.GET_LOGS, async (_event, subsystem) => {
    if (runtimeClient && runtimeClient.connected) {
      runtimeClient.requestLogs(subsystem);
      return null;
    }
    return runtimeClient.getMockLogs(subsystem);
  });

  ipcMain.handle(IPC_CHANNELS.GET_UPDATE_CHANNEL, async () => {
    return currentChannel;
  });

  ipcMain.handle(IPC_CHANNELS.SET_UPDATE_CHANNEL, async (_event, channel) => {
    if (!UPDATE_CHANNELS.includes(channel)) {
      throw new Error(`Invalid channel: ${channel}`);
    }
    currentChannel = channel;
    if (runtimeClient && runtimeClient.connected) {
      runtimeClient.setUpdateChannel(channel);
    }
    return currentChannel;
  });

  ipcMain.handle(IPC_CHANNELS.GET_I18N, async () => {
    return {
      currentLocale: i18n.getLocale(),
      locales: i18n.getAvailableLocales(),
      translations: i18n.loadTranslationsForRenderer(i18n.getLocale()),
    };
  });

  ipcMain.handle(IPC_CHANNELS.SET_LOCALE, async (_event, locale) => {
    asString(locale, 'locale', { maxLen: 32 });
    i18n.setLocale(locale);
    const translations = i18n.loadTranslationsForRenderer(locale);
    return { locale, translations };
  });

  ipcMain.handle(IPC_CHANNELS.GET_ABOUT, async () => settingsService.getAboutInfo());
  ipcMain.handle(IPC_CHANNELS.GET_WINCOMPAT, async () => settingsService.getWinCompatInfo());
  ipcMain.handle(IPC_CHANNELS.GET_SYSTEM_SHORTCUTS, async () => settingsService.getSystemShortcuts());
  ipcMain.handle(IPC_CHANNELS.OPEN_LEGAL, async (_event, docId) =>
    settingsService.openLegalDoc(asString(docId, 'docId', { maxLen: 128 })),
  );
  ipcMain.handle(IPC_CHANNELS.LAUNCH_BUG_REPORT, async () => settingsService.launchBugReporter(true));
  ipcMain.handle(IPC_CHANNELS.OPEN_DESKTOP_SHORTCUT, async (_event, desktopFile) =>
    settingsService.openDesktopShortcut(asString(desktopFile, 'desktopFile')),
  );
  ipcMain.handle(IPC_CHANNELS.GET_APPS, async () => appRegistryService.listApps());
  ipcMain.handle(IPC_CHANNELS.PREVIEW_REMOVE_APP, async (_event, id) =>
    appRegistryService.previewRemoveApp(asString(id, 'appId', { maxLen: 256 })),
  );
  ipcMain.handle(IPC_CHANNELS.REMOVE_APP, async (_event, id) =>
    appRegistryService.removeApp(asString(id, 'appId', { maxLen: 256 })),
  );
  ipcMain.handle(IPC_CHANNELS.SEARCH_FLATHUB, async (_event, query) =>
    flathubService.searchCatalog(asString(query, 'query', { maxLen: 256 })),
  );
  ipcMain.handle(IPC_CHANNELS.GET_FLATHUB_STATUS, async () => flathubService.getFlathubStatus());
  ipcMain.handle(IPC_CHANNELS.INSTALL_FLATHUB, async (_event, appId) =>
    flathubService.installApp(asString(appId, 'appId', { maxLen: 256 })),
  );
  ipcMain.handle(IPC_CHANNELS.GET_DRIVERS_STATUS, async () => driversService.getDriverStatus());
  ipcMain.handle(IPC_CHANNELS.LIST_DRIVERS, async () => driversService.listDrivers());
  ipcMain.handle(IPC_CHANNELS.INSTALL_DRIVER, async (_event, packageName) =>
    driversService.installDriver(asString(packageName, 'packageName', { maxLen: 256 })),
  );
  ipcMain.handle(IPC_CHANNELS.GET_DEVICE_PROXY_STATUS, async () =>
    deviceProxyService.getDeviceProxyStatus(),
  );
  ipcMain.handle(IPC_CHANNELS.GET_SOFTWARE_SOURCES_STATUS, async () =>
    softwareSourcesService.getSoftwareSourcesStatus(),
  );
  ipcMain.handle(IPC_CHANNELS.TOGGLE_SOFTWARE_SOURCE, async (_event, sourceId, enabled) => {
    asString(sourceId, 'sourceId', { maxLen: 128 });
    if (typeof enabled !== 'boolean') {
      throw new Error('invalid enabled: expected boolean');
    }
    return softwareSourcesService.toggleSoftwareSource(sourceId, enabled);
  });
  ipcMain.handle(IPC_CHANNELS.CHECK_SOFTWARE_UPDATES, async () =>
    softwareSourcesService.checkForUpdates(),
  );
  ipcMain.handle(IPC_CHANNELS.GET_BACKUP_STATUS, async () => backupService.getBackupStatus());
  ipcMain.handle(IPC_CHANNELS.LIST_BACKUP_SNAPSHOTS, async () => backupService.listSnapshots());
  ipcMain.handle(IPC_CHANNELS.CREATE_BACKUP_SNAPSHOT, async (_event, label) =>
    backupService.createSnapshot(asString(label, 'label', { maxLen: 128 })),
  );
  ipcMain.handle(IPC_CHANNELS.PREVIEW_BACKUP_RESTORE, async (_event, name) =>
    backupService.previewRestore(asString(name, 'name', { maxLen: 256 })),
  );
}

function parseInitialTab(argv) {
  // strawnt-hub --tab sys-settings  (NTW6 dedicated system apps)
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--tab' && argv[i + 1]) {
      return String(argv[i + 1]);
    }
    if (argv[i].startsWith('--tab=')) {
      return argv[i].slice('--tab='.length);
    }
  }
  return null;
}

app.whenReady().then(() => {
  i18n.init();
  setupRuntimeClient();
  setupIpcHandlers();
  const initialTab = parseInitialTab(process.argv);
  createWindow(initialTab);

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow(initialTab);
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('will-quit', () => {
  if (runtimeClient) {
    runtimeClient.disconnect();
  }
});

const { app, BrowserWindow, ipcMain, nativeTheme } = require('electron');
const path = require('path');
const RuntimeClient = require('./runtime-client');
const i18n = require('../common/i18n');
const { IPC_CHANNELS, UPDATE_CHANNELS } = require('../common/constants');

let mainWindow = null;
let runtimeClient = null;
let currentChannel = 'stable';

function createWindow() {
  nativeTheme.themeSource = 'dark';

  mainWindow = new BrowserWindow({
    width: 960,
    height: 680,
    minWidth: 720,
    minHeight: 520,
    backgroundColor: '#0A0E14',
    title: 'StrawWU Hub',
    icon: path.join(__dirname, '..', '..', 'assets', 'icon.png'),
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));

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
    i18n.setLocale(locale);
    const translations = i18n.loadTranslationsForRenderer(locale);
    return { locale, translations };
  });
}

app.whenReady().then(() => {
  i18n.init();
  setupRuntimeClient();
  setupIpcHandlers();
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
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

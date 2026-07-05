const path = require('path');

module.exports = {
  SOCKET_PATH: process.env.STRAWWU_SOCKET || '/run/strawwu/runtime.sock',

  SUBSYSTEM_NAMES: ['strawwu-runtime', 'strawwu-bridge', 'strawwu-nt', 'strawwu-launcher'],

  UPDATE_CHANNELS: ['stable', 'beta', 'nightly'],

  IPC_CHANNELS: {
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
  },

  COLORS: {
    bg: '#0A0E14',
    teal: '#14B8A6',
    amber: '#F59E0B',
    strawGold: '#D4A853',
    bridgeBlue: '#60A5FA',
    text: '#F4F6F9',
    muted: '#A9B6C3',
  },
};

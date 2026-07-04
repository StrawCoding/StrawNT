const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const constants = require('../src/common/constants');

describe('Constants', () => {
  it('should export all required IPC channels', () => {
    const channels = constants.IPC_CHANNELS;
    assert.ok(channels.GET_STATUS);
    assert.ok(channels.GET_LOGS);
    assert.ok(channels.SET_UPDATE_CHANNEL);
    assert.ok(channels.GET_UPDATE_CHANNEL);
    assert.ok(channels.STATUS_UPDATE);
    assert.ok(channels.LOG_ENTRY);
  });

  it('should have three update channels', () => {
    assert.deepEqual(constants.UPDATE_CHANNELS, ['stable', 'beta', 'nightly']);
  });

  it('should have four subsystem names', () => {
    assert.equal(constants.SUBSYSTEM_NAMES.length, 4);
    assert.ok(constants.SUBSYSTEM_NAMES.includes('strawwu-runtime'));
    assert.ok(constants.SUBSYSTEM_NAMES.includes('strawwu-bridge'));
    assert.ok(constants.SUBSYSTEM_NAMES.includes('strawwu-nt'));
    assert.ok(constants.SUBSYSTEM_NAMES.includes('strawwu-launcher'));
  });

  it('should define StrawWU brand colors', () => {
    const { COLORS } = constants;
    assert.equal(COLORS.bg, '#0A0E14');
    assert.equal(COLORS.teal, '#14B8A6');
    assert.equal(COLORS.amber, '#F59E0B');
    assert.equal(COLORS.strawGold, '#D4A853');
    assert.equal(COLORS.bridgeBlue, '#60A5FA');
    assert.equal(COLORS.text, '#F4F6F9');
    assert.equal(COLORS.muted, '#A9B6C3');
  });

  it('should have a default socket path', () => {
    assert.equal(typeof constants.SOCKET_PATH, 'string');
    assert.ok(constants.SOCKET_PATH.includes('strawwu'));
  });
});

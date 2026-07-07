const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const HUB_ROOT = path.join(__dirname, '..');

describe('Hub Devices page (POST-DDP)', () => {
  it('settings manifest should include devices panel and device-proxy config', () => {
    const manifest = JSON.parse(
      fs.readFileSync(path.join(HUB_ROOT, 'resources', 'settings-manifest.json'), 'utf8'),
    );
    assert.ok(manifest.panels.some((p) => p.id === 'devices'));
    assert.ok(manifest.device_proxy);
    assert.equal(manifest.device_proxy.cli, '/usr/bin/strawwu');
    assert.equal(manifest.device_proxy.list_command, 'devices list --json');
  });

  it('renderer should include devices panel and controls', () => {
    const html = fs.readFileSync(path.join(HUB_ROOT, 'src/renderer/index.html'), 'utf8');
    for (const id of [
      'tab-devices',
      'devices-list',
      'devices-tier-summary',
      'btn-refresh-devices',
      'devices-hotplug-status',
    ]) {
      assert.ok(html.includes(id), `Missing ${id}`);
    }
    assert.ok(html.includes('data-tab="devices"'));
    assert.ok(html.includes('devices.description'));
  });

  it('settings-paths should resolve dev device-proxy fixture', () => {
    const paths = require(path.join(HUB_ROOT, 'src/common/settings-paths.js'));
    const fixture = paths.resolveDeviceProxyFixture();
    assert.ok(fixture);
    assert.ok(fs.existsSync(fixture));
  });

  it('device-proxy-service should return fixture status in dev mode', async () => {
    process.env.STRAWWU_DEVICE_PROXY_FIXTURE = '1';
    const service = require(path.join(HUB_ROOT, 'src/main/device-proxy-service.js'));

    const status = await service.getDeviceProxyStatus();
    assert.ok(status.mock || status.source === 'fixture');
    assert.ok(status.devices.length >= 4);
    assert.ok(status.tierSummary.Tier1 >= 1);
    assert.ok(status.udevTags.includes('strawwu-com-port'));

    delete process.env.STRAWWU_DEVICE_PROXY_FIXTURE;
  });

  it('constants should export device-proxy IPC channels', () => {
    const { IPC_CHANNELS } = require(path.join(HUB_ROOT, 'src/common/constants.js'));
    assert.ok(IPC_CHANNELS.GET_DEVICE_PROXY_STATUS);
  });

  it('preload should expose device-proxy APIs', () => {
    const preload = fs.readFileSync(path.join(HUB_ROOT, 'src/main/preload.js'), 'utf8');
    assert.ok(preload.includes('getDeviceProxyStatus'));
  });

  it('en locale should include devices keys', () => {
    const en = JSON.parse(fs.readFileSync(path.join(HUB_ROOT, 'locales', 'en.json'), 'utf8'));
    assert.ok(en['nav.devices']);
    assert.ok(en['devices.tier_title']);
    assert.ok(en['devices.hotplug_title']);
  });
});

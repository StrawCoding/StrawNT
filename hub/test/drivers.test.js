const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const HUB_ROOT = path.join(__dirname, '..');

describe('Hub Drivers page (POST-D1)', () => {
  it('settings manifest should include drivers panel and drivers config', () => {
    const manifest = JSON.parse(
      fs.readFileSync(path.join(HUB_ROOT, 'resources', 'settings-manifest.json'), 'utf8'),
    );
    assert.ok(manifest.panels.some((p) => p.id === 'drivers'));
    assert.ok(manifest.drivers);
    assert.equal(manifest.drivers.cli, '/usr/bin/strawwu-drivers');
    assert.equal(manifest.drivers.polkit_action, 'xyz.wastebase.strawwu.drivers.install');
    assert.equal(manifest.drivers.secure_boot_plan, 'post-sec-secureboot-route');
  });

  it('renderer should include drivers panel and controls', () => {
    const html = fs.readFileSync(path.join(HUB_ROOT, 'src/renderer/index.html'), 'utf8');
    for (const id of [
      'tab-drivers',
      'drivers-devices',
      'drivers-packages',
      'btn-refresh-drivers',
      'drivers-secure-boot',
    ]) {
      assert.ok(html.includes(id), `Missing ${id}`);
    }
    assert.ok(html.includes('data-tab="drivers"'));
    assert.ok(html.includes('drivers.description'));
  });

  it('settings-paths should resolve dev drivers fixture', () => {
    const paths = require(path.join(HUB_ROOT, 'src/common/settings-paths.js'));
    const fixture = paths.resolveDriversFixture();
    assert.ok(fixture);
    assert.ok(fs.existsSync(fixture));
    const cli = paths.resolveDriversCli();
    assert.ok(cli);
    assert.ok(fs.existsSync(cli));
  });

  it('drivers-service should return fixture status in dev mode', async () => {
    process.env.STRAWWU_DRIVERS_FIXTURE = '1';
    const service = require(path.join(HUB_ROOT, 'src/main/drivers-service.js'));

    const status = await service.getDriverStatus();
    assert.ok(status.mock || status.source === 'fixture');
    assert.equal(status.devices.length, 3);
    assert.ok(status.secureBoot.enabled);
    assert.equal(status.secureBootPlan, 'post-sec-secureboot-route');

    const listing = await service.listDrivers();
    assert.ok(listing.drivers.length >= 2);

    const install = await service.installDriver('nvidia-driver-550');
    assert.equal(install.success, true);
    assert.equal(install.mock, true);

    delete process.env.STRAWWU_DRIVERS_FIXTURE;
  });

  it('constants should export drivers IPC channels', () => {
    const { IPC_CHANNELS } = require(path.join(HUB_ROOT, 'src/common/constants.js'));
    assert.ok(IPC_CHANNELS.GET_DRIVERS_STATUS);
    assert.ok(IPC_CHANNELS.LIST_DRIVERS);
    assert.ok(IPC_CHANNELS.INSTALL_DRIVER);
  });

  it('preload should expose drivers APIs', () => {
    const preload = fs.readFileSync(path.join(HUB_ROOT, 'src/main/preload.js'), 'utf8');
    assert.ok(preload.includes('getDriversStatus'));
    assert.ok(preload.includes('installDriver'));
  });

  it('en locale should include drivers keys', () => {
    const en = JSON.parse(fs.readFileSync(path.join(HUB_ROOT, 'locales', 'en.json'), 'utf8'));
    assert.ok(en['nav.drivers']);
    assert.ok(en['drivers.secure_boot_title']);
    assert.ok(en['drivers.install']);
  });
});

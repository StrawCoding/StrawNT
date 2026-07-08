const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const HUB_ROOT = path.join(__dirname, '..');

describe('software-sources hub integration', () => {
  it('settings manifest should include software-sources panel and config', () => {
    const manifest = JSON.parse(
      fs.readFileSync(path.join(HUB_ROOT, 'resources/settings-manifest.json'), 'utf8'),
    );
    assert.ok(manifest.panels.some((p) => p.id === 'software-sources'));
    assert.ok(manifest.software_sources);
    assert.equal(manifest.software_sources.cli, '/usr/bin/strawwu-software-sources');
    assert.equal(
      manifest.software_sources.polkit_action,
      'xyz.wastebase.strawwu.software-sources.toggle',
    );
    assert.equal(manifest.software_sources.update_notifier, 'strawwu-update-notifier');
  });

  it('renderer should include software-sources panel and controls', () => {
    const html = fs.readFileSync(path.join(HUB_ROOT, 'src/renderer/index.html'), 'utf8');
    for (const token of [
      'tab-software-sources',
      'sources-list',
      'btn-refresh-sources',
      'btn-check-updates',
      'sources-meta',
    ]) {
      assert.ok(html.includes(token), `missing ${token}`);
    }
    assert.ok(html.includes('data-tab="software-sources"'));
    assert.ok(html.includes('sources.description'));
  });

  it('settings-paths should resolve dev software-sources fixture', () => {
    process.env.STRAWWU_SOFTWARE_SOURCES_FIXTURE = '1';
    const paths = require(path.join(HUB_ROOT, 'src/common/settings-paths.js'));
    const fixture = paths.resolveSoftwareSourcesFixture();
    assert.ok(fixture);
    assert.ok(fs.existsSync(fixture));
    delete process.env.STRAWWU_SOFTWARE_SOURCES_FIXTURE;
  });

  it('software-sources-service should return fixture status in dev mode', async () => {
    process.env.STRAWWU_SOFTWARE_SOURCES_FIXTURE = '1';
    const service = require(path.join(HUB_ROOT, 'src/main/software-sources-service.js'));
    const status = await service.getSoftwareSourcesStatus();
    assert.ok(status.mock);
    assert.ok(status.sources.length >= 4);
    assert.equal(status.polkitAction, 'xyz.wastebase.strawwu.software-sources.toggle');
    const updates = await service.checkForUpdates();
    assert.ok(updates.success);
    delete process.env.STRAWWU_SOFTWARE_SOURCES_FIXTURE;
  });

  it('constants should export software-sources IPC channels', () => {
    const { IPC_CHANNELS } = require(path.join(HUB_ROOT, 'src/common/constants.js'));
    assert.ok(IPC_CHANNELS.GET_SOFTWARE_SOURCES_STATUS);
    assert.ok(IPC_CHANNELS.TOGGLE_SOFTWARE_SOURCE);
    assert.ok(IPC_CHANNELS.CHECK_SOFTWARE_UPDATES);
  });

  it('preload should expose software-sources APIs', () => {
    const preload = fs.readFileSync(path.join(HUB_ROOT, 'src/main/preload.js'), 'utf8');
    assert.ok(preload.includes('getSoftwareSourcesStatus'));
    assert.ok(preload.includes('toggleSoftwareSource'));
    assert.ok(preload.includes('checkSoftwareUpdates'));
  });

  it('en locale should include software-sources keys', () => {
    const en = JSON.parse(fs.readFileSync(path.join(HUB_ROOT, 'locales/en.json'), 'utf8'));
    assert.ok(en['nav.software_sources']);
    assert.ok(en['sources.check_updates']);
    assert.ok(en['sources.readonly']);
  });
});

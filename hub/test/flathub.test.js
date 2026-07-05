const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const HUB_ROOT = path.join(__dirname, '..');

describe('Hub Flathub page (W4-F3)', () => {
  it('settings manifest should include flathub panel and flathub config', () => {
    const manifest = JSON.parse(
      fs.readFileSync(path.join(HUB_ROOT, 'resources', 'settings-manifest.json'), 'utf8'),
    );
    assert.ok(manifest.panels.some((p) => p.id === 'flathub'));
    assert.ok(manifest.flathub);
    assert.equal(manifest.flathub.remote, 'flathub');
    assert.ok(manifest.flathub.api.includes('flathub.org'));
  });

  it('renderer should include flathub panel and controls', () => {
    const html = fs.readFileSync(path.join(HUB_ROOT, 'src/renderer/index.html'), 'utf8');
    for (const id of ['tab-flathub', 'flathub-list', 'flathub-search', 'btn-refresh-flathub']) {
      assert.ok(html.includes(id), `Missing ${id}`);
    }
    assert.ok(html.includes('data-tab="flathub"'));
    assert.ok(html.includes('flathub.disclaimer'));
    assert.ok(html.includes('img-src'));
  });

  it('settings-paths should resolve dev flathub fixture', () => {
    const paths = require(path.join(HUB_ROOT, 'src/common/settings-paths.js'));
    const fixture = paths.resolveFlathubFixture();
    assert.ok(fixture);
    assert.ok(fs.existsSync(fixture));
  });

  it('flathub-service should search fixture catalog in dev mode', async () => {
    process.env.STRAWWU_FLATHUB_FIXTURE = '1';
    const service = require(path.join(HUB_ROOT, 'src/main/flathub-service.js'));

    const all = await service.searchCatalog('');
    assert.ok(all.mock);
    assert.ok(all.apps.length >= 3);
    assert.ok(all.apps.some((a) => a.appId === 'org.mozilla.firefox'));

    const filtered = await service.searchCatalog('firefox');
    assert.equal(filtered.apps.length, 1);
    assert.equal(filtered.apps[0].appId, 'org.mozilla.firefox');

    delete process.env.STRAWWU_FLATHUB_FIXTURE;
  });

  it('flathub-service install should simulate in dev mode', async () => {
    process.env.STRAWWU_FLATHUB_FIXTURE = '1';
    const service = require(path.join(HUB_ROOT, 'src/main/flathub-service.js'));
    const result = await service.installApp('org.mozilla.firefox');
    assert.equal(result.appId, 'org.mozilla.firefox');
    assert.equal(result.mock, true);
    delete process.env.STRAWWU_FLATHUB_FIXTURE;
  });

  it('flathub-service getFlathubStatus should expose disclaimer key', async () => {
    process.env.STRAWWU_FLATHUB_FIXTURE = '1';
    const service = require(path.join(HUB_ROOT, 'src/main/flathub-service.js'));
    const status = await service.getFlathubStatus();
    assert.equal(status.remote, 'flathub');
    assert.equal(status.disclaimerKey, 'flathub.disclaimer');
    assert.equal(status.mock, true);
    delete process.env.STRAWWU_FLATHUB_FIXTURE;
  });

  it('constants should export flathub IPC channels', () => {
    const { IPC_CHANNELS } = require(path.join(HUB_ROOT, 'src/common/constants.js'));
    assert.ok(IPC_CHANNELS.SEARCH_FLATHUB);
    assert.ok(IPC_CHANNELS.INSTALL_FLATHUB);
    assert.ok(IPC_CHANNELS.GET_FLATHUB_STATUS);
  });

  it('preload should expose flathub APIs', () => {
    const preload = fs.readFileSync(path.join(HUB_ROOT, 'src/main/preload.js'), 'utf8');
    assert.ok(preload.includes('searchFlathub'));
    assert.ok(preload.includes('installFlathub'));
    assert.ok(preload.includes('getFlathubStatus'));
  });

  it('en/zh locales should define flathub.* keys', () => {
    for (const locale of ['en', 'zh']) {
      const data = JSON.parse(
        fs.readFileSync(path.join(HUB_ROOT, 'locales', `${locale}.json`), 'utf8'),
      );
      assert.ok(data['nav.flathub']);
      assert.ok(data['flathub.title']);
      assert.ok(data['flathub.install']);
      assert.ok(data['flathub.disclaimer']);
    }
  });
});

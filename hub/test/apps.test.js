const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');

const HUB_ROOT = path.join(__dirname, '..');
const REPO_ROOT = path.join(HUB_ROOT, '..');
const COMPONENTS = path.join(REPO_ROOT, 'components');

describe('Hub Apps page (W4-R2)', () => {
  it('settings manifest should include apps panel and app_registry paths', () => {
    const manifest = JSON.parse(
      fs.readFileSync(path.join(HUB_ROOT, 'resources', 'settings-manifest.json'), 'utf8'),
    );
    assert.ok(manifest.panels.some((p) => p.id === 'apps'));
    assert.ok(manifest.app_registry);
    assert.equal(manifest.app_registry.installed, '/var/lib/strawwu/app-registry.json');
    assert.ok(manifest.app_registry.dev.includes('sample-registry.json'));
  });

  it('renderer should include apps panel and controls', () => {
    const html = fs.readFileSync(path.join(HUB_ROOT, 'src/renderer/index.html'), 'utf8');
    for (const id of ['tab-apps', 'apps-list', 'apps-search', 'btn-refresh-apps']) {
      assert.ok(html.includes(id), `Missing ${id}`);
    }
    assert.ok(html.includes('data-tab="apps"'));
  });

  it('settings-paths should resolve dev app registry fixture', () => {
    const paths = require(path.join(HUB_ROOT, 'src/common/settings-paths.js'));
    const registry = paths.resolveAppRegistry();
    assert.ok(registry);
    assert.ok(fs.existsSync(registry));
  });

  it('app-registry-service should list apps from dev fixture', async () => {
    const service = require(path.join(HUB_ROOT, 'src/main/app-registry-service.js'));
    const data = await service.listApps();
    assert.ok(Array.isArray(data.apps));
    assert.ok(data.apps.length >= 1);
    assert.ok(data.apps.some((a) => a.id === 'notepad-plus'));
    assert.ok(data.apps.some((a) => a.id === 'strawwu-hub' && a.protected));
  });

  it('app-registry-service remove should use CLI with temp registry', async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'strawwu-apps-'));
    const registryPath = path.join(tmpDir, 'app-registry.json');
    fs.copyFileSync(
      path.join(
        REPO_ROOT,
        'components/strawwu-app-registry/tests/fixtures/sample-registry.json',
      ),
      registryPath,
    );

    const cli = path.join(COMPONENTS, 'target/debug/strawwu-app-registry');
    assert.ok(fs.existsSync(cli), 'build strawwu-app-registry first');

    process.env.STRAWWU_APP_REGISTRY = registryPath;
    process.env.STRAWWU_APP_REGISTRY_CLI = cli;

    const service = require(path.join(HUB_ROOT, 'src/main/app-registry-service.js'));
    const preview = await service.previewRemoveApp('notepad-plus');
    assert.equal(preview.id, 'notepad-plus');

    const afterPreview = await service.listApps();
    assert.ok(afterPreview.apps.some((a) => a.id === 'notepad-plus'));

    await service.removeApp('notepad-plus');
    const afterRemove = await service.listApps();
    assert.ok(!afterRemove.apps.some((a) => a.id === 'notepad-plus'));

    await assert.rejects(() => service.removeApp('strawwu-hub'), /protected/i);

    delete process.env.STRAWWU_APP_REGISTRY;
    delete process.env.STRAWWU_APP_REGISTRY_CLI;
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it('constants should export apps IPC channels', () => {
    const { IPC_CHANNELS } = require(path.join(HUB_ROOT, 'src/common/constants.js'));
    assert.ok(IPC_CHANNELS.GET_APPS);
    assert.ok(IPC_CHANNELS.REMOVE_APP);
    assert.ok(IPC_CHANNELS.PREVIEW_REMOVE_APP);
  });

  it('preload should expose getApps/removeApp APIs', () => {
    const preload = fs.readFileSync(path.join(HUB_ROOT, 'src/main/preload.js'), 'utf8');
    assert.ok(preload.includes('getApps'));
    assert.ok(preload.includes('removeApp'));
    assert.ok(preload.includes('previewRemoveApp'));
  });

  it('en/zh locales should define apps.* keys', () => {
    for (const locale of ['en', 'zh']) {
      const data = JSON.parse(
        fs.readFileSync(path.join(HUB_ROOT, 'locales', `${locale}.json`), 'utf8'),
      );
      assert.ok(data['nav.apps']);
      assert.ok(data['apps.title']);
      assert.ok(data['apps.remove']);
    }
  });
});

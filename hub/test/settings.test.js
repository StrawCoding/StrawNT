const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const HUB_ROOT = path.join(__dirname, '..');

describe('Hub settings center (W4-D3)', () => {
  it('should have settings manifest with system-settings-center role', () => {
    const manifest = JSON.parse(
      fs.readFileSync(path.join(HUB_ROOT, 'resources', 'settings-manifest.json'), 'utf8'),
    );
    assert.equal(manifest.schema, 'strawwu-hub-settings/v1');
    assert.equal(manifest.role, 'system-settings-center');
    assert.ok(manifest.desktop.categories.includes('Settings'));
    assert.ok(manifest.panels.some((p) => p.id === 'about'));
    assert.ok(manifest.panels.some((p) => p.id === 'wincompat'));
    assert.ok(manifest.panels.some((p) => p.id === 'system'));
  });

  it('desktop file should register as Settings category', () => {
    const desktop = fs.readFileSync(
      path.join(HUB_ROOT, 'resources', 'strawwu-hub.desktop'),
      'utf8',
    );
    assert.ok(desktop.includes('Categories=Settings;System;'));
    assert.ok(desktop.includes('Name=StrawWU Settings'));
  });

  it('renderer should include about, wincompat, and system panels', () => {
    const html = fs.readFileSync(path.join(HUB_ROOT, 'src/renderer/index.html'), 'utf8');
    for (const id of ['tab-about', 'tab-wincompat', 'tab-system']) {
      assert.ok(html.includes(id), `Missing panel ${id}`);
    }
    assert.ok(html.includes('btn-bug-report'));
    assert.ok(html.includes('btn-open-privacy'));
  });

  it('settings-paths should resolve dev legal docs', () => {
    const paths = require(path.join(HUB_ROOT, 'src/common/settings-paths.js'));
    const privacy = paths.resolveLegalDoc('privacy.html');
    assert.ok(privacy);
    assert.ok(fs.existsSync(privacy));
    const version = paths.readVersion();
    assert.match(version, /^\d+\.\d+\.\d+\.\d+$/);
  });

  it('settings-paths should resolve dev compat matrix', () => {
    const paths = require(path.join(HUB_ROOT, 'src/common/settings-paths.js'));
    const matrix = paths.resolveCompatMatrix();
    assert.ok(matrix);
    assert.ok(fs.existsSync(matrix));
  });

  it('settings-service should load about info with legal paths', async () => {
    const service = require(path.join(HUB_ROOT, 'src/main/settings-service.js'));
    const about = await service.getAboutInfo();
    assert.equal(about.productName, 'StrawWU');
    assert.ok(about.version);
    assert.ok(about.legal.privacy);
    assert.ok(about.legal.eula);
    assert.ok(about.legal.thirdParty);
    assert.equal(about.bugReport.gtk, 'strawwu-bug-report-gtk');
  });

  it('settings-service should load wincompat grades from matrix', async () => {
    const service = require(path.join(HUB_ROOT, 'src/main/settings-service.js'));
    const info = await service.getWinCompatInfo();
    assert.ok(info.sessionStatus);
    assert.ok(info.compatMatrix.available);
    assert.ok(Array.isArray(info.grades));
    assert.ok(info.grades.length >= 1);
  });

  it('settings-service should expose system shortcuts', () => {
    const service = require(path.join(HUB_ROOT, 'src/main/settings-service.js'));
    const shortcuts = service.getSystemShortcuts();
    assert.ok(shortcuts.length >= 5);
    assert.ok(shortcuts.some((s) => s.id === 'display'));
  });

  it('constants should export settings IPC channels', () => {
    const { IPC_CHANNELS } = require(path.join(HUB_ROOT, 'src/common/constants.js'));
    assert.ok(IPC_CHANNELS.GET_ABOUT);
    assert.ok(IPC_CHANNELS.GET_WINCOMPAT);
    assert.ok(IPC_CHANNELS.OPEN_LEGAL);
    assert.ok(IPC_CHANNELS.LAUNCH_BUG_REPORT);
  });
});

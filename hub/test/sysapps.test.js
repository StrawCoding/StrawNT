const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const HUB_ROOT = path.join(__dirname, '..');
const REPO_ROOT = path.join(HUB_ROOT, '..');

const ROLES = [
  { role: 'settings', tab: 'sys-settings', desk: 'strawnt-settings.desktop' },
  { role: 'run_dialog', tab: 'sys-run', desk: 'strawnt-run-dialog.desktop' },
  { role: 'installer_wizard', tab: 'sys-installer', desk: 'strawnt-installer-wizard.desktop' },
  { role: 'app_library', tab: 'sys-library', desk: 'strawnt-app-library.desktop' },
  { role: 'compat_center', tab: 'sys-compat', desk: 'strawnt-compat-center.desktop' },
  { role: 'task_manager', tab: 'sys-taskmgr', desk: 'strawnt-task-manager.desktop' },
  { role: 'file_manager', tab: 'sys-files', desk: 'strawnt-file-manager.desktop' },
];

describe('Hub NTW6 dedicated system apps', () => {
  it('renderer should include 7 sysapp tabs', () => {
    const html = fs.readFileSync(path.join(HUB_ROOT, 'src/renderer/index.html'), 'utf8');
    for (const { tab } of ROLES) {
      assert.ok(html.includes(`data-tab="${tab}"`), `missing nav ${tab}`);
      assert.ok(html.includes(`id="tab-${tab}"`), `missing panel ${tab}`);
    }
  });

  it('main should parse --tab for desktop launch entries', () => {
    const main = fs.readFileSync(path.join(HUB_ROOT, 'src/main/main.js'), 'utf8');
    assert.ok(main.includes('parseInitialTab'));
    assert.ok(main.includes('--tab'));
  });

  it('renderer should activateTab from query', () => {
    const js = fs.readFileSync(path.join(HUB_ROOT, 'src/renderer/renderer.js'), 'utf8');
    assert.ok(js.includes('activateTab'));
    assert.ok(js.includes('applyInitialTab') || js.includes('tab='));
  });

  it('desktop entries should exist with powered by Wine + Exec --tab', () => {
    for (const { desk, tab, role } of ROLES) {
      const p = path.join(HUB_ROOT, 'resources', 'desktop', desk);
      assert.ok(fs.existsSync(p), `missing ${desk}`);
      const text = fs.readFileSync(p, 'utf8');
      assert.match(text, /powered by Wine/i);
      assert.ok(text.includes(`--tab ${tab}`), `${desk} missing --tab ${tab}`);
      assert.ok(text.includes(`X-StrawNT-Role=${role}`));
    }
  });

  it('manifests should exist for all 7 roles', () => {
    for (const { role } of ROLES) {
      const p = path.join(
        REPO_ROOT,
        'components/strawnt-sysapps/manifests',
        `${role}.json`,
      );
      assert.ok(fs.existsSync(p), `missing manifest ${role}`);
      const m = JSON.parse(fs.readFileSync(p, 'utf8'));
      assert.equal(m.schema, 'strawnt-app-manifest/v1');
      assert.equal(m.dedicated_role, role);
      assert.equal(m.powered_by_wine, true);
      assert.equal(m.honesty.simulated, false);
    }
  });

  it('settings-manifest should list dedicated roles', () => {
    const manifest = JSON.parse(
      fs.readFileSync(path.join(HUB_ROOT, 'resources', 'settings-manifest.json'), 'utf8'),
    );
    const roles = new Set(manifest.panels.map((p) => p.role).filter(Boolean));
    for (const { role } of ROLES) {
      assert.ok(roles.has(role), `settings-manifest missing role ${role}`);
    }
  });

  it('locales should define sysapps keys', () => {
    for (const locale of ['en', 'zh']) {
      const data = JSON.parse(
        fs.readFileSync(path.join(HUB_ROOT, 'locales', `${locale}.json`), 'utf8'),
      );
      assert.ok(data['nav.sys_settings']);
      assert.ok(data['sysapps.settings.title']);
      assert.ok(data['sysapps.files.title']);
    }
  });
});

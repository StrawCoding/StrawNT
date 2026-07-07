const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const HUB_ROOT = path.join(__dirname, '..');

describe('Hub directory structure', () => {
  const requiredFiles = [
    'package.json',
    'src/main/main.js',
    'src/main/preload.js',
    'src/main/runtime-client.js',
    'src/common/constants.js',
    'src/renderer/index.html',
    'src/renderer/styles.css',
    'src/renderer/renderer.js',
    'assets/icon.png',
    'resources/strawwu-hub.desktop',
    'resources/strawwu-hub-autostart.desktop',
    'resources/settings-manifest.json',
    'src/common/settings-paths.js',
    'src/main/settings-service.js',
    'src/main/app-registry-service.js',
    'src/main/flathub-service.js',
    'src/main/drivers-service.js',
  ];

  for (const file of requiredFiles) {
    it(`should have ${file}`, () => {
      const fullPath = path.join(HUB_ROOT, file);
      assert.ok(fs.existsSync(fullPath), `Missing: ${file}`);
    });
  }

  it('should have valid package.json', () => {
    const pkg = JSON.parse(fs.readFileSync(path.join(HUB_ROOT, 'package.json'), 'utf8'));
    assert.equal(pkg.name, 'strawwu-hub');
    assert.ok(pkg.version);
    assert.ok(pkg.main);
    assert.ok(pkg.scripts.start);
    assert.ok(pkg.scripts.test);
    assert.ok(pkg.scripts.dist);
    assert.ok(pkg.build);
    assert.equal(pkg.build.linux.target, 'deb');
  });

  it('should have desktop files with correct format', () => {
    const desktop = fs.readFileSync(
      path.join(HUB_ROOT, 'resources/strawwu-hub.desktop'),
      'utf8',
    );
    assert.ok(desktop.includes('[Desktop Entry]'));
    assert.ok(desktop.includes('Name=StrawWU Settings'));
    assert.ok(desktop.includes('Categories=Settings;System;'));
  });

  it('should have autostart desktop file with X-GNOME-Autostart', () => {
    const autostart = fs.readFileSync(
      path.join(HUB_ROOT, 'resources/strawwu-hub-autostart.desktop'),
      'utf8',
    );
    assert.ok(autostart.includes('X-GNOME-Autostart-enabled=true'));
  });

  it('renderer HTML should reference styles.css and renderer.js', () => {
    const html = fs.readFileSync(path.join(HUB_ROOT, 'src/renderer/index.html'), 'utf8');
    assert.ok(html.includes('styles.css'));
    assert.ok(html.includes('renderer.js'));
    assert.ok(html.includes('Content-Security-Policy'));
  });
});

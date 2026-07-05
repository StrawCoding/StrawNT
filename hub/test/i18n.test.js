const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const HUB_ROOT = path.join(__dirname, '..');
const LOCALES_DIR = path.join(HUB_ROOT, 'locales');

describe('i18n system', () => {
  it('should have manifest.json with all locales', () => {
    const manifestPath = path.join(LOCALES_DIR, 'manifest.json');
    assert.ok(fs.existsSync(manifestPath));
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf-8'));
    assert.ok(manifest.defaultLocale === 'en');
    assert.ok(Array.isArray(manifest.locales));
    assert.ok(manifest.locales.length >= 200);
    manifest.locales.forEach((l) => {
      assert.ok(l.code, `Locale missing code`);
      assert.ok(l.name, `Locale ${l.code} missing name`);
      assert.ok(l.nativeName, `Locale ${l.code} missing nativeName`);
    });
  });

  it('should have en.json with all required keys', () => {
    const en = JSON.parse(fs.readFileSync(path.join(LOCALES_DIR, 'en.json'), 'utf-8'));
    const requiredKeys = [
      'app.title',
      'nav.status',
      'nav.logs',
      'nav.updates',
      'nav.language',
      'nav.wincompat',
      'nav.system',
      'nav.about',
      'status.title',
      'status.refresh',
      'logs.title',
      'logs.reload',
      'updates.title',
      'language.title',
      'language.search',
      'language.applied',
      'about.title',
      'wincompat.title',
      'system.title',
    ];
    for (const key of requiredKeys) {
      assert.ok(en[key], `Missing key in en.json: ${key}`);
    }
  });

  it('should have zh.json with same keys as en.json', () => {
    const en = JSON.parse(fs.readFileSync(path.join(LOCALES_DIR, 'en.json'), 'utf-8'));
    const zh = JSON.parse(fs.readFileSync(path.join(LOCALES_DIR, 'zh.json'), 'utf-8'));
    const enKeys = Object.keys(en).sort();
    const zhKeys = Object.keys(zh).sort();
    assert.deepEqual(zhKeys, enKeys);
  });

  it('should have a locale file for every entry in manifest', () => {
    const manifest = JSON.parse(fs.readFileSync(path.join(LOCALES_DIR, 'manifest.json'), 'utf-8'));
    const missing = [];
    for (const locale of manifest.locales) {
      const filePath = path.join(LOCALES_DIR, `${locale.code}.json`);
      if (!fs.existsSync(filePath)) missing.push(locale.code);
    }
    assert.equal(missing.length, 0, `Missing locale files: ${missing.join(', ')}`);
  });

  it('every locale file should be valid JSON with app.title key', () => {
    const manifest = JSON.parse(fs.readFileSync(path.join(LOCALES_DIR, 'manifest.json'), 'utf-8'));
    for (const locale of manifest.locales) {
      const filePath = path.join(LOCALES_DIR, `${locale.code}.json`);
      const content = JSON.parse(fs.readFileSync(filePath, 'utf-8'));
      assert.ok(content['app.title'], `${locale.code}.json missing app.title`);
    }
  });

  it('i18n module should init and detect locale', () => {
    const i18n = require(path.join(HUB_ROOT, 'src', 'common', 'i18n.js'));
    i18n.init('en');
    assert.equal(i18n.getLocale(), 'en');
    const locales = i18n.getAvailableLocales();
    assert.ok(locales.length >= 200);
  });

  it('i18n module should switch locale and translate', () => {
    const i18n = require(path.join(HUB_ROOT, 'src', 'common', 'i18n.js'));
    i18n.init('zh');
    assert.equal(i18n.getLocale(), 'zh');
    assert.equal(i18n.t('nav.status'), '子系統狀態');
    assert.equal(i18n.t('status.refresh'), '重新整理');
  });

  it('i18n module should fallback to English for missing keys', () => {
    const i18n = require(path.join(HUB_ROOT, 'src', 'common', 'i18n.js'));
    i18n.init('af');
    assert.equal(i18n.t('app.title'), 'StrawWU Hub');
  });

  it('i18n module should support parameter substitution', () => {
    const i18n = require(path.join(HUB_ROOT, 'src', 'common', 'i18n.js'));
    i18n.init('en');
    const result = i18n.t('updates.switched', { channel: 'beta' });
    assert.equal(result, 'Switched to beta channel');
  });

  it('loadTranslationsForRenderer should merge fallback', () => {
    const i18n = require(path.join(HUB_ROOT, 'src', 'common', 'i18n.js'));
    i18n.init('zh');
    const merged = i18n.loadTranslationsForRenderer('zh');
    assert.equal(merged['nav.status'], '子系統狀態');
    assert.ok(merged['app.title']);
  });
});

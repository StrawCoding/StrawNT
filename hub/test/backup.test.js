const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const HUB_ROOT = path.join(__dirname, '..');

describe('backup hub integration', () => {
  it('settings manifest should include backup panel and config', () => {
    const manifest = JSON.parse(
      fs.readFileSync(path.join(HUB_ROOT, 'resources/settings-manifest.json'), 'utf8'),
    );
    assert.ok(manifest.panels.some((p) => p.id === 'backup'));
    assert.ok(manifest.backup);
    assert.equal(manifest.backup.cli, '/usr/bin/strawwu-backup');
    assert.equal(manifest.backup.upgrade_hook, 'strawwu-upgrade snapshot');
  });

  it('renderer should include backup panel and controls', () => {
    const html = fs.readFileSync(path.join(HUB_ROOT, 'src/renderer/index.html'), 'utf8');
    for (const token of [
      'tab-backup',
      'backup-list',
      'btn-refresh-backup',
      'btn-create-backup',
      'backup-meta',
    ]) {
      assert.ok(html.includes(token), `missing ${token}`);
    }
    assert.ok(html.includes('data-tab="backup"'));
    assert.ok(html.includes('backup.description'));
  });

  it('settings-paths should resolve dev backup fixture', () => {
    process.env.STRAWWU_BACKUP_FIXTURE = '1';
    const paths = require(path.join(HUB_ROOT, 'src/common/settings-paths.js'));
    const fixture = paths.resolveBackupFixture();
    assert.ok(fixture);
    assert.ok(fs.existsSync(fixture));
    delete process.env.STRAWWU_BACKUP_FIXTURE;
  });

  it('backup-service should return fixture status in dev mode', async () => {
    process.env.STRAWWU_BACKUP_FIXTURE = '1';
    const service = require(path.join(HUB_ROOT, 'src/main/backup-service.js'));
    const status = await service.getBackupStatus();
    assert.ok(status.mock);
    assert.ok(status.backends.rsync);
    const listed = await service.listSnapshots();
    assert.ok(listed.snapshots.length >= 2);
    const preview = await service.previewRestore(listed.snapshots[0].name);
    assert.ok(preview.success);
    delete process.env.STRAWWU_BACKUP_FIXTURE;
  });

  it('constants should export backup IPC channels', () => {
    const { IPC_CHANNELS } = require(path.join(HUB_ROOT, 'src/common/constants.js'));
    assert.ok(IPC_CHANNELS.GET_BACKUP_STATUS);
    assert.ok(IPC_CHANNELS.LIST_BACKUP_SNAPSHOTS);
    assert.ok(IPC_CHANNELS.CREATE_BACKUP_SNAPSHOT);
    assert.ok(IPC_CHANNELS.PREVIEW_BACKUP_RESTORE);
  });

  it('preload should expose backup APIs', () => {
    const preload = fs.readFileSync(path.join(HUB_ROOT, 'src/main/preload.js'), 'utf8');
    assert.ok(preload.includes('getBackupStatus'));
    assert.ok(preload.includes('listBackupSnapshots'));
    assert.ok(preload.includes('createBackupSnapshot'));
    assert.ok(preload.includes('previewBackupRestore'));
  });

  it('en locale should include backup keys', () => {
    const en = JSON.parse(fs.readFileSync(path.join(HUB_ROOT, 'locales/en.json'), 'utf8'));
    assert.ok(en['nav.backup']);
    assert.ok(en['backup.create']);
    assert.ok(en['backup.upgrade_hook']);
  });
});

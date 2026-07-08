const fs = require('fs');
const { execFile } = require('child_process');
const { promisify } = require('util');
const {
  resolveBackupCli,
  resolveBackupFixture,
} = require('../common/settings-paths');

const execFileAsync = promisify(execFile);
const CLI_TIMEOUT_MS = 120000;

function readFixtureCatalog() {
  const fixturePath = resolveBackupFixture();
  if (!fixturePath || !fs.existsSync(fixturePath)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
}

function useFixtureMode() {
  if (process.env.STRAWWU_BACKUP_FIXTURE === '1') {
    return true;
  }
  const cli = resolveBackupCli();
  return !cli || !fs.existsSync(cli);
}

async function runCli(args, timeout = CLI_TIMEOUT_MS) {
  const cli = resolveBackupCli();
  if (!cli || !fs.existsSync(cli)) {
    throw new Error('strawwu-backup CLI not found');
  }
  const env = { ...process.env };
  if (useFixtureMode()) {
    env.STRAWWU_BACKUP_FIXTURE = '1';
    const fixture = resolveBackupFixture();
    if (fixture) {
      env.STRAWWU_BACKUP_FIXTURE_PATH = fixture;
    }
  }
  const { stdout } = await execFileAsync(cli, args, {
    timeout,
    env,
    maxBuffer: 4 * 1024 * 1024,
  });
  return JSON.parse(stdout);
}

function normalizeStatus(payload) {
  return {
    backupRoot: payload.backup_root || payload.backupRoot,
    systemRoot: payload.system_root || payload.systemRoot,
    backends: payload.backends || {},
    timeshiftSnapshots: payload.timeshift_snapshots || payload.timeshiftSnapshots || [],
    snapshotCount: payload.snapshot_count ?? payload.snapshotCount ?? 0,
    systemCount: payload.system_count ?? payload.systemCount ?? 0,
    upgradeCount: payload.upgrade_count ?? payload.upgradeCount ?? 0,
    upgradeHook: payload.upgrade_hook || payload.upgradeHook || 'strawwu-upgrade snapshot',
    mock: Boolean(payload.fixture || payload.mock),
    source: payload.fixture || payload.mock ? 'fixture' : 'strawwu-backup',
  };
}

async function getBackupStatus() {
  if (useFixtureMode()) {
    const fixture = readFixtureCatalog();
    if (fixture?.status) {
      return normalizeStatus({ ...fixture.status, fixture: true, mock: true });
    }
    if (fixture) {
      return normalizeStatus({
        schema: 'strawwu-backup-status/v1',
        backup_root: fixture.status?.backup_root || '/var/lib/strawwu/backups',
        backends: fixture.backends || {},
        snapshot_count: (fixture.snapshots || []).length,
        system_count: (fixture.snapshots || []).filter((s) => s.kind === 'system').length,
        upgrade_count: (fixture.snapshots || []).filter((s) => s.kind === 'upgrade').length,
        fixture: true,
        mock: true,
      });
    }
  }

  try {
    const data = await runCli(['--json', 'status']);
    return normalizeStatus(data);
  } catch (err) {
    const fixture = readFixtureCatalog();
    if (fixture?.status) {
      return {
        ...normalizeStatus(fixture.status),
        source: 'fixture-fallback',
        error: err.message,
      };
    }
    throw err;
  }
}

async function listSnapshots() {
  if (useFixtureMode()) {
    const fixture = readFixtureCatalog();
    if (fixture?.snapshots) {
      return { snapshots: fixture.snapshots, mock: true };
    }
  }

  try {
    const data = await runCli(['--json', 'list']);
    return { snapshots: data.snapshots || [], mock: false };
  } catch (err) {
    const fixture = readFixtureCatalog();
    if (fixture?.snapshots) {
      return {
        snapshots: fixture.snapshots,
        mock: true,
        source: 'fixture-fallback',
        error: err.message,
      };
    }
    throw err;
  }
}

async function createSnapshot(label = 'hub-manual') {
  if (useFixtureMode()) {
    return {
      success: true,
      mock: true,
      snapshot: `system-fixture-${Date.now()}`,
      backend: 'rsync',
      label,
    };
  }

  const data = await runCli(['--json', 'snapshot', 'create', '--label', label]);
  return { success: true, mock: false, ...data };
}

async function previewRestore(name) {
  if (useFixtureMode()) {
    const fixture = readFixtureCatalog();
    const snap = (fixture?.snapshots || []).find((s) => s.name === name);
    if (!snap) {
      return { success: false, error: `Unknown snapshot ${name}` };
    }
    const actions =
      snap.kind === 'upgrade'
        ? [`strawwu-upgrade --rollback ${name}`]
        : [`rsync restore files for ${name}`];
    return { success: true, mock: true, snapshot: name, dryRun: true, actions };
  }

  const data = await runCli(['--json', 'restore', name]);
  return { success: true, mock: false, ...data, dryRun: data.dry_run !== false };
}

module.exports = {
  getBackupStatus,
  listSnapshots,
  createSnapshot,
  previewRestore,
};

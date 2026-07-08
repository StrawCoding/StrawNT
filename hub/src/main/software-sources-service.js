const fs = require('fs');
const { execFile } = require('child_process');
const { promisify } = require('util');
const {
  resolveSoftwareSourcesCli,
  resolveSoftwareSourcesFixture,
  SOFTWARE_SOURCES_POLKIT_ACTION,
} = require('../common/settings-paths');

const execFileAsync = promisify(execFile);
const CLI_TIMEOUT_MS = 60000;
const CHECK_UPDATES_TIMEOUT_MS = 180000;

function readFixtureCatalog() {
  const fixturePath = resolveSoftwareSourcesFixture();
  if (!fixturePath || !fs.existsSync(fixturePath)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
}

function useFixtureMode() {
  if (process.env.STRAWWU_SOFTWARE_SOURCES_FIXTURE === '1') {
    return true;
  }
  const cli = resolveSoftwareSourcesCli();
  return !cli || !fs.existsSync(cli);
}

async function runCli(args, timeout = CLI_TIMEOUT_MS) {
  const cli = resolveSoftwareSourcesCli();
  if (!cli || !fs.existsSync(cli)) {
    throw new Error('strawwu-software-sources CLI not found');
  }
  const env = { ...process.env };
  if (useFixtureMode()) {
    env.STRAWWU_SOFTWARE_SOURCES_FIXTURE = '1';
    const fixture = resolveSoftwareSourcesFixture();
    if (fixture) {
      env.STRAWWU_SOFTWARE_SOURCES_FIXTURE_PATH = fixture;
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
    sources: payload.sources || [],
    summary: payload.summary || {
      total: (payload.sources || []).length,
      enabled: (payload.sources || []).filter((s) => s.enabled).length,
      readonly: (payload.sources || []).filter((s) => s.readonly).length,
    },
    upgradable: payload.upgradable ?? payload.upgradable_count ?? null,
    lastCheck: payload.last_check || payload.lastCheck || null,
    mock: Boolean(payload.mock),
    source: payload.mock ? 'fixture' : 'strawwu-software-sources',
    polkitAction: SOFTWARE_SOURCES_POLKIT_ACTION,
    updateNotifier: 'strawwu-update-notifier',
  };
}

async function getSoftwareSourcesStatus() {
  if (useFixtureMode()) {
    const fixture = readFixtureCatalog();
    if (fixture) {
      return normalizeStatus(fixture);
    }
  }

  try {
    const data = await runCli(['--json', 'status']);
    return normalizeStatus(data);
  } catch (err) {
    const fixture = readFixtureCatalog();
    if (fixture) {
      return {
        ...normalizeStatus(fixture),
        source: 'fixture-fallback',
        error: err.message,
      };
    }
    throw err;
  }
}

async function toggleSoftwareSource(sourceId, enabled) {
  if (useFixtureMode()) {
    const fixture = readFixtureCatalog();
    const src = (fixture?.sources || []).find((s) => s.id === sourceId);
    if (!src) {
      return { success: false, error: `Unknown source ${sourceId}` };
    }
    if (src.readonly) {
      return { success: false, error: 'Read-only source' };
    }
    src.enabled = enabled;
    return { success: true, mock: true, sourceId, enabled };
  }

  const flag = enabled ? '--enable' : '--disable';
  const data = await runCli(['--json', 'toggle', sourceId, flag]);
  return data;
}

async function checkForUpdates() {
  if (useFixtureMode()) {
    const fixture = readFixtureCatalog();
    return {
      success: true,
      mock: true,
      upgradable: fixture?.upgradable_count ?? 0,
      checkedAt: fixture?.last_check || new Date().toISOString(),
    };
  }

  try {
    const data = await runCli(['--json', 'check-updates'], CHECK_UPDATES_TIMEOUT_MS);
    return data;
  } catch (err) {
    const fixture = readFixtureCatalog();
    if (fixture) {
      return {
        success: true,
        mock: true,
        upgradable: fixture.upgradable_count ?? 0,
        source: 'fixture-fallback',
        error: err.message,
      };
    }
    return { success: false, error: err.message };
  }
}

module.exports = {
  getSoftwareSourcesStatus,
  toggleSoftwareSource,
  checkForUpdates,
};

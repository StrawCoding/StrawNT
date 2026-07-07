const fs = require('fs');
const { execFile } = require('child_process');
const { promisify } = require('util');
const {
  resolveDeviceProxyCli,
  resolveDeviceProxyFixture,
} = require('../common/settings-paths');

const execFileAsync = promisify(execFile);
const CLI_TIMEOUT_MS = 30000;

function readFixtureCatalog() {
  const fixturePath = resolveDeviceProxyFixture();
  if (!fixturePath || !fs.existsSync(fixturePath)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
}

function useFixtureMode() {
  if (process.env.STRAWWU_DEVICE_PROXY_FIXTURE === '1') {
    return true;
  }
  const cli = resolveDeviceProxyCli();
  return !cli || !fs.existsSync(cli);
}

async function runCli(args, timeout = CLI_TIMEOUT_MS) {
  const cli = resolveDeviceProxyCli();
  if (!cli || !fs.existsSync(cli)) {
    throw new Error('strawwu CLI not found');
  }
  const { stdout } = await execFileAsync(cli, args, {
    timeout,
    maxBuffer: 4 * 1024 * 1024,
  });
  return JSON.parse(stdout);
}

function normalizeStatus(payload) {
  return {
    devices: payload.devices || [],
    tierSummary: payload.tier_summary || payload.tierSummary || {},
    udevTags: payload.udev_tags || payload.udevTags || [],
    mock: Boolean(payload.mock),
    source: payload.mock ? 'fixture' : 'strawwu',
  };
}

async function getDeviceProxyStatus() {
  if (useFixtureMode()) {
    const fixture = readFixtureCatalog();
    if (fixture) {
      return normalizeStatus(fixture);
    }
  }

  try {
    const data = await runCli(['devices', 'list', '--json']);
    return {
      ...normalizeStatus(data),
      source: 'strawwu',
    };
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

module.exports = {
  getDeviceProxyStatus,
  useFixtureMode,
};

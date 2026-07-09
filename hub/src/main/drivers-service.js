const fs = require('fs');
const { execFile } = require('child_process');
const { promisify } = require('util');
const {
  resolveDriversCli,
  resolveDriversFixture,
  DRIVERS_POLKIT_ACTION,
} = require('../common/settings-paths');

const execFileAsync = promisify(execFile);
const CLI_TIMEOUT_MS = 60000;
const INSTALL_TIMEOUT_MS = 900000;

function readFixtureCatalog() {
  const fixturePath = resolveDriversFixture();
  if (!fixturePath || !fs.existsSync(fixturePath)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
}

function useFixtureMode() {
  if (process.env.STRAWWU_DRIVERS_FIXTURE === '1') {
    return true;
  }
  const cli = resolveDriversCli();
  return !cli || !fs.existsSync(cli);
}

async function runCli(args, timeout = CLI_TIMEOUT_MS) {
  const cli = resolveDriversCli();
  if (!cli || !fs.existsSync(cli)) {
    throw new Error('strawwu-drivers CLI not found');
  }
  const env = { ...process.env };
  if (useFixtureMode()) {
    env.STRAWWU_DRIVERS_FIXTURE = '1';
    const fixture = resolveDriversFixture();
    if (fixture) {
      env.STRAWWU_DRIVERS_FIXTURE_PATH = fixture;
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
    devices: payload.devices || [],
    drivers: payload.drivers || [],
    secureBoot: payload.secure_boot || payload.secureBoot || {},
    mock: Boolean(payload.mock),
    source: payload.mock ? 'fixture' : 'strawwu-drivers',
    polkitAction: DRIVERS_POLKIT_ACTION,
    secureBootPlan: 'post-sec-secureboot-route',
  };
}

async function getDriverStatus() {
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

async function listDrivers() {
  if (useFixtureMode()) {
    const fixture = readFixtureCatalog();
    if (fixture) {
      return {
        drivers: fixture.drivers || [],
        secureBoot: fixture.secure_boot || {},
        mock: true,
        source: 'fixture',
      };
    }
  }

  try {
    const data = await runCli(['--json', 'list']);
    return {
      drivers: data.drivers || [],
      secureBoot: data.secure_boot || {},
      mock: Boolean(data.mock),
      source: data.mock ? 'fixture' : 'strawwu-drivers',
    };
  } catch (err) {
    const fixture = readFixtureCatalog();
    if (fixture) {
      return {
        drivers: fixture.drivers || [],
        secureBoot: fixture.secure_boot || {},
        mock: true,
        source: 'fixture-fallback',
        error: err.message,
      };
    }
    throw err;
  }
}

// Debian package names: lowercase alnum plus + . - (must start alnum). Reject
// anything else (and leading '-') so a crafted name cannot become a CLI flag.
function isValidPackageName(name) {
  return typeof name === 'string' && /^[a-z0-9][a-z0-9+.-]*$/.test(name);
}

async function installDriver(packageName) {
  if (!isValidPackageName(packageName)) {
    throw new Error('invalid package name');
  }

  if (useFixtureMode()) {
    return {
      package: packageName,
      success: true,
      mock: true,
      message: `Simulated install of ${packageName}`,
    };
  }

  try {
    // `--` terminates option parsing so packageName can never be read as a flag.
    const data = await runCli(['--json', 'install', '--', packageName], INSTALL_TIMEOUT_MS);
    return {
      package: packageName,
      success: Boolean(data.success),
      mock: Boolean(data.mock),
      message: data.message || data.stderr || '',
      stdout: data.stdout || '',
    };
  } catch (err) {
    return {
      package: packageName,
      success: false,
      mock: false,
      message: (err && err.message) || 'driver install failed',
    };
  }
}

module.exports = {
  getDriverStatus,
  listDrivers,
  installDriver,
  useFixtureMode,
};

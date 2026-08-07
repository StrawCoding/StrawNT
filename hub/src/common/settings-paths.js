const fs = require('fs');
const path = require('path');

const HUB_ROOT = path.join(__dirname, '..', '..');
const REPO_ROOT = path.join(HUB_ROOT, '..');

const INSTALLED_LEGAL = '/usr/share/strawwu/legal';
const DEV_LEGAL = path.join(REPO_ROOT, 'os-image/config/branding/usr/share/strawwu/legal');

const INSTALLED_COMPAT = '/usr/share/strawwu/compat-matrix.json';
const DEV_COMPAT = path.join(REPO_ROOT, 'components/tests/wincompat/output/compat-matrix.json');
const DEV_STRAWNT_MATRIX = path.join(REPO_ROOT, 'tests/strawnt/output/ntw2-matrix.json');
const INSTALLED_STRAWNT_MATRIX = '/usr/share/strawnt/matrix.json';

const VERSION_FILE = path.join(REPO_ROOT, 'VERSION');
const OS_RELEASE = '/etc/os-release';

const DEV_STRAWNT_CLI = path.join(REPO_ROOT, 'components/target/debug/strawnt');
const INSTALLED_STRAWNT_CLI = '/usr/bin/strawnt';

const INSTALLED_APP_REGISTRY = '/var/lib/strawwu/app-registry.json';
const DEV_APP_REGISTRY = path.join(
  REPO_ROOT,
  'components/strawwu-app-registry/tests/fixtures/sample-registry.json',
);
const DEV_APP_REGISTRY_CLI = path.join(
  REPO_ROOT,
  'components/target/debug/strawwu-app-registry',
);

const INSTALLED_FLATPAK = '/usr/bin/flatpak';
const DEV_FLATHUB_FIXTURE = path.join(HUB_ROOT, 'tests/fixtures/flathub-catalog.json');
const FLATHUB_API = 'https://flathub.org/api/v2';
const FLATHUB_REMOTE = 'flathub';

const INSTALLED_DRIVERS_CLI = '/usr/bin/strawwu-drivers';
const DEV_DRIVERS_CLI = path.join(
  REPO_ROOT,
  'os-image/debs/strawwu-drivers/usr/bin/strawwu-drivers',
);
const DEV_DRIVERS_FIXTURE = path.join(HUB_ROOT, 'tests/fixtures/drivers-catalog.json');
const DRIVERS_POLKIT_ACTION = 'xyz.wastebase.strawwu.drivers.install';

const INSTALLED_DEVICE_PROXY_CLI = '/usr/bin/strawwu';
const DEV_DEVICE_PROXY_CLI = path.join(REPO_ROOT, 'components/target/debug/strawwu');
const DEV_DEVICE_PROXY_FIXTURE = path.join(HUB_ROOT, 'tests/fixtures/device-proxy-catalog.json');

const INSTALLED_SOFTWARE_SOURCES_CLI = '/usr/bin/strawwu-software-sources';
const DEV_SOFTWARE_SOURCES_CLI = path.join(
  REPO_ROOT,
  'os-image/debs/strawwu-software-sources/usr/bin/strawwu-software-sources',
);
const DEV_SOFTWARE_SOURCES_FIXTURE = path.join(
  HUB_ROOT,
  'tests/fixtures/software-sources-catalog.json',
);
const SOFTWARE_SOURCES_POLKIT_ACTION = 'xyz.wastebase.strawwu.software-sources.toggle';

const INSTALLED_BACKUP_CLI = '/usr/bin/strawwu-backup';
const DEV_BACKUP_CLI = path.join(
  REPO_ROOT,
  'os-image/debs/strawwu-backup/usr/bin/strawwu-backup',
);
const DEV_BACKUP_FIXTURE = path.join(HUB_ROOT, 'tests/fixtures/backup-catalog.json');

function firstExisting(...candidates) {
  for (const candidate of candidates) {
    if (candidate && fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return null;
}

function resolveLegalDir() {
  return firstExisting(INSTALLED_LEGAL, DEV_LEGAL);
}

function resolveLegalDoc(name) {
  const dir = resolveLegalDir();
  if (!dir) return null;
  const file = path.join(dir, name);
  return fs.existsSync(file) ? file : null;
}

function resolveCompatMatrix() {
  return firstExisting(INSTALLED_COMPAT, DEV_COMPAT);
}

function resolveStrawntMatrix() {
  if (process.env.STRAWNT_MATRIX && fs.existsSync(process.env.STRAWNT_MATRIX)) {
    return process.env.STRAWNT_MATRIX;
  }
  // Prefer XDG data home matrix if present.
  const xdg = process.env.XDG_DATA_HOME
    || path.join(process.env.HOME || '', '.local/share');
  const userMatrix = path.join(xdg, 'strawnt', 'matrix.json');
  return firstExisting(
    process.env.STRAWNT_HOME ? path.join(process.env.STRAWNT_HOME, 'matrix.json') : null,
    userMatrix,
    DEV_STRAWNT_MATRIX,
    INSTALLED_STRAWNT_MATRIX,
  );
}

function resolveStrawntCli() {
  if (process.env.STRAWNT_CLI && fs.existsSync(process.env.STRAWNT_CLI)) {
    return process.env.STRAWNT_CLI;
  }
  return firstExisting(DEV_STRAWNT_CLI, INSTALLED_STRAWNT_CLI) || 'strawnt';
}

function readVersion() {
  try {
    const pkg = JSON.parse(fs.readFileSync(path.join(HUB_ROOT, 'package.json'), 'utf8'));
    if (pkg.version) return pkg.version;
  } catch {
    // fall through
  }
  if (fs.existsSync(VERSION_FILE)) {
    return fs.readFileSync(VERSION_FILE, 'utf8').trim();
  }
  return '0.0.0.0';
}

function readOsPrettyName() {
  if (!fs.existsSync(OS_RELEASE)) {
    return 'StrawNT (development)';
  }
  const text = fs.readFileSync(OS_RELEASE, 'utf8');
  const match = text.match(/^PRETTY_NAME="(.+)"$/m);
  return match ? match[1] : 'StrawNT';
}

function resolveAppRegistry() {
  if (process.env.STRAWWU_APP_REGISTRY) {
    return process.env.STRAWWU_APP_REGISTRY;
  }
  return firstExisting(INSTALLED_APP_REGISTRY, DEV_APP_REGISTRY);
}

function resolveAppRegistryCli() {
  if (process.env.STRAWWU_APP_REGISTRY_CLI && fs.existsSync(process.env.STRAWWU_APP_REGISTRY_CLI)) {
    return process.env.STRAWWU_APP_REGISTRY_CLI;
  }
  if (fs.existsSync(DEV_APP_REGISTRY_CLI)) {
    return DEV_APP_REGISTRY_CLI;
  }
  return 'strawwu-app-registry';
}

function resolveFlatpakCli() {
  if (process.env.STRAWWU_FLATPAK && fs.existsSync(process.env.STRAWWU_FLATPAK)) {
    return process.env.STRAWWU_FLATPAK;
  }
  return firstExisting(INSTALLED_FLATPAK);
}

function resolveFlathubFixture() {
  if (process.env.STRAWWU_FLATHUB_FIXTURE_PATH) {
    return process.env.STRAWWU_FLATHUB_FIXTURE_PATH;
  }
  return firstExisting(DEV_FLATHUB_FIXTURE);
}

function resolveDriversCli() {
  if (process.env.STRAWWU_DRIVERS_CLI && fs.existsSync(process.env.STRAWWU_DRIVERS_CLI)) {
    return process.env.STRAWWU_DRIVERS_CLI;
  }
  return firstExisting(INSTALLED_DRIVERS_CLI, DEV_DRIVERS_CLI);
}

function resolveDriversFixture() {
  if (process.env.STRAWWU_DRIVERS_FIXTURE_PATH) {
    return process.env.STRAWWU_DRIVERS_FIXTURE_PATH;
  }
  const debFixture = path.join(
    REPO_ROOT,
    'os-image/debs/strawwu-drivers/usr/share/strawwu/drivers/fixture-catalog.json',
  );
  return firstExisting(DEV_DRIVERS_FIXTURE, debFixture);
}

function resolveDeviceProxyCli() {
  if (process.env.STRAWWU_DEVICE_PROXY_CLI && fs.existsSync(process.env.STRAWWU_DEVICE_PROXY_CLI)) {
    return process.env.STRAWWU_DEVICE_PROXY_CLI;
  }
  return firstExisting(DEV_DEVICE_PROXY_CLI, INSTALLED_DEVICE_PROXY_CLI);
}

function resolveDeviceProxyFixture() {
  if (process.env.STRAWWU_DEVICE_PROXY_FIXTURE_PATH) {
    return process.env.STRAWWU_DEVICE_PROXY_FIXTURE_PATH;
  }
  const debFixture = path.join(
    REPO_ROOT,
    'os-image/debs/strawwu-device-proxy/usr/share/strawwu/device-proxy/fixture-catalog.json',
  );
  return firstExisting(DEV_DEVICE_PROXY_FIXTURE, debFixture);
}

function resolveSoftwareSourcesCli() {
  if (
    process.env.STRAWWU_SOFTWARE_SOURCES_CLI
    && fs.existsSync(process.env.STRAWWU_SOFTWARE_SOURCES_CLI)
  ) {
    return process.env.STRAWWU_SOFTWARE_SOURCES_CLI;
  }
  return firstExisting(INSTALLED_SOFTWARE_SOURCES_CLI, DEV_SOFTWARE_SOURCES_CLI);
}

function resolveSoftwareSourcesFixture() {
  if (process.env.STRAWWU_SOFTWARE_SOURCES_FIXTURE_PATH) {
    return process.env.STRAWWU_SOFTWARE_SOURCES_FIXTURE_PATH;
  }
  const debFixture = path.join(
    REPO_ROOT,
    'os-image/debs/strawwu-software-sources/usr/share/strawwu/software-sources/fixture-catalog.json',
  );
  return firstExisting(DEV_SOFTWARE_SOURCES_FIXTURE, debFixture);
}

function resolveBackupCli() {
  if (process.env.STRAWWU_BACKUP_CLI && fs.existsSync(process.env.STRAWWU_BACKUP_CLI)) {
    return process.env.STRAWWU_BACKUP_CLI;
  }
  return firstExisting(INSTALLED_BACKUP_CLI, DEV_BACKUP_CLI);
}

function resolveBackupFixture() {
  if (process.env.STRAWWU_BACKUP_FIXTURE_PATH) {
    return process.env.STRAWWU_BACKUP_FIXTURE_PATH;
  }
  const debFixture = path.join(
    REPO_ROOT,
    'os-image/debs/strawwu-backup/usr/share/strawwu/backup/fixture-catalog.json',
  );
  return firstExisting(DEV_BACKUP_FIXTURE, debFixture);
}

module.exports = {
  HUB_ROOT,
  REPO_ROOT,
  FLATHUB_API,
  FLATHUB_REMOTE,
  DRIVERS_POLKIT_ACTION,
  SOFTWARE_SOURCES_POLKIT_ACTION,
  resolveLegalDir,
  resolveLegalDoc,
  resolveCompatMatrix,
  resolveStrawntMatrix,
  resolveStrawntCli,
  resolveAppRegistry,
  resolveAppRegistryCli,
  resolveFlatpakCli,
  resolveFlathubFixture,
  resolveDriversCli,
  resolveDriversFixture,
  resolveDeviceProxyCli,
  resolveDeviceProxyFixture,
  resolveSoftwareSourcesCli,
  resolveSoftwareSourcesFixture,
  resolveBackupCli,
  resolveBackupFixture,
  readVersion,
  readOsPrettyName,
};

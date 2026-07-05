const fs = require('fs');
const path = require('path');

const HUB_ROOT = path.join(__dirname, '..', '..');
const REPO_ROOT = path.join(HUB_ROOT, '..');

const INSTALLED_LEGAL = '/usr/share/strawwu/legal';
const DEV_LEGAL = path.join(REPO_ROOT, 'os-image/config/branding/usr/share/strawwu/legal');

const INSTALLED_COMPAT = '/usr/share/strawwu/compat-matrix.json';
const DEV_COMPAT = path.join(REPO_ROOT, 'components/tests/wincompat/output/compat-matrix.json');

const VERSION_FILE = path.join(REPO_ROOT, 'VERSION');
const OS_RELEASE = '/etc/os-release';

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
    return 'StrawWU (development)';
  }
  const text = fs.readFileSync(OS_RELEASE, 'utf8');
  const match = text.match(/^PRETTY_NAME="(.+)"$/m);
  return match ? match[1] : 'StrawWU';
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

module.exports = {
  HUB_ROOT,
  REPO_ROOT,
  FLATHUB_API,
  FLATHUB_REMOTE,
  resolveLegalDir,
  resolveLegalDoc,
  resolveCompatMatrix,
  resolveAppRegistry,
  resolveAppRegistryCli,
  resolveFlatpakCli,
  resolveFlathubFixture,
  readVersion,
  readOsPrettyName,
};

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

module.exports = {
  HUB_ROOT,
  REPO_ROOT,
  resolveLegalDir,
  resolveLegalDoc,
  resolveCompatMatrix,
  readVersion,
  readOsPrettyName,
};

const fs = require('fs');
const path = require('path');
const { execFile, spawn } = require('child_process');
const { promisify } = require('util');
const {
  HUB_ROOT,
  resolveLegalDoc,
  resolveCompatMatrix,
  readVersion,
  readOsPrettyName,
} = require('../common/settings-paths');

const execFileAsync = promisify(execFile);
const MANIFEST_PATH = path.join(HUB_ROOT, 'resources', 'settings-manifest.json');

let cachedManifest = null;

function loadManifest() {
  if (cachedManifest) return cachedManifest;
  cachedManifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
  return cachedManifest;
}

function readCompatMatrix() {
  const matrixPath = resolveCompatMatrix();
  if (!matrixPath) {
    return {
      available: false,
      path: null,
      summary: { overall: 'UNKNOWN' },
      anticheat_matrix: { cases: [] },
    };
  }
  try {
    const data = JSON.parse(fs.readFileSync(matrixPath, 'utf8'));
    return {
      available: true,
      path: matrixPath,
      summary: data.summary || { overall: 'UNKNOWN' },
      project_version: data.project_version,
      anticheat_matrix: data.anticheat_matrix || { cases: [] },
      sub_stages: data.sub_stages || [],
    };
  } catch {
    return {
      available: false,
      path: matrixPath,
      summary: { overall: 'ERROR' },
      anticheat_matrix: { cases: [] },
    };
  }
}

async function runStrawwuStatus() {
  try {
    const { stdout } = await execFileAsync('strawwu', ['status'], {
      timeout: 5000,
      encoding: 'utf8',
    });
    return { available: true, output: stdout.trim() };
  } catch (err) {
    return {
      available: false,
      output: 'strawwu status — runtime idle, 0 sessions active (mock)',
      mock: true,
      error: err.code || err.message,
    };
  }
}

async function getAboutInfo() {
  const manifest = loadManifest();
  const legal = manifest.legal || {};
  return {
    version: readVersion(),
    osName: readOsPrettyName(),
    productName: 'StrawWU',
    role: manifest.role,
    legal: {
      privacy: resolveLegalDoc('privacy.html'),
      eula: resolveLegalDoc('eula.html'),
      thirdParty: resolveLegalDoc('third-party.html'),
      configured: legal,
    },
    bugReport: manifest.bug_report || {},
  };
}

async function getWinCompatInfo() {
  const [status, matrix] = await Promise.all([runStrawwuStatus(), readCompatMatrix()]);
  const cases = matrix.anticheat_matrix?.cases || [];
  const grades = cases.map((c) => ({
    name: c.name,
    grade: c.grade,
    status: c.status,
    backend: c.backend,
  }));
  return {
    sessionStatus: status,
    compatMatrix: matrix,
    grades,
    overallGrade: matrix.summary?.overall || 'PARTIAL',
  };
}

function getSystemShortcuts() {
  const manifest = loadManifest();
  return manifest.system_shortcuts || [];
}

function openPath(targetPath) {
  return new Promise((resolve, reject) => {
    const child = spawn('xdg-open', [targetPath], { stdio: 'ignore', detached: true });
    child.on('error', reject);
    child.unref();
    resolve({ opened: targetPath });
  });
}

async function openLegalDoc(docId) {
  const map = {
    privacy: 'privacy.html',
    eula: 'eula.html',
    third_party: 'third-party.html',
  };
  const fileName = map[docId];
  if (!fileName) {
    throw new Error(`Unknown legal document: ${docId}`);
  }
  const filePath = resolveLegalDoc(fileName);
  if (!filePath) {
    throw new Error(`Legal document not found: ${fileName}`);
  }
  return openPath(`file://${filePath}`);
}

async function launchBugReporter(useGtk = true) {
  const manifest = loadManifest();
  const cmd = useGtk ? manifest.bug_report?.gtk : manifest.bug_report?.cli;
  if (!cmd) {
    throw new Error('Bug reporter not configured');
  }
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, [], { stdio: 'ignore', detached: true });
    child.on('error', reject);
    child.unref();
    resolve({ launched: cmd });
  });
}

async function openDesktopShortcut(desktopFile) {
  const candidates = [
    `/usr/share/applications/${desktopFile}`,
    `/usr/local/share/applications/${desktopFile}`,
  ];
  const found = candidates.find((p) => fs.existsSync(p));
  if (!found) {
    throw new Error(`Desktop file not found: ${desktopFile}`);
  }
  return openPath(found);
}

module.exports = {
  loadManifest,
  getAboutInfo,
  getWinCompatInfo,
  getSystemShortcuts,
  openLegalDoc,
  launchBugReporter,
  openDesktopShortcut,
  readCompatMatrix,
};

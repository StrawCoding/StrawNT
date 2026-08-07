const fs = require('fs');
const path = require('path');
const { execFile, spawn } = require('child_process');
const { promisify } = require('util');
const {
  HUB_ROOT,
  REPO_ROOT,
  resolveLegalDoc,
  resolveCompatMatrix,
  resolveStrawntCli,
  resolveStrawntMatrix,
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
  // Prefer StrawNT wine/GE matrix when present (NTW2).
  const strawntMatrix = resolveStrawntMatrix();
  if (strawntMatrix) {
    try {
      const data = JSON.parse(fs.readFileSync(strawntMatrix, 'utf8'));
      const entries = data.entries || {};
      const cases = Object.values(entries).map((e) => ({
        name: e.name || e.app_key,
        grade: e.status === 'PASS' ? 'A' : e.status === 'PARTIAL' ? 'C' : e.status === 'FAIL' ? 'F' : 'U',
        status: e.status || 'UNKNOWN',
        backend: e.execution_backend || e.backend || 'wine',
        engine: e.engine || 'proton-ge',
        powered_by: e.powered_by || 'Wine',
      }));
      return {
        available: true,
        path: strawntMatrix,
        source: 'strawnt-matrix',
        summary: {
          overall: cases.some((c) => c.status === 'FAIL')
            ? 'FAIL'
            : cases.some((c) => c.status === 'PARTIAL' || c.status === 'UNKNOWN')
              ? 'PARTIAL'
              : cases.length
                ? 'PASS'
                : 'UNKNOWN',
        },
        project_version: data.version,
        anticheat_matrix: { cases },
        golden: {
          line: entries['line.exe'] || null,
          steam: entries['steam.exe'] || null,
        },
        sub_stages: data.sub_stages || [],
        execution_backend: 'wine',
        engine: 'proton-ge',
        powered_by_wine: true,
      };
    } catch {
      // fall through to legacy
    }
  }

  const matrixPath = resolveCompatMatrix();
  if (!matrixPath) {
    return {
      available: false,
      path: null,
      summary: { overall: 'UNKNOWN' },
      anticheat_matrix: { cases: [] },
      execution_backend: 'wine',
      engine: 'proton-ge',
      powered_by_wine: true,
    };
  }
  try {
    const data = JSON.parse(fs.readFileSync(matrixPath, 'utf8'));
    return {
      available: true,
      path: matrixPath,
      source: 'legacy-wincompat',
      summary: data.summary || { overall: 'UNKNOWN' },
      project_version: data.project_version,
      anticheat_matrix: data.anticheat_matrix || { cases: [] },
      sub_stages: data.sub_stages || [],
      execution_backend: 'wine',
      engine: 'proton-ge',
      powered_by_wine: true,
    };
  } catch {
    return {
      available: false,
      path: matrixPath,
      summary: { overall: 'ERROR' },
      anticheat_matrix: { cases: [] },
      execution_backend: 'wine',
      engine: 'proton-ge',
      powered_by_wine: true,
    };
  }
}

async function runStrawntDoctor() {
  const cli = resolveStrawntCli();
  try {
    const { stdout } = await execFileAsync(cli, ['doctor', '--json'], {
      timeout: 15000,
      encoding: 'utf8',
      env: { ...process.env, STRAWNT_ROOT: REPO_ROOT },
    });
    const data = JSON.parse(stdout);
    return { available: true, mock: false, data, cli };
  } catch (err) {
    return {
      available: false,
      mock: true,
      cli,
      error: err.code || err.message,
      data: {
        product: 'StrawNT',
        execution_backend: 'wine',
        backend: 'wine',
        engine: 'proton-ge',
        powered_by: 'Wine',
        powered_by_wine: true,
        status: 'UNKNOWN',
        wine: { found: false },
      },
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
      output: 'strawnt: execution_backend=wine (proton-ge); powered by Wine',
      mock: true,
      error: err.code || err.message,
    };
  }
}

async function getAboutInfo() {
  const manifest = loadManifest();
  const legal = manifest.legal || {};
  const doctor = await runStrawntDoctor();
  return {
    version: readVersion(),
    osName: readOsPrettyName(),
    productName: 'StrawNT',
    hub: 'electron',
    role: manifest.role,
    execution_backend: 'wine',
    backend: 'wine',
    engine: doctor.data?.engine || 'proton-ge',
    engine_pin: doctor.data?.pin || doctor.data?.engine_pin || null,
    powered_by: 'Wine',
    powered_by_wine: true,
    engineStatus: doctor,
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
  const [status, matrix, doctor] = await Promise.all([
    runStrawwuStatus(),
    Promise.resolve(readCompatMatrix()),
    runStrawntDoctor(),
  ]);
  const cases = matrix.anticheat_matrix?.cases || [];
  const grades = cases.map((c) => ({
    name: c.name,
    grade: c.grade,
    status: c.status,
    backend: c.backend || 'wine',
    engine: c.engine || doctor.data?.engine || 'proton-ge',
  }));
  return {
    hub: 'electron',
    execution_backend: 'wine',
    backend: 'wine',
    engine: doctor.data?.engine || 'proton-ge',
    engine_pin: doctor.data?.pin || doctor.data?.engine_pin || null,
    powered_by: 'Wine',
    powered_by_wine: true,
    sessionStatus: status,
    engineStatus: doctor,
    compatMatrix: matrix,
    grades,
    overallGrade: matrix.summary?.overall || 'PARTIAL',
    golden: matrix.golden || {
      line: null,
      steam: null,
    },
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

module.exports = {
  getAboutInfo,
  getWinCompatInfo,
  getSystemShortcuts,
  openLegalDoc,
  launchBugReporter,
  openPath,
  readCompatMatrix,
  runStrawntDoctor,
};

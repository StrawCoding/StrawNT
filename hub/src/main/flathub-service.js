const fs = require('fs');
const { execFile } = require('child_process');
const { promisify } = require('util');
const {
  resolveFlatpakCli,
  resolveFlathubFixture,
  FLATHUB_API,
  FLATHUB_REMOTE,
} = require('../common/settings-paths');

const execFileAsync = promisify(execFile);
const SEARCH_TIMEOUT_MS = 15000;
const INSTALL_TIMEOUT_MS = 600000;

function normalizeApp(hit) {
  const appId = hit.app_id || (hit.id ? hit.id.replace(/_/g, '.') : '');
  return {
    appId,
    name: hit.name || appId,
    summary: hit.summary || '',
    icon: hit.icon || null,
    developer: hit.developer_name || '',
    license: hit.project_license || '',
    verified: Boolean(hit.verification_verified),
  };
}

function readFixtureCatalog() {
  const fixturePath = resolveFlathubFixture();
  if (!fixturePath || !fs.existsSync(fixturePath)) {
    return [];
  }
  const data = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
  return (data.apps || []).map(normalizeApp);
}

function filterFixtureApps(query, limit = 48) {
  const apps = readFixtureCatalog();
  const q = (query || '').trim().toLowerCase();
  if (!q) {
    return apps.slice(0, limit);
  }
  return apps
    .filter(
      (app) =>
        app.name.toLowerCase().includes(q) ||
        app.appId.toLowerCase().includes(q) ||
        app.summary.toLowerCase().includes(q),
    )
    .slice(0, limit);
}

function useFixtureMode() {
  if (process.env.STRAWWU_FLATHUB_FIXTURE === '1') {
    return true;
  }
  const cli = resolveFlatpakCli();
  return !cli || !fs.existsSync(cli);
}

async function fetchJson(url, options = {}) {
  const res = await fetch(url, {
    ...options,
    headers: {
      Accept: 'application/json',
      ...(options.headers || {}),
    },
    signal: AbortSignal.timeout(SEARCH_TIMEOUT_MS),
  });
  if (!res.ok) {
    throw new Error(`Flathub API error: ${res.status}`);
  }
  return res.json();
}

async function searchRemote(query, limit = 48) {
  const q = (query || '').trim();
  if (!q) {
    const data = await fetchJson(`${FLATHUB_API}/collection/popular`);
    return (data.hits || []).slice(0, limit).map(normalizeApp);
  }
  const data = await fetchJson(`${FLATHUB_API}/search`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: q }),
  });
  return (data.hits || []).slice(0, limit).map(normalizeApp);
}

async function searchCatalog(query, limit = 48) {
  const fixture = useFixtureMode();
  if (fixture) {
    return {
      apps: filterFixtureApps(query, limit),
      source: 'fixture',
      mock: true,
      query: query || '',
    };
  }

  try {
    const apps = await searchRemote(query, limit);
    return {
      apps,
      source: 'flathub-api',
      mock: false,
      query: query || '',
    };
  } catch (err) {
    const fallback = filterFixtureApps(query, limit);
    if (fallback.length) {
      return {
        apps: fallback,
        source: 'fixture-fallback',
        mock: true,
        query: query || '',
        error: err.message,
      };
    }
    throw err;
  }
}

async function listInstalledFlatpaks() {
  const cli = resolveFlatpakCli();
  if (!cli || !fs.existsSync(cli)) {
    return { installed: [], mock: true, available: false };
  }

  try {
    const { stdout } = await execFileAsync(
      cli,
      ['list', '--app', '--columns=application', `--system`],
      { timeout: 10000, encoding: 'utf8' },
    );
    const installed = stdout
      .split('\n')
      .map((line) => line.trim())
      .filter(Boolean);
    return { installed, mock: false, available: true };
  } catch {
    return { installed: [], mock: false, available: true, error: true };
  }
}

async function getFlathubStatus() {
  const cli = resolveFlatpakCli();
  const cliPath = cli && fs.existsSync(cli) ? cli : null;
  const fixturePath = resolveFlathubFixture();
  const installedInfo = await listInstalledFlatpaks();

  return {
    flatpakAvailable: Boolean(cliPath),
    flatpakPath: cliPath,
    remote: FLATHUB_REMOTE,
    apiBase: FLATHUB_API,
    fixturePath,
    mock: useFixtureMode(),
    installed: installedInfo.installed,
    disclaimerKey: 'flathub.disclaimer',
  };
}

// Flatpak application IDs are reverse-DNS. Reject anything else (and anything
// starting with '-') so a crafted id cannot be treated as a flatpak option even
// though execFile does not use a shell.
function isValidFlatpakAppId(appId) {
  if (typeof appId !== 'string' || appId.length === 0 || appId.startsWith('-') || !appId.includes('.')) {
    return false;
  }
  return appId
    .split('.')
    .every((seg) => seg.length > 0 && /^[A-Za-z0-9_-]+$/.test(seg));
}

async function installApp(appId) {
  if (!isValidFlatpakAppId(appId)) {
    throw new Error('Invalid Flatpak application ID');
  }

  const cli = resolveFlatpakCli();
  if (!cli || !fs.existsSync(cli)) {
    return {
      appId,
      installed: false,
      mock: true,
      message: 'Install simulated (flatpak CLI unavailable in development)',
    };
  }

  const installed = await listInstalledFlatpaks();
  if (installed.installed.includes(appId)) {
    return { appId, installed: true, alreadyInstalled: true };
  }

  try {
    // `--` terminates option parsing so appId can never be read as a flag.
    await execFileAsync(
      cli,
      ['install', '-y', '--noninteractive', '--system', FLATHUB_REMOTE, '--', appId],
      { timeout: INSTALL_TIMEOUT_MS, encoding: 'utf8' },
    );
  } catch (err) {
    return {
      appId,
      installed: false,
      mock: false,
      error: (err && err.message) || 'flatpak install failed',
    };
  }

  return { appId, installed: true, mock: false };
}

module.exports = {
  searchCatalog,
  installApp,
  listInstalledFlatpaks,
  getFlathubStatus,
  normalizeApp,
  readFixtureCatalog,
  filterFixtureApps,
  useFixtureMode,
};

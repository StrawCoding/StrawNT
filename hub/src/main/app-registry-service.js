const fs = require('fs');
const { execFile } = require('child_process');
const { promisify } = require('util');
const { resolveAppRegistry, resolveAppRegistryCli } = require('../common/settings-paths');

const execFileAsync = promisify(execFile);
const REMOVED_STATE = 'removed';

function registryEnv() {
  const registryPath = resolveAppRegistry();
  if (!registryPath) {
    return { ...process.env };
  }
  return { ...process.env, STRAWWU_APP_REGISTRY: registryPath };
}

function readRegistryFromFile() {
  const registryPath = resolveAppRegistry();
  if (!registryPath || !fs.existsSync(registryPath)) {
    return {
      available: false,
      path: registryPath,
      mock: true,
      schemaVersion: '1.0',
      updatedAt: null,
      apps: [],
    };
  }

  try {
    const data = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
    const apps = (data.apps || []).filter((app) => app.install_state !== REMOVED_STATE);
    return {
      available: true,
      path: registryPath,
      mock: registryPath.includes('/tests/fixtures/'),
      schemaVersion: data.schema_version || '1.0',
      updatedAt: data.updated_at || null,
      apps,
    };
  } catch {
    return {
      available: false,
      path: registryPath,
      error: true,
      schemaVersion: null,
      updatedAt: null,
      apps: [],
    };
  }
}

async function listApps() {
  const registry = readRegistryFromFile();
  return {
    apps: registry.apps,
    registryPath: registry.path,
    available: registry.available,
    mock: registry.mock || false,
    error: registry.error || false,
    schemaVersion: registry.schemaVersion,
    updatedAt: registry.updatedAt,
    cliAvailable: Boolean(resolveAppRegistryCli()),
  };
}

async function previewRemoveApp(id) {
  return removeApp(id, true);
}

async function removeApp(id, dryRun = false) {
  const cli = resolveAppRegistryCli();
  if (!cli) {
    throw new Error('strawwu-app-registry CLI not found');
  }

  const args = ['remove', id];
  if (dryRun) {
    args.push('--dry-run');
  }
  args.push('--json');

  try {
    const { stdout } = await execFileAsync(cli, args, {
      timeout: 10000,
      encoding: 'utf8',
      env: registryEnv(),
    });
    return JSON.parse(stdout);
  } catch (err) {
    if (err.code === 2) {
      const protectedErr = new Error(`App is protected: ${id}`);
      protectedErr.code = 'PROTECTED';
      throw protectedErr;
    }
    if (err.code === 1) {
      const notFoundErr = new Error(`App not found: ${id}`);
      notFoundErr.code = 'NOT_FOUND';
      throw notFoundErr;
    }
    throw err;
  }
}

module.exports = {
  listApps,
  previewRemoveApp,
  removeApp,
  readRegistryFromFile,
};

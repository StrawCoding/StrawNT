const { strawwuHub } = window;

const $statusGrid = document.getElementById('status-grid');
const $logContainer = document.getElementById('log-container');
const $logSubsystemFilter = document.getElementById('log-subsystem-filter');
const $logLevelFilter = document.getElementById('log-level-filter');
const $channelStatus = document.getElementById('channel-status');
const $languageList = document.getElementById('language-list');
const $languageSearch = document.getElementById('language-search');
const $languageStatus = document.getElementById('language-status');
const $wincompatStatus = document.getElementById('wincompat-status');
const $wincompatGrades = document.getElementById('wincompat-grades');
const $systemShortcuts = document.getElementById('system-shortcuts');
const $aboutInfo = document.getElementById('about-info');
const $appsList = document.getElementById('apps-list');
const $appsSearch = document.getElementById('apps-search');
const $appsKindFilter = document.getElementById('apps-kind-filter');
const $appsMeta = document.getElementById('apps-meta');
const $appsStatus = document.getElementById('apps-status');
const $flathubList = document.getElementById('flathub-list');
const $flathubSearch = document.getElementById('flathub-search');
const $flathubMeta = document.getElementById('flathub-meta');
const $flathubStatus = document.getElementById('flathub-status');
const $driversDevices = document.getElementById('drivers-devices');
const $driversPackages = document.getElementById('drivers-packages');
const $driversMeta = document.getElementById('drivers-meta');
const $driversStatus = document.getElementById('drivers-status');
const $driversSecureBoot = document.getElementById('drivers-secure-boot');
const $devicesList = document.getElementById('devices-list');
const $devicesTierSummary = document.getElementById('devices-tier-summary');
const $devicesMeta = document.getElementById('devices-meta');
const $devicesHotplugStatus = document.getElementById('devices-hotplug-status');
const $sourcesList = document.getElementById('sources-list');
const $sourcesMeta = document.getElementById('sources-meta');
const $sourcesStatus = document.getElementById('sources-status');
const $backupList = document.getElementById('backup-list');
const $backupMeta = document.getElementById('backup-meta');
const $backupStatus = document.getElementById('backup-status');

let currentLogs = [];
let currentTranslations = {};
let availableLocales = [];
let currentLocale = 'en';
let currentApps = [];
let currentFlathubApps = [];
let flathubInstalled = new Set();

// --- i18n ---
async function initI18n() {
  const i18nData = await strawwuHub.getI18n();
  if (i18nData) {
    availableLocales = i18nData.locales;
    currentLocale = i18nData.currentLocale;
    currentTranslations = i18nData.translations;
    applyTranslations();
    renderLanguageList();
  }
}

function applyTranslations() {
  document.querySelectorAll('[data-i18n]').forEach((el) => {
    const key = el.getAttribute('data-i18n');
    const text = currentTranslations[key];
    if (text) el.textContent = text;
  });
  document.querySelectorAll('[data-i18n-placeholder]').forEach((el) => {
    const key = el.getAttribute('data-i18n-placeholder');
    const text = currentTranslations[key];
    if (text) el.placeholder = text;
  });
}

function t(key, params) {
  let text = currentTranslations[key] || key;
  if (params) {
    Object.entries(params).forEach(([k, v]) => {
      text = text.replace(new RegExp(`\\{${k}\\}`, 'g'), v);
    });
  }
  return text;
}

// --- Language List ---
function renderLanguageList(filter = '') {
  const lowerFilter = filter.toLowerCase();
  const filtered = availableLocales.filter((l) => {
    if (!lowerFilter) return true;
    return (
      l.code.toLowerCase().includes(lowerFilter) ||
      l.name.toLowerCase().includes(lowerFilter) ||
      l.nativeName.toLowerCase().includes(lowerFilter)
    );
  });

  $languageList.innerHTML = filtered
    .map(
      (l) => `
    <label class="language-item ${l.code === currentLocale ? 'active' : ''}" data-locale="${l.code}">
      <input type="radio" name="locale" value="${l.code}" ${l.code === currentLocale ? 'checked' : ''}>
      <span class="language-native">${escapeHtml(l.nativeName)}</span>
      <span class="language-english">${escapeHtml(l.name)}</span>
      <span class="language-code">${l.code}</span>
    </label>
  `,
    )
    .join('');

  $languageList.querySelectorAll('input[name="locale"]').forEach((radio) => {
    radio.addEventListener('change', async (e) => {
      const locale = e.target.value;
      const result = await strawwuHub.setLocale(locale);
      if (result) {
        currentLocale = result.locale;
        currentTranslations = result.translations;
        applyTranslations();
        renderLanguageList(filter);
        const localeName =
          availableLocales.find((l) => l.code === locale)?.nativeName || locale;
        $languageStatus.textContent = t('language.applied', { language: localeName });
        setTimeout(() => {
          $languageStatus.textContent = '';
        }, 3000);
      }
    });
  });
}

if ($languageSearch) {
  $languageSearch.addEventListener('input', (e) => {
    renderLanguageList(e.target.value);
  });
}

// --- Tab Navigation ---
document.querySelectorAll('.nav-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.nav-btn').forEach((b) => b.classList.remove('active'));
    document.querySelectorAll('.tab-panel').forEach((p) => p.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById(`tab-${btn.dataset.tab}`).classList.add('active');
  });
});

// --- Status ---
function formatUptime(seconds) {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

function renderStatus(subsystems) {
  $statusGrid.innerHTML = subsystems
    .map(
      (s) => `
    <div class="status-card">
      <div class="status-card-header">
        <span class="status-card-name">${escapeHtml(s.name)}</span>
        <span class="status-badge ${s.status}">${s.status}</span>
      </div>
      <div class="status-metrics">
        <div class="metric">
          <span class="metric-label">${t('status.pid')}</span>
          <span class="metric-value">${s.pid}</span>
        </div>
        <div class="metric">
          <span class="metric-label">${t('status.uptime')}</span>
          <span class="metric-value">${formatUptime(s.uptime)}</span>
        </div>
        <div class="metric">
          <span class="metric-label">${t('status.memory')}</span>
          <span class="metric-value">${s.memory_mb} MB</span>
        </div>
        <div class="metric">
          <span class="metric-label">${t('status.cpu')}</span>
          <span class="metric-value">${s.cpu_percent}%</span>
        </div>
      </div>
    </div>
  `,
    )
    .join('');
}

async function refreshStatus() {
  const data = await strawwuHub.getStatus();
  if (data) renderStatus(data);
}

document.getElementById('btn-refresh-status').addEventListener('click', refreshStatus);

// --- Logs ---
function formatLogTime(iso) {
  const d = new Date(iso);
  return d.toLocaleTimeString(currentLocale, { hour12: false });
}

function renderLogs(logs) {
  const subsystemFilter = $logSubsystemFilter.value;
  const levelFilter = $logLevelFilter.value;

  const filtered = logs.filter((l) => {
    if (subsystemFilter && l.subsystem !== subsystemFilter) return false;
    if (levelFilter && l.level !== levelFilter) return false;
    return true;
  });

  $logContainer.innerHTML = filtered
    .map(
      (l) => `
    <div class="log-entry">
      <span class="log-time">${formatLogTime(l.timestamp)}</span>
      <span class="log-level ${l.level}">${l.level}</span>
      <span class="log-subsystem">${escapeHtml(l.subsystem)}</span>
      <span class="log-message">${escapeHtml(l.message)}</span>
    </div>
  `,
    )
    .join('');
}

async function refreshLogs() {
  const subsystem = $logSubsystemFilter.value || undefined;
  const data = await strawwuHub.getLogs(subsystem);
  if (data) {
    currentLogs = data;
    renderLogs(currentLogs);
  }
}

document.getElementById('btn-refresh-logs').addEventListener('click', refreshLogs);
$logSubsystemFilter.addEventListener('change', () => renderLogs(currentLogs));
$logLevelFilter.addEventListener('change', () => renderLogs(currentLogs));

// --- Update Channel ---
async function initUpdateChannel() {
  const ch = await strawwuHub.getUpdateChannel();
  const radio = document.querySelector(`input[name="update-channel"][value="${ch}"]`);
  if (radio) radio.checked = true;
}

document.querySelectorAll('input[name="update-channel"]').forEach((radio) => {
  radio.addEventListener('change', async (e) => {
    const ch = e.target.value;
    const result = await strawwuHub.setUpdateChannel(ch);
    $channelStatus.textContent = t('updates.switched', { channel: result });
    setTimeout(() => {
      $channelStatus.textContent = '';
    }, 3000);
  });
});

// --- WinCompat ---
function gradeClass(grade) {
  if (!grade) return 'grade-unknown';
  if (grade === 'A' || grade === 'B') return 'grade-good';
  if (grade === 'C' || grade === 'D') return 'grade-partial';
  return 'grade-poor';
}

function renderWinCompat(data) {
  if (!data) return;
  const status = data.sessionStatus || {};
  const engine = data.engineStatus?.data || {};
  $wincompatStatus.innerHTML = `
    <div class="info-row">
      <span class="info-label">${t('wincompat.session')}</span>
      <span class="info-value">${escapeHtml(status.output || t('wincompat.unavailable'))}</span>
    </div>
    <div class="info-row">
      <span class="info-label">Hub</span>
      <span class="info-value">${escapeHtml(data.hub || 'electron')}</span>
    </div>
    <div class="info-row">
      <span class="info-label">Backend</span>
      <span class="info-value">${escapeHtml(data.execution_backend || data.backend || 'wine')}</span>
    </div>
    <div class="info-row">
      <span class="info-label">Engine</span>
      <span class="info-value">${escapeHtml((data.engine || 'proton-ge') + (data.engine_pin ? '@' + data.engine_pin : ''))}</span>
    </div>
    <div class="info-row">
      <span class="info-label">Powered by</span>
      <span class="info-value">${escapeHtml(data.powered_by || engine.powered_by || 'Wine')}</span>
    </div>
    <div class="info-row">
      <span class="info-label">${t('wincompat.overall')}</span>
      <span class="info-value badge-overall">${escapeHtml(data.overallGrade || 'PARTIAL')}</span>
    </div>
    <div class="info-row">
      <span class="info-label">${t('wincompat.matrix')}</span>
      <span class="info-value">${data.compatMatrix?.available ? t('wincompat.matrix_loaded') : t('wincompat.matrix_mock')}</span>
    </div>
  `;

  const grades = data.grades || [];
  $wincompatGrades.innerHTML = grades.length
    ? grades
        .map(
          (g) => `
      <div class="grade-card">
        <div class="grade-card-header">
          <span class="grade-name">${escapeHtml(g.name)}</span>
          <span class="grade-badge ${gradeClass(g.grade)}">${escapeHtml(g.grade)}</span>
        </div>
        <div class="grade-meta">
          <span>${escapeHtml(g.status)}</span>
          <span>${escapeHtml(g.backend || 'wine')}</span>
          <span>${escapeHtml(g.engine || 'proton-ge')}</span>
        </div>
      </div>
    `,
        )
        .join('')
    : `<p class="muted-text">${t('wincompat.no_grades')}</p>`;
}

async function refreshWinCompat() {
  const data = await strawwuHub.getWinCompat();
  renderWinCompat(data);
}

document.getElementById('btn-refresh-wincompat').addEventListener('click', refreshWinCompat);

// --- System Shortcuts ---
const SHORTCUT_LABELS = {
  wifi: 'system.shortcut.wifi',
  network: 'system.shortcut.network',
  display: 'system.shortcut.display',
  sound: 'system.shortcut.sound',
  power: 'system.shortcut.power',
  region: 'system.shortcut.region',
  users: 'system.shortcut.users',
};

async function renderSystemShortcuts() {
  const shortcuts = await strawwuHub.getSystemShortcuts();
  $systemShortcuts.innerHTML = (shortcuts || [])
    .map(
      (s) => `
    <button class="shortcut-btn" data-desktop="${escapeHtml(s.desktop)}">
      <span class="shortcut-label">${t(SHORTCUT_LABELS[s.id] || s.id)}</span>
      <span class="shortcut-arrow">→</span>
    </button>
  `,
    )
    .join('');

  $systemShortcuts.querySelectorAll('.shortcut-btn').forEach((btn) => {
    btn.addEventListener('click', async () => {
      try {
        await strawwuHub.openDesktopShortcut(btn.dataset.desktop);
      } catch {
        btn.classList.add('shortcut-error');
      }
    });
  });
}

// --- About ---
async function renderAbout() {
  const about = await strawwuHub.getAbout();
  if (!about) return;
  $aboutInfo.innerHTML = `
    <div class="about-brand">
      <img class="brand-icon-lg" src="../../assets/icon.png" alt="StrawWU">
      <div>
        <div class="about-product">${escapeHtml(about.productName)}</div>
        <div class="about-version">${t('about.version', { version: about.version })}</div>
        <div class="about-os muted-text">${escapeHtml(about.osName)}</div>
      </div>
    </div>
  `;
}

document.getElementById('btn-open-privacy').addEventListener('click', () => strawwuHub.openLegal('privacy'));
document.getElementById('btn-open-eula').addEventListener('click', () => strawwuHub.openLegal('eula'));
document.getElementById('btn-open-third-party').addEventListener('click', () => strawwuHub.openLegal('third_party'));
document.getElementById('btn-bug-report').addEventListener('click', () => strawwuHub.launchBugReport());

// --- Apps (App Registry) ---
const KIND_LABELS = {
  win32: 'apps.kind.win32',
  linux: 'apps.kind.linux',
  flatpak: 'apps.kind.flatpak',
  native: 'apps.kind.native',
};

function kindBadgeClass(kind) {
  if (kind === 'win32') return 'app-kind-win32';
  if (kind === 'flatpak') return 'app-kind-flatpak';
  if (kind === 'native') return 'app-kind-native';
  return 'app-kind-linux';
}

function renderApps(apps) {
  const search = ($appsSearch?.value || '').toLowerCase();
  const kindFilter = $appsKindFilter?.value || '';

  const filtered = apps.filter((app) => {
    if (kindFilter && app.kind !== kindFilter) return false;
    if (!search) return true;
    return (
      app.id.toLowerCase().includes(search) ||
      app.name.toLowerCase().includes(search) ||
      (app.install_path || '').toLowerCase().includes(search)
    );
  });

  if (!filtered.length) {
    $appsList.innerHTML = `<p class="muted-text">${t('apps.empty')}</p>`;
    return;
  }

  $appsList.innerHTML = filtered
    .map(
      (app) => `
    <div class="app-card" data-app-id="${escapeHtml(app.id)}">
      <div class="app-card-header">
        <div>
          <div class="app-name">${escapeHtml(app.name)}</div>
          <div class="app-id">${escapeHtml(app.id)}</div>
        </div>
        <div class="app-badges">
          <span class="app-kind-badge ${kindBadgeClass(app.kind)}">${t(KIND_LABELS[app.kind] || app.kind)}</span>
          ${app.protected ? `<span class="app-protected-badge">${t('apps.protected')}</span>` : ''}
        </div>
      </div>
      <div class="app-meta">
        <span>${t('apps.source')}: ${escapeHtml(app.source || '—')}</span>
        <span>${t('apps.backend')}: ${escapeHtml(app.execution_backend || 'wine')}</span>
        <span>${t('apps.state')}: ${escapeHtml(app.install_state || 'installed')}</span>
      </div>
      ${
        app.install_path
          ? `<div class="app-path">${escapeHtml(app.install_path)}</div>`
          : ''
      }
      <div class="app-actions">
        ${
          app.protected
            ? `<button class="btn btn-secondary" disabled>${t('apps.remove')}</button>`
            : `<button class="btn btn-secondary btn-remove-app" data-app-id="${escapeHtml(app.id)}" data-app-name="${escapeHtml(app.name)}">${t('apps.remove')}</button>`
        }
      </div>
    </div>
  `,
    )
    .join('');

  $appsList.querySelectorAll('.btn-remove-app').forEach((btn) => {
    btn.addEventListener('click', () => confirmRemoveApp(btn.dataset.appId, btn.dataset.appName));
  });
}

async function refreshApps() {
  const data = await strawwuHub.getApps();
  if (!data) return;
  currentApps = data.apps || [];
  const metaParts = [t('apps.count', { count: currentApps.length })];
  if (data.mock) metaParts.push(t('apps.dev_fixture'));
  if (!data.cliAvailable) metaParts.push(t('apps.cli_unavailable'));
  $appsMeta.textContent = metaParts.join(' · ');
  renderApps(currentApps);
}

async function confirmRemoveApp(id, name) {
  if (!window.confirm(t('apps.remove_confirm', { name }))) return;
  $appsStatus.textContent = '';
  try {
    await strawwuHub.previewRemoveApp(id);
    await strawwuHub.removeApp(id);
    $appsStatus.textContent = t('apps.removed', { name });
    await refreshApps();
    setTimeout(() => {
      $appsStatus.textContent = '';
    }, 3000);
  } catch (err) {
    if (err?.message?.includes('protected') || err?.message?.includes('Protected')) {
      $appsStatus.textContent = t('apps.remove_protected');
    } else {
      $appsStatus.textContent = t('apps.remove_failed', { name });
    }
    $appsStatus.classList.add('status-error');
    setTimeout(() => {
      $appsStatus.textContent = '';
      $appsStatus.classList.remove('status-error');
    }, 4000);
  }
}

if ($appsSearch) {
  $appsSearch.addEventListener('input', () => renderApps(currentApps));
}
if ($appsKindFilter) {
  $appsKindFilter.addEventListener('change', () => renderApps(currentApps));
}
document.getElementById('btn-refresh-apps')?.addEventListener('click', refreshApps);

// --- Flathub browse/install ---
function renderFlathubApps(apps) {
  if (!apps.length) {
    $flathubList.innerHTML = `<p class="muted-text">${t('flathub.empty')}</p>`;
    return;
  }

  $flathubList.innerHTML = apps
    .map(
      (app) => {
        const installed = flathubInstalled.has(app.appId);
        return `
    <div class="flathub-card" data-app-id="${escapeHtml(app.appId)}">
      <div class="flathub-card-header">
        ${
          app.icon
            ? `<img class="flathub-icon" src="${escapeHtml(app.icon)}" alt="" loading="lazy">`
            : '<div class="flathub-icon flathub-icon-placeholder">⬡</div>'
        }
        <div class="flathub-card-info">
          <div class="app-name">${escapeHtml(app.name)}</div>
          <div class="app-id">${escapeHtml(app.appId)}</div>
          ${app.verified ? `<span class="flathub-verified">${t('flathub.verified')}</span>` : ''}
        </div>
      </div>
      <p class="flathub-summary">${escapeHtml(app.summary || '')}</p>
      <div class="flathub-meta-row">
        ${app.developer ? `<span>${escapeHtml(app.developer)}</span>` : ''}
        ${app.license ? `<span>${escapeHtml(app.license)}</span>` : ''}
      </div>
      <div class="app-actions">
        ${
          installed
            ? `<button class="btn btn-secondary" disabled>${t('flathub.installed')}</button>`
            : `<button class="btn btn-primary btn-install-flathub" data-app-id="${escapeHtml(app.appId)}" data-app-name="${escapeHtml(app.name)}">${t('flathub.install')}</button>`
        }
      </div>
    </div>
  `;
      },
    )
    .join('');

  $flathubList.querySelectorAll('.btn-install-flathub').forEach((btn) => {
    btn.addEventListener('click', () => installFlathubApp(btn.dataset.appId, btn.dataset.appName, btn));
  });
}

async function refreshFlathubStatus() {
  const status = await strawwuHub.getFlathubStatus();
  if (status) {
    flathubInstalled = new Set(status.installed || []);
  }
}

async function refreshFlathubCatalog() {
  $flathubStatus.textContent = '';
  const query = $flathubSearch?.value || '';
  try {
    const data = await strawwuHub.searchFlathub(query);
    currentFlathubApps = data.apps || [];
    const metaParts = [t('flathub.count', { count: currentFlathubApps.length })];
    if (data.mock) metaParts.push(t('flathub.dev_fixture'));
    if (data.source === 'fixture-fallback') metaParts.push(t('flathub.api_fallback'));
    $flathubMeta.textContent = metaParts.join(' · ');
    renderFlathubApps(currentFlathubApps);
  } catch {
    $flathubList.innerHTML = `<p class="muted-text">${t('flathub.load_failed')}</p>`;
  }
}

async function installFlathubApp(appId, name, btn) {
  if (!window.confirm(t('flathub.install_confirm', { name }))) return;
  if (btn) {
    btn.disabled = true;
    btn.textContent = t('flathub.installing');
  }
  $flathubStatus.textContent = '';
  try {
    const result = await strawwuHub.installFlathub(appId);
    if (result.mock) {
      $flathubStatus.textContent = t('flathub.install_mock', { name });
    } else if (result.alreadyInstalled) {
      $flathubStatus.textContent = t('flathub.already_installed', { name });
    } else {
      $flathubStatus.textContent = t('flathub.installed_success', { name });
    }
    flathubInstalled.add(appId);
    renderFlathubApps(currentFlathubApps);
    setTimeout(() => {
      $flathubStatus.textContent = '';
    }, 4000);
  } catch {
    $flathubStatus.textContent = t('flathub.install_failed', { name });
    $flathubStatus.classList.add('status-error');
    if (btn) {
      btn.disabled = false;
      btn.textContent = t('flathub.install');
    }
    setTimeout(() => {
      $flathubStatus.textContent = '';
      $flathubStatus.classList.remove('status-error');
    }, 4000);
  }
}

if ($flathubSearch) {
  let flathubSearchTimer = null;
  $flathubSearch.addEventListener('input', () => {
    clearTimeout(flathubSearchTimer);
    flathubSearchTimer = setTimeout(refreshFlathubCatalog, 300);
  });
}
document.getElementById('btn-refresh-flathub')?.addEventListener('click', refreshFlathubCatalog);

// --- Drivers (GPU / firmware) ---
const VENDOR_LABELS = {
  nvidia: 'drivers.vendor.nvidia',
  amd: 'drivers.vendor.amd',
  intel: 'drivers.vendor.intel',
  unknown: 'drivers.vendor.unknown',
};

const STATUS_LABELS = {
  available: 'drivers.status.available',
  installed: 'drivers.status.installed',
  'in-kernel': 'drivers.status.in_kernel',
  unknown: 'drivers.status.unknown',
};

function vendorBadgeClass(vendor) {
  if (vendor === 'nvidia') return 'driver-vendor-nvidia';
  if (vendor === 'amd') return 'driver-vendor-amd';
  if (vendor === 'intel') return 'driver-vendor-intel';
  return 'driver-vendor-unknown';
}

function renderSecureBootWarning(secureBoot) {
  if (!secureBoot?.enabled || !secureBoot?.warning) {
    $driversSecureBoot.classList.add('hidden');
    $driversSecureBoot.innerHTML = '';
    return;
  }
  $driversSecureBoot.classList.remove('hidden');
  $driversSecureBoot.innerHTML = `
    <div class="drivers-warning-icon">⚠</div>
    <div>
      <div class="drivers-warning-title">${t('drivers.secure_boot_title')}</div>
      <p class="drivers-warning-text">${escapeHtml(secureBoot.warning)}</p>
      <p class="muted-text drivers-warning-plan">${t('drivers.secure_boot_plan', { plan: secureBoot.plan || 'post-sec-secureboot-route' })}</p>
    </div>
  `;
}

function renderDriverDevices(devices) {
  if (!devices.length) {
    $driversDevices.innerHTML = `<p class="muted-text">${t('drivers.no_devices')}</p>`;
    return;
  }

  $driversDevices.innerHTML = devices
    .map(
      (device) => `
    <div class="driver-card" data-pci="${escapeHtml(device.pci_id || '')}">
      <div class="driver-card-header">
        <div>
          <div class="app-name">${escapeHtml(device.model || device.pci_id || 'GPU')}</div>
          <div class="app-id">${escapeHtml(device.pci_id || '')}</div>
        </div>
        <span class="driver-vendor-badge ${vendorBadgeClass(device.vendor)}">${t(VENDOR_LABELS[device.vendor] || VENDOR_LABELS.unknown)}</span>
      </div>
      <div class="driver-meta-row">
        <span>${t('drivers.current_driver')}: ${escapeHtml(device.driver_label || device.driver || t('drivers.none'))}</span>
        <span>${t(STATUS_LABELS[device.status] || STATUS_LABELS.unknown)}</span>
      </div>
    </div>
  `,
    )
    .join('');
}

function renderDriverPackages(drivers) {
  if (!drivers.length) {
    $driversPackages.innerHTML = `<p class="muted-text">${t('drivers.no_packages')}</p>`;
    return;
  }

  $driversPackages.innerHTML = drivers
    .map(
      (driver) => `
    <div class="driver-card" data-package="${escapeHtml(driver.package)}">
      <div class="driver-card-header">
        <div>
          <div class="app-name">${escapeHtml(driver.label || driver.package)}</div>
          <div class="app-id">${escapeHtml(driver.package)}</div>
        </div>
        <span class="driver-vendor-badge ${vendorBadgeClass(driver.vendor)}">${t(VENDOR_LABELS[driver.vendor] || VENDOR_LABELS.unknown)}</span>
      </div>
      <div class="driver-meta-row">
        ${driver.recommended ? `<span class="driver-recommended">${t('drivers.recommended')}</span>` : ''}
        <span>${driver.installed ? t('drivers.status.installed') : t('drivers.status.available')}</span>
      </div>
      <div class="app-actions">
        ${
          driver.installed
            ? `<button class="btn btn-secondary" disabled>${t('drivers.installed')}</button>`
            : `<button class="btn btn-primary btn-install-driver" data-package="${escapeHtml(driver.package)}" data-label="${escapeHtml(driver.label || driver.package)}">${t('drivers.install')}</button>`
        }
      </div>
    </div>
  `,
    )
    .join('');

  $driversPackages.querySelectorAll('.btn-install-driver').forEach((btn) => {
    btn.addEventListener('click', () => installDriverPackage(btn.dataset.package, btn.dataset.label, btn));
  });
}

async function refreshDrivers() {
  $driversStatus.textContent = '';
  try {
    const data = await strawwuHub.getDriversStatus();
    const metaParts = [
      t('drivers.device_count', { count: (data.devices || []).length }),
      t('drivers.package_count', { count: (data.drivers || []).length }),
    ];
    if (data.mock) metaParts.push(t('drivers.dev_fixture'));
    if (data.source === 'fixture-fallback') metaParts.push(t('drivers.cli_fallback'));
    $driversMeta.textContent = metaParts.join(' · ');
    renderSecureBootWarning(data.secureBoot);
    renderDriverDevices(data.devices || []);
    renderDriverPackages(data.drivers || []);
  } catch {
    $driversDevices.innerHTML = `<p class="muted-text">${t('drivers.load_failed')}</p>`;
    $driversPackages.innerHTML = '';
  }
}

async function installDriverPackage(packageName, label, btn) {
  if (!window.confirm(t('drivers.install_confirm', { name: label }))) return;
  if (btn) {
    btn.disabled = true;
    btn.textContent = t('drivers.installing');
  }
  $driversStatus.textContent = '';
  try {
    const result = await strawwuHub.installDriver(packageName);
    if (result.mock) {
      $driversStatus.textContent = t('drivers.install_mock', { name: label });
    } else if (result.success) {
      $driversStatus.textContent = t('drivers.installed_success', { name: label });
    } else {
      throw new Error(result.message || 'install failed');
    }
    await refreshDrivers();
    setTimeout(() => {
      $driversStatus.textContent = '';
    }, 4000);
  } catch {
    $driversStatus.textContent = t('drivers.install_failed', { name: label });
    $driversStatus.classList.add('status-error');
    if (btn) {
      btn.disabled = false;
      btn.textContent = t('drivers.install');
    }
    setTimeout(() => {
      $driversStatus.textContent = '';
      $driversStatus.classList.remove('status-error');
    }, 4000);
  }
}

document.getElementById('btn-refresh-drivers')?.addEventListener('click', refreshDrivers);

// --- Software Sources ---
const SOURCE_TYPE_KEYS = {
  apt: 'sources.type.apt',
  flatpak: 'sources.type.flatpak',
};

const SOURCE_CATEGORY_KEYS = {
  strawwu: 'sources.category.strawwu',
  security: 'sources.category.security',
  'third-party': 'sources.category.third-party',
  flatpak: 'sources.category.flatpak',
};

function renderSourceCard(source) {
  const readonly = Boolean(source.readonly);
  const typeKey = SOURCE_TYPE_KEYS[source.type] || source.type;
  const categoryKey = SOURCE_CATEGORY_KEYS[source.category] || source.category;
  const suites = source.suites ? `<span>${escapeHtml(source.suites)}</span>` : '';

  return `
    <article class="source-card${readonly ? ' readonly' : ''}" data-source-id="${escapeHtml(source.id)}">
      <div class="source-card-info">
        <div class="source-card-title">${escapeHtml(source.label || source.id)}</div>
        <div class="source-card-uri">${escapeHtml(source.uri || '')}</div>
        <div class="source-card-meta">
          <span class="source-type-badge">${t(typeKey)}</span>
          ${categoryKey ? `<span class="source-category-badge">${t(categoryKey)}</span>` : ''}
          ${readonly ? `<span class="source-readonly-badge">${t('sources.readonly')}</span>` : ''}
          ${suites}
        </div>
      </div>
      <div class="source-toggle">
        ${
          readonly
            ? `<span class="muted-text">${source.enabled ? t('sources.enabled') : t('sources.disabled')}</span>`
            : `<label class="toggle-switch">
                <input type="checkbox" class="source-enable-toggle" data-source-id="${escapeHtml(source.id)}" data-label="${escapeHtml(source.label || source.id)}" ${source.enabled ? 'checked' : ''}>
                <span>${source.enabled ? t('sources.enabled') : t('sources.disabled')}</span>
              </label>`
        }
      </div>
    </article>
  `;
}

function renderSourcesList(sources) {
  if (!sources.length) {
    $sourcesList.innerHTML = `<p class="muted-text">${t('sources.no_sources')}</p>`;
    return;
  }
  $sourcesList.innerHTML = sources.map(renderSourceCard).join('');
  $sourcesList.querySelectorAll('.source-enable-toggle').forEach((input) => {
    input.addEventListener('change', () => handleSourceToggle(input));
  });
}

async function refreshSoftwareSources() {
  $sourcesStatus.textContent = '';
  $sourcesStatus.classList.remove('status-error');
  try {
    const data = await strawwuHub.getSoftwareSourcesStatus();
    const metaParts = [
      t('sources.source_count', { count: (data.sources || []).length }),
      t('sources.enabled_count', { count: data.summary?.enabled ?? 0 }),
    ];
    if (data.mock) metaParts.push(t('sources.dev_fixture'));
    if (data.source === 'fixture-fallback') metaParts.push(t('sources.cli_fallback'));
    $sourcesMeta.textContent = metaParts.join(' · ');
    renderSourcesList(data.sources || []);
  } catch (err) {
    $sourcesList.innerHTML = `<p class="muted-text">${t('sources.load_failed')}</p>`;
    $sourcesStatus.textContent = err.message || t('sources.load_failed');
    $sourcesStatus.classList.add('status-error');
  }
}

async function handleSourceToggle(input) {
  const sourceId = input.dataset.sourceId;
  const label = input.dataset.label || sourceId;
  const enabled = input.checked;
  const confirmKey = enabled ? 'sources.toggle_confirm_enable' : 'sources.toggle_confirm_disable';
  if (!window.confirm(t(confirmKey, { name: label }))) {
    input.checked = !enabled;
    return;
  }

  $sourcesStatus.textContent = '';
  $sourcesStatus.classList.remove('status-error');
  try {
    const result = await strawwuHub.toggleSoftwareSource(sourceId, enabled);
    if (!result.success) {
      throw new Error(result.error || t('sources.toggle_failed', { name: label }));
    }
    if (result.mock) {
      $sourcesStatus.textContent = t('sources.toggle_mock', { name: label });
    } else {
      $sourcesStatus.textContent = t('sources.toggle_success', { name: label });
    }
    await refreshSoftwareSources();
  } catch (err) {
    input.checked = !enabled;
    $sourcesStatus.textContent = err.message || t('sources.toggle_failed', { name: label });
    $sourcesStatus.classList.add('status-error');
  }
}

async function checkSoftwareUpdates() {
  const btn = document.getElementById('btn-check-updates');
  if (btn) btn.disabled = true;
  $sourcesStatus.textContent = '';
  $sourcesStatus.classList.remove('status-error');
  try {
    const result = await strawwuHub.checkSoftwareUpdates();
    if (!result.success) {
      throw new Error(result.error || t('sources.updates_check_failed'));
    }
    const count = result.upgradable ?? 0;
    $sourcesStatus.textContent =
      count > 0 ? t('sources.updates_found', { count }) : t('sources.updates_none');
  } catch (err) {
    $sourcesStatus.textContent = err.message || t('sources.updates_check_failed');
    $sourcesStatus.classList.add('status-error');
  } finally {
    if (btn) btn.disabled = false;
  }
}

document.getElementById('btn-refresh-sources')?.addEventListener('click', refreshSoftwareSources);
document.getElementById('btn-check-updates')?.addEventListener('click', checkSoftwareUpdates);

// --- Backup ---
function renderBackupCard(snap) {
  const kind = snap.kind || 'system';
  const kindKey = kind === 'upgrade' ? 'backup.kind_upgrade' : 'backup.kind_system';
  const version =
    kind === 'upgrade' && snap.from_version
      ? t('backup.from_version', { version: snap.from_version })
      : snap.label || '';
  return `
    <article class="source-card backup-card" data-snapshot="${escapeHtml(snap.name)}">
      <div class="source-info">
        <div class="source-title-row">
          <span class="source-label">${escapeHtml(snap.name)}</span>
          <span class="source-category-badge">${t(kindKey)}</span>
        </div>
        <div class="source-desc muted-text">
          ${escapeHtml(snap.backend || '')}
          ${version ? ` · ${escapeHtml(version)}` : ''}
          ${snap.created_at ? ` · ${escapeHtml(snap.created_at)}` : ''}
        </div>
      </div>
      <div class="source-toggle">
        <button class="btn btn-secondary btn-preview-restore" data-snapshot="${escapeHtml(snap.name)}">
          ${t('backup.preview_restore')}
        </button>
      </div>
    </article>
  `;
}

function renderBackupList(snapshots) {
  if (!snapshots.length) {
    $backupList.innerHTML = `<p class="muted-text">${t('backup.no_snapshots')}</p>`;
    return;
  }
  $backupList.innerHTML = snapshots.map(renderBackupCard).join('');
  $backupList.querySelectorAll('.btn-preview-restore').forEach((btn) => {
    btn.addEventListener('click', () => handlePreviewRestore(btn.dataset.snapshot));
  });
}

async function refreshBackup() {
  $backupStatus.textContent = '';
  $backupStatus.classList.remove('status-error');
  try {
    const [status, listed] = await Promise.all([
      strawwuHub.getBackupStatus(),
      strawwuHub.listBackupSnapshots(),
    ]);
    const metaParts = [
      t('backup.snapshot_count', { count: status.snapshotCount ?? 0 }),
      t('backup.backend', { name: status.backends?.preferred || 'rsync' }),
    ];
    if (status.mock) metaParts.push(t('backup.dev_fixture'));
    if (status.source === 'fixture-fallback') metaParts.push(t('backup.cli_fallback'));
    metaParts.push(t('backup.upgrade_hook'));
    $backupMeta.textContent = metaParts.join(' · ');
    renderBackupList(listed.snapshots || []);
  } catch (err) {
    $backupList.innerHTML = `<p class="muted-text">${t('backup.load_failed')}</p>`;
    $backupStatus.textContent = err.message || t('backup.load_failed');
    $backupStatus.classList.add('status-error');
  }
}

async function handleCreateBackup() {
  const btn = document.getElementById('btn-create-backup');
  if (btn) btn.disabled = true;
  $backupStatus.textContent = '';
  $backupStatus.classList.remove('status-error');
  try {
    const result = await strawwuHub.createBackupSnapshot('hub-manual');
    if (!result.success && result.error) {
      throw new Error(result.error);
    }
    $backupStatus.textContent = t('backup.created', {
      name: result.snapshot || 'snapshot',
    });
    await refreshBackup();
  } catch (err) {
    $backupStatus.textContent = err.message || t('backup.create_failed');
    $backupStatus.classList.add('status-error');
  } finally {
    if (btn) btn.disabled = false;
  }
}

async function handlePreviewRestore(name) {
  $backupStatus.textContent = '';
  $backupStatus.classList.remove('status-error');
  try {
    const result = await strawwuHub.previewBackupRestore(name);
    if (!result.success) {
      throw new Error(result.error || t('backup.restore_failed'));
    }
    const actions = (result.actions || []).join('\n');
    window.alert(`${t('backup.restore_plan', { name })}\n\n${actions}`);
  } catch (err) {
    $backupStatus.textContent = err.message || t('backup.restore_failed');
    $backupStatus.classList.add('status-error');
  }
}

document.getElementById('btn-refresh-backup')?.addEventListener('click', refreshBackup);
document.getElementById('btn-create-backup')?.addEventListener('click', handleCreateBackup);

// --- Devices (device-proxy) ---
function renderDeviceTierSummary(summary) {
  const tiers = Object.entries(summary || {}).sort(([a], [b]) => a.localeCompare(b));
  if (!tiers.length) {
    $devicesTierSummary.innerHTML = `<p class="muted-text">${t('devices.no_tiers')}</p>`;
    return;
  }
  $devicesTierSummary.innerHTML = tiers
    .map(
      ([tier, count]) => `
    <div class="device-tier-card">
      <span class="device-tier-label">${escapeHtml(tier)}</span>
      <span class="device-tier-count">${escapeHtml(String(count))}</span>
    </div>
  `,
    )
    .join('');
}

function renderDeviceList(devices) {
  if (!devices.length) {
    $devicesList.innerHTML = `<p class="muted-text">${t('devices.no_devices')}</p>`;
    return;
  }
  $devicesList.innerHTML = devices
    .map(
      (device) => `
    <div class="device-card" data-tier="${escapeHtml(device.tier || '')}">
      <div class="device-card-header">
        <div>
          <div class="app-name">${escapeHtml(device.class || 'Device')}</div>
          <div class="app-id">${escapeHtml(device.win32_path || '')}</div>
        </div>
        <span class="device-tier-badge">${escapeHtml(device.tier || '')}</span>
      </div>
      <div class="device-card-meta">
        <span>${escapeHtml(device.linux_path || '')}</span>
        <span class="device-status ${String(device.status || '').toLowerCase()}">${escapeHtml(device.status || '')}</span>
      </div>
      <p class="muted-text device-notes">${escapeHtml(device.notes || '')}</p>
    </div>
  `,
    )
    .join('');
}

async function refreshDevices() {
  $devicesHotplugStatus.textContent = '';
  try {
    const data = await strawwuHub.getDeviceProxyStatus();
    const metaParts = [
      t('devices.device_count', { count: (data.devices || []).length }),
    ];
    if (data.mock) metaParts.push(t('devices.dev_fixture'));
    if (data.source === 'fixture-fallback') metaParts.push(t('devices.cli_fallback'));
    $devicesMeta.textContent = metaParts.join(' · ');
    renderDeviceTierSummary(data.tierSummary || {});
    renderDeviceList(data.devices || []);
    if ((data.udevTags || []).length) {
      $devicesHotplugStatus.textContent = t('devices.hotplug_tags', {
        tags: (data.udevTags || []).join(', '),
      });
    }
  } catch (err) {
    $devicesList.innerHTML = `<p class="muted-text">${t('devices.load_failed')}</p>`;
    $devicesTierSummary.innerHTML = '';
    $devicesHotplugStatus.textContent = err.message || t('devices.load_failed');
  }
}

document.getElementById('btn-refresh-devices')?.addEventListener('click', refreshDevices);

// --- Live Updates ---
strawwuHub.onStatusUpdate((data) => {
  if (data) renderStatus(data);
});

strawwuHub.onLogEntry((data) => {
  if (data) {
    currentLogs.push(data);
    if (currentLogs.length > 500) currentLogs.shift();
    renderLogs(currentLogs);
  }
});

// --- Utilities ---
function escapeHtml(str) {
  // Escape quotes too: values are interpolated into attribute contexts
  // (data-*, src=...) where textContent→innerHTML alone leaves " and '
  // unescaped, allowing attribute-breakout injection.
  return String(str ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// --- Init ---
initI18n().then(() => {
  refreshStatus();
  refreshLogs();
  initUpdateChannel();
  refreshWinCompat();
  renderSystemShortcuts();
  renderAbout();
  refreshApps();
  refreshFlathubStatus().then(refreshFlathubCatalog);
  refreshDrivers();
  refreshSoftwareSources();
  refreshBackup();
  refreshDevices();
});

setInterval(refreshStatus, 10000);

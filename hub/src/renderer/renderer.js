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

let currentLogs = [];
let currentTranslations = {};
let availableLocales = [];
let currentLocale = 'en';

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
  $wincompatStatus.innerHTML = `
    <div class="info-row">
      <span class="info-label">${t('wincompat.session')}</span>
      <span class="info-value">${escapeHtml(status.output || t('wincompat.unavailable'))}</span>
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
          <span>${escapeHtml(g.backend)}</span>
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
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

// --- Init ---
initI18n().then(() => {
  refreshStatus();
  refreshLogs();
  initUpdateChannel();
  refreshWinCompat();
  renderSystemShortcuts();
  renderAbout();
});

setInterval(refreshStatus, 10000);

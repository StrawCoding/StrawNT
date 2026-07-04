const { strawwuHub } = window;

const $statusGrid = document.getElementById('status-grid');
const $logContainer = document.getElementById('log-container');
const $logSubsystemFilter = document.getElementById('log-subsystem-filter');
const $logLevelFilter = document.getElementById('log-level-filter');
const $channelStatus = document.getElementById('channel-status');

let currentLogs = [];

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
          <span class="metric-label">PID</span>
          <span class="metric-value">${s.pid}</span>
        </div>
        <div class="metric">
          <span class="metric-label">Uptime</span>
          <span class="metric-value">${formatUptime(s.uptime)}</span>
        </div>
        <div class="metric">
          <span class="metric-label">Memory</span>
          <span class="metric-value">${s.memory_mb} MB</span>
        </div>
        <div class="metric">
          <span class="metric-label">CPU</span>
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
  return d.toLocaleTimeString('zh-TW', { hour12: false });
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
    $channelStatus.textContent = `已切換至 ${result} 通道`;
    setTimeout(() => {
      $channelStatus.textContent = '';
    }, 3000);
  });
});

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
refreshStatus();
refreshLogs();
initUpdateChannel();

setInterval(refreshStatus, 10000);

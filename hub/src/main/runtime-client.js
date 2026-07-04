const net = require('net');
const EventEmitter = require('events');
const { SOCKET_PATH, SUBSYSTEM_NAMES } = require('../common/constants');

class RuntimeClient extends EventEmitter {
  constructor(socketPath = SOCKET_PATH) {
    super();
    this._socketPath = socketPath;
    this._socket = null;
    this._connected = false;
    this._stopped = false;
    this._buffer = '';
    this._reconnectTimer = null;
  }

  connect() {
    if (this._connected) return;
    this._stopped = false;

    this._socket = net.createConnection(this._socketPath, () => {
      this._connected = true;
      this.emit('connected');
      this._send({ type: 'subscribe', topics: ['status', 'logs'] });
    });

    this._socket.on('data', (chunk) => {
      this._buffer += chunk.toString();
      this._processBuffer();
    });

    this._socket.on('error', (err) => {
      this._connected = false;
      this.emit('error', err);
      this._scheduleReconnect();
    });

    this._socket.on('close', () => {
      this._connected = false;
      this.emit('disconnected');
      this._scheduleReconnect();
    });
  }

  disconnect() {
    this._stopped = true;
    clearTimeout(this._reconnectTimer);
    if (this._socket) {
      this._socket.destroy();
      this._socket = null;
    }
    this._connected = false;
  }

  get connected() {
    return this._connected;
  }

  _send(obj) {
    if (this._socket && this._connected) {
      this._socket.write(JSON.stringify(obj) + '\n');
    }
  }

  _processBuffer() {
    const lines = this._buffer.split('\n');
    this._buffer = lines.pop();
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const msg = JSON.parse(line);
        this.emit('message', msg);
      } catch {
        // non-JSON line, ignore
      }
    }
  }

  _scheduleReconnect() {
    if (this._stopped) return;
    clearTimeout(this._reconnectTimer);
    this._reconnectTimer = setTimeout(() => this.connect(), 3000);
  }

  async requestStatus() {
    this._send({ type: 'query', topic: 'status' });
  }

  async requestLogs(subsystem, limit = 100) {
    this._send({ type: 'query', topic: 'logs', subsystem, limit });
  }

  async setUpdateChannel(channel) {
    this._send({ type: 'command', action: 'set_update_channel', channel });
  }

  getMockStatus() {
    return SUBSYSTEM_NAMES.map((name) => ({
      name,
      status: 'running',
      pid: Math.floor(Math.random() * 30000) + 1000,
      uptime: Math.floor(Math.random() * 86400),
      memory_mb: Math.floor(Math.random() * 512) + 64,
      cpu_percent: +(Math.random() * 15).toFixed(1),
    }));
  }

  getMockLogs(subsystem) {
    const levels = ['INFO', 'DEBUG', 'WARN', 'ERROR'];
    const messages = [
      'Session initialized',
      'Process graph updated',
      'IPC channel opened',
      'Profile loaded',
      'Bridge handshake complete',
      'GPU context acquired',
      'Filesystem mount ready',
      'Registry hive loaded',
      'Health check passed',
      'Update check completed',
    ];
    return Array.from({ length: 20 }, (_, i) => ({
      timestamp: new Date(Date.now() - (20 - i) * 60000).toISOString(),
      level: levels[Math.floor(Math.random() * levels.length)],
      subsystem: subsystem || SUBSYSTEM_NAMES[Math.floor(Math.random() * SUBSYSTEM_NAMES.length)],
      message: messages[Math.floor(Math.random() * messages.length)],
    }));
  }
}

module.exports = RuntimeClient;

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const net = require('net');
const path = require('path');
const os = require('os');
const fs = require('fs');

const RuntimeClient = require('../src/main/runtime-client');

describe('RuntimeClient', () => {
  it('should generate mock status for all subsystems', () => {
    const client = new RuntimeClient('/nonexistent.sock');
    const status = client.getMockStatus();

    assert.equal(status.length, 4);
    const names = status.map((s) => s.name);
    assert.ok(names.includes('strawwu-runtime'));
    assert.ok(names.includes('strawwu-bridge'));
    assert.ok(names.includes('strawwu-nt'));
    assert.ok(names.includes('strawwu-launcher'));

    for (const s of status) {
      assert.equal(typeof s.pid, 'number');
      assert.equal(typeof s.uptime, 'number');
      assert.equal(typeof s.memory_mb, 'number');
      assert.equal(typeof s.cpu_percent, 'number');
      assert.equal(s.status, 'running');
    }
  });

  it('should generate mock logs with correct structure', () => {
    const client = new RuntimeClient('/nonexistent.sock');
    const logs = client.getMockLogs();

    assert.equal(logs.length, 20);
    for (const entry of logs) {
      assert.ok(entry.timestamp);
      assert.ok(['INFO', 'DEBUG', 'WARN', 'ERROR'].includes(entry.level));
      assert.equal(typeof entry.subsystem, 'string');
      assert.equal(typeof entry.message, 'string');
    }
  });

  it('should generate logs filtered by subsystem', () => {
    const client = new RuntimeClient('/nonexistent.sock');
    const logs = client.getMockLogs('strawwu-bridge');

    for (const entry of logs) {
      assert.equal(entry.subsystem, 'strawwu-bridge');
    }
  });

  it('should connect to a Unix socket server', async () => {
    const sockPath = path.join(os.tmpdir(), `strawwu-test-${Date.now()}.sock`);
    const connections = [];

    const server = net.createServer((conn) => {
      connections.push(conn);
      conn.on('data', (data) => {
        const msg = JSON.parse(data.toString().trim());
        if (msg.type === 'subscribe') {
          conn.write(
            JSON.stringify({ topic: 'status', data: [{ name: 'test', status: 'running' }] }) +
              '\n',
          );
        }
      });
    });

    await new Promise((resolve) => server.listen(sockPath, resolve));

    const client = new RuntimeClient(sockPath);

    const messageReceived = new Promise((resolve) => {
      client.on('message', (msg) => {
        if (msg.topic === 'status') resolve(msg);
      });
    });

    client.connect();

    const msg = await messageReceived;
    assert.equal(msg.topic, 'status');
    assert.equal(msg.data[0].name, 'test');

    client.disconnect();
    connections.forEach((c) => c.destroy());
    await new Promise((resolve) => server.close(resolve));
    try { fs.unlinkSync(sockPath); } catch {}
  });

  it('should emit disconnected event on socket close', async () => {
    const sockPath = path.join(os.tmpdir(), `strawwu-test-dc-${Date.now()}.sock`);
    const connections = [];

    const server = net.createServer((conn) => {
      connections.push(conn);
    });
    await new Promise((resolve) => server.listen(sockPath, resolve));

    const client = new RuntimeClient(sockPath);

    const connected = new Promise((resolve) => client.on('connected', resolve));
    client.connect();
    await connected;

    assert.equal(client.connected, true);

    const disconnected = new Promise((resolve) => client.on('disconnected', resolve));
    client._socket.destroy();
    await disconnected;

    assert.equal(client.connected, false);
    client.disconnect();
    connections.forEach((c) => c.destroy());
    await new Promise((resolve) => server.close(resolve));
    try { fs.unlinkSync(sockPath); } catch {}
  });
});

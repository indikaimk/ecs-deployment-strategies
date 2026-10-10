const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const { app, server } = require('../src/server');

// Helper to make local HTTP requests
function request(path, options = {}) {
  return new Promise((resolve, reject) => {
    const port = server.address().port;
    const req = http.request(
      {
        host: '127.0.0.1',
        port,
        path,
        method: options.method || 'GET',
        headers: options.headers || {},
      },
      (res) => {
        let body = '';
        res.on('data', (chunk) => (body += chunk));
        res.on('end', () => {
          let json = null;
          try {
            json = JSON.parse(body);
          } catch (_) {}
          resolve({ status: res.statusCode, headers: res.headers, body, json });
        });
      }
    );
    req.on('error', reject);
    if (options.body) {
      req.write(typeof options.body === 'string' ? options.body : JSON.stringify(options.body));
    }
    req.end();
  });
}

test('ECS Demo App - API & Health Check Tests', async (t) => {
  t.after(() => {
    server.close();
  });

  await t.test('GET /health returns 200 and healthy status', async () => {
    const res = await request('/health');
    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.json.status, 'HEALTHY');
    assert.strictEqual(res.headers['x-app-version'], 'v1.0.0');
  });

  await t.test('GET /api/info returns instance metadata', async () => {
    const res = await request('/api/info');
    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.json.version, 'v1.0.0');
    assert.strictEqual(res.json.color, 'blue');
    assert.strictEqual(res.json.isFaulty, false);
    assert.ok(res.json.hostname);
  });

  await t.test('GET /api/ping returns 200 OK', async () => {
    const res = await request('/api/ping');
    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.json.ok, true);
    assert.strictEqual(res.json.color, 'blue');
  });

  await t.test('Fault Injection - /api/fault/fail triggers HTTP 500 on /health', async () => {
    const faultRes = await request('/api/fault/fail', { method: 'POST' });
    assert.strictEqual(faultRes.status, 200);
    assert.strictEqual(faultRes.json.isFaulty, true);

    const healthRes = await request('/health');
    assert.strictEqual(healthRes.status, 500);
    assert.strictEqual(healthRes.json.status, 'UNHEALTHY');

    const pingRes = await request('/api/ping');
    assert.strictEqual(pingRes.status, 500);
  });

  await t.test('Fault Recovery - /api/fault/recover restores HTTP 200', async () => {
    const recoverRes = await request('/api/fault/recover', { method: 'POST' });
    assert.strictEqual(recoverRes.status, 200);
    assert.strictEqual(recoverRes.json.isFaulty, false);

    const healthRes = await request('/health');
    assert.strictEqual(healthRes.status, 200);
    assert.strictEqual(healthRes.json.status, 'HEALTHY');
  });
});

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

test('server writes manual overrides on POST', async () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'learning-research-server-'));
  const overridesDir = path.join(tempRoot, 'knowledge-tree');
  const overridesPath = path.join(overridesDir, 'manual-overrides.json');
  const webDir = path.join(tempRoot, 'web');
  fs.mkdirSync(overridesDir, { recursive: true });
  fs.mkdirSync(webDir, { recursive: true });
  fs.writeFileSync(overridesPath, JSON.stringify({ nodes: [] }), 'utf8');
  fs.writeFileSync(path.join(webDir, 'index.html'), '<!doctype html><h1>Dashboard</h1>', 'utf8');

  const { createServer } = await import('../../web/server.mjs');
  const server = await createServer({ rootDir: tempRoot, port: 0 });

  try {
    const address = server.address();
    const response = await fetch(`http://127.0.0.1:${address.port}/api/knowledge-tree/overrides`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ nodes: [{ id: 'demo', status: 'want' }] })
    });

    assert.equal(response.status, 200);
    const saved = JSON.parse(fs.readFileSync(overridesPath, 'utf8'));
    assert.equal(saved.nodes[0].id, 'demo');
  } finally {
    server.close();
  }
});

test('server serves static index and blocks traversal', async () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'learning-research-static-'));
  const overridesDir = path.join(tempRoot, 'knowledge-tree');
  const overridesPath = path.join(overridesDir, 'manual-overrides.json');
  const webDir = path.join(tempRoot, 'web');
  fs.mkdirSync(overridesDir, { recursive: true });
  fs.mkdirSync(webDir, { recursive: true });
  fs.writeFileSync(overridesPath, JSON.stringify({ secret: true }), 'utf8');
  fs.writeFileSync(path.join(webDir, 'index.html'), '<!doctype html><h1>Home</h1>', 'utf8');

  const { createServer } = await import('../../web/server.mjs');
  const server = await createServer({ rootDir: tempRoot, port: 0 });

  try {
    const address = server.address();
    const indexResponse = await fetch(`http://127.0.0.1:${address.port}/`);
    const indexText = await indexResponse.text();
    assert.equal(indexResponse.status, 200);
    assert.match(indexText, /Home/);

    const traversalResponse = await fetch(`http://127.0.0.1:${address.port}/../knowledge-tree/manual-overrides.json`);
    assert.equal(traversalResponse.status, 404);
  } finally {
    server.close();
  }
});

test('server rejects invalid override JSON', async () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'learning-research-invalid-json-'));
  const overridesDir = path.join(tempRoot, 'knowledge-tree');
  const overridesPath = path.join(overridesDir, 'manual-overrides.json');
  const webDir = path.join(tempRoot, 'web');
  fs.mkdirSync(overridesDir, { recursive: true });
  fs.mkdirSync(webDir, { recursive: true });
  fs.writeFileSync(overridesPath, JSON.stringify({ nodes: [] }), 'utf8');
  fs.writeFileSync(path.join(webDir, 'index.html'), '<!doctype html><h1>Home</h1>', 'utf8');

  const { createServer } = await import('../../web/server.mjs');
  const server = await createServer({ rootDir: tempRoot, port: 0 });

  try {
    const address = server.address();
    const response = await fetch(`http://127.0.0.1:${address.port}/api/knowledge-tree/overrides`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{invalid json'
    });

    assert.equal(response.status, 400);
    const saved = JSON.parse(fs.readFileSync(overridesPath, 'utf8'));
    assert.equal(saved.nodes.length, 0);
  } finally {
    server.close();
  }
});

test('server returns 413 for oversized override payloads', async () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'learning-research-too-large-'));
  const overridesDir = path.join(tempRoot, 'knowledge-tree');
  const overridesPath = path.join(overridesDir, 'manual-overrides.json');
  const webDir = path.join(tempRoot, 'web');
  fs.mkdirSync(overridesDir, { recursive: true });
  fs.mkdirSync(webDir, { recursive: true });
  fs.writeFileSync(overridesPath, JSON.stringify({ nodes: [] }), 'utf8');
  fs.writeFileSync(path.join(webDir, 'index.html'), '<!doctype html><h1>Home</h1>', 'utf8');

  const { createServer } = await import('../../web/server.mjs');
  const server = await createServer({ rootDir: tempRoot, port: 0 });

  try {
    const address = server.address();
    const largeNode = 'x'.repeat(1024 * 1024);
    const response = await fetch(`http://127.0.0.1:${address.port}/api/knowledge-tree/overrides`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ nodes: [{ id: largeNode, status: 'want' }] })
    });

    assert.equal(response.status, 413);
    const saved = JSON.parse(fs.readFileSync(overridesPath, 'utf8'));
    assert.equal(saved.nodes.length, 0);
  } finally {
    server.close();
  }
});

test('dashboard homepage is served from the project web root', async () => {
  const { createServer } = await import('../../web/server.mjs');
  const server = await createServer({ rootDir: process.cwd(), port: 0 });

  try {
    const address = server.address();
    const response = await fetch(`http://127.0.0.1:${address.port}/`);
    const html = await response.text();

    assert.equal(response.status, 200);
    assert.match(html, /assets\/home\.js/);
  } finally {
    server.close();
  }
});

test('server returns existing manual overrides through GET API', async () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'learning-research-get-overrides-'));
  const overridesDir = path.join(tempRoot, 'knowledge-tree');
  const overridesPath = path.join(overridesDir, 'manual-overrides.json');
  const webDir = path.join(tempRoot, 'web');
  fs.mkdirSync(overridesDir, { recursive: true });
  fs.mkdirSync(webDir, { recursive: true });
  fs.writeFileSync(overridesPath, JSON.stringify({ nodes: [{ id: 'saved', status: 'learning' }] }), 'utf8');
  fs.writeFileSync(path.join(webDir, 'index.html'), '<!doctype html><h1>Home</h1>', 'utf8');

  const { createServer } = await import('../../web/server.mjs');
  const server = await createServer({ rootDir: tempRoot, port: 0 });

  try {
    const address = server.address();
    const response = await fetch(`http://127.0.0.1:${address.port}/api/knowledge-tree/overrides`);
    const payload = await response.json();

    assert.equal(response.status, 200);
    assert.equal(payload.nodes[0].id, 'saved');
  } finally {
    server.close();
  }
});

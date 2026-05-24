import childProcess from 'node:child_process';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MAX_REQUEST_BYTES = 1024 * 1024;

const mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.md': 'text/markdown; charset=utf-8'
};

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, { 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(payload));
}

function resolvePathWithin(baseDir, requestPath) {
  const candidate = path.resolve(baseDir, `.${requestPath}`);

  if (candidate !== baseDir && !candidate.startsWith(`${baseDir}${path.sep}`)) {
    return null;
  }

  return candidate;
}

export async function createServer(options = {}) {
  const rootDir = options.rootDir ?? path.resolve(__dirname, '..');
  const port = options.port ?? 4173;
  const webRoot = path.join(rootDir, 'web');
  const overridesPath = path.join(rootDir, 'knowledge-tree', 'manual-overrides.json');
  const buildKnowledgeTreeScript = path.join(rootDir, 'build_knowledge_tree.ps1');

  const server = http.createServer((req, res) => {
    const parsedUrl = new URL(req.url ?? '/', 'http://127.0.0.1');
    const pathname = parsedUrl.pathname;

    if (req.method === 'GET' && pathname === '/api/knowledge-tree/overrides') {
      try {
        if (!fs.existsSync(overridesPath)) {
          sendJson(res, 200, { nodes: [] });
          return;
        }

        const payload = JSON.parse(fs.readFileSync(overridesPath, 'utf8'));
        sendJson(res, 200, payload);
      } catch (error) {
        sendJson(res, 500, { ok: false, error: 'Failed to read overrides' });
      }
      return;
    }

    if (req.method === 'POST' && pathname === '/api/knowledge-tree/overrides') {
      let body = '';
      let tooLarge = false;
      req.on('data', chunk => {
        if (tooLarge) {
          return;
        }
        body += chunk;
        if (Buffer.byteLength(body, 'utf8') > MAX_REQUEST_BYTES) {
          tooLarge = true;
          sendJson(res, 413, { ok: false, error: 'Request body too large' });
          req.resume();
        }
      });
      req.on('error', () => {
        if (!res.writableEnded) {
          sendJson(res, 400, { ok: false, error: 'Request stream error' });
        }
      });
      req.on('end', () => {
        if (tooLarge) {
          return;
        }

        try {
          const payload = JSON.parse(body);
          if (!payload || !Array.isArray(payload.nodes)) {
            sendJson(res, 400, { ok: false, error: 'Invalid override payload' });
            return;
          }

          fs.mkdirSync(path.dirname(overridesPath), { recursive: true });
          fs.writeFileSync(overridesPath, JSON.stringify(payload, null, 2), 'utf8');

          if (fs.existsSync(buildKnowledgeTreeScript)) {
            const rebuild = childProcess.spawnSync('pwsh', ['-File', buildKnowledgeTreeScript], {
              cwd: rootDir,
              encoding: 'utf8'
            });
            if (rebuild.status !== 0) {
              sendJson(res, 500, { ok: false, error: 'Failed to rebuild knowledge tree' });
              return;
            }
          }

          sendJson(res, 200, { ok: true });
        } catch (error) {
          if (error instanceof SyntaxError) {
            sendJson(res, 400, { ok: false, error: 'Invalid JSON body' });
            return;
          }

          sendJson(res, 500, { ok: false, error: 'Failed to save overrides' });
        }
      });
      return;
    }

    let target = null;
    if (pathname === '/' || /^\/(index|archive|weekly|knowledge)\.html$/.test(pathname) || pathname.startsWith('/assets/')) {
      const webRequestPath = pathname === '/' ? '/index.html' : pathname;
      target = resolvePathWithin(webRoot, webRequestPath);
    } else if (pathname.startsWith('/data/') || pathname.startsWith('/weekly-reports/')) {
      target = resolvePathWithin(rootDir, pathname);
    } else if (pathname.startsWith('/knowledge-tree/')) {
      if (pathname === '/knowledge-tree/merged-tree.json' || pathname === '/knowledge-tree/auto-draft.json') {
        target = resolvePathWithin(rootDir, pathname);
      }
    }

    if (!target || !fs.existsSync(target) || fs.statSync(target).isDirectory()) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }

    const ext = path.extname(target).toLowerCase();
    const contentType = mimeTypes[ext] ?? 'application/octet-stream';
    res.writeHead(200, { 'content-type': contentType });
    const stream = fs.createReadStream(target);
    stream.on('error', () => {
      if (!res.headersSent) {
        res.writeHead(500);
      }
      res.end('Failed to read file');
    });
    stream.pipe(res);
  });

  await new Promise(resolve => server.listen(port, '127.0.0.1', resolve));
  return server;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const server = await createServer();
  const address = server.address();
  console.log(`Dashboard server running at http://127.0.0.1:${address.port}`);
}

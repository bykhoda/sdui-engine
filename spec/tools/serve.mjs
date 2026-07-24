#!/usr/bin/env node
// Zero-dependency mock backend for SDUI. It serves the example screens exactly the
// way a real server would, mounts Swagger UI over spec/openapi.yaml, and — crucially
// — validates every screen with the SAME validator your CI runs before handing it to
// a device. Point the app at http://localhost:8787 and a backend dev can build and
// try a whole app from JSON alone.
//
//   node spec/tools/serve.mjs           # → http://localhost:8787  (Swagger UI at /docs)
//   PORT=9000 node spec/tools/serve.mjs
//
// Endpoints (see spec/openapi.yaml for the full contract):
//   GET  /screens/:id        one screen document (validated at boot)
//   GET  /tokens             design tokens
//   POST /submit/:form       echo endpoint for `request` actions (forms/mutations)
//   GET  /healthz            liveness
//   GET  /docs               Swagger UI
//   GET  /openapi.yaml       the spec  (plus /schema/* and /examples/* for $ref resolution)

import { createServer } from 'node:http';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, extname } from 'node:path';
import { Validator, flattenTokenPaths } from './validate.mjs';
import * as T from '../mcp/tools.mjs';

const SPEC_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');   // .../spec
const PORT = Number(process.env.PORT ?? 8787);
const read = (rel) => readFileSync(join(SPEC_DIR, rel), 'utf8');
const readJSON = (rel) => JSON.parse(read(rel));

// --- Load + validate the screen store at boot (dogfood the validator) -------------
const tokens = readJSON('schema/tokens.example.json');
const tokenPaths = flattenTokenPaths(tokens);
const screens = new Map();
let boas = 0;
console.log('SDUI mock server — validating screens:');
for (const file of readdirSync(join(SPEC_DIR, 'examples')).filter((f) => f.endsWith('.json'))) {
  const doc = readJSON(`examples/${file}`);
  const errors = new Validator(tokenPaths).validate(doc);
  const id = doc?.screen?.id ?? file.replace(/\.json$/, '');
  if (errors.length) {
    boas++;
    console.log(`  ✗ ${id.padEnd(16)} (${file})`);
    errors.forEach((e) => console.log(`      ${e}`));
  } else {
    screens.set(id, doc);
    console.log(`  ✓ ${id.padEnd(16)} (${file})`);
  }
}
if (boas) console.log(`  ${boas} screen(s) failed validation and will 404.`);

// --- Tiny helpers -----------------------------------------------------------------
const MIME = { '.json': 'application/json', '.yaml': 'application/yaml', '.yml': 'application/yaml' };
function send(res, status, body, type = 'application/json') {
  const payload = typeof body === 'string' ? body : JSON.stringify(body, null, 2);
  res.writeHead(status, {
    'content-type': `${type}; charset=utf-8`,
    // Dev-only CORS so a browser Swagger UI / a simulator on another origin can call in.
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    'access-control-allow-headers': 'content-type',
  });
  res.end(payload);
}
const readBody = (req) => new Promise((resolve) => {
  let b = ''; req.on('data', (c) => (b += c)); req.on('end', () => resolve(b));
});

const DOCS_HTML = `<!doctype html><html><head><meta charset="utf-8">
<title>SDUI Screen API — Swagger UI</title>
<link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist/swagger-ui.css">
<style>body{margin:0}</style></head><body>
<div id="swagger-ui"></div>
<script src="https://unpkg.com/swagger-ui-dist/swagger-ui-bundle.js"></script>
<script>
  window.onload = () => SwaggerUIBundle({ url: '/openapi.yaml', dom_id: '#swagger-ui', deepLinking: true });
</script>
<noscript>Swagger UI needs JavaScript and the unpkg CDN. The raw spec is at <a href="/openapi.yaml">/openapi.yaml</a>.</noscript>
</body></html>`;

// --- Router -----------------------------------------------------------------------
const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const path = url.pathname;
  if (req.method === 'OPTIONS') return send(res, 204, '');

  if (path === '/' ) { res.writeHead(302, { location: '/docs' }); return res.end(); }
  if (path === '/docs') return send(res, 200, DOCS_HTML, 'text/html');
  if (path === '/healthz') return send(res, 200, { ok: true });

  // Static: the spec + its $ref targets (schema/*, examples/*) so Swagger UI resolves refs.
  if (path === '/openapi.yaml') return send(res, 200, read('openapi.yaml'), 'application/yaml');
  if (path.startsWith('/schema/') || path.startsWith('/examples/')) {
    try { return send(res, 200, read(path.slice(1)), MIME[extname(path)] ?? 'text/plain'); }
    catch { return send(res, 404, { error: 'not found', detail: path }); }
  }

  if (path === '/tokens' && req.method === 'GET') return send(res, 200, tokens);

  // --- Visual composer: build a screen by hand and get valid contract JSON ---------
  if (path === '/compose') return send(res, 200, read('compose/index.html'), 'text/html');
  if (path === '/catalog' && req.method === 'GET') {
    return send(res, 200, { components: T.listComponents(), actions: T.listActions(), tokens: T.listTokens(), examples: T.listExamples(), modifiers: T.modifierFields() });
  }
  if (path === '/validate' && req.method === 'POST') {
    const raw = await readBody(req);
    let payload; try { payload = JSON.parse(raw); } catch (e) { return send(res, 400, { error: 'invalid JSON', detail: e.message }); }
    return send(res, 200, T.validateScreen(payload));   // same Validator as CI + the engine
  }

  const screenMatch = path.match(/^\/screens\/([A-Za-z0-9_.]+)$/);
  if (screenMatch && req.method === 'GET') {
    const doc = screens.get(screenMatch[1]);
    if (!doc) return send(res, 404, { error: 'no such screen', detail: screenMatch[1] });
    return send(res, 200, doc);
  }

  const submitMatch = path.match(/^\/submit\/([A-Za-z0-9_.]+)$/);
  if (submitMatch && req.method === 'POST') {
    const raw = await readBody(req);
    let parsed = null; try { parsed = raw ? JSON.parse(raw) : {}; } catch { /* echo raw */ }
    console.log(`  POST /submit/${submitMatch[1]}`, parsed ?? raw);
    // A real backend validates here and may return 422 { error }. The mock accepts all.
    return send(res, 200, { ok: true, id: `${submitMatch[1]}_mock` });
  }

  send(res, 404, { error: 'not found', detail: path });
});

server.listen(PORT, () => {
  console.log(`\nSDUI mock server on http://localhost:${PORT}`);
  console.log(`  Swagger UI  →  http://localhost:${PORT}/docs`);
  console.log(`  Screens     →  ${[...screens.keys()].map((s) => `/screens/${s}`).join('  ')}`);
});

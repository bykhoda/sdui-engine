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
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, extname } from 'node:path';
import { Validator, flattenTokenPaths } from './validate.mjs';
import * as T from '../mcp/tools.mjs';

const SPEC_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');   // .../spec
// The real premium app screens + their tokens live in the iOS playground, one level
// up from spec/. The mock server dogfoods them alongside the 5 canonical examples so
// the visual composer can open and edit the actual product screens, not just demos.
const IOS_CONTENT = join(SPEC_DIR, '..', 'ios', 'Sources', 'SDUIPlayground', 'Content');
const PORT = Number(process.env.PORT ?? 8787);
const read = (rel) => readFileSync(join(SPEC_DIR, rel), 'utf8');
const readJSON = (rel) => JSON.parse(read(rel));
const readJSONAbs = (abs) => JSON.parse(readFileSync(abs, 'utf8'));

// --- Design tokens: two contracts, one served set --------------------------------
// The 5 spec examples reference spec/schema/tokens.example.json; the 23 app screens
// reference the iOS tokens.json. The iOS set is nearly a superset but the two are NOT
// interchangeable: the spec examples use 3 paths absent from iOS (color.background,
// colorDark.background, spacing.xxl), and ~30 shared leaves hold DIFFERENT values
// (e.g. color.primary #0A84FF vs #5B5BF0, spacing.lg 24 vs 22). So we:
//   • validate each family against ITS OWN token file (below) — dogfooding stays strict
//     and a typo'd $token still 404s the offending screen; and
//   • serve, at GET /tokens, a deep-merge where iOS values WIN. That renders the real
//     app screens correctly in the composer (the primary goal of loading them) while
//     still resolving every $token the 5 examples use, so they render too.
const specTokens = readJSON('schema/tokens.example.json');
const specTokenPaths = flattenTokenPaths(specTokens);
const appTokens = readJSONAbs(join(IOS_CONTENT, 'tokens.json'));
const appTokenPaths = flattenTokenPaths(appTokens);
const deepMerge = (base, over) => {
  const out = Array.isArray(base) ? [...base] : { ...base };
  for (const [k, v] of Object.entries(over)) {
    out[k] = v && typeof v === 'object' && !Array.isArray(v) && base[k] && typeof base[k] === 'object' && !Array.isArray(base[k])
      ? deepMerge(base[k], v) : v;
  }
  return out;
};
const tokens = deepMerge(specTokens, appTokens);   // union of paths; iOS values win on conflicts

// --- Load + validate the screen store at boot (dogfood the validator) -------------
// `screens` maps id → doc for GET /screens/:id. `appExamples` collects catalog metadata
// for the real app screens (the 5 examples' metadata comes from T.listExamples()).
const screens = new Map();
const appExamples = [];
let boas = 0;
// Register one validated doc under its id; returns the id actually used. A rare id
// collision (the example `feed` and the app screen feed.json share an id) is resolved
// by namespacing the later app screen as `app.<id>` so BOTH stay reachable.
function register(doc, fallbackFile, group, tokenPathSet) {
  const errors = new Validator(tokenPathSet).validate(doc);
  const baseId = doc?.screen?.id ?? fallbackFile.replace(/\.json$/, '');
  const id = (group === 'app' && screens.has(baseId)) ? `app.${baseId}` : baseId;
  if (errors.length) {
    boas++;
    console.log(`  ✗ ${id.padEnd(16)} (${fallbackFile})`);
    errors.forEach((e) => console.log(`      ${e}`));
    return null;
  }
  screens.set(id, doc);
  console.log(`  ✓ ${id.padEnd(16)} (${fallbackFile})`);
  return id;
}

console.log('SDUI mock server — validating screens:');
console.log('  spec examples:');
for (const file of readdirSync(join(SPEC_DIR, 'examples')).filter((f) => f.endsWith('.json'))) {
  register(readJSON(`examples/${file}`), file, 'example', specTokenPaths);
}
// Real premium app screens (Content/screens/*.json) + navigation stacks (Content/nav/*.json),
// validated against the iOS tokens they reference.
console.log('  app screens:');
for (const [sub, label] of [['screens', 'screens'], ['nav', 'nav']]) {
  const dir = join(IOS_CONTENT, sub);
  if (!existsSync(dir)) continue;
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.json'))) {
    const doc = readJSONAbs(join(dir, file));
    const id = register(doc, file, 'app', appTokenPaths);
    if (id) appExamples.push({ id, title: doc?.screen?.title ?? '', file: `ios/${sub}/${file}`, group: 'app' });
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
    // examples = 5 canonical spec examples (group:"example") + the real app screens
    // (group:"app"). The composer reads only `e.id`; `group`/`title` are additive so
    // the two families stay distinguishable in richer UIs.
    const examples = [...T.listExamples(), ...appExamples];
    return send(res, 200, { components: T.listComponents(), actions: T.listActions(), tokens: T.listTokens(), examples, modifiers: T.modifierFields() });
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

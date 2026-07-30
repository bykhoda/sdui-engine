#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
//  SDUI reference backend — the clean, copy-me example of "your own backend".
//
//  The whole app is JSON. This server is all a client needs: it hands out
//  design tokens and screens, and it GUARANTEES every screen it serves is valid
//  against the contract (spec/schema) — so the native app can never receive a
//  payload it can't render.
//
//  Zero dependencies. Node 18+. Run:  node examples/backend/server.mjs
//
//  The request flow a client follows (see README.md):
//    1. GET /tokens              once at boot — the shared design tokens
//    2. GET /screens/home        the root screen → the app renders it natively
//    3. user taps a `navigate`   → GET /screens/<to>  → render the next screen
//  Every response is a validated SDUI document (or a renderable fallback screen).
// ─────────────────────────────────────────────────────────────────────────────

import { createServer } from 'node:http';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
// Dogfood the ONE shared validator — the same gate CI and the client use, so the
// backend can never drift from the contract.
import { Validator, flattenTokenPaths } from '../../spec/tools/validate.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT) || 4000;

// ── Boot: load tokens + every screen, and VALIDATE before adding it. ──────────
// An invalid screen is logged and skipped — it is never served, so a bad edit
// fails loudly here instead of crashing a phone in the field.
const tokens = JSON.parse(readFileSync(join(HERE, 'tokens.json'), 'utf8'));
const tokenPaths = flattenTokenPaths(tokens);

const screens = new Map(); // id → SDUI document
for (const file of readdirSync(join(HERE, 'screens')).filter((f) => f.endsWith('.json'))) {
  const doc = JSON.parse(readFileSync(join(HERE, 'screens', file), 'utf8'));
  const errors = new Validator(tokenPaths).validate(doc);
  if (errors.length) {
    console.error(`✗ ${file} is INVALID — NOT served:\n    ${errors.join('\n    ')}`);
    continue;
  }
  screens.set(doc.screen.id, doc);
  console.log(`✓ ${file.padEnd(16)} → GET /screens/${doc.screen.id}`);
}

// ── Helpers ──────────────────────────────────────────────────────────────────
function send(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify(body));
}

// The client always receives renderable SDUI — never a raw 500. This is the last
// link of the resolution chain (network → cache → bundled fallback → error stub).
const errorScreen = (message) => ({
  version: '1.0',
  screen: {
    id: 'error',
    title: 'Unavailable',
    content: {
      type: 'vstack',
      alignment: 'center',
      spacing: '$token.spacing.md',
      modifiers: { padding: '$token.spacing.lg' },
      children: [
        { type: 'text', value: "Couldn't load this screen", style: '$token.typography.title2', color: '$token.color.textPrimary' },
        { type: 'text', value: message, color: '$token.color.textSecondary' },
      ],
    },
  },
});

// ── Router ───────────────────────────────────────────────────────────────────
createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const t0 = Date.now();
  const done = (status) => console.log(`${req.method} ${url.pathname} → ${status} (${Date.now() - t0}ms)`);

  if (url.pathname === '/health') { send(res, 200, { ok: true, screens: screens.size }); return done(200); }

  // The shared design tokens; the client resolves every `$token.*` against these.
  if (url.pathname === '/tokens') { send(res, 200, tokens); return done(200); }

  // Discovery: what screens this backend can serve.
  if (url.pathname === '/catalog') { send(res, 200, { screens: [...screens.keys()] }); return done(200); }

  // The core call: hand the client a validated screen document by id.
  const match = url.pathname.match(/^\/screens\/([a-zA-Z0-9_.-]+)$/);
  if (match && req.method === 'GET') {
    const doc = screens.get(match[1]);
    if (!doc) { send(res, 404, errorScreen(`No screen named "${match[1]}".`)); return done(404); }
    send(res, 200, doc);
    return done(200);
  }

  send(res, 404, errorScreen('Unknown route.'));
  done(404);
}).listen(PORT, () => {
  console.log(`\n  SDUI reference backend → http://localhost:${PORT}`);
  console.log('  GET /tokens · GET /catalog · GET /screens/:id · GET /health\n');
});

#!/usr/bin/env node
// Conformance harness — Level A reference runner. See docs/blueprint/09-conformance-fixtures.md.
//
// For every fixture under fixtures/<id>/ it runs the deterministic contract checks that
// MUST be bit-identical on iOS/Android/Aurora, and compares to the fixture's expect.json.
// This is the SHARED corpus: each native platform will run these same fixtures in its own
// language, so "identical everywhere" becomes a red/green signal instead of a claim.
//
// Implemented now (zero new interpreter → zero drift risk): **validation conformance**,
// by reusing the production Validator from spec/tools/validate.mjs. Binding / condition /
// action-effect / render conformance are declared in expect.json but reported as "pending"
// until their reference runners land (staged in doc 09) — we never silently claim coverage
// we don't have.
//
// Usage: node spec/conformance/check.mjs            (all fixtures)
//        node spec/conformance/check.mjs <id> ...   (named fixtures)
// Exit 0 = every implemented check matched expect; 1 = a mismatch; 2 = harness/setup error.

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Validator, flattenTokenPaths } from '../tools/validate.mjs';
import { resolveString, evalCondition } from './binding.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(HERE, 'fixtures');
const DEFAULT_TOKENS = join(HERE, '..', 'schema', 'tokens.example.json');

const readJSON = (p) => JSON.parse(readFileSync(p, 'utf8'));

// Aspects declared in expect.json that the harness can't yet check (never silently
// claim coverage): binding + condition are now implemented; effect/render are staged.
const PENDING_KEYS = ['effects', 'render'];

// Build the binding context for a fixture: tokens (nested, from tokens.json or the
// default set) + state/data/env/params/item from an optional state.json.
function loadCtx(dir) {
  const tokensPath = existsSync(join(dir, 'tokens.json')) ? join(dir, 'tokens.json') : DEFAULT_TOKENS;
  const tokens = readJSON(tokensPath);
  const s = existsSync(join(dir, 'state.json')) ? readJSON(join(dir, 'state.json')) : {};
  return { tokens, data: s.data || {}, state: s.state || {}, env: s.env || {}, params: s.params || {}, item: s.item };
}

function runValidation(dir, expect) {
  if (expect.validation === undefined) return null; // fixture doesn't assert validation
  const screen = readJSON(join(dir, 'screen.json'));
  const tokensPath = existsSync(join(dir, 'tokens.json')) ? join(dir, 'tokens.json') : DEFAULT_TOKENS;
  const tokenPaths = flattenTokenPaths(readJSON(tokensPath));
  const errors = new Validator(tokenPaths).validate(screen);
  const valid = errors.length === 0;
  const want = expect.validation;
  if (valid !== want.valid) {
    return { ok: false, msg: want.valid
      ? `expected valid, got errors: ${errors.join('; ')}`
      : `expected invalid, but it validated clean` };
  }
  if (!want.valid && want.errorContains && !errors.join('\n').includes(want.errorContains)) {
    return { ok: false, msg: `expected an error containing "${want.errorContains}", got: ${errors.join('; ')}` };
  }
  return { ok: true, msg: want.valid ? 'valid' : `invalid (as expected)` };
}

function runBindings(dir, expect) {
  if (expect.bindings === undefined) return null;
  const ctx = loadCtx(dir);
  for (const [input, want] of Object.entries(expect.bindings)) {
    const got = resolveString(input, ctx);
    if (got !== want) return { ok: false, msg: `binding "${input}" → "${got}", expected "${want}"` };
  }
  return { ok: true, msg: `${Object.keys(expect.bindings).length} binding(s)` };
}

function runConditions(dir, expect) {
  if (expect.conditions === undefined) return null;
  const ctx = loadCtx(dir);
  for (let i = 0; i < expect.conditions.length; i++) {
    const { expr, value } = expect.conditions[i];
    const got = evalCondition(expr, ctx);
    if (got !== value) return { ok: false, msg: `condition[${i}] → ${got}, expected ${value}` };
  }
  return { ok: true, msg: `${expect.conditions.length} condition(s)` };
}

function main() {
  if (!existsSync(FIXTURES)) { console.error(`✗ no fixtures dir at ${FIXTURES}`); process.exit(2); }
  const want = process.argv.slice(2);
  let ids = readdirSync(FIXTURES, { withFileTypes: true }).filter(d => d.isDirectory()).map(d => d.name).sort();
  if (want.length) ids = ids.filter(id => want.includes(id));
  if (ids.length === 0) { console.error('✗ no matching fixtures'); process.exit(2); }

  let failed = 0, pendingCount = 0;
  for (const id of ids) {
    const dir = join(FIXTURES, id);
    let expect;
    try { expect = readJSON(join(dir, 'expect.json')); }
    catch (e) { console.error(`✗ ${id}: bad/missing expect.json — ${e.message}`); failed++; continue; }

    let results;
    try { results = [runValidation(dir, expect), runBindings(dir, expect), runConditions(dir, expect)].filter(Boolean); }
    catch (e) { console.error(`✗ ${id}: harness error — ${e.message}`); failed++; continue; }

    const pending = PENDING_KEYS.filter(k => expect[k] !== undefined);
    pendingCount += pending.length;
    if (results.length === 0 && pending.length === 0) { console.error(`✗ ${id}: expect.json asserts nothing`); failed++; continue; }

    const bad = results.find(r => !r.ok);
    const tag = pending.length ? `  [pending: ${pending.join(',')}]` : '';
    if (bad) { console.error(`✗ ${id}: ${bad.msg}`); failed++; }
    else console.log(`✓ ${id}${results.length ? ` — ${results.map(r => r.msg).join('; ')}` : ''}${tag}`);
  }

  console.log(`\n${ids.length} fixture(s), ${failed} failed` +
    (pendingCount ? `, ${pendingCount} aspect(s) pending a reference runner (effect/render — see doc 09)` : ''));
  process.exit(failed ? 1 : 0);
}

main();

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

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(HERE, 'fixtures');
const DEFAULT_TOKENS = join(HERE, '..', 'schema', 'tokens.example.json');

const readJSON = (p) => JSON.parse(readFileSync(p, 'utf8'));

// Which non-validation aspects a fixture declares but the harness can't yet check.
const PENDING_KEYS = ['bindings', 'conditions', 'effects', 'render'];

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

    let res;
    try { res = runValidation(dir, expect); }
    catch (e) { console.error(`✗ ${id}: harness error — ${e.message}`); failed++; continue; }

    const pending = PENDING_KEYS.filter(k => expect[k] !== undefined);
    pendingCount += pending.length;
    if (res === null && pending.length === 0) { console.error(`✗ ${id}: expect.json asserts nothing`); failed++; continue; }

    const tag = pending.length ? `  [pending: ${pending.join(',')}]` : '';
    if (res && !res.ok) { console.error(`✗ ${id}: ${res.msg}`); failed++; }
    else console.log(`✓ ${id}${res ? ` — ${res.msg}` : ''}${tag}`);
  }

  console.log(`\n${ids.length} fixture(s), ${failed} failed` +
    (pendingCount ? `, ${pendingCount} aspect(s) pending a reference runner (binding/effect/render — see doc 09)` : ''));
  process.exit(failed ? 1 : 0);
}

main();

#!/usr/bin/env node
// Conformance coverage report — which contract surface the fixture corpus exercises.
// See docs/blueprint/09-conformance-fixtures.md §4. Informational by default (the corpus
// is young); pass --strict to exit non-zero when anything is uncovered (a future gate).
//
// Usage: node spec/conformance/coverage.mjs [--strict]

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { KNOWN_ACTIONS, KNOWN_COMPONENTS } from '../tools/validate.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(HERE, 'fixtures');
const SCHEMA = JSON.parse(readFileSync(join(HERE, '..', 'schema', 'sdui.schema.json'), 'utf8'));
const MOD_KEYS = Object.keys((SCHEMA.$defs || SCHEMA.definitions).Modifiers.properties);

const readJSON = (p) => JSON.parse(readFileSync(p, 'utf8'));
const strict = process.argv.includes('--strict');

const usedActions = new Set(), usedComponents = new Set(), usedModifiers = new Set();

// Walk any action tree (action.json or a modifier's onTap etc.).
function walkAction(a) {
  if (!a || typeof a !== 'object') return;
  if (typeof a.action === 'string') usedActions.add(a.action);
  for (const child of a.actions || []) walkAction(child);
  for (const k of ['then', 'else', 'onSuccess', 'onError']) if (a[k]) walkAction(a[k]);
}

// Walk a component tree: record type + modifier keys + any embedded actions.
function walkNode(n) {
  if (!n || typeof n !== 'object') return;
  if (typeof n.type === 'string') usedComponents.add(n.type);
  if (n.modifiers && typeof n.modifiers === 'object') {
    for (const k of Object.keys(n.modifiers)) usedModifiers.add(k);
    for (const k of ['onTap', 'onDoubleTap', 'onLongPress']) if (n.modifiers[k]) walkAction(n.modifiers[k]);
  }
  for (const c of n.children || []) walkNode(c);
  if (n.child) walkNode(n.child);
  if (n.template) walkNode(n.template);
}

for (const id of readdirSync(FIXTURES, { withFileTypes: true }).filter(d => d.isDirectory()).map(d => d.name)) {
  const dir = join(FIXTURES, id);
  if (existsSync(join(dir, 'screen.json'))) walkNode(readJSON(join(dir, 'screen.json')).screen?.content);
  if (existsSync(join(dir, 'action.json'))) walkAction(readJSON(join(dir, 'action.json')));
}

function report(label, known, used) {
  const knownArr = [...known].sort();
  const missing = knownArr.filter(k => !used.has(k));
  const pct = knownArr.length ? Math.round((knownArr.length - missing.length) / knownArr.length * 100) : 100;
  console.log(`\n${label}: ${knownArr.length - missing.length}/${knownArr.length} (${pct}%)`);
  if (missing.length) console.log(`  uncovered: ${missing.join(', ')}`);
  return missing.length;
}

console.log('Conformance corpus coverage (informational — grow toward 100%)');

// Action taxonomy (see doc 09): pure Level-A effects vs host-outcome (integration/Level-B)
// vs not-yet-implemented in any engine. Only the Level-A tier is fixture-gated here.
const INTEGRATION_TIER = new Set(['requireVersion', 'requestPermission']); // implemented, but outcome-driven
const UNIMPLEMENTED = new Set(['request', 'saveFile']);                     // no engine implements these yet (see doc 12)
const levelAActions = new Set([...KNOWN_ACTIONS].filter(a => !INTEGRATION_TIER.has(a) && !UNIMPLEMENTED.has(a)));

let gaps = 0;
gaps += report('Actions (Level-A, pure effects)', levelAActions, usedActions);
console.log(`  integration-tier (host outcome, Level B): ${[...INTEGRATION_TIER].sort().join(', ')}`);
console.log(`  not implemented in any engine yet: ${[...UNIMPLEMENTED].sort().join(', ')}`);
gaps += report('Components', KNOWN_COMPONENTS, usedComponents);
gaps += report('Modifiers', new Set(MOD_KEYS), usedModifiers);

console.log(`\n${gaps} surface item(s) uncovered.` + (strict ? '' : ' (run with --strict to fail on gaps)'));
process.exit(strict && gaps ? 1 : 0);

#!/usr/bin/env node
// Figma → SDUI design-token bridge.
//
// Converts a Figma variables / design-tokens export into an SDUI tokens file.
// The very same output drives BOTH platforms (`$token.<group>.<name>` resolves
// identically on iOS and Android) — so a designer changes a variable in Figma,
// exports, and every screen on every platform picks it up. No engineer in the loop.
//
// Supported inputs (auto-detected):
//   - W3C Design Tokens        ({ "$value", "$type" } leaves, aliases "{a.b}")
//   - Tokens Studio / Figma    ({ "value", "type" } leaves, aliases "{a.b}")
//
// Usage:
//   node spec/tools/figma-tokens.mjs figma-export.json > tokens.json
//   node spec/tools/figma-tokens.mjs figma-export.json tokens.json

import { readFileSync, writeFileSync } from 'node:fs';

/** Flattens the token tree into a map of dotted path -> { type, value }. */
function flatten(node, prefix, out) {
  if (node && typeof node === 'object' && !Array.isArray(node)) {
    const value = node.$value !== undefined ? node.$value : node.value;
    const type = node.$type !== undefined ? node.$type : node.type;
    if (value !== undefined) {
      out.set(prefix, { type, value });
      return;
    }
    for (const [key, child] of Object.entries(node)) {
      if (key.startsWith('$') || key === 'type' || key === 'description') continue;
      flatten(child, prefix ? `${prefix}.${key}` : key, out);
    }
  }
}

/** Resolves "{a.b.c}" aliases against the flat map (bounded to avoid cycles). */
function resolveAlias(raw, flat, depth = 0) {
  if (typeof raw !== 'string' || depth > 16) return raw;
  const match = raw.match(/^\{([^}]+)\}$/);
  if (!match) return raw;
  const target = flat.get(match[1].trim());
  return target ? resolveAlias(target.value, flat, depth + 1) : raw;
}

/** Maps a leaf token to the primitive SDUI expects. */
function primitive(type, value, flat) {
  const resolved = resolveAlias(value, flat);
  switch ((type || '').toLowerCase()) {
    case 'color':
      return typeof resolved === 'string' ? resolved.toUpperCase() : resolved;
    case 'dimension':
    case 'spacing':
    case 'borderradius':
    case 'sizing':
    case 'number': {
      const n = parseFloat(String(resolved));
      return Number.isFinite(n) ? n : resolved;
    }
    case 'typography': {
      const t = resolved || {};
      return {
        size: parseFloat(t.fontSize ?? t.size ?? 0) || undefined,
        weight: mapWeight(t.fontWeight ?? t.weight),
      };
    }
    default:
      return resolved;
  }
}

function mapWeight(w) {
  const n = Number(w);
  if (Number.isFinite(n)) {
    if (n >= 700) return 'bold';
    if (n >= 600) return 'semibold';
    if (n >= 500) return 'medium';
    if (n <= 300) return 'light';
    return 'regular';
  }
  return String(w ?? 'regular').toLowerCase();
}

/** Rebuilds the nested SDUI token object from the resolved flat map. */
function build(flat) {
  const root = {};
  for (const [path, { type, value }] of flat) {
    const parts = path.split('.');
    let node = root;
    for (let i = 0; i < parts.length - 1; i++) {
      node[parts[i]] ??= {};
      node = node[parts[i]];
    }
    node[parts[parts.length - 1]] = primitive(type, value, flat);
  }
  return root;
}

const [input, output] = process.argv.slice(2);
if (!input) {
  console.error('usage: node figma-tokens.mjs <figma-export.json> [tokens.json]');
  process.exit(2);
}

const source = JSON.parse(readFileSync(input, 'utf8'));
const flat = new Map();
flatten(source, '', flat);
const tokens = build(flat);
const json = JSON.stringify(tokens, null, 2) + '\n';

if (output) {
  writeFileSync(output, json);
  console.error(`✓ wrote ${flat.size} tokens → ${output}`);
} else {
  process.stdout.write(json);
}

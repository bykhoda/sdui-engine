#!/usr/bin/env node
// Zero-dependency TypeScript codegen for the SDUI contract.
//
// Reads spec/schema/sdui.schema.json (JSON Schema draft 2020-12) and emits
// spec/types/sdui.d.ts — one `export interface` per object $def, one
// `export type` per enum / union def. The .d.ts is the type surface a
// TypeScript backend (a BFF assembling payloads) codes against.
//
// Deterministic: $defs are emitted in the order they appear in the schema and
// object keys are sorted, so re-running produces byte-identical output.
//
// Other backend languages can generate equivalent models from the SAME schema
// (or spec/openapi.yaml) via `openapi-generator` or `quicktype` — this script
// is just the zero-install path for TypeScript.
//
// Usage:  node spec/tools/codegen.mjs

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SCHEMA_PATH = resolve(HERE, '../schema/sdui.schema.json');
const OUT_PATH = resolve(HERE, '../types/sdui.d.ts');

const schema = JSON.parse(readFileSync(SCHEMA_PATH, 'utf8'));
const defs = schema.$defs ?? {};
const defNames = new Set(Object.keys(defs));

// Track type-name references we emit so we can warn on dangling ones.
const missingRefs = new Set();

/** Turn a "#/$defs/Foo" ref into the TS type name `Foo`, or `unknown` if absent. */
function refToTypeName(ref) {
  const m = /^#\/\$defs\/(.+)$/.exec(ref);
  if (!m) return 'unknown';
  const name = m[1];
  if (!defNames.has(name)) { missingRefs.add(name); return 'unknown'; }
  return name;
}

/** Render an inline TS type for an arbitrary schema node. */
function tsType(node) {
  if (node === true || node === undefined) return 'unknown';
  if (node === false) return 'never';
  if (typeof node !== 'object') return 'unknown';

  if (node.$ref) return refToTypeName(node.$ref);

  if (Array.isArray(node.enum)) {
    return node.enum.map((v) => JSON.stringify(v)).join(' | ') || 'never';
  }
  if ('const' in node) return JSON.stringify(node.const);

  const combiner = node.oneOf ?? node.anyOf ?? node.allOf;
  if (Array.isArray(combiner)) {
    const parts = combiner.map(tsType);
    const uniq = [...new Set(parts)];
    const joiner = node.allOf ? ' & ' : ' | ';
    return uniq.length === 1 ? uniq[0] : `(${uniq.join(joiner)})`;
  }

  const t = node.type;
  if (t === 'array') return `${wrapArrayItem(tsType(node.items ?? {}))}[]`;
  if (t === 'object' || node.properties || node.additionalProperties !== undefined) {
    return objectType(node);
  }
  if (t === 'string') return 'string';
  if (t === 'integer' || t === 'number') return 'number';
  if (t === 'boolean') return 'boolean';
  if (t === 'null') return 'null';
  if (Array.isArray(t)) return t.map((x) => tsType({ type: x })).join(' | ');

  return 'unknown';
}

/** Parenthesise a union item before appending `[]`. */
function wrapArrayItem(inner) {
  return /[ |&]/.test(inner) && !inner.startsWith('(') ? `(${inner})` : inner;
}

/** Render an inline object type (properties + index signature). */
function objectType(node) {
  const props = node.properties ?? {};
  const required = new Set(node.required ?? []);
  const keys = Object.keys(props).sort();
  const lines = [];
  for (const key of keys) {
    const opt = required.has(key) ? '' : '?';
    lines.push(`${quoteKey(key)}${opt}: ${tsType(props[key])};`);
  }
  const ap = node.additionalProperties;
  if (ap && ap !== false) {
    lines.push(`[key: string]: ${ap === true ? 'unknown' : tsType(ap)};`);
  } else if (ap === undefined && keys.length === 0) {
    // Schema-open object with no declared props → permissive record.
    lines.push('[key: string]: unknown;');
  }
  if (lines.length === 0) return '{}';
  return `{ ${lines.join(' ')} }`;
}

/** Quote an object key only when it isn't a plain identifier. */
function quoteKey(key) {
  return /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(key) ? key : JSON.stringify(key);
}

/** Collect the `then` subschemas of an `if`/`then` discriminator `allOf`. */
function conditionalBranches(node) {
  if (!Array.isArray(node.allOf)) return [];
  return node.allOf
    .filter((b) => b && typeof b === 'object' && b.if && b.then)
    .map((b) => b.then);
}

/** Emit a top-level declaration for one named $def. */
function emitDef(name, node) {
  const doc = docComment(node.description, 0);
  const branches = conditionalBranches(node);

  // Discriminated node (Component / Action): a base object whose `allOf`
  // holds `if type==X then <props>` branches. Emit the base interface, then
  // intersect it with the union of every branch's shape so the concrete
  // fields (e.g. a text's `value`, a navigate's `to`) are all typed.
  if (branches.length && (node.type === 'object' || node.properties)) {
    const base = { ...node };
    delete base.allOf;
    const baseIface = emitDef(name + '__Base', base).replace(
      `export interface ${name}__Base`,
      `interface ${name}Base`
    );
    const parts = branches.map(tsType).filter((p) => p && p !== '{}' && p !== 'unknown');
    const union = parts.length ? `(${[...new Set(parts)].join('\n  | ')})` : '{}';
    return `${baseIface.replace(doc, '')}\n\n${doc}export type ${name} = ${name}Base & ${union};`;
  }

  // Object with properties → interface (nicest to consume / extend).
  const isPlainObject =
    (node.type === 'object' || node.properties) &&
    !node.enum && !node.oneOf && !node.anyOf && !node.allOf && !node.$ref;

  if (isPlainObject || (node.properties && branches.length === 0 && node.allOf)) {
    const props = node.properties ?? {};
    const required = new Set(node.required ?? []);
    const keys = Object.keys(props).sort();
    const body = [];
    for (const key of keys) {
      const p = props[key];
      const pdoc = docComment(p.description, 2).replace(/\n$/, '');
      const opt = required.has(key) ? '' : '?';
      if (pdoc) body.push(pdoc);
      body.push(`  ${quoteKey(key)}${opt}: ${tsType(p)};`);
    }
    const ap = node.additionalProperties;
    if (ap && ap !== false) {
      body.push(`  [key: string]: ${ap === true ? 'unknown' : tsType(ap)};`);
    } else if (ap === undefined && keys.length === 0) {
      body.push('  [key: string]: unknown;');
    }
    return `${doc}export interface ${name} {\n${body.join('\n')}\n}`;
  }

  // Everything else (enum / union / primitive / $ref alias) → type alias.
  return `${doc}export type ${name} = ${tsType(node)};`;
}

/** Build a JSDoc block from a description, indented by `indent` spaces. */
function docComment(desc, indent) {
  if (!desc) return '';
  const pad = ' '.repeat(indent);
  const clean = String(desc).replace(/\*\//g, '*\\/');
  if (!clean.includes('\n') && clean.length <= 100) {
    return `${pad}/** ${clean} */\n`;
  }
  const lines = clean.split('\n').map((l) => `${pad} * ${l}`.replace(/\s+$/, ''));
  return `${pad}/**\n${lines.join('\n')}\n${pad} */\n`;
}

// ---- assemble the file -----------------------------------------------------

const header =
  `// Generated from spec/schema/sdui.schema.json by spec/tools/codegen.mjs — do not edit by hand.\n` +
  `// Other backend languages can generate equivalent types from the same schema\n` +
  `// (or spec/openapi.yaml) via \`openapi-generator\` or \`quicktype\`.\n`;

const blocks = [];
for (const [name, node] of Object.entries(defs)) {
  blocks.push(emitDef(name, node));
}

// Top-level document type: mirrors the schema root { version, screen }.
const topDoc = docComment(
  'The root SDUI payload: a contract version plus exactly one screen.',
  0
);
const screenType = defNames.has('Screen') ? 'Screen' : 'unknown';
if (!defNames.has('Screen')) missingRefs.add('Screen');
blocks.push(`${topDoc}export interface SDUIDocument {\n  version: string;\n  screen: ${screenType};\n}`);

const output = `${header}\n${blocks.join('\n\n')}\n`;

mkdirSync(dirname(OUT_PATH), { recursive: true });
writeFileSync(OUT_PATH, output, 'utf8');

console.log(`✓ wrote ${OUT_PATH}`);
console.log(`  ${Object.keys(defs).length} $defs → ${blocks.length} declarations`);
if (missingRefs.size) {
  console.warn(`  ⚠ ${missingRefs.size} dangling ref(s) emitted as \`unknown\`: ${[...missingRefs].join(', ')}`);
}

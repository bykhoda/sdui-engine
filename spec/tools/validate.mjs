#!/usr/bin/env node
// Zero-dependency validator for SDUI payloads.
//
// It mirrors the most valuable constraints of spec/schema/sdui.schema.json and,
// crucially, resolves cross-references the schema alone can't: every $data.<id>
// binding must have a matching data source. Precise paths make failures obvious
// BEFORE a payload ever reaches a device.
//
// Usage:  node spec/tools/validate.mjs spec/examples/product_detail.json [...]
//         node spec/tools/validate.mjs spec/examples/*.json

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// ── The contract IS the single source of truth ──────────────────────────────
// Everything below is DERIVED from spec/schema/sdui.schema.json at load time —
// component & action vocabularies, their required fields, and every enum / numeric
// / shape constraint. Nothing is hand-listed, so the validator (and, through its
// exports, the MCP server) can never drift from the schema. Add a component or an
// action to the schema and it is enforced here automatically.
const SCHEMA = JSON.parse(
  readFileSync(join(dirname(fileURLToPath(import.meta.url)), '..', 'schema', 'sdui.schema.json'), 'utf8'),
);
const DEFS = SCHEMA.$defs;
// Resolve a one-level `$ref` into #/$defs; returns the node unchanged otherwise.
const deref = (node) => (node && node.$ref ? DEFS[node.$ref.split('/').pop()] : node);

// Component vocabulary + per-type props schema, from the Component discriminator's
// `allOf` branches (`if type == "x" then <XProps>`).
export const KNOWN_COMPONENTS = new Set();
export const REQUIRED_COMPONENT_FIELDS = {};
const COMPONENT_PROPS = {};   // type → resolved *Props schema (for strict checks)
for (const branch of DEFS.Component.allOf ?? []) {
  const type = branch.if?.properties?.type?.const;
  if (!type) continue;
  KNOWN_COMPONENTS.add(type);
  const props = deref(branch.then);
  COMPONENT_PROPS[type] = props ?? null;
  if (props?.required?.length) REQUIRED_COMPONENT_FIELDS[type] = props.required;
}

// Action vocabulary from the Action enum; required fields + props schema from the
// Action's `allOf` branches (their `then` blocks are inline, not $refs).
export const KNOWN_ACTIONS = new Set(DEFS.Action.properties.action.enum);
export const REQUIRED_ACTION_FIELDS = {};
const ACTION_THEN = {};       // action kind → its inline `then` schema
for (const branch of DEFS.Action.allOf ?? []) {
  const kind = branch.if?.properties?.action?.const;
  if (!kind) continue;
  ACTION_THEN[kind] = branch.then ?? null;
  if (branch.then?.required?.length) REQUIRED_ACTION_FIELDS[kind] = branch.then.required;
}

export class Validator {
  // `tokenPaths` (optional): a Set of every valid "$token.<path>" tail (both group
  // and leaf paths) from a tokens file. When supplied, token refs are checked so a
  // typo like `$token.spacing.mdd` fails in CI instead of silently rendering empty.
  constructor(tokenPaths = null) {
    this.errors = []; this.sourceIds = new Set(); this.dataRefs = []; this.tokenRefs = [];
    this.tokenPaths = tokenPaths;
  }
  err(path, msg) { this.errors.push(`${path}: ${msg}`); }

  validate(doc) {
    if (typeof doc !== 'object' || doc === null) return this.err('<root>', 'payload must be an object');
    if (!/^\d+\.\d+$/.test(doc.version ?? '')) this.err('version', 'required, format "<major>.<minor>"');
    const screen = doc.screen;
    if (!screen) return this.err('screen', 'required');

    if (!/^[a-z][a-z0-9_.]*$/.test(screen.id ?? '')) this.err('screen.id', 'required, matches ^[a-z][a-z0-9_.]*$');
    if (screen.data?.sources) {
      screen.data.sources.forEach((s, i) => {
        if (!s.id) this.err(`screen.data.sources[${i}].id`, 'required');
        else this.sourceIds.add(s.id);
        if (!s.service) this.err(`screen.data.sources[${i}].service`, 'required');
        if (!s.path) this.err(`screen.data.sources[${i}].path`, 'required');
      });
    }
    if (!screen.content) this.err('screen.content', 'required (exactly one root component)');
    else this.walkComponent(screen.content, 'screen.content');

    this.collectBindings(screen);
    // Cross-reference: every $data.<id> must resolve to a declared source.
    for (const { ref, path } of this.dataRefs) {
      const id = ref.split('.')[1];
      if (id && !this.sourceIds.has(id)) {
        this.err(path, `binding "$data.${id}" has no matching data source (declared: ${[...this.sourceIds].join(', ') || 'none'})`);
      }
    }
    // Token cross-reference (only when a tokens file was supplied).
    if (this.tokenPaths) {
      for (const { ref, path } of this.tokenRefs) {
        const tail = ref.slice('$token.'.length);
        if (!this.tokenPaths.has(tail)) this.err(path, `token "${ref}" is not defined in the tokens file`);
      }
    }
    return this.errors;
  }

  walkComponent(node, path) {
    if (typeof node !== 'object' || node === null) return this.err(path, 'component must be an object');
    const type = node.type;
    if (!type) return this.err(`${path}.type`, 'required');
    if (!KNOWN_COMPONENTS.has(type) && !type.startsWith('custom.')) {
      this.err(`${path}.type`, `unknown component "${type}" (use one of ${[...KNOWN_COMPONENTS].join(', ')} or custom.*)`);
    }
    // Strict, schema-derived shape check: required fields, enum membership, numeric
    // types & ranges — for this component's props and for its modifiers.
    this.checkShape(node, COMPONENT_PROPS[type], path);
    if (node.modifiers !== undefined) {
      this.checkShape(node.modifiers, DEFS.Modifiers, `${path}.modifiers`);
      // The Modifiers object is a closed set (schema additionalProperties:false). Unlike a
      // component node — which carries structural keys (type/children/modifiers) beyond its
      // props — a modifiers map should ONLY hold known modifier keys, so a typo like
      // "shadwo" or an invented "glow" is a real authoring bug, caught here.
      if (node.modifiers && typeof node.modifiers === 'object' && !Array.isArray(node.modifiers)) {
        for (const k of Object.keys(node.modifiers)) {
          if (!(k in DEFS.Modifiers.properties)) this.err(`${path}.modifiers.${k}`, `unknown modifier "${k}"`);
        }
      }
    }
    if (node.modifiers?.onTap) this.walkAction(node.modifiers.onTap, `${path}.modifiers.onTap`);
    if (node.modifiers?.onLongPress) this.walkAction(node.modifiers.onLongPress, `${path}.modifiers.onLongPress`);
    (node.modifiers?.contextMenu ?? []).forEach((m, i) => m.action && this.walkAction(m.action, `${path}.modifiers.contextMenu[${i}].action`));
    (node.modifiers?.swipe?.leading ?? []).forEach((s, i) => s.action && this.walkAction(s.action, `${path}.modifiers.swipe.leading[${i}].action`));
    (node.modifiers?.swipe?.trailing ?? []).forEach((s, i) => s.action && this.walkAction(s.action, `${path}.modifiers.swipe.trailing[${i}].action`));
    if (node.onTap) this.walkAction(node.onTap, `${path}.onTap`);
    (node.children ?? []).forEach((c, i) => this.walkComponent(c, `${path}.children[${i}]`));
    if (node.child) this.walkComponent(node.child, `${path}.child`);
    if (node.template) this.walkComponent(node.template, `${path}.template`);
    if (node.collapsingHeader?.expanded) this.walkComponent(node.collapsingHeader.expanded, `${path}.collapsingHeader.expanded`);
    if (node.collapsingHeader?.compact) this.walkComponent(node.collapsingHeader.compact, `${path}.collapsingHeader.compact`);
    // `async` declares its data source inline and renders slot components; register
    // the source id so `$data.<id>` bindings inside `content` resolve.
    if (type === 'async') {
      // `source`/`content` required-ness is enforced by checkShape above; here we
      // add the async-specific rule (the source needs an id — it becomes the $data
      // key) and walk the slot components.
      if (node.source && node.source.id === undefined) this.err(`${path}.source.id`, 'required — it becomes the $data.<id> key inside content');
      if (node.source?.id) this.sourceIds.add(node.source.id);
      if (node.content) this.walkComponent(node.content, `${path}.content`);
      if (node.loading) this.walkComponent(node.loading, `${path}.loading`);
      if (node.error) this.walkComponent(node.error, `${path}.error`);
    }
  }

  walkAction(node, path) {
    if (typeof node !== 'object' || node === null) return this.err(path, 'action must be an object');
    if (!node.action) return this.err(`${path}.action`, 'required');
    if (!KNOWN_ACTIONS.has(node.action)) this.err(`${path}.action`, `unknown action "${node.action}"`);
    // Strict, schema-derived check of this action kind's own fields (required +
    // enums like transition/haptic style). Nested child actions are walked below.
    this.checkShape(node, ACTION_THEN[node.action], path);
    (node.actions ?? []).forEach((a, i) => this.walkAction(a, `${path}.actions[${i}]`));
    ['then', 'else', 'onSuccess', 'onError'].forEach((k) => node[k] && this.walkAction(node[k], `${path}.${k}`));
  }

  // Conservative, schema-driven shape check. It only ever fires on unambiguous
  // authoring mistakes, because it deliberately bows out of anything ambiguous:
  //  • a binding ("$state.x", "$data…", "$token…") skips every scalar rule;
  //  • $ref types (Color/Dimension/BindableString/Component/Action/…) and
  //    oneOf/anyOf unions are skipped — they're intentionally flexible;
  //  • unknown keys are left alone (no additionalProperties enforcement here).
  // What remains is real: a mistyped enum, a string where a number belongs, an
  // out-of-range value, or a missing nested-required field.
  checkShape(val, spec, path) {
    if (!spec || typeof spec !== 'object') return;
    if (spec.$ref || spec.oneOf || spec.anyOf || spec.allOf) return;
    if (typeof val === 'string' && val.startsWith('$')) return;   // a binding — not a literal
    if (spec.enum) {
      if (typeof val === 'string' && !spec.enum.includes(val)) {
        this.err(path, `"${val}" is not a valid value (expected one of: ${spec.enum.join(' | ')})`);
      }
      return;
    }
    const t = spec.type;
    if (t === 'object' || (!t && (spec.properties || spec.required))) {
      if (!val || typeof val !== 'object' || Array.isArray(val)) return;
      for (const r of spec.required ?? []) {
        if (val[r] === undefined) this.err(`${path}.${r}`, 'required');
      }
      if (spec.properties) {
        for (const [k, s] of Object.entries(spec.properties)) {
          if (k in val) this.checkShape(val[k], s, `${path}.${k}`);
        }
      }
      return;
    }
    if (t === 'array') {
      if (Array.isArray(val) && spec.items) val.forEach((v, i) => this.checkShape(v, spec.items, `${path}[${i}]`));
      return;
    }
    if (t === 'boolean') {
      if (typeof val !== 'boolean') this.err(path, 'must be true or false');
    } else if (t === 'number' || t === 'integer') {
      if (typeof val !== 'number') { this.err(path, 'must be a number'); return; }
      if (t === 'integer' && !Number.isInteger(val)) this.err(path, 'must be a whole number');
      if (spec.minimum !== undefined && val < spec.minimum) this.err(path, `must be ≥ ${spec.minimum}`);
      if (spec.maximum !== undefined && val > spec.maximum) this.err(path, `must be ≤ ${spec.maximum}`);
      if (spec.exclusiveMinimum !== undefined && val <= spec.exclusiveMinimum) this.err(path, `must be greater than ${spec.exclusiveMinimum}`);
    } else if (t === 'string') {
      if (typeof val !== 'string') this.err(path, 'must be a string');
    }
  }

  // Collect every "$data.<id>..." string in the tree for cross-referencing.
  collectBindings(obj, path = 'screen') {
    if (typeof obj === 'string') {
      const m = obj.match(/\$data\.[A-Za-z0-9_.]+/g);
      if (m) m.forEach((ref) => this.dataRefs.push({ ref, path }));
      const t = obj.match(/\$token\.[A-Za-z0-9_.]+/g);
      if (t) t.forEach((ref) => this.tokenRefs.push({ ref, path }));
    } else if (Array.isArray(obj)) {
      obj.forEach((v, i) => this.collectBindings(v, `${path}[${i}]`));
    } else if (obj && typeof obj === 'object') {
      for (const [k, v] of Object.entries(obj)) this.collectBindings(v, `${path}.${k}`);
    }
  }
}

// Flatten a tokens object to the set of every "$token.<tail>" a payload may use —
// both group paths (color, spacing) and leaf paths (color.primary). Skips $comment*
// and the top-level version so those never look like tokens.
export function flattenTokenPaths(obj, prefix = '', out = new Set()) {
  for (const [k, v] of Object.entries(obj)) {
    if (k.startsWith('$comment') || (prefix === '' && k === 'version')) continue;
    const path = prefix ? `${prefix}.${k}` : k;
    out.add(path);
    if (v && typeof v === 'object' && !Array.isArray(v)) flattenTokenPaths(v, path, out);
  }
  return out;
}

// CLI entry — skipped when this module is imported (e.g. by the mock server).
if (import.meta.url === `file://${process.argv[1]}`) runCli();

function runCli() {
// Args: [--tokens <file>] <payload.json> [...]
const args = process.argv.slice(2);
let tokenPaths = null;
const files = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--tokens') {
    const f = args[++i];
    try { tokenPaths = flattenTokenPaths(JSON.parse(readFileSync(f, 'utf8'))); }
    catch (e) { console.error(`✗ --tokens ${f}: ${e.message}`); process.exit(2); }
  } else { files.push(args[i]); }
}
if (files.length === 0) {
  console.error('usage: node validate.mjs [--tokens <tokens.json>] <payload.json> [...]');
  process.exit(2);
}

let failed = 0;
for (const file of files) {
  let doc;
  try { doc = JSON.parse(readFileSync(file, 'utf8')); }
  catch (e) { console.error(`✗ ${file}: invalid JSON — ${e.message}`); failed++; continue; }
  const errors = new Validator(tokenPaths).validate(doc);
  if (errors.length === 0) {
    console.log(`✓ ${file}`);
  } else {
    failed++;
    console.error(`✗ ${file}`);
    errors.forEach((e) => console.error(`    ${e}`));
  }
}
process.exit(failed ? 1 : 0);
}

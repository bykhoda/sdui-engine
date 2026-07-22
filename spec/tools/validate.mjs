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

const KNOWN_COMPONENTS = new Set([
  'vstack', 'hstack', 'zstack', 'scroll', 'list', 'grid', 'spacer', 'divider',
  'text', 'icon', 'image', 'button', 'textfield', 'toggle', 'picker', 'progress',
  'chart', 'gradient', 'rings', 'spinner', 'async', 'slider', 'roadmap', 'disclosure', 'ticker',
  'datepicker', 'filecell', 'calendar', 'clips',
]);
const KNOWN_ACTIONS = new Set([
  'navigate', 'dismiss', 'dismissRoot', 'openURL', 'openDeepLink', 'setState',
  'refresh', 'request', 'sequence', 'parallel', 'condition', 'delay', 'showToast', 'scrollTo',
  'haptic', 'share', 'log', 'analytics', 'custom', 'increment',
]);
const REQUIRED_COMPONENT_FIELDS = {
  vstack: ['children'], hstack: ['children'], zstack: ['children'],
  scroll: ['child'], text: ['value'], image: ['source'], button: ['onTap'],
  icon: ['name'], textfield: ['bind'], toggle: ['bind'], picker: ['bind', 'options'],
  slider: ['bind'], disclosure: ['title'], ticker: ['bind'], datepicker: ['bind'],
  calendar: ['mode'],
  clips: ['pages'],
};
const REQUIRED_ACTION_FIELDS = {
  navigate: ['to'], openURL: ['url'], openDeepLink: ['url'], setState: ['key'],
  request: ['source'], sequence: ['actions'], parallel: ['actions'],
  condition: ['if', 'then'], showToast: ['message'], scrollTo: ['target'], custom: ['name'],
};

class Validator {
  constructor() { this.errors = []; this.sourceIds = new Set(); this.dataRefs = []; }
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
    return this.errors;
  }

  walkComponent(node, path) {
    if (typeof node !== 'object' || node === null) return this.err(path, 'component must be an object');
    const type = node.type;
    if (!type) return this.err(`${path}.type`, 'required');
    if (!KNOWN_COMPONENTS.has(type) && !type.startsWith('custom.')) {
      this.err(`${path}.type`, `unknown component "${type}" (use one of ${[...KNOWN_COMPONENTS].join(', ')} or custom.*)`);
    }
    for (const f of REQUIRED_COMPONENT_FIELDS[type] ?? []) {
      if (node[f] === undefined) this.err(`${path}.${f}`, `required for "${type}"`);
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
      if (node.source?.id) this.sourceIds.add(node.source.id);
      else this.err(`${path}.source`, 'required for "async" (with an id)');
      if (node.content) this.walkComponent(node.content, `${path}.content`);
      else this.err(`${path}.content`, 'required for "async"');
      if (node.loading) this.walkComponent(node.loading, `${path}.loading`);
      if (node.error) this.walkComponent(node.error, `${path}.error`);
    }
  }

  walkAction(node, path) {
    if (typeof node !== 'object' || node === null) return this.err(path, 'action must be an object');
    if (!node.action) return this.err(`${path}.action`, 'required');
    if (!KNOWN_ACTIONS.has(node.action)) this.err(`${path}.action`, `unknown action "${node.action}"`);
    for (const f of REQUIRED_ACTION_FIELDS[node.action] ?? []) {
      if (node[f] === undefined) this.err(`${path}.${f}`, `required for action "${node.action}"`);
    }
    (node.actions ?? []).forEach((a, i) => this.walkAction(a, `${path}.actions[${i}]`));
    ['then', 'else', 'onSuccess', 'onError'].forEach((k) => node[k] && this.walkAction(node[k], `${path}.${k}`));
  }

  // Collect every "$data.<id>..." string in the tree for cross-referencing.
  collectBindings(obj, path = 'screen') {
    if (typeof obj === 'string') {
      const m = obj.match(/\$data\.[A-Za-z0-9_.]+/g);
      if (m) m.forEach((ref) => this.dataRefs.push({ ref, path }));
    } else if (Array.isArray(obj)) {
      obj.forEach((v, i) => this.collectBindings(v, `${path}[${i}]`));
    } else if (obj && typeof obj === 'object') {
      for (const [k, v] of Object.entries(obj)) this.collectBindings(v, `${path}.${k}`);
    }
  }
}

let failed = 0;
for (const file of process.argv.slice(2)) {
  let doc;
  try { doc = JSON.parse(readFileSync(file, 'utf8')); }
  catch (e) { console.error(`✗ ${file}: invalid JSON — ${e.message}`); failed++; continue; }
  const errors = new Validator().validate(doc);
  if (errors.length === 0) {
    console.log(`✓ ${file}`);
  } else {
    failed++;
    console.error(`✗ ${file}`);
    errors.forEach((e) => console.error(`    ${e}`));
  }
}
if (process.argv.length <= 2) { console.error('usage: node validate.mjs <payload.json> [...]'); process.exit(2); }
process.exit(failed ? 1 : 0);

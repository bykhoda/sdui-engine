// The SDUI toolbox, protocol-independent. Each function returns plain JSON so it can
// be surfaced by the MCP server (spec/mcp/server.mjs) or called directly in a test.
// Everything reads from the ONE contract in spec/ — schema, tokens, examples, the
// validator — so a model driving these tools can never drift from what a device renders.

import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import {
  Validator, flattenTokenPaths,
  KNOWN_COMPONENTS, KNOWN_ACTIONS, REQUIRED_COMPONENT_FIELDS, REQUIRED_ACTION_FIELDS,
} from '../tools/validate.mjs';
import { lint, RULES } from '../tools/lint.mjs';

// The contract lives in spec/. By default we find it relative to this file, so the
// server works no matter the cwd. `SDUI_SPEC_DIR` overrides it — point it at another
// checkout's spec/ dir to drive that contract from anywhere.
const SPEC_DIR = process.env.SDUI_SPEC_DIR
  ? resolve(process.env.SDUI_SPEC_DIR)
  : join(dirname(fileURLToPath(import.meta.url)), '..');   // .../spec
const read = (rel) => readFileSync(join(SPEC_DIR, rel), 'utf8');
const readJSON = (rel) => JSON.parse(read(rel));

const schema = readJSON('schema/sdui.schema.json');
const tokens = readJSON('schema/tokens.example.json');
const tokenPaths = flattenTokenPaths(tokens);

// One-line purpose for a component, straight from its `<Type>Props` $def description.
// The type→props mapping is derived from the schema by `propsDefFor` (below), so there
// is no hand-maintained list to drift.
const purposeFor = (type) => propsDefFor(type)?.description ?? '';

// ---- schema-driven field introspection -------------------------------------------
// Classify a JSON-Schema property into an editor control kind. Color/Dimension/enum/
// number/bool/text get typed controls; everything structural falls back to 'raw'.
function propKind(p) {
  if (!p || typeof p !== 'object') return { kind: 'raw' };
  if (p.enum) return { kind: 'enum', options: p.enum };
  const ref = typeof p.$ref === 'string' ? p.$ref.split('/').pop() : null;
  if (ref === 'Color') return { kind: 'color' };
  if (ref === 'Dimension') return { kind: 'dimension' };
  if (ref === 'BindableString') return { kind: 'text' };
  if (ref) return { kind: 'raw' };
  if (p.type === 'boolean') return { kind: 'bool' };
  if (p.type === 'integer' || p.type === 'number') return { kind: 'number' };
  if (p.type === 'string') return { kind: 'text' };
  return { kind: 'raw' };   // object / array / oneOf → raw JSON editor
}
function propsDefFor(type) {
  for (const b of (schema.$defs.Component.allOf || [])) {
    if (b.if?.properties?.type?.const === type) {
      const ref = b.then?.$ref?.split('/').pop();
      return ref ? schema.$defs[ref] : null;
    }
  }
  return null;
}
// Every editable field of a component type, straight from the schema — so the composer
// exposes ALL props, never a hand-picked subset.
export function componentFields(type) {
  const def = propsDefFor(type);
  if (!def?.properties) return [];
  const req = new Set(def.required || []);
  return Object.entries(def.properties)
    .filter(([k]) => k !== 'type' && k !== 'children' && k !== 'child' && k !== 'template' && k !== 'items')
    .map(([key, p]) => ({ key, ...propKind(p), required: req.has(key), desc: p.description || '' }));
}
// Every modifier the contract supports (padding, background, material, shadow, swipe,
// animation, …) — from the Modifiers def, so the whole modifier surface is reachable.
export function modifierFields() {
  const def = schema.$defs.Modifiers;
  return Object.entries(def.properties || {}).map(([key, p]) => ({ key, ...propKind(p), desc: p.description || '' }));
}

export function listComponents() {
  return [...KNOWN_COMPONENTS].sort().map((type) => ({
    type,
    required: REQUIRED_COMPONENT_FIELDS[type] ?? [],
    purpose: purposeFor(type),
    fields: componentFields(type),
  }));
}

export function listActions() {
  return [...KNOWN_ACTIONS].sort().map((kind) => ({
    kind,
    required: REQUIRED_ACTION_FIELDS[kind] ?? [],
  }));
}

export function listTokens() {
  // Group → names, plus the flat set of every valid $token.<tail> a payload may use.
  const groups = {};
  for (const [k, v] of Object.entries(tokens)) {
    if (k.startsWith('$comment') || k === 'version') continue;
    groups[k] = v && typeof v === 'object' && !Array.isArray(v) ? Object.keys(v) : v;
  }
  return { groups, valid: [...tokenPaths].sort() };
}

// The 5 canonical spec examples. Each entry carries `group: 'example'` so callers
// (e.g. the /catalog handler) can keep them distinct from the real app screens the
// mock server also loads. The field is additive — existing readers use only `id`.
export function listExamples() {
  return readdirSync(join(SPEC_DIR, 'examples'))
    .filter((f) => f.endsWith('.json'))
    .map((f) => {
      const doc = readJSON(`examples/${f}`);
      return { id: doc?.screen?.id ?? f.replace(/\.json$/, ''), title: doc?.screen?.title ?? '', file: `examples/${f}`, group: 'example' };
    });
}

export function getExample(id) {
  const hit = listExamples().find((e) => e.id === id);
  if (!hit) throw new Error(`no example "${id}". Available: ${listExamples().map((e) => e.id).join(', ')}`);
  return readJSON(hit.file);
}

export function getSchema() { return schema; }
export function getGuide() { return read('docs/authoring.md'); }   // spec/docs/authoring.md

// Validate a payload object. `checkTokens` (default true) also flags $token typos.
export function validateScreen(payload, { checkTokens = true } = {}) {
  const errors = new Validator(checkTokens ? tokenPaths : null).validate(payload);
  return { ok: errors.length === 0, errors };
}

// Design-lint a payload against the shared rule set (spec/tools/lint.mjs): off-token
// literals, WCAG contrast, tap-target, dead buttons, layout-jumpy images, palette
// cohesion. Returns the findings plus a severity summary so the model (or composer)
// can reflect on the SAME diagnostics a designer sees inline. `minSeverity` filters
// out lower-severity noise ('error' | 'warn' | 'info', default 'info' = everything).
export function lintScreen(payload, { minSeverity = 'info', rules = null } = {}) {
  const order = { error: 0, warn: 1, info: 2 };
  const cutoff = order[minSeverity] ?? 2;
  const wanted = rules ? new Set(rules) : null;
  let { findings } = lint(payload, tokens);
  findings = findings.filter((f) => order[f.severity] <= cutoff && (!wanted || wanted.has(f.rule)));
  const summary = { error: 0, warn: 0, info: 0 };
  for (const f of findings) summary[f.severity]++;
  return { ok: summary.error === 0, summary, findings };
}

// The lint rule catalogue (id → default severity + one-line rationale). Lets a model
// (or a composer settings pane) discover what lint_screen checks and why.
export function listLintRules() {
  return Object.entries(RULES).map(([rule, { severity, doc }]) => ({ rule, severity, description: doc }));
}

// Minimal, VALID starter screens by intent — a launch pad the model can flesh out.
export function scaffoldScreen(kind = 'blank', { id = kind, title = 'Untitled' } = {}) {
  const t = (value, style = '$token.typography.body', color = '$token.color.textPrimary') =>
    ({ type: 'text', value, style, color });
  const pad = { modifiers: { padding: '$token.spacing.lg', size: { width: { mode: 'fill' } } } };

  switch (kind) {
    case 'list':
      return {
        version: '0.1',
        screen: {
          id, title,
          data: { mode: 'parallel', sources: [{ id: 'items', service: 'content', path: '/items', method: 'GET', policy: 'cacheThenNetwork' }] },
          refresh: { sources: ['items'] },
          content: { type: 'list', items: '$data.items.list', spacing: '$token.spacing.md',
            template: { type: 'text', value: '$item.title', style: '$token.typography.headline', color: '$token.color.textPrimary' } },
        },
      };
    case 'form':
      return {
        version: '0.1',
        screen: {
          id, title, state: { email: '', error: '' },
          content: { type: 'vstack', alignment: 'leading', spacing: '$token.spacing.md', ...pad, children: [
            t(title, '$token.typography.largeTitle'),
            { type: 'textfield', bind: '$state.email', label: 'Email', keyboardType: 'email', modifiers: { size: { width: { mode: 'fill' } } } },
            { type: 'button', title: 'Submit', style: '$token.button.primary', modifiers: { size: { width: { mode: 'fill' } } },
              onTap: { action: 'request', source: { service: 'api', path: '/submit', method: 'POST', body: { email: '$state.email' } },
                onSuccess: { action: 'navigate', to: `${id}_success` },
                onError: { action: 'setState', key: 'error', value: 'Something went wrong' } } },
            { type: 'text', value: '$state.error', style: '$token.typography.caption', color: '$token.color.error', visibleWhen: { field: '$state.error', op: 'nonempty' } },
          ] },
        },
      };
    case 'detail':
      return {
        version: '0.1',
        screen: {
          id, title,
          content: { type: 'async', source: { id: 'item', service: 'catalog', path: '/items/{id}', method: 'GET' },
            loading: { type: 'spinner' },
            error: { type: 'text', value: 'Failed to load', style: '$token.typography.body', color: '$token.color.error' },
            content: { type: 'vstack', alignment: 'leading', spacing: '$token.spacing.md', ...pad, children: [
              { type: 'image', source: '$data.item.image', loader: { placeholder: 'skeleton', aspectRatio: 1 }, modifiers: { size: { width: { mode: 'fill' } }, cornerRadius: '$token.radius.lg' } },
              t('$data.item.title', '$token.typography.title2'),
              t('$data.item.subtitle', '$token.typography.subheadline', '$token.color.textSecondary'),
            ] } },
        },
      };
    default: // blank
      return {
        version: '0.1',
        screen: { id, title, content: { type: 'vstack', alignment: 'leading', spacing: '$token.spacing.md', ...pad, children: [
          t(title, '$token.typography.largeTitle'), t('Start building here.', '$token.typography.body', '$token.color.textSecondary'),
        ] } },
      };
  }
}

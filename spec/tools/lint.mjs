#!/usr/bin/env node
// Zero-dependency design linter for SDUI payloads — the guardrail layer ABOVE
// schema validation (spec/tools/validate.mjs). Validation answers "is this a legal
// contract?"; lint answers "is this a GOOD screen?" — off-token literals, WCAG
// contrast, tap-target size, dead controls, layout-jumpy images, palette cohesion.
//
// One engine, two surfaces: it is a pure function so the visual composer can badge
// nodes inline AND the MCP server can expose it as `lint_screen` (spec/mcp) — the
// designer and the AI reflect on the *same* rule ids from the *same* source of truth.
// See docs/blueprint/23-composer-and-authoring.md §4 for the rule set and its
// research citations (WCAG 2.2, the premium-UI playbook, YADL/Stark parity).
//
// Every finding is deterministic and auto-fixable or clearly explainable — no taste
// calls. `fix`, when present, is a minimal RFC-6902-style patch a composer can apply
// in one click and the AI can auto-apply in its reflect loop.
//
// Usage:  node spec/tools/lint.mjs spec/snapshots/components/*.json
//         node spec/tools/lint.mjs --tokens spec/schema/tokens.example.json screen.json
//         node spec/tools/lint.mjs --strict screen.json      # exit 1 on any error finding

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
// Default tokens: the shipped example set, so the CLI resolves $token.* refs and
// off-token literals out of the box. `--tokens` overrides it per brand/theme.
const DEFAULT_TOKENS_PATH = join(HERE, '..', 'schema', 'tokens.example.json');

// ── Rule catalogue (ids + default severities), cited to doc 23 §4 ───────────────
// Kept as data so teams can tune severity and the MCP can teach each diagnostic.
export const RULES = {
  'token/literal-color':    { severity: 'warn',  doc: 'A raw hex where a $token.color.* holds the same value — use the token.' },
  'token/literal-spacing':  { severity: 'warn',  doc: 'A raw spacing/padding number matching a $token.spacing.* value — use the token.' },
  'token/literal-radius':   { severity: 'warn',  doc: 'A raw cornerRadius matching a $token.radius.* value — use the token.' },
  'token/off-grid-spacing': { severity: 'info',  doc: 'A raw spacing/padding off the 4/8-pt grid (YADL parity) — snap to a token.' },
  'a11y/contrast':          { severity: 'error', doc: 'Text vs its background below WCAG AA (4.5:1 normal, 3:1 large ≥24px/≥19px-bold).' },
  'a11y/tap-target':        { severity: 'warn',  doc: 'A tappable control smaller than 44pt effective (Apple HIG; WCAG 2.5.8 min 24).' },
  'action/button-no-ontap': { severity: 'error', doc: 'A button with no onTap — a dead control.' },
  'layout/image-no-aspect': { severity: 'warn',  doc: 'An image with neither aspectRatio nor a fixed height — reserves no space, so the layout jumps (CLS).' },
  'premium/one-accent':     { severity: 'info',  doc: 'More than two distinct accent hues on one screen — one accent reads as premium.' },
  'premium/rainbow':        { severity: 'warn',  doc: 'Four or more saturated hues competing — reduce the palette (no rainbow).' },
};
export const SEVERITY_ORDER = { error: 0, warn: 1, info: 2 };

// ── Colour maths (WCAG relative luminance + HSL, ~30 lines, no dep) ──────────────
// Normalise a hex string to canonical upper-case form WITHOUT dropping alpha, so a
// literal like "#FFFFFFCC" never matches the 6-digit token "#FFFFFF".
function normHex(s) {
  if (typeof s !== 'string' || s[0] !== '#') return null;
  let h = s.slice(1);
  if (h.length === 3) h = h.split('').map((c) => c + c).join('');
  if (!/^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(h)) return null;
  return `#${h.toUpperCase()}`;
}
// Parse a hex string to opaque {r,g,b} (alpha ignored — luminance/hue are of the ink).
function parseRGB(s) {
  const n = normHex(s);
  if (!n) return null;
  const h = n.slice(1);
  return { r: parseInt(h.slice(0, 2), 16), g: parseInt(h.slice(2, 4), 16), b: parseInt(h.slice(4, 6), 16) };
}
// Alpha (0–255) of a hex; 255 for 6-digit / non-hex. A translucent fill (< 255) shows
// through to the layer beneath, so it can't be treated as a known solid background.
function alphaOf(s) {
  const n = normHex(s);
  return n && n.length === 9 ? parseInt(n.slice(7, 9), 16) : 255;
}
function relLuminance({ r, g, b }) {
  const lin = (c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}
function contrastRatio(a, b) {
  const L1 = relLuminance(a), L2 = relLuminance(b);
  const hi = Math.max(L1, L2), lo = Math.min(L1, L2);
  return (hi + 0.05) / (lo + 0.05);
}
function toHSL({ r, g, b }) {
  const R = r / 255, G = g / 255, B = b / 255;
  const max = Math.max(R, G, B), min = Math.min(R, G, B), d = max - min;
  const l = (max + min) / 2;
  let h = 0, s = 0;
  if (d !== 0) {
    s = d / (1 - Math.abs(2 * l - 1));
    if (max === R) h = ((G - B) / d) % 6;
    else if (max === G) h = (B - R) / d + 2;
    else h = (R - G) / d + 4;
    h *= 60; if (h < 0) h += 360;
  }
  return { h, s, l };
}
// A colour is a chromatic "accent" (vs a neutral gray/black/white) when it carries
// real saturation at a visible lightness. Neutrals fall out via low saturation.
function isAccent(rgb) {
  const { s, l } = toHSL(rgb);
  return s > 0.25 && l > 0.15 && l < 0.92;
}

// ── Token index: value → ref (for off-token detection) and ref → rgb (for maths) ─
function buildTokenIndex(tokens) {
  const colorHexToRef = new Map();   // "#0A84FF" → "$token.color.primary"
  const colorRefToRGB = new Map();   // "$token.color.primary" → {r,g,b}
  const spacingByValue = new Map();  // 16 → "$token.spacing.md"
  const radiusByValue = new Map();   // 12 → "$token.radius.md"
  const t = tokens || {};
  for (const [k, v] of Object.entries(t.color || {})) {
    if (typeof v !== 'string') continue;
    const n = normHex(v); const rgb = parseRGB(v);
    if (n && !colorHexToRef.has(n)) colorHexToRef.set(n, `$token.color.${k}`);
    if (rgb) colorRefToRGB.set(`$token.color.${k}`, rgb);
  }
  // Dark palette only feeds ref→rgb resolution, never the off-token suggestion map.
  for (const [k, v] of Object.entries(t.colorDark || {})) {
    const rgb = parseRGB(v);
    if (rgb && !colorRefToRGB.has(`$token.color.${k}`)) colorRefToRGB.set(`$token.color.${k}`, rgb);
  }
  for (const [k, v] of Object.entries(t.spacing || {})) if (typeof v === 'number' && !spacingByValue.has(v)) spacingByValue.set(v, `$token.spacing.${k}`);
  for (const [k, v] of Object.entries(t.radius || {})) if (typeof v === 'number' && !radiusByValue.has(v)) radiusByValue.set(v, `$token.radius.${k}`);
  // Typography: ref → {size, weight}, for the contrast large-text threshold.
  const typography = new Map();
  for (const [k, v] of Object.entries(t.typography || {})) if (v && typeof v === 'object') typography.set(`$token.typography.${k}`, v);
  return { colorHexToRef, colorRefToRGB, spacingByValue, radiusByValue, typography };
}
// Resolve any colour expression (token ref or hex) to rgb; null for bindings we can't resolve.
function resolveColor(value, idx) {
  if (typeof value !== 'string') return null;
  if (value.startsWith('$token.color.')) return idx.colorRefToRGB.get(value) ?? null;
  if (value[0] === '#') return parseRGB(value);
  return null;   // $data / $state / $env binding — unknowable at author time
}

// Dotted authoring path (mirrors validate.mjs) → JSON Pointer for a `fix` patch.
const toPointer = (dotted) => '/' + dotted.replace(/\[(\d+)\]/g, '/$1').replace(/\./g, '/');

// ── The linter ──────────────────────────────────────────────────────────────────
class Linter {
  constructor(tokens) {
    this.idx = buildTokenIndex(tokens);
    this.findings = [];
    this.accents = new Map();   // hue-bucket → { ref, path } — screen-wide palette
  }
  add(rule, path, message, fix) {
    this.findings.push({ rule, severity: RULES[rule].severity, path, message, ...(fix ? { fix } : {}) });
  }

  lint(doc) {
    const screen = doc?.screen;
    if (!screen || typeof screen.content !== 'object' || screen.content === null) return { findings: [] };
    // Contrast is judged only against an EXPLICITLY set background (a modifiers.background
    // an ancestor declares). The implicit screen default is deliberately NOT assumed: it
    // both floods on the design system's own muted-secondary-on-white pairings and — worse —
    // false-positives wherever a real background is a gradient/image/material we can't
    // resolve (white text then looks like white-on-white). Explicit-only = every contrast
    // finding is real and actionable. The root seeds the value for the palette pass only.
    const rootBg = this.idx.colorRefToRGB.get('$token.color.background') ?? null;
    this.walk(screen.content, 'screen.content', { bg: rootBg, explicit: false, ambiguous: screen.chrome === 'immersive' });
    this.paletteCheck();
    this.findings.sort((a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity]);
    return { findings: this.findings };
  }

  // Iterate every colour-bearing field of a node as {value, path}.
  *colorsOf(node, path) {
    const emit = (v, sub) => (typeof v === 'string' ? { value: v, path: `${path}.${sub}` } : null);
    for (const key of ['color', 'tint', 'accent']) { const e = emit(node[key], key); if (e) yield e; }
    if (Array.isArray(node.colors)) for (let i = 0; i < node.colors.length; i++) { const e = emit(node.colors[i], `colors[${i}]`); if (e) yield e; }
    const m = node.modifiers;
    if (m) {
      if (typeof m.background === 'string') yield { value: m.background, path: `${path}.modifiers.background` };
      if (m.shadow && typeof m.shadow.color === 'string') yield { value: m.shadow.color, path: `${path}.modifiers.shadow.color` };
    }
  }

  walk(node, path, ctx) {
    if (typeof node !== 'object' || node === null) return;
    const type = node.type;
    const m = node.modifiers || {};

    // ── token/* : off-token colour literals + palette collection ──
    for (const { value, path: cpath } of this.colorsOf(node, path)) {
      const n = normHex(value);
      if (n) {
        const ref = this.idx.colorHexToRef.get(n);
        if (ref) this.add('token/literal-color', cpath, `literal ${value} equals ${ref} — use the token`, { op: 'replace', path: toPointer(cpath), value: ref });
      }
      const rgb = resolveColor(value, this.idx);
      if (rgb && isAccent(rgb)) {
        const bucket = Math.round(toHSL(rgb).h / 30) % 12;
        if (!this.accents.has(bucket)) this.accents.set(bucket, { ref: value, path: cpath });
      }
    }

    // ── token/* : off-token spacing / radius ──
    if (typeof node.spacing === 'number') this.checkSpacing(node.spacing, `${path}.spacing`);
    if (m.padding !== undefined) this.checkPadding(m.padding, `${path}.modifiers.padding`);
    if (typeof m.cornerRadius === 'number') {
      const ref = this.idx.radiusByValue.get(m.cornerRadius);
      if (ref) this.add('token/literal-radius', `${path}.modifiers.cornerRadius`, `literal ${m.cornerRadius} equals ${ref} — use the token`, { op: 'replace', path: toPointer(`${path}.modifiers.cornerRadius`), value: ref });
    }

    // ── action/button-no-ontap : dead control ──
    if (type === 'button' && !node.onTap && !m.onTap) {
      this.add('action/button-no-ontap', path, 'button has no onTap — a dead control; wire an action or use a text/label');
    }

    // ── a11y/tap-target : tappable smaller than 44pt effective ──
    const tappable = !!(node.onTap || m.onTap || type === 'button' || (type === 'icon' && (node.onTap || m.onTap)));
    if (tappable) this.checkTapTarget(m, path);

    // ── layout/image-no-aspect ──
    if (type === 'image') {
      const hasAspect = node.loader && typeof node.loader.aspectRatio === 'number';
      const hasHeight = fixedAxis(m, 'height') !== null;
      if (!hasAspect && !hasHeight) {
        this.add('layout/image-no-aspect', path, 'image has neither loader.aspectRatio nor a fixed height — the layout jumps while it loads', { op: 'add', path: toPointer(`${path}.loader`), value: { placeholder: 'skeleton', aspectRatio: 1 } });
      }
    }

    // Effective background for this node and its subtree — a node's OWN opaque background
    // sits directly behind its own text, so derive it before judging contrast.
    const childCtx = this.deriveBg(node, ctx);

    // ── a11y/contrast : text vs resolved background ──
    if (type === 'text' && typeof node.value === 'string') this.checkContrast(node, path, childCtx);

    for (const { child, cpath } of childrenOf(node, path)) this.walk(child, cpath, childCtx);
  }

  checkSpacing(value, path, rule = 'token/literal-spacing') {
    const ref = this.idx.spacingByValue.get(value);
    if (ref) return this.add('token/literal-spacing', path, `literal ${value} equals ${ref} — use the token`, { op: 'replace', path: toPointer(path), value: ref });
    if (value > 0 && value % 4 !== 0) this.add('token/off-grid-spacing', path, `${value}pt is off the 4/8-pt grid — snap to a $token.spacing.* step`);
  }
  checkPadding(pad, path) {
    if (typeof pad === 'number') return this.checkSpacing(pad, path);
    if (pad && typeof pad === 'object') for (const [edge, v] of Object.entries(pad)) if (typeof v === 'number') this.checkSpacing(v, `${path}.${edge}`);
  }

  checkTapTarget(m, path) {
    const slop = typeof m.hitSlop === 'number' ? m.hitSlop : 0;
    for (const axis of ['width', 'height']) {
      const v = fixedAxis(m, axis);
      if (v === null) continue;   // hug/fill/unset — unmeasurable, don't guess
      const eff = v + 2 * slop;
      if (eff < 44) {
        this.add('a11y/tap-target', path, `tappable ${axis} is ${eff}pt (< 44pt) — below the Apple HIG minimum touch target`, { op: 'add', path: toPointer(`${path}.modifiers.hitSlop`), value: Math.ceil((44 - eff) / 2) });
        return;   // one finding per control is enough
      }
    }
  }

  checkContrast(node, path, ctx) {
    if (!ctx.explicit || ctx.ambiguous || !ctx.bg) return;   // only judge against an explicitly-set, resolvable background
    const fg = resolveColor(node.color ?? '$token.color.textPrimary', this.idx);
    if (!fg) return;                                          // colour is a binding
    const ratio = contrastRatio(fg, ctx.bg);
    const { size, bold } = this.typographyOf(node.style);
    const large = size >= 24 || (size >= 19 && bold);
    const required = large ? 3.0 : 4.5;
    if (ratio >= required) return;
    // Severity split keeps errors rare & real: below 3:1 fails at ANY size (error);
    // otherwise it only fails for its size class (warn). Tuned to be useful, not noisy.
    const r2 = Math.round(ratio * 100) / 100;
    const msg = `text contrast ${r2}:1 vs its background is below WCAG AA (${required}:1 for ${large ? 'large' : 'normal'} text)`;
    const finding = { rule: 'a11y/contrast', severity: ratio < 3.0 ? 'error' : 'warn', path: `${path}.color`, message: msg };
    // Auto-fix: the strongest same-role token that passes against this background.
    const onLight = relLuminance(ctx.bg) > 0.5;
    const candidate = onLight ? '$token.color.textPrimary' : '$token.color.onPrimary';
    const candRGB = this.idx.colorRefToRGB.get(candidate);
    if (node.color !== candidate && candRGB && contrastRatio(candRGB, ctx.bg) >= required) {
      finding.fix = { op: 'replace', path: toPointer(`${path}.color`), value: candidate };
    }
    this.findings.push(finding);
  }

  typographyOf(style) {
    const t = typeof style === 'string' ? this.idx.typography.get(style) : null;
    const size = t && typeof t.size === 'number' ? t.size : 17;   // body default
    const bold = t ? ['bold', 'semibold', 'heavy', 'black'].includes(t.weight) : false;
    return { size, bold };
  }

  // The subtree background: a solid background modifier sets it; a binding, a material,
  // a gradient, or a zstack (layered media) makes it ambiguous so contrast bows out.
  deriveBg(node, ctx) {
    let { bg, explicit, ambiguous } = ctx;
    const m = node.modifiers || {};
    if (typeof m.background === 'string') {
      const rgb = resolveColor(m.background, this.idx);
      // Only an OPAQUE, resolvable fill is a known background; a binding or a translucent
      // fill (alpha < 255, e.g. a frosted "#FFFFFF26" card) shows through to an unknown layer.
      if (rgb && alphaOf(m.background) === 255) { bg = rgb; explicit = true; ambiguous = false; } else ambiguous = true;
    }
    if (m.material) ambiguous = true;
    if (node.type === 'zstack' || node.type === 'gradient') ambiguous = true;
    return { bg, explicit, ambiguous };
  }

  paletteCheck() {
    const count = this.accents.size;
    if (count < 3) return;
    const list = [...this.accents.values()].map((a) => a.ref).join(', ');
    if (count >= 4) this.add('premium/rainbow', 'screen.content', `${count} competing saturated hues (${list}) — reduce the palette to one accent`);
    else this.add('premium/one-accent', 'screen.content', `${count} distinct accent hues (${list}) — a single accent reads as more premium`);
  }
}

// Fixed length along an axis from modifiers.size (mode:fixed) or modifiers.frame.
function fixedAxis(m, axis) {
  const s = m?.size?.[axis];
  if (s && s.mode === 'fixed' && typeof s.value === 'number') return s.value;
  const f = m?.frame?.[axis];
  if (typeof f === 'number') return f;
  return null;
}

// Child components of a node (mirrors validate.mjs traversal, plus list/grid templates).
function childrenOf(node, path) {
  const out = [];
  const push = (child, sub) => { if (child && typeof child === 'object') out.push({ child, cpath: `${path}.${sub}` }); };
  (node.children ?? []).forEach((c, i) => push(c, `children[${i}]`));
  push(node.child, 'child');
  push(node.template, 'template');
  push(node.content, 'content');       // async
  push(node.loading, 'loading');
  push(node.error, 'error');
  push(node.empty, 'empty');           // list empty state
  if (node.collapsingHeader) { push(node.collapsingHeader.expanded, 'collapsingHeader.expanded'); push(node.collapsingHeader.compact, 'collapsingHeader.compact'); }
  return out;
}

/**
 * Lint an SDUI document. Pure — no I/O, no mutation of `doc`.
 * @param {object} doc     the screen document ({ version, screen }).
 * @param {object} [tokens] the parsed design-token set (tokens.example.json shape).
 * @returns {{ findings: Array<{rule,severity,path,message,fix?}> }}
 */
export function lint(doc, tokens = null) {
  return new Linter(tokens).lint(doc);
}

// ── CLI ─────────────────────────────────────────────────────────────────────────
if (import.meta.url === `file://${process.argv[1]}`) runCli();

function runCli() {
  const args = process.argv.slice(2);
  let tokensPath = DEFAULT_TOKENS_PATH;
  let strict = false;
  const files = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--tokens') tokensPath = args[++i];
    else if (args[i] === '--strict') strict = true;
    else files.push(args[i]);
  }
  if (files.length === 0) {
    console.error('usage: node lint.mjs [--tokens <tokens.json>] [--strict] <payload.json> [...]');
    process.exit(2);
  }
  let tokens = null;
  try { tokens = JSON.parse(readFileSync(tokensPath, 'utf8')); }
  catch (e) { console.error(`✗ --tokens ${tokensPath}: ${e.message}`); process.exit(2); }

  const glyph = { error: '✗', warn: '▲', info: '·' };
  const total = { error: 0, warn: 0, info: 0 };
  let errorFiles = 0;

  for (const file of files) {
    let doc;
    try { doc = JSON.parse(readFileSync(file, 'utf8')); }
    catch (e) { console.error(`✗ ${file}: invalid JSON — ${e.message}`); errorFiles++; continue; }
    const { findings } = lint(doc, tokens);
    if (findings.length === 0) { console.log(`✓ ${file}`); continue; }
    const hasError = findings.some((f) => f.severity === 'error');
    console.log(`${hasError ? '✗' : '▲'} ${file}  (${findings.length} finding${findings.length === 1 ? '' : 's'})`);
    for (const f of findings) {
      total[f.severity]++;
      console.log(`    ${glyph[f.severity]} [${f.rule}] ${f.path}`);
      console.log(`        ${f.message}`);
    }
    if (hasError) errorFiles++;
  }

  console.log(`\n${files.length} file(s) · ${total.error} error · ${total.warn} warn · ${total.info} info`);
  process.exit(strict && total.error > 0 ? 1 : 0);
}

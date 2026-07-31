#!/usr/bin/env node
// Emits spec/snapshots/manifest.json — the SINGLE source of truth for the visual
// snapshot suite. Every platform's snapshot test iterates this list, so the set is
// identical on iOS, Android and (later) Aurora. Regenerated, never hand-edited, so it
// can't drift from the real corpus. See docs/blueprint/20-visual-snapshot-harness.md.
//
// Usage: node spec/snapshots/gen-manifest.mjs        # write manifest.json
//        node spec/snapshots/gen-manifest.mjs --check # fail if it would change (CI)

import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, basename } from 'node:path';
import { KNOWN_COMPONENTS } from '../tools/validate.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..');
const SCREENS_DIR = join(ROOT, 'ios', 'Sources', 'SDUIPlayground', 'Content', 'screens');
const CARDS_DIR = join(HERE, 'components');
const OUT = join(HERE, 'manifest.json');

const readJSON = (p) => JSON.parse(readFileSync(p, 'utf8'));

// ── Mechanics: derive interaction end-states from the REAL contract ──────────────────
// Rather than hand-list which screens have a swipe or a chart scrub, we walk each screen's
// component tree and let the modifiers/types it actually uses declare the mechanics to
// capture. Same discipline as the rest of this generator: the set can't drift from the
// corpus, and it answers "go through our contracts for what we can do" automatically.
// Each native leg reads these and drives (gesture → target) before capturing `{id}@{state}`.
const MECH_FOR_TYPE = {
  chart: { id: 'scrub', gesture: 'dragAlongX', note: 'drag a finger across the chart — crosshair/scrub' },
  pager: { id: 'page', gesture: 'swipeLeft', note: 'swipe to the next page' },
  slider: { id: 'slide', gesture: 'dragAlongX', note: 'drag the slider thumb' },
  disclosure: { id: 'expand', gesture: 'tap', note: 'tap to expand the disclosure' },
};

// A stable selector a leg can use to find the node: explicit id → first text → type.
function selectorFor(node) {
  if (node.id) return node.id;
  let text = null;
  (function dfs(n) {
    if (text || !n || typeof n !== 'object') return;
    if (typeof n.text === 'string' && n.text.trim()) { text = n.text.trim(); return; }
    for (const v of Object.values(n)) { if (Array.isArray(v)) v.forEach(dfs); else if (v && typeof v === 'object') dfs(v); }
  })(node);
  return text || node.type || null;
}

function detectMechanics(doc) {
  const found = new Map(); // mechanic id → spec (first occurrence wins)
  (function walk(n) {
    if (!n || typeof n !== 'object') return;
    if (Array.isArray(n)) { n.forEach(walk); return; }
    if (typeof n.type === 'string') {
      const mods = n.modifiers || {};
      if (mods.swipe && !found.has('swipe'))
        found.set('swipe', { id: 'swipe', gesture: 'swipeLeft', target: selectorFor(n), note: 'reveal swipe actions on the row' });
      if ((mods.contextMenu || mods.onLongPress) && !found.has('menu'))
        found.set('menu', { id: 'menu', gesture: 'longPress', target: selectorFor(n), note: 'long-press → context menu' });
      const mt = MECH_FOR_TYPE[n.type];
      if (mt && !found.has(mt.id)) found.set(mt.id, { ...mt, target: selectorFor(n) });
    }
    for (const v of Object.values(n)) walk(v);
  })(doc);
  return [...found.values()];
}

// ── Whole screens: enumerate the shared corpus, key by the screen's own id ──────────
// The filename may be numbered (01-discover.json) but the stable cross-platform key is
// screen.id, which every renderer loads the screen by.
function screens() {
  const out = [];
  for (const f of readdirSync(SCREENS_DIR).filter((f) => f.endsWith('.json')).sort()) {
    let doc;
    try { doc = readJSON(join(SCREENS_DIR, f)); } catch { continue; }
    const id = doc?.screen?.id;
    if (!id) continue;
    const mechanics = detectMechanics(doc);
    out.push({ id, source: `content/screens/${f}`, viewport: 'phone', ...(mechanics.length ? { mechanics } : {}) });
  }
  return out;
}

// ── Components: one isolated card per KNOWN_COMPONENTS type. Phase 0 includes only the
// cards that exist; the rest are reported so the visual set can never *silently* fall
// behind the vocabulary (mirrors spec/conformance/coverage.mjs --strict). ────────────
function components() {
  const have = existsSync(CARDS_DIR)
    ? new Set(readdirSync(CARDS_DIR).filter((f) => f.endsWith('.json')).map((f) => basename(f, '.json')))
    : new Set();
  const out = [];
  for (const type of [...KNOWN_COMPONENTS].sort()) {
    if (!have.has(type)) continue;
    let mechanics = [];
    try { mechanics = detectMechanics(readJSON(join(CARDS_DIR, `${type}.json`))); } catch { /* card unreadable → no mechanics */ }
    out.push({ id: type, source: `snapshots/components/${type}.json`, viewport: 'phone', ...(mechanics.length ? { mechanics } : {}) });
  }
  const missing = [...KNOWN_COMPONENTS].sort().filter((t) => !have.has(t));
  return { out, missing };
}

const { out: comps, missing } = components();
const manifest = {
  $comment: 'GENERATED by spec/snapshots/gen-manifest.mjs — do not edit by hand. Single source of truth for the visual snapshot suite; every platform iterates this list. See docs/blueprint/20-visual-snapshot-harness.md.',
  version: 1,
  viewports: {
    phone: { width: 390, height: 844, density: 3, label: 'iPhone-ish 390pt' },
    'phone-small': { width: 360, height: 800, density: 3, label: 'compact 360dp' },
  },
  schemes: ['light', 'dark'],
  // Pinned reference devices — every leg captures on THESE so the glued sheets compare
  // like-for-like. Bump deliberately (a device/OS change is a reviewed visual diff).
  devices: {
    ios: { simulator: 'iPhone 15', os: 'iOS 17.5' },
    android: { emulator: 'Pixel 7', api: 34 },
    aurora: { device: 'Aurora emulator', os: 'Aurora 5.x' },
  },
  env: { locale: 'ru_RU', timezone: 'Europe/Moscow', reduceMotion: true, textScale: 1.0 },
  // Gesture vocabulary a leg must implement to reach each mechanic end-state.
  gestures: {
    swipeLeft: 'swipe the target from right to left',
    longPress: 'press and hold the target ~600ms',
    dragAlongX: 'press the target and drag horizontally across its width',
    tap: 'single tap the target',
  },
  screens: screens(),
  components: comps,
};

const json = JSON.stringify(manifest, null, 2) + '\n';

if (process.argv.includes('--check')) {
  const current = existsSync(OUT) ? readFileSync(OUT, 'utf8') : '';
  if (current !== json) {
    console.error('manifest.json is stale — run: node spec/snapshots/gen-manifest.mjs');
    process.exit(1);
  }
  console.log('manifest.json up to date');
} else {
  writeFileSync(OUT, json);
  console.log(`manifest: ${manifest.screens.length} screens, ${manifest.components.length} component cards → ${OUT}`);
}

const cardCoverage = KNOWN_COMPONENTS.size ? Math.round((comps.length / KNOWN_COMPONENTS.size) * 100) : 100;
console.log(`component-card coverage: ${comps.length}/${KNOWN_COMPONENTS.size} (${cardCoverage}%)`);
if (missing.length) console.log(`  cards still needed: ${missing.join(', ')}`);

const mechCount = [...manifest.screens, ...manifest.components].reduce((n, e) => n + (e.mechanics?.length || 0), 0);
const mechFixtures = [...manifest.screens, ...manifest.components].filter((e) => e.mechanics?.length).length;
console.log(`mechanics: ${mechCount} interaction states across ${mechFixtures} fixtures (auto-derived from contracts)`);

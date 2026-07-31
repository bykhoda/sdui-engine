#!/usr/bin/env node
// Glues the per-platform PNGs of each fixture into ONE side-by-side sheet — the portable,
// shareable sibling of stitch.mjs's HTML gallery. Every sheet is always three columns
// (iOS │ Android │ Aurora); a platform with no PNG gets a visible "not captured / not
// built" placeholder, so a missing leg reads as a gap, never as silent success. This is
// the artifact you scan to see which platform lags where.
// See docs/blueprint/20-visual-snapshot-harness.md.
//
// Input  (naming convention, shared with stitch.mjs / collect.mjs):
//   __out__/{fixture}[@{state}].{platform}.{scheme}.png
//     {state} is an optional interaction/mechanic end-state (swipe, menu, scrub, page2…);
//     absent means the resting "default" state.
// Output:
//   __out__/_sheets/{fixture}[@{state}].{scheme}.png   # one glued iOS│Android│Aurora row
//   __out__/_sheets/index.html                         # every sheet on one scrollable page
//
// Usage: node spec/snapshots/sheet.mjs            # build all sheets from __out__
//        node spec/snapshots/sheet.mjs --height 1200   # normalise column height (px)
//
// Requires ImageMagick (`magick`) on PATH — install with `brew install imagemagick`.

import { readdirSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { execFileSync } from 'node:child_process';

// ImageMagick on macOS ships no fontconfig default, so `-font <name>` fails with an empty
// "unable to read font" error. Resolve a real font file up front; fall back to unlabelled
// montages if none of the usual paths exist (Linux CI, minimal images).
const FONT = [
  '/System/Library/Fonts/Helvetica.ttc',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/usr/share/fonts/TTF/DejaVuSans.ttf',
].find((p) => existsSync(p));
const fontArgs = FONT ? ['-font', FONT] : [];

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, '__out__');
// The glued sheets are the primary, STORED artifact (individual per-platform PNGs stay
// ephemeral in __out__). `--commit` writes the gallery into spec/snapshots/__gallery__/ —
// the committed cross-platform gallery. Default writes a throwaway preview to __out__/_sheets.
const COMMIT = process.argv.includes('--commit');
const GALLERY = join(HERE, '__gallery__');
const SHEETS = COMMIT ? GALLERY : join(OUT, '_sheets');
const PLATFORMS = ['ios', 'android', 'aurora'];
const LABELS = { ios: 'iOS', android: 'Android', aurora: 'Aurora' };
const INK = '#e8e8ea';
const BG = '#0f0f12';
const PANEL = '#1a1a20';

const arg = (name, dflt) => {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : dflt;
};
const HEIGHT = Number(arg('--height', '1000')); // column height sheets are normalised to (smaller = leaner committed gallery)
const COL_W = Math.round(HEIGHT * (390 / 844));  // phone aspect → a sensible column width
const has = (f) => process.argv.includes(f);
const DIFF = has('--diff');                       // opt-in: add the pixel-diff band (off by default)
const FUZZ = arg('--fuzz', '5%');                // colour tolerance so AA/subpixel isn't "divergence"
// Reference platform every other column is diffed against — iOS is the parity source of
// truth (Android/Aurora must match it). Falls back down the list if iOS wasn't captured.
const REF_PRIORITY = (arg('--ref', 'ios,android,aurora')).split(',').map((s) => s.trim());

// ImageMagick 7 exposes everything under a single `magick` entrypoint. Fail loud and
// early with the install hint rather than emitting half-built sheets.
function haveMagick() {
  try { execFileSync('magick', ['-version'], { stdio: 'ignore' }); return true; } catch { return false; }
}
const magick = (args) => execFileSync('magick', args, { stdio: ['ignore', 'ignore', 'inherit'] });

// A labelled stand-in for a platform that produced no PNG for this fixture/state. Wording
// distinguishes "no renderer yet" (Aurora) from "renderer exists, not captured this run".
function placeholder(platform, dest) {
  const note = platform === 'aurora' ? 'Aurora\nrenderer not built yet' : `${LABELS[platform]}\nnot captured this run`;
  magick([
    '-size', `${COL_W}x${HEIGHT}`, `xc:${PANEL}`, ...fontArgs,
    '-gravity', 'center', '-fill', '#6b6b76', '-pointsize', '26',
    '-annotate', '0', note,
    '-bordercolor', '#33333a', '-border', '1', dest,
  ]);
}

// A solid labelled tile for the diff band's non-diff cells (the reference marker, or an
// "n/a" where a platform wasn't captured so there's nothing to diff).
function textTile(lines, dest, fill = '#8a8a95') {
  magick([
    '-size', `${COL_W}x${HEIGHT}`, `xc:${BG}`, ...fontArgs,
    '-gravity', 'center', '-fill', fill, '-pointsize', '30',
    '-annotate', '0', lines,
    '-bordercolor', '#26262b', '-border', '1', dest,
  ]);
}

// Force both operands to the SAME canvas before comparing: fit to the column box preserving
// aspect, then pad to exact WxH. Different device resolutions then diff like-for-like.
function normalize(src, dest) {
  magick([src, '-resize', `${COL_W}x${HEIGHT}`, '-background', BG, '-gravity', 'center', '-extent', `${COL_W}x${HEIGHT}`, dest]);
}

// `magick compare` writes a heat-map (differing pixels flared red over a faded base) and
// prints the AE (absolute-error pixel count) to stderr; it exits 1 when images differ, so
// the count arrives via the thrown error. Returns the divergence as a % of total pixels.
function diffImage(refNorm, otherNorm, dest) {
  const parse = (s) => { const m = /(\d+(?:\.\d+)?)(?:e[+-]?\d+)?/i.exec(String(s).trim()); return m ? Number(m[1]) : 0; };
  let ae = 0;
  try {
    const out = execFileSync('magick', ['compare', '-metric', 'AE', '-fuzz', FUZZ, refNorm, otherNorm, dest],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    ae = parse(out);
  } catch (e) {
    if (e.status === 1) ae = parse(e.stderr || e.stdout || '0'); // "differ" is expected, not a failure
    else throw e;
  }
  return { ae, pct: (ae / (COL_W * HEIGHT)) * 100 };
}

const pickRef = (cells) => REF_PRIORITY.find((p) => cells[p]) || null;

// Parse __out__ into { `${fixture}|${state}|${scheme}`: {fixture,state,scheme,cells} }.
function groups() {
  const re = /^(.+?)(?:@([a-z0-9-]+))?\.(ios|android|aurora)\.(light|dark)\.png$/;
  const map = new Map();
  for (const f of existsSync(OUT) ? readdirSync(OUT) : []) {
    const m = re.exec(f);
    if (!m) continue;
    const [, fixture, state = 'default', platform, scheme] = m;
    const key = `${fixture}|${state}|${scheme}`;
    const g = map.get(key) ?? { fixture, state, scheme, cells: {} };
    g.cells[platform] = join(OUT, f);
    map.set(key, g);
  }
  return [...map.values()].sort(
    (a, b) => a.fixture.localeCompare(b.fixture) || a.state.localeCompare(b.state) || a.scheme.localeCompare(b.scheme),
  );
}

function sheetName(g) {
  return `${g.fixture}${g.state === 'default' ? '' : `@${g.state}`}.${g.scheme}`;
}

function buildSheet(g, tmpDir) {
  // ── Row 1: the renders (real PNG, or a visible placeholder for a missing leg).
  const cellPath = {};
  const renderInputs = [];
  for (const p of PLATFORMS) {
    let src = g.cells[p];
    if (!src) { src = join(tmpDir, `_ph.${p}.png`); placeholder(p, src); }
    cellPath[p] = src;
    renderInputs.push('-label', LABELS[p], src);
  }

  // ── Row 2: the diff band — only meaningful with ≥2 real renders to compare.
  const realCount = PLATFORMS.filter((p) => g.cells[p]).length;
  const ref = DIFF && realCount >= 2 ? pickRef(g.cells) : null;
  const metrics = {}; // platform → divergence % vs ref (for the gallery)
  let diffInputs = null;
  if (ref) {
    const refNorm = join(tmpDir, `_norm.${ref}.png`);
    normalize(cellPath[ref], refNorm);
    diffInputs = [];
    for (const p of PLATFORMS) {
      if (p === ref) {
        const tile = join(tmpDir, `_ref.${p}.png`);
        textTile(`◎ reference\n${LABELS[ref]}`, tile, '#6ee7b7');
        diffInputs.push('-label', `reference · ${LABELS[ref]}`, tile);
      } else if (g.cells[p]) {
        const otherNorm = join(tmpDir, `_norm.${p}.png`);
        normalize(cellPath[p], otherNorm);
        const dst = join(tmpDir, `_diff.${p}.png`);
        const { pct } = diffImage(refNorm, otherNorm, dst);
        metrics[p] = pct;
        diffInputs.push('-label', `${LABELS[p]} Δ${LABELS[ref]} · ${pct.toFixed(1)}%`, dst);
      } else {
        const na = join(tmpDir, `_na.${p}.png`);
        textTile(`${LABELS[p]}\nnot captured\n— no diff —`, na, '#5a5a63');
        diffInputs.push('-label', `${LABELS[p]} Δ —`, na);
      }
    }
  }

  const title = `${g.fixture}${g.state === 'default' ? '' : `  ·  ${g.state}`}  ·  ${g.scheme}`;
  const dest = join(SHEETS, `${sheetName(g)}.png`);
  // One montage: renders on row 1, diff heat-maps on row 2 (aligned under each platform).
  // Every cell is normalised to the same HEIGHT so the columns line up row-for-row (devices
  // differ in native resolution, so widths vary — height alignment is what makes a like-for-
  // like read possible). A flat matte frame delineates each column; the title names the
  // fixture/scheme; per-cell labels name the platform.
  magick([
    'montage', ...renderInputs, ...(diffInputs || []),
    '-tile', diffInputs ? '3x2' : '3x1',
    '-geometry', `${COL_W}x${HEIGHT}+16+20`,
    '-background', BG, '-fill', INK, ...fontArgs, '-pointsize', '26',
    '-frame', '4', '-mattecolor', '#33333e',   // clear per-column frame
    '-title', title,
    '-strip', '-define', 'png:compression-level=9', '-define', 'png:compression-filter=5',
    dest,
  ]);
  return { metrics, ref };
}

function galleryHtml(sheets) {
  // Worst divergence first — the whole point is to see what lags, at a glance.
  const ordered = [...sheets].sort((a, b) => (b.maxPct ?? -1) - (a.maxPct ?? -1)
    || a.fixture.localeCompare(b.fixture) || a.state.localeCompare(b.state));
  const badge = (s) => {
    const entries = Object.entries(s.metrics || {});
    if (!entries.length) return s.ref === null && (s.maxPct ?? -1) < 0
      ? '<span class="dim">1 platform · no diff</span>' : '';
    return entries.map(([p, pct]) => {
      const cls = pct < 1 ? 'ok' : pct < 8 ? 'warn' : 'bad';
      return `<span class="delta ${cls}">${p} Δ ${pct.toFixed(1)}%</span>`;
    }).join(' ');
  };
  const rows = ordered.map((s) => `
    <figure>
      <figcaption>${s.fixture}${s.state === 'default' ? '' : ` · <b>${s.state}</b>`} · ${s.scheme}
        ${s.ref ? `<span class="dim">vs ${s.ref}</span>` : ''} ${badge(s)}</figcaption>
      <img loading="lazy" src="${s.name}.png">
    </figure>`).join('\n');
  const mech = sheets.filter((s) => s.state !== 'default').length;
  const diffed = sheets.filter((s) => Object.keys(s.metrics || {}).length).length;
  return `<!doctype html><meta charset=utf8><meta name=viewport content="width=device-width,initial-scale=1">
  <title>SDUI glued snapshots</title>
  <style>
    body{font:14px/1.4 system-ui,sans-serif;margin:0;background:#0f0f12;color:#e8e8ea}
    header{position:sticky;top:0;background:#0f0f12ee;backdrop-filter:blur(8px);padding:16px 24px;border-bottom:1px solid #26262b}
    h1{margin:0 0 4px;font-size:18px}.sub{opacity:.6;font-size:13px}
    main{padding:16px 24px 64px;display:grid;gap:28px}
    figure{margin:0}figcaption{font-size:12px;opacity:.75;margin-bottom:6px;display:flex;gap:8px;align-items:center;flex-wrap:wrap}
    img{max-width:100%;display:block;border:1px solid #26262b;border-radius:8px}
    .dim{opacity:.5}
    .delta{font-size:11px;font-weight:600;padding:2px 8px;border-radius:999px}
    .delta.ok{background:#064e3b;color:#6ee7b7}.delta.warn{background:#4a3a06;color:#fcd34d}.delta.bad{background:#4c0519;color:#fda4af}
  </style>
  <header><h1>SDUI glued snapshots — iOS │ Android │ Aurora + pixel diff</h1>
  <div class="sub">${sheets.length} sheets · ${mech} mechanic states · ${diffed} with a cross-platform diff · sorted by worst divergence · row 1 renders, row 2 = Δ vs reference (fuzz ${FUZZ})</div></header>
  <main>${rows}</main>`;
}

if (!haveMagick()) {
  console.error('sheet.mjs needs ImageMagick — `brew install imagemagick` (provides `magick`).');
  process.exit(2);
}
if (!existsSync(SHEETS)) mkdirSync(SHEETS, { recursive: true });
const tmp = join(SHEETS, '_tmp');
if (!existsSync(tmp)) mkdirSync(tmp, { recursive: true });

const gs = groups();
const built = [];
for (const g of gs) {
  const { metrics, ref } = buildSheet(g, tmp);
  const maxPct = Object.values(metrics).length ? Math.max(...Object.values(metrics)) : -1;
  built.push({ ...g, name: sheetName(g), metrics, ref, maxPct });
}
writeFileSync(join(SHEETS, 'index.html'), galleryHtml(built));
console.log(`glued ${built.length} sheet(s) → ${SHEETS}`);
if (!built.length) console.log('  (no PNGs in __out__ yet — capture a platform leg or seed with collect.mjs)');

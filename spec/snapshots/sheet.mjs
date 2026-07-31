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
const SHEETS = join(OUT, '_sheets');
const PLATFORMS = ['ios', 'android', 'aurora'];
const LABELS = { ios: 'iOS', android: 'Android', aurora: 'Aurora' };
const INK = '#e8e8ea';
const BG = '#0f0f12';
const PANEL = '#1a1a20';

const arg = (name, dflt) => {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : dflt;
};
const HEIGHT = Number(arg('--height', '1280')); // column height sheets are normalised to
const COL_W = Math.round(HEIGHT * (390 / 844));  // phone aspect → a sensible column width

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
  const inputs = [];
  for (const p of PLATFORMS) {
    let src = g.cells[p];
    if (!src) { src = join(tmpDir, `_ph.${p}.png`); placeholder(p, src); }
    inputs.push('-label', LABELS[p], src);
  }
  const title = `${g.fixture}${g.state === 'default' ? '' : `  ·  ${g.state}`}  ·  ${g.scheme}`;
  const dest = join(SHEETS, `${sheetName(g)}.png`);
  // One montage call: three tiles, fixed height so columns align for a fair comparison,
  // per-tile platform labels, a title strip naming the fixture/mechanic/scheme.
  magick([
    'montage', ...inputs,
    '-tile', '3x1', '-geometry', `${COL_W}x${HEIGHT}+10+10`,
    '-background', BG, '-fill', INK, ...fontArgs, '-pointsize', '22',
    '-title', title,
    dest,
  ]);
  return dest;
}

function galleryHtml(sheets) {
  const rows = sheets.map((s) => `
    <figure>
      <figcaption>${s.fixture}${s.state === 'default' ? '' : ` · <b>${s.state}</b>`} · ${s.scheme}</figcaption>
      <img loading="lazy" src="${s.name}.png">
    </figure>`).join('\n');
  const mech = sheets.filter((s) => s.state !== 'default').length;
  return `<!doctype html><meta charset=utf8><meta name=viewport content="width=device-width,initial-scale=1">
  <title>SDUI glued snapshots</title>
  <style>
    body{font:14px/1.4 system-ui,sans-serif;margin:0;background:#0f0f12;color:#e8e8ea}
    header{position:sticky;top:0;background:#0f0f12ee;backdrop-filter:blur(8px);padding:16px 24px;border-bottom:1px solid #26262b}
    h1{margin:0 0 4px;font-size:18px}.sub{opacity:.6;font-size:13px}
    main{padding:16px 24px 64px;display:grid;gap:28px}
    figure{margin:0}figcaption{font-size:12px;opacity:.7;margin-bottom:6px}
    img{max-width:100%;display:block;border:1px solid #26262b;border-radius:8px}
  </style>
  <header><h1>SDUI glued snapshots — iOS │ Android │ Aurora</h1>
  <div class="sub">${sheets.length} sheets · ${mech} mechanic states · each row is one fixture glued across platforms</div></header>
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
for (const g of gs) { buildSheet(g, tmp); built.push({ ...g, name: sheetName(g) }); }
writeFileSync(join(SHEETS, 'index.html'), galleryHtml(built));
console.log(`glued ${built.length} sheet(s) → ${SHEETS}`);
if (!built.length) console.log('  (no PNGs in __out__ yet — capture a platform leg or seed with collect.mjs)');

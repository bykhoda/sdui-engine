#!/usr/bin/env node
// Zero-dep visual contact-sheet generator. Groups per-platform PNGs by fixture and
// emits a static HTML gallery (iOS | Android | Aurora, golden vs current) for eyeballing
// cross-platform divergence at a glance. Pass/fail lives in the native snapshot tools
// (Paparazzi verify, swift-snapshot precision); this is the human review surface.
// See docs/blueprint/20-visual-snapshot-harness.md.
//
// Input (naming convention):
//   __out__/{fixture}.{platform}.{scheme}.png        # current run (any platform writes here)
//   __golden__/{platform}/{fixture}.{scheme}.png     # committed goldens
//
// Usage: node spec/snapshots/stitch.mjs
//        node spec/snapshots/stitch.mjs --open   # print the index path to open

import { readdirSync, readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, '__out__');
const GOLD = join(HERE, '__golden__');
const PLATFORMS = ['ios', 'android', 'aurora'];

const manifest = existsSync(join(HERE, 'manifest.json'))
  ? JSON.parse(readFileSync(join(HERE, 'manifest.json'), 'utf8'))
  : { screens: [], components: [] };
const kindOf = (() => {
  const screens = new Set(manifest.screens.map((s) => s.id));
  const comps = new Set(manifest.components.map((c) => c.id));
  return (fixture) => (comps.has(fixture) ? 'component' : screens.has(fixture) ? 'screen' : 'other');
})();

// Read PNG width/height from the IHDR chunk without decoding pixels (zero-dep).
function pngSize(path) {
  try {
    const b = readFileSync(path);
    if (b.length < 24 || b.readUInt32BE(0) !== 0x89504e47) return null; // PNG signature
    return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
  } catch { return null; }
}

// Group current-run PNGs named {fixture}.{platform}.{scheme}.png into review rows.
function index() {
  const rows = new Map(); // `${fixture}@${state}::${scheme}` → { fixture, state, scheme, kind, cells }
  // {fixture}[@{state}].{platform}.{scheme}.png — @state is an optional mechanic end-state.
  const re = /^(.+?)(?:@([a-z0-9-]+))?\.(ios|android|aurora)\.(light|dark)\.png$/;
  for (const f of existsSync(OUT) ? readdirSync(OUT) : []) {
    const m = re.exec(f);
    if (!m) continue;
    const [, fixture, state = 'default', platform, scheme] = m;
    const stem = state === 'default' ? fixture : `${fixture}@${state}`;
    const key = `${stem}::${scheme}`;
    const row = rows.get(key) ?? { fixture, state, scheme, kind: kindOf(fixture), cells: {} };
    const cur = join(OUT, f);
    const gold = join(GOLD, platform, `${stem}.${scheme}.png`);
    row.cells[platform] = {
      cur, gold: existsSync(gold) ? gold : null,
      size: pngSize(cur), goldSize: existsSync(gold) ? pngSize(gold) : null,
    };
    rows.set(key, row);
  }
  return [...rows.values()].sort(
    (a, b) => a.kind.localeCompare(b.kind) || a.fixture.localeCompare(b.fixture)
      || a.state.localeCompare(b.state) || a.scheme.localeCompare(b.scheme),
  );
}

const rel = (p) => (p ? p.replace(HERE + '/', '') : null);
const img = (p) => (p ? `<img loading="lazy" src="${rel(p)}">` : `<div class="missing">— none —</div>`);

function cell(platform, c) {
  if (!c) return `<td class="gap" data-drift="0"><div class="missing">not rendered</div></td>`;
  const drift = !!(c.gold && c.goldSize && c.size && (c.goldSize.w !== c.size.w || c.goldSize.h !== c.size.h));
  const noGold = !c.gold;
  return `<td class="${drift ? 'drift' : ''}" data-drift="${drift ? 1 : 0}">
    <figure><figcaption>golden</figcaption>${img(c.gold)}</figure>
    <figure><figcaption>current${drift ? ' ⚠ size drift' : noGold ? ' • new' : ''}</figcaption>${img(c.cur)}</figure>
  </td>`;
}

function render(rows) {
  const counts = {
    screen: new Set(rows.filter((r) => r.kind === 'screen').map((r) => r.fixture)).size,
    component: new Set(rows.filter((r) => r.kind === 'component').map((r) => r.fixture)).size,
    mech: rows.filter((r) => r.state !== 'default').length,
    drift: rows.filter((r) => PLATFORMS.some((p) => {
      const c = r.cells[p];
      return c && c.gold && c.goldSize && c.size && (c.goldSize.w !== c.size.w || c.goldSize.h !== c.size.h);
    })).length,
  };
  const body = rows.map((r) => `
    <section class="row" data-kind="${r.kind}" data-fixture="${r.fixture}" data-mech="${r.state !== 'default' ? 1 : 0}">
      <h2>${r.fixture}${r.state !== 'default' ? ` <span class="mech">${r.state}</span>` : ''} <span class="scheme">${r.scheme}</span> <span class="kind">${r.kind}</span></h2>
      <table><thead><tr>${PLATFORMS.map((p) => `<th>${p}</th>`).join('')}</tr></thead>
      <tbody><tr>${PLATFORMS.map((p) => cell(p, r.cells[p])).join('')}</tr></tbody></table>
    </section>`).join('\n');

  return `<!doctype html><meta charset=utf8><meta name=viewport content="width=device-width,initial-scale=1">
  <title>SDUI visual snapshots</title>
  <style>
    :root{color-scheme:dark light}
    body{font:14px/1.4 system-ui,sans-serif;margin:0;background:#0f0f12;color:#e8e8ea}
    header{position:sticky;top:0;background:#0f0f12ee;backdrop-filter:blur(8px);padding:16px 24px;border-bottom:1px solid #26262b;z-index:2}
    h1{margin:0 0 8px;font-size:18px} .sub{opacity:.6;font-size:13px}
    .filters{margin-top:10px;display:flex;gap:8px;flex-wrap:wrap}
    .filters button{font:inherit;padding:5px 12px;border-radius:999px;border:1px solid #333;background:#1a1a20;color:#ddd;cursor:pointer}
    .filters button.on{background:#5b5bd6;border-color:#5b5bd6;color:#fff}
    main{padding:8px 24px 64px}
    table{border-collapse:collapse;width:100%;table-layout:fixed} td,th{border:1px solid #2a2a30;padding:8px;vertical-align:top;width:33.33%}
    th{font-size:12px;text-transform:uppercase;letter-spacing:.06em;opacity:.7;text-align:left}
    figure{margin:0 0 8px} figcaption{font-size:11px;opacity:.55;margin-bottom:4px}
    img{max-width:100%;display:block;border:1px solid #222;border-radius:6px;background:#000}
    td.drift{outline:2px solid #e5484d;outline-offset:-2px} td.gap{opacity:.45}
    .missing{padding:28px 8px;text-align:center;opacity:.4;border:1px dashed #333;border-radius:6px}
    .scheme{font-size:12px;opacity:.5;font-weight:400} .kind{font-size:11px;opacity:.4;font-weight:400;float:right}
    .mech{font-size:11px;font-weight:600;color:#fff;background:#8b5cf6;padding:2px 8px;border-radius:999px;vertical-align:middle}
    h2{margin:28px 0 8px;font-size:15px} section.hide{display:none}
  </style>
  <header>
    <h1>SDUI visual snapshots</h1>
    <div class="sub">${rows.length} cells · ${counts.screen} screens · ${counts.component} components · ${counts.mech} mechanic states · ${counts.drift} with size-drift · columns: iOS │ Android │ Aurora, golden vs current</div>
    <div class="filters">
      <button class="on" data-f="all">all</button>
      <button data-f="screen">screens</button>
      <button data-f="component">components</button>
      <button data-f="mech">mechanics</button>
      <button data-f="drift">drift only</button>
    </div>
  </header>
  <main>${body}</main>
  <script>
    const btns=[...document.querySelectorAll('.filters button')], secs=[...document.querySelectorAll('section.row')];
    btns.forEach(b=>b.onclick=()=>{btns.forEach(x=>x.classList.toggle('on',x===b));const f=b.dataset.f;
      secs.forEach(s=>{const drift=[...s.querySelectorAll('td')].some(t=>t.dataset.drift==='1');
        const ok=f==='all'||(f==='drift'?drift:f==='mech'?s.dataset.mech==='1':s.dataset.kind===f);
        s.classList.toggle('hide', !ok);});});
  </script>`;
}

if (!existsSync(OUT)) mkdirSync(OUT, { recursive: true });
const rows = index();
writeFileSync(join(OUT, 'index.html'), render(rows));
console.log(`stitched ${rows.length} fixture×scheme rows → ${join(OUT, 'index.html')}`);
if (!rows.length) console.log('  (no PNGs in __out__ yet — run a platform snapshot leg, or seed with node collect.mjs)');

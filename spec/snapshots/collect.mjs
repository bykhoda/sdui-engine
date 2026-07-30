#!/usr/bin/env node
// Moves per-platform snapshot PNGs into the shared review tree so stitch.mjs can build
// the cross-platform gallery, and promotes accepted images to goldens on --record.
// Goldens are REVIEWED, never blindly regenerated (doc-09 rule: "a diff to a golden is
// a design decision"). See docs/blueprint/20-visual-snapshot-harness.md.
//
// Ingest a platform's freshly-rendered PNGs into __out__ (named {fixture}.{platform}.{scheme}.png):
//   node spec/snapshots/collect.mjs --platform android --from <dir> [--scheme light]
//     <dir> holds PNGs named {fixture}.png or {fixture}.{scheme}.png.
//
// Promote the current run to goldens (after human review of the gallery):
//   node spec/snapshots/collect.mjs --record [--platform android]

import { readdirSync, readFileSync, writeFileSync, existsSync, mkdirSync, copyFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, basename } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, '__out__');
const GOLD = join(HERE, '__golden__');
const PLATFORMS = ['ios', 'android', 'aurora'];

function arg(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}
const has = (name) => process.argv.includes(name);
const ensure = (d) => { if (!existsSync(d)) mkdirSync(d, { recursive: true }); };

if (has('--record')) {
  // Promote __out__/{fixture}.{platform}.{scheme}.png → __golden__/{platform}/{fixture}.{scheme}.png
  const only = arg('--platform');
  let n = 0;
  for (const f of existsSync(OUT) ? readdirSync(OUT) : []) {
    const m = /^(.+)\.(ios|android|aurora)\.(light|dark)\.png$/.exec(f);
    if (!m) continue;
    const [, fixture, platform, scheme] = m;
    if (only && platform !== only) continue;
    ensure(join(GOLD, platform));
    copyFileSync(join(OUT, f), join(GOLD, platform, `${fixture}.${scheme}.png`));
    n++;
  }
  console.log(`recorded ${n} golden(s)${only ? ` for ${only}` : ''} → ${GOLD}`);
  process.exit(0);
}

// Ingest mode
const platform = arg('--platform');
const from = arg('--from');
const scheme = arg('--scheme') || 'light';
if (!platform || !PLATFORMS.includes(platform) || !from) {
  console.error('usage: collect.mjs --platform <ios|android|aurora> --from <dir> [--scheme light|dark]');
  console.error('   or: collect.mjs --record [--platform <p>]');
  process.exit(2);
}
if (!existsSync(from)) { console.error(`--from dir not found: ${from}`); process.exit(2); }
ensure(OUT);

let n = 0;
for (const f of readdirSync(from).filter((f) => f.toLowerCase().endsWith('.png'))) {
  // Accept {fixture}.png or {fixture}.{scheme}.png; the embedded scheme wins.
  const stem = basename(f, '.png');
  const m = /^(.+)\.(light|dark)$/.exec(stem);
  const fixture = (m ? m[1] : stem).replace(/\.(ios|android|aurora)$/, '');
  const sch = m ? m[2] : scheme;
  copyFileSync(join(from, f), join(OUT, `${fixture}.${platform}.${sch}.png`));
  n++;
}
console.log(`ingested ${n} PNG(s) for ${platform} (scheme default ${scheme}) → ${OUT}`);

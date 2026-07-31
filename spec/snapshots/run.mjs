#!/usr/bin/env node
// One command → the full cross-platform gallery. Runs each platform's AUTOMATED snapshot
// leg (never a human clicking a device): the legs render every fixture from manifest.json
// through the real renderer and drive each mechanic, writing PNGs straight into __out__.
// Then this builds the HTML gallery (stitch) and the glued iOS│Android│Aurora sheets.
//
// A leg whose toolchain is missing is SKIPPED with a note — the gallery still builds from
// whatever legs ran, and the missing platform shows as a visible gap (never silent).
//
// Usage:
//   node spec/snapshots/run.mjs                 # every available leg, then gallery + sheets
//   node spec/snapshots/run.mjs --android       # only the named leg(s)
//   node spec/snapshots/run.mjs --gallery-only  # skip legs, just re-stitch what's in __out__
//   node spec/snapshots/run.mjs --schemes light # restrict schemes (default: light,dark)

import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { execFileSync } from 'node:child_process';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..');
const has = (f) => process.argv.includes(f);
const arg = (f, d) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : d; };
const only = ['android', 'ios', 'aurora'].filter((p) => has(`--${p}`));
const want = (p) => only.length === 0 || only.includes(p);
const schemes = arg('--schemes', 'light,dark');

const run = (cmd, args, opts = {}) => {
  console.log(`\n$ ${cmd} ${args.join(' ')}`);
  execFileSync(cmd, args, { stdio: 'inherit', cwd: ROOT, ...opts });
};
const step = (label, fn) => {
  try { fn(); return true; }
  catch (e) { console.warn(`  ⚠ ${label} skipped: ${e.shortMessage || e.message}`); return false; }
};

// Locate a runnable Gradle: the wrapper if present, else a cached distribution.
function gradle() {
  const wrapper = join(ROOT, 'android', 'gradlew');
  if (existsSync(wrapper)) return wrapper;
  const dists = join(process.env.HOME || '', '.gradle', 'wrapper', 'dists');
  if (existsSync(dists)) {
    // find any gradle-*/bin/gradle under the dists cache
    try {
      const found = execFileSync('find', [dists, '-name', 'gradle', '-type', 'f', '-path', '*/bin/gradle'], { encoding: 'utf8' })
        .split('\n').filter(Boolean)[0];
      if (found) return found;
    } catch { /* fall through */ }
  }
  throw new Error('no Gradle wrapper or cached distribution found');
}

if (!has('--gallery-only')) {
  // ── Android leg — Roborazzi renders every fixture + mechanic on the JVM (no emulator).
  if (want('android')) {
    step('android (Roborazzi)', () => {
      const g = gradle();
      run(g, ['-p', join(ROOT, 'android'), ':snapshots:recordRoborazziDebug',
        `-Psdui.snapshot.schemes=${schemes}`, '--console=plain']);
    });
  }

  // ── iOS leg — swift-snapshot / ImageRenderer renders every fixture + mechanic.
  if (want('ios')) {
    step('ios (swift-snapshot)', () => {
      run('bash', [join(HERE, 'capture-ios.sh'), schemes]);
    });
  }

  // ── Aurora leg — offscreen QML render (renderer not built yet → leg is a no-op stub).
  if (want('aurora')) {
    step('aurora (offscreen QML)', () => {
      const sh = join(HERE, 'capture-aurora.sh');
      if (!existsSync(sh)) throw new Error('Aurora renderer not built yet');
      run('bash', [sh, schemes]);
    });
  }
}

// ── Always (re)build the review surfaces from whatever landed in __out__.
run('node', [join(HERE, 'stitch.mjs')]);
run('node', [join(HERE, 'sheet.mjs')]);
console.log('\n✓ gallery:  spec/snapshots/__out__/index.html');
console.log('✓ glued sheets: spec/snapshots/__out__/_sheets/index.html');

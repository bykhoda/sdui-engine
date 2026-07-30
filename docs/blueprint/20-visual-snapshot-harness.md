# 20 — Visual snapshot harness: seeing all three renderers side-by-side

> **Owner's ask (verbatim):** «нам нужен какой-то механизм снапов, на котором будут
> видны наши экраны (iOS + Android + Aurora) возможно склеенные и мы будем потом
> гонять тесты. Нужно также с компонентами. чтоб когда мы гоняли было всё видно —
> это очень поможет ничего не ломать при тестировании.»

This is the **visual sibling** of the behavioural conformance harness in
[09-conformance-fixtures.md](09-conformance-fixtures.md). That doc makes *contract
logic* (validation, bindings, conditions, effects) provably identical across
platforms via `spec/conformance/check.mjs` + native test legs. It explicitly leaves
**Level B — render/layout conformance** staged ("pixels differ by device, so we
DON'T assert pixels… reference screenshots are kept per platform for human review").

This doc specifies exactly that missing Level-B leg: render **every shared screen and
every component** on iOS + Android (+ Aurora later), capture a PNG per platform,
**stitch them side-by-side per fixture** so divergence is obvious at a glance, and run
it as a repeatable, CI-gated suite so a change that breaks one renderer turns red
before it ships.

---

## 0. What we already have to build on

| Asset | Path | Reuse |
|---|---|---|
| Shared screen corpus (40 screens) | `ios/Sources/SDUIPlayground/Content/screens/*.json` | The screens to snapshot. Already synced to Android assets via the `syncPlaygroundContent` Gradle `Copy` task (`android/app/build.gradle.kts`) and read by Aurora. **One source of truth.** |
| Component vocabulary (30) | `spec/tools/validate.mjs` → `KNOWN_COMPONENTS` | Drives the per-component snapshot set. |
| Action vocabulary (24) | `validate.mjs` → `KNOWN_ACTIONS` | Interaction-state snapshots (later phase). |
| Whole-screen fixtures | `spec/conformance/fixtures/screen-*/` | Already carry `screen.json` + `tokens.json`; extend with a `render` block. |
| iOS renderer entry | `SDUIScreenView` / `SDUIScreenModel(screen, tokens, env, params, loader, delegate, registry)` | The real view we snapshot — no test-only rendering path. |
| Android renderer entry | `SduiScreen(document, tokens, env, loader, registry, delegate)` composable | The real composable we snapshot. |
| Aurora renderer entry | `aurora/qml/sdui/SduiRenderer.qml` | The real QML item we snapshot. |
| Parity matrix | `spec/tools/parity.mjs` → `PARITY.md` | Tells the harness which `{fixture,platform}` cells are *expected* to differ (unimplemented components degrade, they don't crash — Android 18/30, Aurora needs re-measuring). The gallery colour-codes these as "known gap", not "regression". |
| Default tokens | `spec/schema/tokens.example.json` | Binding context for fixtures without their own `tokens.json`. |

**Golden rule inherited from doc 09:** the snapshot suite renders the *real* renderer
from the *shared* JSON. No bespoke test screens, no per-platform forks of the content.
Same manifest → same set on every platform → any difference is a real difference.

---

## 1. Per-platform tool recommendation

Requirements every candidate is judged against: **(a)** renders our *actual* renderer
from a shared JSON fixture, **(b)** deterministic (byte-stable goldens), **(c)** runs
headless in CI, **(d)** first-class record-vs-verify with a diff threshold.

### 1.1 Android → **Paparazzi** (primary) + Roborazzi (interaction fallback)

| Tool | Repo | ★ | Engine | Verdict |
|---|---|---|---|---|
| **Paparazzi** | [cashapp/paparazzi](https://github.com/cashapp/paparazzi) | **~2.6k** | Pure JVM `layoutlib` render — **no emulator** | ✅ **Recommended** |
| Roborazzi | [takahirom/roborazzi](https://github.com/takahirom/roborazzi) | ~0.93k | Robolectric (JVM) | Fallback — needed for *post-interaction* frames |
| Shot | [pedrovgs/Shot](https://github.com/pedrovgs/Shot) | ~1.2k | Instrumented (needs device/emulator) | ✗ needs a device; slower, flakier |
| Compose Preview Screenshot Testing | Google/AndroidX (`screenshot` plugin) | (official, experimental) | JVM (layoutlib, same as Paparazzi) | Watch it — still alpha, `@Preview`-oriented; revisit when stable |

**Why Paparazzi.** It renders real Jetpack Compose on the JVM without a device or
emulator ("Render your Android screens without a physical device or emulator") — the
fastest, most deterministic option, and it drops straight into our existing
`android/sdui` unit-test source set (`src/test/java`, JVM 17) alongside
`ConformanceTest.kt`. We call our **real** `SduiScreen(...)` composable inside a
`@get:Rule val paparazzi = Paparazzi(deviceConfig = …)` and `paparazzi.snapshot { … }`.
Record/verify is built in: `./gradlew recordPaparazziDebug` writes goldens under
`src/test/snapshots/images/`; `./gradlew verifyPaparazziDebug` re-renders and fails on
drift, emitting a delta PNG. Threshold via `maxPercentDifference`.

**Two caveats to design around:**
- **Async images.** `image` uses Coil; layoutlib has no network. Inject a deterministic
  fake `ImageLoader`/`AsyncImagePreviewHandler` that returns a solid placeholder (this
  is the Paparazzi+Coil/Glide issue class, e.g. cashapp/paparazzi#1396). Snapshots must
  never depend on the network.
- **Post-interaction frames.** Paparazzi captures a *single laid-out frame*; it can't
  "swipe then snapshot". Our signature interactions (swipe-to-reveal, collapsing
  scroll) need the revealed/collapsed state. Two options: (a) drive the renderer into
  that state via seed `state.json` (preferred — declarative, shared with iOS/Aurora),
  or (b) use **Roborazzi** for the handful of gesture-result frames, since it can
  snapshot *after* a UI action. Keep Roborazzi as a scoped fallback, not the default.

### 1.2 iOS → **pointfreeco/swift-snapshot-testing** (primary) + `ImageRenderer` (zero-dep offscreen fallback)

| Tool | Repo | ★ | Engine | Verdict |
|---|---|---|---|---|
| **swift-snapshot-testing** | [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | **~4.1k** | Renders a SwiftUI/UIKit view on the iOS Simulator | ✅ **Recommended gate** |
| SwiftUI `ImageRenderer` | Apple, iOS 16+ | (first-party) | `view → UIImage/CGImage` offscreen | ✅ **Zero-dep companion** for emitting the PNG |
| `xcresult` attachment scraping | Xcode | — | screenshots from UI tests | ✗ heavy, flaky, needs full UI-test host |

**Why swift-snapshot-testing.** It is the de-facto standard (~4.1k★), with the same
mental model as Jest/Paparazzi: first run in **record** mode writes the reference PNG,
later runs re-render and diff, with image diffs surfaced as XCTest attachments and a
tunable `precision` / `perceptualPrecision` threshold. It renders **device-agnostic**
snapshots (a named device + trait collection) from a single simulator, which is exactly
how we pin a deterministic viewport. We add a new **`SDUISnapshotTests`** iOS test
target to `ios/Package.swift` and run it via
`xcodebuild test -scheme SDUI -destination 'platform=iOS Simulator,name=iPhone 15'`
(the package is SwiftPM-only today — no `.xcodeproj` — but `xcodebuild` builds SwiftPM
test targets for the simulator, and this is the first iOS *screenshotting* leg, so it's
net-new setup either way).

**Determinism knobs (must-set):** pin one simulator device + OS, disable animations,
fix the locale/timezone and `Dynamic Type` size, and force light/dark explicitly per
entry rather than inheriting the host. Snapshots of async/remote images must use a
stubbed image provider (same principle as Android).

**The `ImageRenderer` companion.** For a *zero-dependency* offscreen path — and to
future-proof against needing a simulator at all — `ImageRenderer` (iOS 16+) turns any
SwiftUI view into a `UIImage`/`CGImage` directly. Recommendation: swift-snapshot-testing
owns record/verify + thresholding (mature diffing we don't want to reinvent), and its
snapshot strategy can be backed by `ImageRenderer` for the actual bitmap. Caveat noted
across the ImageRenderer write-ups: a view handed to `ImageRenderer` is detached from
the layout/environment tree, so we must inject tokens/env/size **explicitly** (which
`SDUIScreenModel` already takes as init params) and pin an explicit frame — otherwise
scroll content and safe-area insets render inconsistently.

### 1.3 Aurora (later) → offscreen QML render via `QQuickRenderControl` / `grabToImage`

Aurora OS is Qt/QML/Silica. Qt already ships headless capture:
[`QQuickRenderControl`](https://doc.qt.io/qt-6/qquickrendercontrol.html) "provides a
mechanism for rendering the Qt Quick scenegraph onto an offscreen render target… the
`QQuickWindow` does not have to be shown or even created at all" — hardware-accelerated,
no visible window, ideal for CI. For a per-item capture, QML's `Item.grabToImage()`
grabs any item (our `SduiRenderer` root) into an in-memory image. A small Qt Test /
`qml`-runner harness loads each manifest entry into `SduiRenderer.qml`, sizes it to the
manifest viewport, `grabToImage` → save `{fixture}.aurora.png`. No third-party dep.
Deferred to Phase 4; the manifest and gallery are built platform-count-agnostic so
Aurora slots in as a third column with zero changes to the stitcher.

---

## 2. The shared driver — `spec/snapshots/manifest.json`

One file lists the **entire** snapshot set; **every** platform's test iterates it, so
the three suites are guaranteed identical. It reuses the existing corpus rather than
inventing screens.

```jsonc
{
  "$comment": "Single source of truth for the visual snapshot suite. Every platform's snapshot test iterates THIS list so the set is identical everywhere. See docs/blueprint/20.",
  "version": 1,

  // Named viewports — pinned device metrics so goldens are byte-stable.
  "viewports": {
    "phone":       { "width": 390, "height": 844, "density": 3, "label": "iPhone-ish 390pt" },
    "phone-small": { "width": 360, "height": 800, "density": 3, "label": "compact 360dp" }
  },

  // Colour schemes to capture. Each becomes its own golden + gallery cell.
  "schemes": ["light", "dark"],

  // Deterministic environment applied to every entry unless overridden.
  "env": { "locale": "ru_RU", "timezone": "Europe/Moscow", "reduceMotion": true, "textScale": 1.0 },

  // ── WHOLE SCREENS: reference the shared content screens by id ──────────────
  "screens": [
    { "id": "home",      "source": "content/screens/home.json",      "viewport": "phone" },
    { "id": "fitness",   "source": "content/screens/fitness.json",   "viewport": "phone" },
    { "id": "messenger", "source": "content/screens/messenger.json", "viewport": "phone" },
    { "id": "swipe",     "source": "content/screens/swipe.json",     "viewport": "phone",
      "state": { "state": { "revealedRow": "row-2" } },            // seed the revealed state
      "note": "signature interaction: swipe-to-reveal shown via seeded state" }
    // … all 40 from Content/screens, generated, not hand-listed (see §2.1)
  ],

  // ── COMPONENTS: one isolated 'component card' per KNOWN_COMPONENTS type ─────
  "components": [
    { "id": "button",   "source": "components/button.json",   "viewport": "phone" },
    { "id": "toggle",   "source": "components/toggle.json",   "viewport": "phone" },
    { "id": "chart",    "source": "components/chart.json",    "viewport": "phone" },
    { "id": "rings",    "source": "components/rings.json",    "viewport": "phone" }
    // … one per component in KNOWN_COMPONENTS (30)
  ]
}
```

**Entry contract (identical for screens & components):** `id` (unique, → filename),
`source` (path to the SDUI JSON, resolved relative to the shared `Content/` root that
each platform already mounts), optional `viewport`, optional `state` (seed
state/data/env/item — same shape `check.mjs` already loads), optional per-entry
`schemes` override.

### 2.1 Where the two lists come from (no hand-maintenance drift)

- **Screens** = the 40 files in `Content/screens/` — enumerated by a generator, not
  typed by hand, so adding a screen adds a snapshot automatically.
- **Components** = one tiny wrapper screen per `KNOWN_COMPONENTS` type under
  `spec/snapshots/components/<type>.json`: a `vstack` "card" that instantiates the
  component with representative props (light on props, heavy on covering *states* — a
  `button` card shows primary/secondary/disabled/icon in one column). A
  `coverage`-style check (mirroring `spec/conformance/coverage.mjs --strict`, already
  at 100%) fails CI if any `KNOWN_COMPONENTS` type lacks a component card — so the
  visual set can never silently fall behind the vocabulary.

A generator `spec/snapshots/gen-manifest.mjs` emits `manifest.json` from
`Content/screens/*` + `KNOWN_COMPONENTS` + the component-card dir, keeping the manifest
mechanically in sync with reality. The manifest is committed (diff-reviewable) but
regenerated, never edited by hand.

---

## 3. The stitching mechanism — `spec/snapshots/stitch.mjs` (zero-dep HTML/SVG gallery)

Node ships no image libraries, and pulling in `sharp`/`canvas` violates the repo's
zero-dep-tooling norm (every tool in `spec/tools/` is dependency-free). So the stitcher
does **not** re-encode pixels — it emits a **static HTML gallery** that references the
per-platform PNGs by relative `<img src>` and lays them out side-by-side with CSS
grid. This is:

- **zero-dep** — pure string templating, same class as `parity.mjs`/`gen-reference.mjs`;
- **diff-friendly** — the output is text/HTML, reviewable in a PR, no binary churn;
- **instantly viewable** — opens in any browser, no build step;
- **platform-count-agnostic** — 2 columns today (iOS | Android), 3 when Aurora lands.

### Input contract

The stitcher consumes a flat directory of PNGs named by convention:

```
spec/snapshots/__out__/{fixture}.{platform}.{scheme}.png     # current run
spec/snapshots/__golden__/{platform}/{fixture}.{scheme}.png  # committed goldens
```

`{platform} ∈ {ios, android, aurora}`. Each platform's test writes its PNGs into
`__out__/` (or into its native golden dir on `--record`). The stitcher globs, groups
by `{fixture,scheme}`, and for each group renders one **row**: the golden and the
current side-by-side per platform, so a human sees iOS-vs-Android *and*
current-vs-golden in one strip.

### Output

- `spec/snapshots/__out__/index.html` — a grid **index**: one thumbnail strip per
  fixture, filterable (screens / components / has-drift), each linking to…
- `spec/snapshots/__out__/{fixture}.html` — a **contact sheet** for one fixture: full-res
  iOS | Android | (Aurora) columns × light/dark rows, golden vs current, and a "known
  gap" badge for cells the `PARITY.md` matrix says are unimplemented on that platform.

The stitcher stays a *review* aid; **pass/fail is owned by the native tools** (Paparazzi
`verify`, swift-snapshot `precision`). Optionally the stitcher reads each PNG's `IHDR`
chunk (first 24 bytes — a zero-dep 4-line parse, no decoding) to flag **dimension
mismatches** and to annotate whether a golden is missing for a given cell.

### `stitch.mjs` skeleton

```js
#!/usr/bin/env node
// Zero-dep visual contact-sheet generator. Groups per-platform PNGs by fixture and
// emits a static HTML gallery (iOS | Android | Aurora, golden vs current) for eyeballing
// cross-platform divergence. Pass/fail lives in the native snapshot tools; this is the
// human review surface. See docs/blueprint/20-visual-snapshot-harness.md.
//
// Usage: node spec/snapshots/stitch.mjs
//        node spec/snapshots/stitch.mjs --out __out__ --golden __golden__

import { readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, basename } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, '__out__');
const GOLD = join(HERE, '__golden__');
const PLATFORMS = ['ios', 'android', 'aurora'];

// Read PNG width/height from the IHDR chunk without decoding pixels (zero-dep).
function pngSize(path) {
  try {
    const b = readFileSync(path);
    // 8-byte signature, then a length+type, then IHDR: width@16, height@20 (big-endian).
    return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
  } catch { return null; }
}

// Discover fixtures from current-run PNGs named {fixture}.{platform}.{scheme}.png
function index() {
  const rows = new Map(); // key `${fixture}::${scheme}` → { fixture, scheme, cells:{platform:{cur,gold,size,drift}} }
  for (const f of existsSync(OUT) ? readdirSync(OUT) : []) {
    const m = /^(.+)\.(ios|android|aurora)\.(light|dark)\.png$/.exec(f);
    if (!m) continue;
    const [, fixture, platform, scheme] = m;
    const key = `${fixture}::${scheme}`;
    const row = rows.get(key) ?? { fixture, scheme, cells: {} };
    const cur = join(OUT, f);
    const gold = join(GOLD, platform, `${fixture}.${scheme}.png`);
    row.cells[platform] = {
      cur, gold: existsSync(gold) ? gold : null,
      size: pngSize(cur), goldSize: existsSync(gold) ? pngSize(gold) : null,
    };
    rows.set(key, row);
  }
  return [...rows.values()].sort((a, b) => a.fixture.localeCompare(b.fixture) || a.scheme.localeCompare(b.scheme));
}

const rel = (p) => p ? p.replace(HERE + '/', '') : null;
const img = (p) => p ? `<img loading="lazy" src="${rel(p)}">` : `<div class="missing">— no image —</div>`;

function cell(platform, c) {
  if (!c) return `<td class="gap"><div class="missing">not rendered</div></td>`;
  const drift = c.gold && c.goldSize && c.size &&
    (c.goldSize.w !== c.size.w || c.goldSize.h !== c.size.h);
  return `<td class="${drift ? 'drift' : ''}">
    <figure><figcaption>golden</figcaption>${img(c.gold)}</figure>
    <figure><figcaption>current${drift ? ' ⚠ size' : ''}</figcaption>${img(c.cur)}</figure>
  </td>`;
}

function render(rows) {
  const body = rows.map((r) => `
    <section id="${r.fixture}-${r.scheme}">
      <h2>${r.fixture} <span class="scheme">${r.scheme}</span></h2>
      <table><thead><tr>${PLATFORMS.map((p) => `<th>${p}</th>`).join('')}</tr></thead>
      <tbody><tr>${PLATFORMS.map((p) => cell(p, r.cells[p])).join('')}</tr></tbody></table>
    </section>`).join('\n');

  return `<!doctype html><meta charset=utf8><title>SDUI visual snapshots</title>
  <style>
    body{font:14px system-ui;margin:24px;background:#111;color:#eee}
    table{border-collapse:collapse;width:100%} td,th{border:1px solid #333;padding:8px;vertical-align:top;width:33%}
    figure{margin:0 0 8px} figcaption{font-size:11px;opacity:.6} img{max-width:100%;display:block;border:1px solid #222}
    td.drift{outline:2px solid #e5484d} td.gap{opacity:.4} .missing{padding:24px;text-align:center;opacity:.4}
    .scheme{font-size:12px;opacity:.5} h2{margin-top:32px}
  </style>
  <h1>SDUI visual snapshots — ${rows.length} cells</h1>${body}`;
}

const rows = index();
writeFileSync(join(OUT, 'index.html'), render(rows));
console.log(`stitched ${rows.length} fixture×scheme rows → ${join(OUT, 'index.html')}`);
```

(The skeleton is intentionally compact; the shipped version adds the per-fixture pages,
the screens/components/drift filter, and the `PARITY.md` "known gap" badge.)

---

## 4. The regression flow — record, verify, gate

Mirrors the proven record/verify pattern of both native tools:

| Step | Android (Paparazzi) | iOS (swift-snapshot-testing) |
|---|---|---|
| **Record goldens** | `./gradlew recordPaparazziDebug` writes PNGs to the module's snapshot dir | run the target with `record: true` (`withSnapshotTesting(record: .all)`), writes reference PNGs |
| **Verify (CI)** | `./gradlew verifyPaparazziDebug` re-renders, diffs, **fails on drift**, emits a delta PNG | default run re-renders, diffs, **fails on drift**, attaches the diff to the `.xcresult` |
| **Threshold** | `maxPercentDifference` on the Paparazzi rule | `precision` / `perceptualPrecision` on the strategy |

**Golden location.** Native tools keep their own golden dirs by default, but for the
*stitched cross-platform view* we also sync every accepted golden into one reviewable
tree:

```
spec/snapshots/__golden__/
  ios/{fixture}.{scheme}.png
  android/{fixture}.{scheme}.png
  aurora/{fixture}.{scheme}.png      # later
```

A thin `spec/snapshots/collect.mjs` copies each platform's freshly-verified PNGs into
`__out__/` (for the gallery) and, on `--record`, promotes them into `__golden__/`.
Goldens are **reviewed, never blindly regenerated** — exactly the doc-09 rule: "a diff
to a golden is a design decision." A PR that changes a golden shows the before/after in
the stitched gallery as a first-class review artifact.

**CI gate.**
1. `snapshot-android` job: JDK 21, `verifyPaparazziDebug` — no emulator, pure JVM.
2. `snapshot-ios` job: macOS runner, `xcodebuild test` of `SDUISnapshotTests` on a
   pinned simulator.
3. On failure, each job uploads its `__out__/` PNGs; a final `stitch` step runs
   `node spec/snapshots/stitch.mjs` and uploads `index.html` + delta PNGs as the review
   bundle. **Any platform red = PR red** — same gate philosophy as the Level-A
   conformance job. Adding a component without a component-card = red (coverage check).

**Threshold policy.** Start strict but not zero — a small `maxPercentDifference` /
`perceptualPrecision` absorbs sub-pixel AA noise while still catching real layout/colour
drift. Font rendering differs *between* platforms by design, so the cross-platform
comparison is **human-eyeball via the gallery**, never an automated iOS-vs-Android pixel
diff; the automated gate is always *platform-vs-its-own-golden*.

---

## 5. Concrete first implementation — file tree & phased plan

### Target file tree (new files only; everything else reused)

```
spec/snapshots/
  manifest.json                 # generated: screens (40) + components (30) × viewport × scheme
  gen-manifest.mjs              # emits manifest.json from Content/screens + KNOWN_COMPONENTS
  components/<type>.json        # 30 isolated component "cards" (one per KNOWN_COMPONENTS)
  coverage.mjs                  # --strict: every KNOWN_COMPONENTS type has a card (CI gate)
  stitch.mjs                    # zero-dep HTML gallery (§3)
  collect.mjs                   # sync/promote per-platform PNGs → __out__ / __golden__
  README.md
  __golden__/{ios,android,aurora}/…   # committed reference PNGs
  __out__/…                           # gitignored: current-run PNGs + index.html

android/sdui/src/test/java/dev/sdui/snapshot/
  SnapshotTest.kt               # reads manifest.json, Paparazzi.snapshot { SduiScreen(...) } per entry

ios/Tests/SDUISnapshotTests/
  SnapshotTests.swift           # reads manifest.json, assertSnapshot(of: SDUIScreenView(...)) per entry
  # + Package.swift: add .testTarget(name:"SDUISnapshotTests", dependencies:[… ,"SnapshotTesting"])

aurora/tests/snapshot/          # Phase 4: QQuickRenderControl/grabToImage runner over the manifest
```

Both native tests locate `spec/snapshots/manifest.json` by walking up from the source
file, **exactly** as `ConformanceTest.kt` and `ConformanceTests.swift` already locate
`spec/conformance/fixtures` — so the wiring pattern is copy-paste-proven.

### Phased build plan (small, incremental — ship value at each step)

- **Phase 0 — driver + gallery (JS only, no native yet).**
  Write `gen-manifest.mjs` (enumerate the 40 screens; stub the 30 component cards),
  `stitch.mjs`, `collect.mjs`, `coverage.mjs`, and the `README`. Feed the stitcher
  hand-placed placeholder PNGs to prove the gallery. *No devices needed — pure Node,
  lands day one.*

- **Phase 1 — Android leg (Paparazzi).** Add Paparazzi to `android/sdui` test deps;
  write `SnapshotTest.kt` iterating the manifest through the real `SduiScreen`
  composable with a stubbed Coil loader; `recordPaparazziDebug` the first goldens;
  `collect.mjs` → gallery. **This alone already guards Android from silent breakage** —
  the owner's core ask, on the fastest platform to stand up.

- **Phase 2 — iOS leg (swift-snapshot-testing).** Add the `SDUISnapshotTests` target +
  the dependency to `Package.swift`; `SnapshotTests.swift` iterating the manifest
  through the real `SDUIScreenView`; record goldens on a pinned simulator; `collect.mjs`
  now fills the **iOS | Android** side-by-side gallery — the first moment "видно всё"
  becomes literally true.

- **Phase 3 — CI gate + interaction states.** Wire `verifyPaparazziDebug` +
  `xcodebuild test` into CI with artifact upload of the stitched gallery. Add seeded
  interaction-state entries (swipe-revealed, collapsed header) via `state.json`; use
  Roborazzi only where a true post-gesture frame is unavoidable.

- **Phase 4 — Aurora leg.** `QQuickRenderControl`/`grabToImage` runner over the same
  manifest → `{fixture}.aurora.png`; the gallery's third column lights up with **zero**
  changes to `stitch.mjs`. Cross-check against `PARITY.md` so unimplemented Aurora
  components render as "known gap", not regression.

- **Phase 5 — tie to the composer.** Point the composer's preview at the same goldens so
  "the composer looks like the device" becomes a *tested* property (the open item from
  [doc 09 §7.5](09-conformance-fixtures.md) and [doc 08](08-composer-direct-manipulation.md)).

### Why this design fits the project's DNA

- **One manifest, three legs** = the same "shared corpus, N languages" model that made
  the Level-A conformance harness the project's #1 lever — now for pixels.
- **Zero-dep stitcher** honours the `spec/tools/` no-dependency norm and stays
  diff-reviewable.
- **Real renderers, shared JSON** — no test-only rendering path can drift from prod.
- **Degrade-not-crash respected** — the gallery reads `PARITY.md` so expected gaps read
  as gaps, keeping the signal clean while parity is still filling in.

---

## Sources

- Paparazzi — [github.com/cashapp/paparazzi](https://github.com/cashapp/paparazzi) (~2.6k★)
- Roborazzi — [github.com/takahirom/roborazzi](https://github.com/takahirom/roborazzi) (~0.93k★)
- Shot — [github.com/pedrovgs/Shot](https://github.com/pedrovgs/Shot) (~1.2k★)
- swift-snapshot-testing — [github.com/pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) (~4.1k★)
- SwiftUI `ImageRenderer` — [pointfreeco discussion #612](https://github.com/pointfreeco/swift-snapshot-testing/discussions/612), Apple iOS 16 API
- `QQuickRenderControl` — [doc.qt.io/qt-6/qquickrendercontrol.html](https://doc.qt.io/qt-6/qquickrendercontrol.html)
- Library comparison — [Comparing Snapshot testing libraries (Kulbaka, Medium)](https://medium.com/@natalia.kulbaka/comparing-snapshot-testing-libraries-paparazzi-roborazzi-compose-previews-screenshot-testing-b7c3b47f7f59)

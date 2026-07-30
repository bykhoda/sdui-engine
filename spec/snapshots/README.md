# Visual snapshot harness

The **visual** sibling of the behavioural conformance corpus (`spec/conformance/`,
doc 09). That harness proves contract *logic* is identical across platforms; this one
renders **every shared screen and component** on iOS + Android (+ Aurora later),
captures a PNG per platform, and **stitches them side-by-side** so any divergence is
obvious at a glance. Full design: [`docs/blueprint/20-visual-snapshot-harness.md`](../../docs/blueprint/20-visual-snapshot-harness.md).

**Golden rule (inherited from doc 09):** render the *real* renderer from the *shared*
JSON. No bespoke test screens, no per-platform content forks. Same manifest → same set
everywhere → any difference is a real difference.

## Layout

```
spec/snapshots/
  manifest.json        # GENERATED — the single source of truth every platform iterates
  gen-manifest.mjs     # emits manifest.json from Content/screens/* + KNOWN_COMPONENTS + components/
  components/<type>.json  # one isolated "card" per component type (states in one column)
  stitch.mjs           # zero-dep HTML gallery: iOS | Android | Aurora, golden vs current
  collect.mjs          # ingest a platform's PNGs → __out__ ; promote to goldens on --record
  __out__/             # current run's PNGs + index.html (git-ignored)
  __golden__/{ios,android,aurora}/{fixture}.{scheme}.png   # committed reference PNGs
```

PNG naming convention (how the three legs and the stitcher agree):

```
__out__/{fixture}.{platform}.{scheme}.png          # e.g. inbox.android.light.png
__golden__/{platform}/{fixture}.{scheme}.png
```

## Commands

```bash
# 1. Regenerate the manifest from the real corpus (never hand-edit it).
node spec/snapshots/gen-manifest.mjs           # --check fails in CI if stale

# 2. Ingest a platform's freshly-rendered PNGs into the review tree.
node spec/snapshots/collect.mjs --platform android --from <dir> [--scheme light]

# 3. Build the cross-platform gallery, then open it.
node spec/snapshots/stitch.mjs
open spec/snapshots/__out__/index.html

# 4. After reviewing the gallery, promote the current run to goldens.
node spec/snapshots/collect.mjs --record [--platform android]
```

The gallery is a **review aid** — pass/fail stays inside each native tool
(Paparazzi `verify`, swift-snapshot `precision`). A diff to a golden is a design
decision, reviewed in the gallery, never blindly regenerated.

## Status — phased build

- **Phase 0 — driver + gallery (JS only). ✅ DONE.** `gen-manifest.mjs` (40 screens +
  component cards), `stitch.mjs` (filterable iOS│Android│Aurora gallery with
  golden-vs-current and zero-decode IHDR size-drift flags), `collect.mjs`. Runs today;
  seed `__out__` with any platform's PNGs to see the gallery light up.
- **Phase 1 — Android leg (Paparazzi).** `SnapshotTest.kt` reads `manifest.json` and
  `Paparazzi.snapshot { SduiScreen(...) }` per entry; no emulator, byte-stable.
- **Phase 2 — iOS leg (swift-snapshot-testing / `ImageRenderer`).**
- **Phase 3 — component cards to 100%** (`gen-manifest.mjs` reports the gap each run,
  so the visual set can't silently fall behind `KNOWN_COMPONENTS`).
- **Phase 4 — Aurora leg** (offscreen QML), same manifest, 3rd gallery column.
- **Phase 5 — CI gate** + stitched gallery uploaded as the review artifact.

Component-card coverage and the list of cards still needed print on every
`gen-manifest.mjs` run.

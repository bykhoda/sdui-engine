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
# 0. ONE command: run every available leg, then build the gallery + glued sheets.
#    Legs render from the manifest automatically — no hand-capture. A leg whose
#    toolchain is missing is skipped; the missing platform shows as a visible gap.
node spec/snapshots/run.mjs                     # or --android / --ios / --gallery-only

# 1. Regenerate the manifest from the real corpus (never hand-edit it).
node spec/snapshots/gen-manifest.mjs            # --check fails in CI if stale
#    Screens + component cards + MECHANICS (swipe/menu/scrub/page/slide/expand) are
#    auto-derived by walking each contract — the set can't drift from what we can do.

# 2. (manual ingest, if running a leg by hand) pull a platform's PNGs into __out__.
node spec/snapshots/collect.mjs --platform android --from <dir> [--scheme light] [--state swipe]

# 3. Review surfaces: HTML gallery (golden vs current, drift + mechanics filters)…
node spec/snapshots/stitch.mjs && open spec/snapshots/__out__/index.html
#    …and the glued, shareable iOS│Android│Aurora sheets (one PNG per fixture/mechanic).
node spec/snapshots/sheet.mjs && open spec/snapshots/__out__/_sheets/index.html

# 4. After reviewing, promote the current run to goldens.
node spec/snapshots/collect.mjs --record [--platform android]
```

The gallery is a **review aid** — pass/fail stays inside each native tool
(Roborazzi `verify`, swift-snapshot `precision`). A diff to a golden is a design
decision, reviewed in the gallery, never blindly regenerated.

**PNG naming carries the mechanic dimension:** `{fixture}[@{state}].{platform}.{scheme}.png`
— no `@state` is the resting screen; `inbox@swipe`, `stocks@scrub`, `home@page` are
interaction end-states. All three tools understand it, backward-compatibly.

## Persistence — what's stored vs regenerated

Standard visual-snapshot layout: every re-run re-glues all platforms into the combined
gallery, but only the reviewed baseline is committed.

- **`__out__/`** — the current run's PNGs + glued sheets. **Gitignored, ephemeral**; a leg
  writes here and `stitch.mjs`/`sheet.mjs` rebuild the gallery from it each run.
- **`__golden__/{platform}/{fixture}[@state].{scheme}.png`** — the **committed** reference
  every future run diffs against. Promote a reviewed run with `collect.mjs --record`.
- Goldens are binaries that get re-recorded over time, so they're tracked with **Git LFS**
  (`.gitattributes`) — pointers in git, blobs in LFS — keeping history lean. A fresh clone
  needs `git lfs install`; `git lfs pull` fetches the images.

## Status — phased build

- **Phase 0 — driver + gallery (JS only). ✅ DONE.** `gen-manifest.mjs` (43 screens + 30
  component cards + **17 auto-derived mechanics**, 100% card coverage), `stitch.mjs`
  (filterable iOS│Android│Aurora gallery, golden-vs-current, size-drift + mechanics
  filters), `collect.mjs`, `sheet.mjs` (glued shareable sheets), `run.mjs` (one-command
  orchestrator). All run today with zero deps beyond Node + ImageMagick.
- **Phase 1 — Android leg (Roborazzi). ✅ WIRED** in `android/:snapshots` (test-only, no
  app bloat). `SnapshotTest.kt` reads `manifest.json`, renders every fixture through the
  real `SduiScreen` on the JVM (Robolectric, no emulator), and drives each mechanic.
  `<gradle> :snapshots:recordRoborazziDebug`. First run fetches Roborazzi/Robolectric from
  Maven — so it needs network (blocked in the CI sandbox this was authored in; runs in
  Android Studio / networked CI).
- **Phase 2 — iOS leg (swift-snapshot-testing / `ImageRenderer`).** Same manifest, writes
  `{fixture}[@state].ios.{scheme}.png`. `capture-ios.sh` hook is stubbed in `run.mjs`.
- **Phase 3 — mechanic targeting.** Per-node gestures via `Modifier.testTag(id)` in the
  renderer (today the leg applies each gesture at the screen level — enough for the
  single-purpose fixtures).
- **Phase 4 — Aurora leg** (offscreen QML), same manifest, 3rd column.
- **Phase 5 — CI gate** + glued sheets uploaded as the review artifact.

Component-card coverage, cards still needed, and mechanic count print on every
`gen-manifest.mjs` run.

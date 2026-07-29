# 05 · Roadmap to "ideal"

Sequenced so each milestone is verifiable and unblocks the next. iOS is the
reference; every renderer feature = schema field + validator rule + parity entry +
conformance fixture. Re-run `node spec/tools/parity.mjs > PARITY.md` per batch.

## Milestone 0 — make everything runnable/verifiable (foundation)
- [ ] **Aurora launches** — B1 (re-run `gen_qrc.sh`), B2 (QML deploy rule), decide
  B3 (desktop shim *or* Aurora-SDK CI). → [02](02-launch-aurora.md)
- [ ] **Composer edits real screens** — expose all app screens to `/compose`. → [03]
- [ ] **Conformance fixtures scaffold** — golden screens + expected layout facts,
  one runner per platform. This is what makes "identical everywhere" testable. → [04A]
- [ ] Decide `request`/`saveFile`: implement on all three or remove from schema.

## Milestone 1 — Android reaches iOS parity (the biggest gap)
Batches from [01](01-parity-android.md):
- [ ] Images (Coil) + press-feedback (#1, #5)
- [ ] Modifier surface: blur/pulse/rotation/animation/zoomable/accessibility/swipe/
  safe-area + presentWhen + material + maxWidth-fill + weighted size + real shadow
  (#2, #3, #9, #11, #12, #13)
- [ ] State correctness ($state normalize, slider bind) + action verbs (#6, #7, #8)
- [ ] Layout defaults + flexible spacer + lazy scroll-safe grid (#14, #16, #17)
- [ ] Rich components: list feature-set, smooth chart, disclosure card, textfield
  (#15, #18, #19, #22)
- [ ] Scroll/screen chrome + cosmetics (#23–#29)
- [ ] Android component tail: calendar, clips, datepicker, filecell, picker, roadmap
  → 30/30

## Milestone 2 — Aurora reaches parity
- [ ] Full action runtime + mutable state (A1, A2). → [02]
- [ ] Component tail (16): pager, list, progress, chart, disclosure, slider, rings
  first, then the rest → 30/30.
- [ ] Correctness nits (`_fixed`, `fontSize`, `cGrid`).

## Milestone 3 — the enterprise pillars
- [ ] **Offline/local-cache** spec + 3 implementations behind one test suite. → [04B]
- [ ] **Embedded docs** + component⇄native mapping matrix. → [04C]
- [ ] **Everything-configurable sweep** — hunt remaining hardcoded values (swipe
  geometry, textfield colors, accent fallbacks, timeouts) → contract knobs.
- [ ] **Benchmark techniques ledger** → adopt div-patch partial updates, templates,
  fallback components. → [04A]

## Milestone 4 — polish & proof
- [ ] Snapshot tests per platform against the conformance fixtures; CI gates drift.
- [ ] Premium-polish pass on remaining screens (paywall/fitness/settings/cart) to
  the discover.json bar.
- [ ] Perf pass (list virtualization parity, image caching, launch time).
- [ ] Release engineering: Aurora RPM + icons + translations; Android release; iOS.

## Signature interactions (must feel identical on all three)
The premium "wow" moments the platform is judged on. iOS ships them; parity means
Android + Aurora reproduce them pixel-for-pixel, and the composer exposes them.
- [ ] **Collapsing scroll** — already in the contract + on iOS: `collapsingHero`
  (Apple-Weather `expanded`↔`compact`, pins to a material bar), `collapsingHeader`,
  `pinnedHeader` (sticky), and `scrollBehavior` (`largeTitle`, `range`, `pinTitle`,
  `revealOnPull`). **Port to Android** (audit #23) and **Aurora**, add composer UI.
- [ ] **Swipe-to-reveal** row actions (iOS `swipe`) — port to Android (#2) / Aurora.
- [ ] **Press-feedback** (scale+dim+haptic) everywhere — Android in flight (#5).
- [ ] **Story rings / segmented player**, **auto-advancing pager** — parity + composer.
- [ ] **Interactive chart scrub** (crosshair + value pill) — Android (#19) / Aurora.

## How we work the list
Pick a milestone, work its batches top-down, verify (iOS local / Android CI /
Aurora SDK), update PARITY.md + check boxes here, then move on. Keep [00 current
state](00-current-state.md) honest as things land.

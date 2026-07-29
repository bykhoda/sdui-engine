# 02 · Aurora OS — make it launch, then reach parity

Aurora is a real pure-QML/Silica renderer (14 components, modifier surface, binding
engine) but **as committed it cannot present anything**. This is the enterprise-
critical front (the RU target platform). Source audit 2026-07-29.

Files: `aurora/ru.auroraos.SduiPlayground.pro`, `aurora/src/main.cpp`,
`aurora/qml/{SduiPlayground,pages/ScreenPage}.qml`,
`aurora/qml/sdui/{SduiRenderer.qml,Tokens.js}`, `aurora/resources.qrc`,
`aurora/content-manifest.json`, `aurora/tools/gen_qrc.sh`.

## Launch blockers (fix these first)

- [ ] **B1 · home screen not bundled → blank app.** `SduiPlayground.qml:38` loads
  `qrc:/content/screens/home.json` and roots at `screenId:"home"` (`:67-73`), but
  `resources.qrc:6-46` and `content-manifest.json` **omit `home.json`** — they were
  generated (15:41) *before* `home.json` landed (20:15). `screensById["home"]` is
  never populated → renderer gets `null` → empty flickable. **Fix:** re-run
  `sh aurora/tools/gen_qrc.sh` (it globs `screens/*.json`, so it will pick it up),
  commit the regenerated qrc + manifest. Consider a CI check that fails if they're
  stale vs the content dir.
- [ ] **B2 · QML never deployed.** `main.cpp:16` resolves QML via
  `Aurora::Application::pathTo("qml/…")` (install datadir), but the `.pro` lists the
  5 QML/JS files only under `DISTFILES` (`:16-23`) — **no `INSTALLS`, no
  `target.path`, no `qml.files/qml.path`**, and the qrc bundles content JSON only.
  Unless `auroraapp.prf` auto-deploys `qml/` (SDK-version dependent), `setSource`
  finds nothing. **Fix:** add an explicit deploy rule (INSTALLS qml → datadir) *or*
  compile QML into a `qml.qrc` and load `qrc:/…`. Verify against the SDK.
- [ ] **B3 · toolchain wall.** Builds only with the Aurora SDK (`sfdk`/`mb2`,
  emulator i486 or device armv7hl/aarch64). No macOS/desktop-Qt path exists
  (`main.cpp` uses `Aurora::Application`; every QML imports `Sailfish.Silica`).
  **Decision needed:** add a thin desktop-Qt shim (QGuiApplication + a Silica-lite
  shim) so the renderer is testable off-device in CI, **or** stand up an Aurora SDK
  build in CI. Without one of these, Aurora is unverifiable on this host.

## Action runtime (top parity task)

- [x] **A1 · full dispatcher** (done 2026-07-29, pending SDK build). `dispatch(
  action, host)` in `SduiPlayground.qml` now implements `sequence` (stepwise, so an
  embedded `delay` pauses/resumes), `parallel`, `condition`, `delay`, `navigate`
  (incl. `transition:"replace"`), `dismiss`, `dismissRoot`, `openURL`,
  `openDeepLink`, `setState`, `increment` (+min/max clamp), `showToast` (Silica
  banner), `scrollTo`, `log`, `analytics`, `custom`. Clean commented stubs (never
  crash) for `haptic`, `share`, `refresh`, and `request`/`saveFile`/`preview`/
  `requireVersion`/`requestPermission` (need infra Aurora lacks — parity with
  Android's unimplemented set). **Field names verified against iOS + Android
  ActionInterpreter** (`delay.seconds`, `scrollTo.target`, `navigate.to`,
  `increment.by`) — identical behavior. `evalCondition` added to `Tokens.js`
  (equals/notEquals/exists/not/and/or, matching reference truthiness).
- [x] **A2 · mutable, bindable state** (done 2026-07-29, pending SDK build).
  `ScreenPage.qml` backs state with `property var _state` (seeded once from
  `screen.state`, source doc never mutated); `_ctx` is a binding that READS `_state`,
  so a `setState`/`increment` reassigns `_state` **wholesale** → QML re-evaluates
  `_ctx` → the renderer gets a fresh ctx → every `$state`-bound label/color
  re-resolves. Host hooks: `stateValue`/`setStateValue` (normalizes `$state.`
  prefix) / `scrollToId`.
- [ ] **A-verify · build on the Aurora SDK.** The above is careful, pattern-matched
  QML but **unbuilt** (no SDK on the dev host) — must be compiled/run on an Aurora
  target (or a desktop-Qt shim, B3) before it's trusted. This is the gate.

## Component tail (16 missing → 30/30)
`async, calendar, chart, clips, datepicker, disclosure, filecell, list, pager,
picker, progress, rings, roadmap, slider, spinner, ticker` all render a red
`[unsupported: …]` marker (`SduiRenderer.qml:353-364`). Even `home.json` shows one
`[unsupported: pager]` band. Port in the order real screens need them: **pager,
list, progress, chart, disclosure, slider, rings** first (highest hit-count).

## Correctness nits (after it launches)
- [ ] `_fixed()` returns `size.value` unresolved (`SduiRenderer.qml:23`) → a token
  fixed-size becomes `NaN`.
- [ ] `fontSize()` hardcodes a typography map, ignores the tokens `typography` table
  (`Tokens.js:69-79`).
- [ ] `cGrid` uses fragile `parent.parent.parent` chains (`SduiRenderer.qml:224`).
- [ ] Stale README describes a non-existent `CatalogPage.qml` flow — align docs.
- [ ] No launcher icons / translations (stubbed) — fine for now, needed for release.

## Definition of done for Aurora
`sh aurora/tools/gen_qrc.sh` current in CI · QML deploy rule verified · app roots at
`home.json` and renders premium (no unsupported bands) · full action runtime with
mutable state · 30/30 components · builds in an Aurora-SDK CI job.

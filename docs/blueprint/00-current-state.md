# 00 · Current state — ground-truth audit (2026-07-29)

First-hand inspection + two deep renderer audits (Android, Aurora). Numbers from
`spec/tools/parity.mjs`. This is the honest baseline we polish from.

## Contract & tooling — solid
- **Schema is the single source of truth.** `spec/tools/validate.mjs` derives
  known components/actions/required-props from `spec/schema/sdui.schema.json` at
  load; a `checkShape` pass enforces enums / numeric ranges / nested-required.
- **Validator = CI = engine = mock server.** `spec/tools/serve.mjs` validates
  every example at boot with the same `Validator` CI runs; iOS re-decodes all
  bundled screens in a test.
- **MCP live** — `spec/mcp/server.mjs` (zero-dep), tools: `validate_screen`,
  `list_components/actions/tokens`, `get_example`, `scaffold_screen`.
- **Parity matrix** — `parity.mjs` computes support from *actual renderer source*,
  not a hand list → `PARITY.md`.

## iOS — the reference (polished, minor tail)
- 30/30 components, 22/24 actions. `swift build` **green** (verified this session).
- Rigorous review found **zero** force-unwraps / `try!` / `as!` / `fatalError` in
  Sources. Press-feedback, swipe, Swift Charts, materials, accessibility all real.
- Open tail: `request` + `saveFile` actions are in the schema but **unimplemented
  even on iOS** (fall through to "Unhandled action") — decide implement-or-remove.
- P2 nits from earlier audit: swipe geometry still partly hardcoded (contract-drive
  it), textfield colors bypass tokens, async has no timeout/retry.

## Android — builds, but 29 discrepancies vs iOS → [01](01-parity-android.md)
Headlines (full list with file:line in 01):
- **P0:** images never render (Coil TODO — every `image` is a grey box); modifier
  chain drops 8 modifiers (blur, pulse, rotation, animation, zoomable,
  accessibility, swipe, ignoresSafeArea); `presentWhen` modals absent; `scrollTo`
  is a no-op; no press-feedback (taps feel dead).
- **P1:** missing action verbs (`preview`, `requireVersion`, `requestPermission`);
  `setState`/slider don't normalize `$state.` prefix; `material` only handles
  `glass`; no dark-mode palette swap; `maxWidth` doesn't fill; default stack/list/
  grid spacing 0 vs iOS ~8; `list` has none of iOS's filter/sort/limit/paginate/
  reorder/empty/swipe; `chart` is angular (no smoothing/axes/scrub); `textfield`
  ignores keyboardType/status/helper/icon.
- 24/30 components (missing calendar, clips, datepicker, filecell, picker, roadmap).

## Aurora — cannot launch as committed → [02](02-launch-aurora.md)
- **Blocker 1:** the only entry screen `home.json` is **not in the bundle** —
  `resources.qrc` + `content-manifest.json` are stale (generated before home.json
  landed). Re-run `sh aurora/tools/gen_qrc.sh` to fix.
- **Blocker 2:** the `.pro` lists QML only under `DISTFILES` — **no `INSTALLS`/
  deploy rule**, so `Aurora::Application::pathTo("qml/…")` may resolve to nothing.
- **Toolchain wall:** builds only with the Aurora SDK (emulator/device) — no
  macOS/desktop-Qt path. Cannot verify locally on this host.
- **No action runtime:** `dispatch()` handles only `navigate` + `sequence`;
  `setState`/`haptic`/`showToast`/… are no-ops; `_ctx.state` is seeded once and
  never mutable → no two-way state. 14/30 components; 16 render a red
  `[unsupported: …]` marker (incl. `pager` on the home screen).
- Stale README describes a `CatalogPage.qml` flow that doesn't exist.

## Web composer — was raw, now hardening → [03](03-composer.md)
- Real strengths: schema-driven inspector, layers tree with drag-reparent, token
  pickers, device presets + dark mode, live server validation, import/export.
- **Just fixed:** preview now **resolves `$data`/`$state`/`$item`/`$env` bindings**
  to realistic sample values (was showing raw `$data.product.title` strings) —
  verified live; the canvas now reads like a real screen.
- Still raw: only 5 spec examples loadable (not the 39 premium screens); onTap
  editor covers 4 of 24 actions; no undo/redo; preview is structural (hardcoded
  fakes for chart/ticker/rings); no per-component fidelity to native metrics.

## Missing pillars (not started)
- **Offline / local-cache DB** — no design yet. Needed for enterprise resilience
  and identical cache semantics cross-platform. → [04](04-benchmark-and-docs.md).
- **Embedded platform docs** — Apple/Android/Aurora references not in-repo. → [04].

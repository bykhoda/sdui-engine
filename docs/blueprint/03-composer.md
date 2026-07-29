# 03 · Web composer — from raw to production authoring tool

The visual builder at `GET /compose` (`spec/compose/index.html`, served by
`spec/tools/serve.mjs`). It's the "build by hand" on-ramp. Strong bones, but "very
raw" per the owner — this is the plan to make it a tool enterprises trust.

Run it: `node spec/tools/serve.mjs` → http://localhost:8787/compose

## What's already good
- Schema-driven inspector — every contract field for a type, with token pickers and
  hybrid raw/token color+dimension controls.
- Layers tree with drag-to-reparent, duplicate, reorder, delete; keyboard delete.
- Device presets (SE/iPhone/Pro Max/Pixel/iPad) + rotate + dark mode; realistic
  status bar / island / punch-hole chrome.
- Live validation against the **same** server `Validator` CI runs; import/export;
  copy JSON.

## Done this session
- [x] **Binding resolution in preview.** `$data/$state/$item/$env` bindings now
  resolve to realistic sample values (premium, keyed by leaf name) instead of
  showing raw `$data.product.title`. Images with binding sources get a sample photo.
  Verified live — the canvas reads like a real screen. (`resolveText`/`resolveImg`
  in `index.html`.)

## Backlog to "ideal"

### Fidelity (make preview match native)
- [ ] Load **all** app screens, not just the 5 `spec/examples`. The 38+ premium
  screens live in `ios/.../Content/screens`; expose them via the catalog/server so
  "Open example…" can edit the real ones.
- [ ] Replace hardcoded fakes (chart bars, ticker "1,248", rings) with previews
  driven by the node's actual props.
- [ ] Per-component metrics that match iOS defaults (spacing, radii, type scale) so
  what you see maps to the native render. Consider rendering the preview from a
  shared JS renderer used as the "approximate preview" (mark it as such).
- [ ] Honour more modifiers in preview: shadow, blur, material, rotation, opacity
  already partial — complete the set.

### Authoring power
- [x] **onTap/action editor covers all 24 actions** (done 2026-07-29). Driven by
  `CATALOG.actions`; per-action field sets via `AFIELDS`; dynamic (switching type
  rebuilds fields); required marks; raw-JSON escape hatch for sequence/condition/
  parallel. Verified live: dropdown lists all 24; navigate→to/transition/params,
  showToast→message/style — fields match the schema exactly.
- [x] **Undo/redo** (done 2026-07-29). 100-deep snapshot ring, debounced commit on
  every mutation (not on selection), Cmd/Ctrl+Z + Cmd/Ctrl+Shift+Z / Ctrl+Y, plus
  ↺/↻ toolbar buttons. Verified live.
- [ ] Multi-select + copy/paste of subtrees across screens.
- [ ] Bind-aware fields: autocomplete `$data.*`/`$state.*` from the screen's declared
  `state`/`data` sources; warn on unknown bindings.
- [ ] Component templates / snippets (hero, rail, form) to drop in proven patterns.
- [ ] Inline design-lint (per [[feedback-composer-guardrails]]): flag off-token
  colors, contrast issues, non-native spacing — guardrails, not just freedom.

### Robustness
- [x] **Persist work-in-progress** (done 2026-07-29). Debounced write of `doc` to
  `localStorage['sdui_wip']`, restored on boot; a **New** button resets to blank +
  clears saved work. Verified: survives a full page reload.
- [ ] Keyboard-first: arrow-key layer navigation, Enter to rename.
- [ ] Accessibility of the composer UI itself (focus order, ARIA).

## Definition of done
A backend/designer can open a real premium screen, edit it with full action support
and undo, see a preview that matches the device, get inline guardrail feedback, and
export contract JSON that validates — without touching code.

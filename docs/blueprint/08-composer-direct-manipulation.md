# 08 — Composer Direct Manipulation

**Goal:** make the SDUI Composer canvas feel like Figma/Photoshop — drag elements on
the artboard, set padding/spacing by dragging handles with live px badges, edit color
on-screen, with every change flowing straight into the contract JSON. Today all real
editing lives in the right-hand inspector and the left-hand layers tree; the canvas is a
read-only structural preview you can only *click to select*. This document specifies how
to close that gap in the existing **vanilla-JS single-file composer**
(`spec/compose/index.html`), framework-free.

> Scope note: our canvas is a *structural DOM preview* (`el()` builds real `<div>`s with
> flex layout in `renderPreview()`), not a free-canvas like Figma. That is an advantage —
> we do not need absolute-position math or a scene graph. Every node is already a laid-out
> DOM element whose `getBoundingClientRect()` we can read. Direct manipulation becomes:
> *read the rect → draw chrome/handles in an overlay → map a pointer delta to a modifier
> value → write the node → `render()`*.

---

## 1. What "great" looks like

The reference tools converge on a small set of interactions. Grouped, with sources.

### Selection
- **Selection chrome = outline + size badge + type tab.** Selecting shows an outline plus
  a dimensions readout (W×H) and can reveal alignment/distance measurements. Figma shows
  offset H/V measurements when you hold Alt/Option and hover another object.
  ([Figma — adjust alignment/position/dimensions](https://help.figma.com/hc/en-us/articles/360039956914-Adjust-alignment-rotation-position-and-dimensions),
  [Design+Code — Smart Selection](https://designcode.io/figma-handbook-smart-selection/))
- **Hover pre-highlight.** Before you click, hovering an element shows a thin highlight so
  you know exactly what will be selected — standard in Figma/Webflow canvases.
  ([Webflow canvas overview](https://help.webflow.com/hc/en-us/articles/33961319255059-Webflow-canvas-overview))

### Move / reorder
- **Drag the element itself to reorder.** In an auto-layout / flex parent, dragging a child
  reflows siblings and a gap opens where it will land. The dragged item follows the pointer
  via `transform: translate()` (cheap, no repaint); idle siblings shift by `itemSize + gap`;
  the drop index is decided by comparing the dragged center against each sibling's center.
  ([Taha Shashtari — drag-to-reorder in vanilla JS](https://tahazsh.com/blog/seamless-ui-with-js-drag-to-reorder-example/),
  [Alex Reardon — rethinking drag and drop](https://medium.com/@alexandereardon/rethinking-drag-and-drop-d9f5770b4e6b))
- **Drop indicator, not just a ghost.** A gap/line shows the insertion point continuously
  during `move`. ([robehickman — pointer-events sortable](https://robehickman.com/js-drag-drop-sortable))

### Spacing / padding (the signature Figma interaction)
- **On-canvas pink handles for padding and gap.** Select an auto-layout frame, hover, and
  handles appear; click a handle to type a value, or **click-drag the handle to change
  spacing/padding live.** ([Figma — guide to auto layout](https://help.figma.com/hc/en-us/articles/360040451373-Guide-to-auto-layout),
  [Figma — horizontal/vertical flows](https://help.figma.com/hc/en-us/articles/31289464393751-Use-the-horizontal-and-vertical-flows-in-auto-layout))
- **Modifier keys mirror sides.** `⇧Shift` while dragging a handle uses the big-nudge step
  and/or applies to all sides; `⌥Alt` grows both opposite sides equally.
  ([Figma auto layout](https://help.figma.com/hc/en-us/articles/360040451373-Guide-to-auto-layout))
- **Webflow: canvas spacing mode.** `⌘⇧D` shows margin/padding directly on the selected
  element as draggable bands; `⇧` drag = all sides, `⌥` drag = both sides.
  ([Webflow — spacing (margin & padding)](https://help.webflow.com/hc/en-us/articles/33961243177875-Spacing-margin-and-padding))

### Sizing
- **Edge / corner resize handles.** Drag a corner to resize; drag an edge for one axis.
  Framer keeps handles on every corner and preserves aspect where relevant.
  ([Framer — resize handles](https://www.framer.com/blog/create-a-canvas-like-website/))
- **Scrub numeric fields.** `⌥`-drag on an input field scrubs the value — Webflow ships this
  exact affordance for spacing/size inputs. ([Webflow — Option+drag to change input values](https://webflow.com/updates/option-drag-to-change-input-values))

### Color
- **Swatch → picker on the object.** A color swatch on the selection (or in a floating
  popover) opens an eyedropper + spectrum; recents persist. (Our inspector already has the
  hybrid hex/token picker + recents; the gap is putting it *on the canvas*.)

### Alignment / snapping
- **Smart guides + snap to objects/pixel grid.** Red guides appear when the moved element's
  edges/centers align to siblings or to equal spacing; snapping to object edges/centers and
  to the pixel grid keeps things crisp. ([Figma — smart selection/snap](https://designcode.io/figma-handbook-smart-selection/),
  [Figma forum — snapping to guides](https://forum.figma.com/t/red-auto-measurement-thingy/2929))
- **Snap-to-grid with a visible grid + threshold.** Snapping engages within a small pixel
  threshold and shows a guide. ([Framer snapping devlog](https://ltngames.itch.io/elements-plugin/devlog/921674/devlog-new-editor-features-incoming))

### Keyboard
- **Arrow nudge (1px) + `⇧` big nudge; `⌥` duplicate-drag; `Esc` cancels a drag;
  `⌘D` duplicate; `Tab`/`Enter` to walk the tree.** These are table stakes across all four
  tools. ([Figma auto layout — nudge with handles](https://help.figma.com/hc/en-us/articles/360040451373-Guide-to-auto-layout))

### SDUI-specific reference
- **DivKit playground** proves the *round-trip* model: a JSON layout editor with a live
  cross-platform preview over websockets — edits to JSON reflect instantly. Our composer
  already has the live preview; we are adding the *inverse* — canvas gestures that write the
  JSON. ([DivKit playground](https://divkit.tech/playground),
  [DivKit repo](https://github.com/divkit/divkit))

---

## 2. Gap list vs our current composer

What exists today in `spec/compose/index.html`:

- **Layers tree** (left) with HTML5-drag reorder **and** reparent — `renderTree()` sets
  `r.draggable`, and `ondragover`/`ondrop` compute `before`/`after`/`inside` from the
  pointer's Y ratio inside the row, calling `reparent(id, targetId, pos)`.
- **Click-to-select on canvas** — `el()` attaches `onclick` → `selId = n.__id; render()`.
  Selection is shown as a static outline via the `.selhint` class (outline + glow).
- **Inspector-driven everything** — `renderInspector()` builds schema controls; `frameCtl()`
  drives `modifiers.size.{width,height}` (auto/fill/fixed/weight via `setFrame`); the
  **Style** section edits `padding`, `background`, `cornerRadius`, `opacity`, `material`;
  `spacing` is a token/number `dimension` control; color uses the hybrid hex+token picker
  with persisted recents.
- **Model & re-render** — a node tree under `doc.screen.content`, each node carrying `__id`;
  helpers `find`, `parentOf`, `walk`, `subtreeHas`; `render()`/`touch()` re-render the whole
  UI; `commit()` snapshots for undo; `persist()` saves WIP to `localStorage`.
- **Keyboard** — `⌘Z`/`⌘⇧Z`/`⌘Y` undo-redo, `Delete` removes the selection. That's it.

**Missing to reach "Photoshop-like" (the whole point of this doc):**

| Capability | Today | Gap |
|---|---|---|
| On-canvas **drag-to-reorder** | Tree only | No dragging the element on the artboard; must use the tree or ↑/↓ buttons |
| **Padding drag-handles + px badge** | Inspector number/token | No on-canvas handle; no live badge; no per-side padding at all (padding is a single scalar) |
| **Spacing (gap) drag-handle** | Inspector token | No on-canvas gap handle between children |
| **Resize handles** | Inspector `fixed` value field | No corner/edge handles; can't drag to set width/height |
| **Inline color editing** | Inspector hybrid picker | No swatch/eyedropper on the canvas |
| **Alignment guides / snapping** | None | No smart guides, no snap to sibling edges, no snap to token steps |
| **Selection chrome** | Static outline | No size badge, no type tab, no padding/gap visualization |
| **Hover pre-highlight** | None | You don't see what you'll select until you click |
| **Keyboard nudge / `⌘D` / `Esc`-cancel / `⌥`-scrub** | None | No fine control; no gesture cancel |
| **Undo granularity for gestures** | Per-edit debounce (350ms) | A drag would spam history unless we scope one commit per gesture |

Net: we have a solid *model layer* and a *live preview*, but zero *direct manipulation*.
Everything below builds one thin **overlay layer** over the existing preview and reuses the
existing model helpers — no framework, no rewrite of `render()`.

---

## 3. Implementation plan (vanilla JS, single file)

### 3.0 The overlay layer (foundation for everything)

Add one absolutely-positioned, `pointer-events:none` overlay **inside `.screen`** (the
element `#preview` renders into), stacked above the preview content:

```
.overlay{position:absolute;inset:0;z-index:5;pointer-events:none}
.overlay > *{pointer-events:auto}   /* handles opt back in */
```

- `.screen` becomes `position:relative` (it already scrolls). Insert `<div id="overlay">`
  once in `renderPreview()` *after* `p.appendChild(el(s.content))`, or keep it as a sibling
  that is re-measured.
- A single `drawOverlay()` reads geometry from the live DOM. For the selected node, get its
  preview element (`el()` should stamp `e.dataset.id = n.__id` so we can
  `preview.querySelector('[data-id="…"]')`). Compute a rect **relative to `.screen`**:
  `r = elRect - screenRect (+ screen.scrollLeft/Top)`. Position chrome/handles from `r`.
- `drawOverlay()` runs at the end of `render()` and also on `#preview` `scroll` and window
  `resize` (rAF-batched). Because `render()` rebuilds the preview DOM, the overlay is always
  redrawn from fresh rects — no stale coordinates.

This overlay is the single home for: selection chrome, resize handles, padding/gap handles,
the drop line, snap guides, and measurement badges. It never mutates layout; it only reads
rects and draws.

Add a global gesture guard so overlay drags and history play nicely:

```js
let gesture=null;               // {kind, node, axis, startPx, startVal, restore}
function beginGesture(g){gesture=g; flush();}          // land any pending edit first
function endGesture(commitIt){ if(commitIt)commit(true); gesture=null; drawOverlay(); }
```

### 3.1 Selection chrome with measurements

- **Outline + type tab + size badge.** Replace the static `.selhint` glow with an overlay
  rect: a 1.5px accent border box positioned at `r`, a small type label tab at its top-left
  (`n.type`), and a size badge at bottom-center showing `Math.round(r.w)×Math.round(r.h)`
  (px, read from the rect — the *rendered* size, exactly like Figma's readout).
- **Hover pre-highlight.** On `#preview` `pointermove` (rAF-throttled), hit-test the element
  under the pointer (`document.elementFromPoint` → nearest `[data-id]`), draw a faint hover
  outline in the overlay. Clear on `pointerleave`.
- **Container extras.** If the selected node is a container, additionally shade its padding
  band and mark the child gaps (see 3.3) so the chrome doubles as the spacing editor.

### 3.2 On-canvas drag-to-reorder

Reuse the model op `reparent(id, targetId, pos)` — we only add the *gesture* that computes
`targetId`+`pos` from pointer position. Approach mirrors the vanilla technique
([Taha Shashtari](https://tahazsh.com/blog/seamless-ui-with-js-drag-to-reorder-example/)):

1. **Start.** `pointerdown` on a selected preview element (not on a handle) →
   `el.setPointerCapture(e.pointerId)`; record `start={x,y}`, the node, its parent, and the
   sibling rects. Add `will-change:transform` and a dragging class; set `cursor:grabbing`.
2. **Move (rAF-batched).** Translate the dragged element by the pointer delta
   (`transform: translate(dx,dy)`). Determine the parent's flow from the node's container
   type (`vstack`/`list`/`grid` = column, `hstack` = row → compare `clientY` or `clientX`).
   Compute the insertion index by walking siblings and finding the first whose midpoint is
   past the pointer (`pointer < rect.top + rect.height/2` for a column). Draw a **drop line**
   in the overlay at that boundary. Optionally, if the pointer is deep inside another
   container's body, target `pos:'inside'` (reuse the tree's 25–75% band heuristic).
3. **End.** `pointerup` → clear transform/line, call `reparent(dragId, targetId, pos)` (which
   already re-renders), then `endGesture(true)` for exactly **one** undo entry.
4. **Cancel.** `Escape` (or `pointercancel`) → clear transform, `drawOverlay()`, no model
   change.

No HTML5 drag API on canvas — pointer events unify mouse/touch and let us draw our own line
([robehickman](https://robehickman.com/js-drag-drop-sortable)). The tree's existing
`draggable` reorder stays as-is.

### 3.3 Padding & spacing drag-handles with px badges

This is the highest-value, most-Figma interaction. It operates on the **selected container**.

**Padding.** Our model stores `modifiers.padding` as a single scalar (token or number),
applied uniformly by `applyMods()` (`e.style.padding = px(m.padding,0)`). Two options:

- *Phase 1 (uniform):* one padding band drawn just inside the selection rect on all four
  sides; drag any edge of the band to change the single `padding` value.
- *Phase 2 (per-side):* extend the contract to accept
  `padding:{top,right,bottom,left}` (Figma/Webflow parity) and draw four independent bands.
  Keep back-compat: a scalar means all sides. (This is a contract change — schedule after
  Phase 1 ships.)

Handle mechanics (per side handle):
1. `pointerdown` on the band handle → `beginGesture`. Resolve the current px:
   `start = typeof padding==='number' ? padding : (tok(padding) ?? 0)` via the existing
   `tok()`/`px()` resolvers. `setPointerCapture`.
2. `pointermove` (rAF): `next = clamp(start + delta, 0, MAX)`, where `delta` is inward pointer
   travel for that side (top handle → `dy`; left handle → `dx`; sign so dragging inward grows
   padding). Write a **raw number** to the model (`n.modifiers.padding = next`) and call
   `touch()` (not full `render()` — cheaper, keeps focus). Draw a **px badge** at the handle
   showing `next`. Snapping: see 3.5 (snap to token steps 4/8/12/16/24/32).
3. Modifiers: `⇧` = big step / apply to all sides; `⌥` = grow both opposite sides equally
   (needs the per-side model) — matches Figma & Webflow
   ([Figma](https://help.figma.com/hc/en-us/articles/360040451373-Guide-to-auto-layout),
   [Webflow](https://help.webflow.com/hc/en-us/articles/33961243177875-Spacing-margin-and-padding)).
4. `pointerup` → `endGesture(true)`. `Escape` → restore `start`, `endGesture(false)`.

**Spacing (gap).** For `vstack`/`hstack`/`grid`, `spacing` is a node prop resolved by `px()`
in `el()` (`gap:'+px(n.spacing,8)+'`). Draw a **gap handle** in the middle of the gap between
the first two children (a small pill). Dragging along the flow axis maps delta → `n.spacing`
as a raw number, live-updating via `touch()` with a px badge. Same snap/modifier rules.

**Value write-back rule (important).** A drag always writes a **raw number** so the gesture is
continuous. If the pre-drag value was a token, offer a subtle "snap to `$token.spacing.md`"
affirmation when the dragged number lands within ±1px of a token value (write the token back
instead of the number) — keeps designs token-clean without fighting the drag.

### 3.4 Sizing (resize handles)

- Draw 8 handles (4 corners + 4 edges) on the selection rect, but **only enable the ones that
  make sense**: width handles when `size.width.mode!=='fill'`, height handles when a fixed
  height is meaningful. Cursor per handle (`ew-resize`, `ns-resize`, `nwse-resize`, …).
- `pointerdown` → read current fixed value (or the measured rect size if mode is `auto`/`fill`)
  as `start`. `pointermove` → `next = start + delta`; call `setFrame(n,'width','fixed',next)`
  (the existing helper) + `touch()` + px badge. Dragging an `auto`/`fill` edge **converts to
  `fixed`** at the measured size + delta (Figma does the same when you drag a hug/fill edge).
- `⇧` preserves aspect on corner drags (scale both from one ratio). `pointerup` →
  `endGesture(true)`; `Esc` restores.

### 3.5 Alignment guides & snapping

A shared `snap(value, candidates, threshold)` used by move/padding/spacing/resize:

- **Candidate lines** while moving/resizing a node: sibling edges & centers, the parent's
  content box (padding edges), and the artboard center. Collect their canvas coordinates from
  the live rects.
- **Token snapping** for padding/spacing/size: candidate *values* = the numeric resolutions of
  `TOKENS.spacing` / `TOKENS.radius` (e.g. 4, 8, 12, 16, 24, 32) — snap the *number*, not a
  coordinate. This nudges authors toward the design system for free.
- **Engage within threshold** (`~5px` at 1× — Figma/Framer feel). On snap: freeze the value to
  the candidate and draw a **guide line** (accent, 1px) in the overlay spanning the aligned
  extent, plus an equal-spacing badge when two gaps match. Release past threshold to break.
  ([Figma smart guides](https://designcode.io/figma-handbook-smart-selection/),
  [Framer snapping](https://ltngames.itch.io/elements-plugin/devlog/921674/devlog-new-editor-features-incoming))
- Hold a key (e.g. hold `⌘`/`Ctrl`) to **suspend snapping** for free movement — standard
  escape hatch.

### 3.6 Inline on-canvas color editing

- When the selected node has a color-bearing field (`text.color`, `icon.color`, container
  `background`), draw a **swatch chip** in the selection chrome showing the resolved color
  (`hexOnly()`/`tok()`).
- Click the swatch → open a small floating popover anchored to it that reuses the *existing*
  hybrid control markup from `control()` (native `<input type=color>` + hex/token field +
  recents from `getRecent()`/`addRecent()`). Writing calls the same setter path + `touch()`.
- Optional wow: the browser `EyeDropper` API (Chromium) for pick-from-screen; feature-detect
  and hide where unsupported.

### 3.7 Keyboard (extend the existing `keydown` handler)

Add, guarded by "not typing in a field" (the handler already checks `INPUT|TEXTAREA|SELECT`):

- **Arrow keys** = nudge selection order/size by context; `⇧+Arrow` = big step. In a flex
  parent, `↑/↓` (col) or `←/→` (row) reorder within siblings (reuse `move(id,±1)`).
- **`⌘D`** duplicate (reuse `duplicate(id)`); **`⌫/Delete`** already deletes.
- **`Esc`** cancels an in-flight gesture (restores `gesture.restore`) or clears selection.
- **`Enter`/`Tab`** = select first child / next sibling (tree walk) for keyboard-only editing.

### 3.8 Write-back & re-render contract

Every gesture funnels through the **same model helpers already in the file** — no new source
of truth:

- Structure: `reparent`, `move`, `duplicate`, `remove`.
- Props/modifiers: direct node mutation (`n.modifiers.padding = …`, `n.spacing = …`) then
  `touch()` during a drag (skips `renderInspector()`/`renderTree()` for speed and to keep the
  overlay stable), and one `render()` + `commit(true)` at gesture end.
- `drawOverlay()` re-reads rects after each render, so canvas and model never diverge. The
  inspector, tree, JSON pane, and validation all stay live because they already hang off
  `render()`/`touch()`.

---

## 4. UX details that keep it from feeling janky (криво)

- **Pointer capture.** Always `setPointerCapture(e.pointerId)` on gesture start so the drag
  survives the pointer leaving the element/artboard; release on end. Prevents the classic
  "drag drops when you move fast" bug.
- **rAF batching.** `pointermove` only stores the latest event; a single rAF loop applies it
  (`if(!raf) raf=requestAnimationFrame(apply)`). Never write the model or the DOM directly in
  the event — this is the difference between 60fps and stutter
  ([react-beautiful-dnd approach, per the reorder survey](https://tahazsh.com/blog/seamless-ui-with-js-drag-to-reorder-example/)).
- **`will-change:transform` + `transform` for the dragged element**, not `top/left` — avoids
  layout/paint thrash; strip it on end.
- **Snap threshold ~4–6px**, with hysteresis (engage at 5px, break at 8px) so guides don't
  flicker. Suspend snapping while a modifier is held.
- **Cursor affordances** per zone: `grab`/`grabbing` on body drag, `ew/ns/nwse-resize` on
  resize handles, `col-resize`/`row-resize` on spacing, `crosshair` near padding bands. Set on
  the handle elements so the intent is legible before the click.
- **Live px badge follows the handle** during any spacing/padding/size drag, tabular-nums,
  same badge style as the selection size readout — instant numeric feedback (Figma parity).
- **Undo granularity = one entry per gesture.** `beginGesture()` calls `flush()` to land prior
  edits; interim `touch()` calls must *not* `commit()` (or the debounce coalesces them — the
  current 350ms debounce already helps, but explicitly suppress commits mid-gesture and call
  `commit(true)` exactly once on `pointerup`).
- **`Escape` cancels** and restores the pre-drag value (`gesture.restore`), `pointercancel`
  too. Nothing is worse than a half-applied drag with no way out.
- **Hit-slop / dead-zone.** Require ~3px of movement before a click becomes a drag, so a plain
  click still just selects (don't accidentally reorder on a click).
- **Handles hide during drag** of a different gesture and while the parent is scrolling; the
  overlay stays `pointer-events:none` except on the handles themselves so canvas clicks still
  reach the preview for selection.
- **Reduced motion.** Respect the existing `prefers-reduced-motion` block — snap instantly, no
  reflow animation, when it's set.

---

## 5. Top 10 to build first (wow-per-effort, ranked)

1. **Overlay layer + selection chrome with W×H badge & type tab** — foundation for everything;
   instantly reads as "a real editor." (Low effort, high signal.)
2. **On-canvas padding drag-handles with live px badge** (uniform, Phase 1) — the single most
   Figma-defining gesture; reuses `modifiers.padding` + `tok()`/`px()`.
3. **Spacing (gap) drag-handle between children** — same machinery as #2 on `n.spacing`;
   enormous perceived power for a container-heavy SDUI.
4. **Hover pre-highlight on canvas** — tiny code, huge "it's alive" feel; removes select-guessing.
5. **On-canvas drag-to-reorder with drop line** — reuses `reparent`; brings the tree's power to
   the artboard where the eye already is.
6. **Snap-to-token for spacing/padding/size (value snapping) + guide line** — keeps output
   design-system-clean and feels magnetic; small once the drag exists.
7. **Resize handles (fixed width/height) via `setFrame`** — corners/edges; converts hug/fill to
   fixed on drag like Figma.
8. **Keyboard: arrow-nudge reorder, `⌘D`, `Esc`-cancel** — cheap, makes the whole thing feel
   professional and controllable.
9. **Inline color swatch → popover (reuse `control()` markup) + `EyeDropper`** — on-canvas color
   without a trip to the inspector.
10. **Smart alignment guides (sibling edges/centers, equal-gap badges)** — the final "pixel-
    perfect" polish layer; highest effort, so last.

---

## Sources

- Figma — Guide to auto layout: https://help.figma.com/hc/en-us/articles/360040451373-Guide-to-auto-layout
- Figma — Horizontal/vertical flows in auto layout: https://help.figma.com/hc/en-us/articles/31289464393751-Use-the-horizontal-and-vertical-flows-in-auto-layout
- Figma — Adjust alignment, rotation, position, dimensions: https://help.figma.com/hc/en-us/articles/360039956914-Adjust-alignment-rotation-position-and-dimensions
- Design+Code — Figma Smart Selection: https://designcode.io/figma-handbook-smart-selection/
- Figma forum — measurement/snap guides: https://forum.figma.com/t/red-auto-measurement-thingy/2929
- Webflow — Spacing (margin & padding): https://help.webflow.com/hc/en-us/articles/33961243177875-Spacing-margin-and-padding
- Webflow — Canvas overview: https://help.webflow.com/hc/en-us/articles/33961319255059-Webflow-canvas-overview
- Webflow — Canvas settings (show spacing on canvas): https://help.webflow.com/hc/en-us/articles/33961230930579-Canvas-settings
- Webflow — Option+drag to scrub input values: https://webflow.com/updates/option-drag-to-change-input-values
- Framer — Draggable canvas / resize handles: https://www.framer.com/blog/create-a-canvas-like-website/
- Framer — snapping devlog (grid + threshold): https://ltngames.itch.io/elements-plugin/devlog/921674/devlog-new-editor-features-incoming
- Plasmic vs Builder.io (architecture overview): https://www.subframe.com/tips/plasmic-vs-builderio
- Plasmic repo: https://github.com/plasmicapp/plasmic
- DivKit playground (SDUI JSON round-trip): https://divkit.tech/playground
- DivKit repo: https://github.com/divkit/divkit
- Taha Shashtari — Seamless drag-to-reorder in vanilla JS (transform + midpoint hit-test): https://tahazsh.com/blog/seamless-ui-with-js-drag-to-reorder-example/
- Alex Reardon — Rethinking drag and drop: https://medium.com/@alexandereardon/rethinking-drag-and-drop-d9f5770b4e6b
- robehickman — Sortable list with pointer events: https://robehickman.com/js-drag-drop-sortable

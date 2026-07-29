# 01 · Android ↔ iOS parity — the discrepancy backlog

iOS is the reference. Every item below is a place Android diverges from it, with
file:line on both sides, prioritized. Check off as fixed; re-run
`node spec/tools/parity.mjs` after each batch. Source: full renderer audit
2026-07-29.

Android renderer: `android/sdui/src/main/java/dev/sdui/render/{Builtins,SduiModifiers,DataViz,Theme,ComponentRegistry,SduiScreen}.kt`,
`core/{Models,BindingEngine,SduiParser}.kt`, `runtime/ActionInterpreter.kt`.
iOS reference: `ios/Sources/SDUIRender/*.swift`, `SDUIRuntime/ActionInterpreter.swift`.

## P0 — visible or functional breakage

> **Batch 1 done 2026-07-29** (pending CI compile): #1 images (Coil), #5 press
> feedback, #2 modifier surface (blur/rotation/pulse/animation/safe-area), #9
> material×6, #11 maxWidth-fill, #13 real shadow. Also reconciled the schema —
> `blur`/`rotation`/`pulse`/`zoomable`/`presentWhen`/`presentStyle`/`onDoubleTap`/
> `hitSlop` were read by the renderers but missing from `sdui.schema.json` (a real
> contract bug — `home.json`'s `pulse` would have failed strict validation); added
> them, regenerated types, and CI now validates all 25 shared content screens.

- [x] **1. Images never render.** `Builtins.kt:407-425` draws a grey box (`TODO:
  plug in Coil`); `source` is resolved but never fetched. iOS `Builtins.swift:1515`
  loads remote images, honours `contentMode`/`placeholder`/`aspectRatio`/`clipped`.
  → **Add Coil**; honour loader props.
- [ ] **2. Modifier chain drops 8 modifiers.** `SduiModifiers.kt:44-55` applies
  padding/size/frame/background/material/shadow/opacity/scale/gesture only. Missing
  vs `Modifiers.swift:25-43`: `blur`, `pulse`, `rotation`, `animation` (field exists
  `Models.kt:152` but unused), `zoomable`, `accessibility`, `swipe`,
  `ignoresSafeArea` (field exists `Models.kt:143` but unused), plus `onDoubleTap`,
  `hitSlop`. → Extend `Modifiers` data class + `sduiModifiers`.
- [ ] **3. `presentWhen` modals absent.** iOS presents sheet/fullScreenCover at
  registry level (`ComponentRegistry.swift:110-114`). Android `Modifiers` has no
  `presentWhen`/`presentStyle`; `ComponentRegistry.kt:89-100` never presents. →
  Add fields + modal host.
- [ ] **4. `scrollTo` is a no-op.** Target recorded (`SduiScreen.kt:174-176`) but no
  container consumes it; `ScrollView`/`ListView` are plain. iOS wires
  `ScrollViewReader` + `.onChange` (`Builtins.swift:367`). → Consume target in
  scroll/list.
- [ ] **5. No press-feedback.** iOS routes every `onTap` through `Button` +
  `SDUIPressableStyle` (scale/dim/haptic, `Modifiers.swift:414-458`). Android
  `gestureModifier` (`SduiModifiers.kt:134-144`) is a bare `detectTapGestures` —
  taps feel dead. → Add scale+dim+haptic press feedback.

## P1 — styling/behaviour divergence

- [ ] **6. Missing action verbs** in `ActionInterpreter.kt:78-163`: `preview`
  (iOS `:200`), `requireVersion` (iOS `:224`), `requestPermission` (iOS `:246`).
  Add cases + `ActionHost` methods + delegate to `SduiHostDelegate`. *(Note:
  `request` + `saveFile` are unimplemented on iOS too — not Android regressions.)*
- [ ] **7. `setState` doesn't normalize `$state.` prefix.** iOS normalizes
  (`SDUIScreenView.swift:105,129`). Android writes key verbatim (`SduiScreen.kt:163`)
  → `state["$state.foo"]` vs iOS `state["foo"]`. `increment` strips it manually
  (`ActionInterpreter.kt:157`) — internally inconsistent. → Normalize centrally.
- [ ] **8. Slider `bind` double-prefixes.** `DataViz.kt:423` reads `bind` raw then
  resolves `"$state.$key"` → `$state.$state.volume`. Toggle/TextField use
  `bindKey()` (`Builtins.kt:103`). → Use `bindKey()` in slider.
- [ ] **9. `material` only handles `glass`.** `SduiModifiers.kt:110-125`; the other
  5 (ultraThin/thin/regular/thick/bar) fall through. iOS maps all six
  (`Modifiers.swift:353-377`). → Map all materials.
- [ ] **10. No dark-mode palette swap.** iOS swaps `color.*`→`colorDark.*` on
  `$env.theme=="dark"` (`Theme.swift:29-41`). Android `Theme.kt:50-54` has none. →
  Add dark swap.
- [ ] **11. `maxWidth` doesn't fill.** iOS `.frame(maxWidth:.infinity)`
  (`Modifiers.swift:307`). Android `widthIn(max=Infinity)` (`SduiModifiers.kt:98`)
  only lifts the constraint. → Use `fillMaxWidth` semantics.
- [ ] **12. `size` weight/min/max unsupported.** iOS handles fill/weight/min/max
  (`Modifiers.swift:215-250`). Android only fixed/fill (`SduiModifiers.kt:84-96`). →
  Add weight (RowScope/ColumnScope) + min/max.
- [ ] **13. Shadow is monochrome elevation.** iOS uses color/radius/x/y
  (`Modifiers.swift:396`). Android uses radius→elevation only, drops color/x/y
  (`SduiModifiers.kt:127`). → Real colored offset shadow.
- [ ] **14. Default spacing mismatch.** iOS stacks `nil`→~8pt; Android `0.dp`
  (`Builtins.kt:284`). Same for list (`:336`) and grid (`:153`). → Match iOS
  defaults.
- [ ] **15. `list` is a bare LazyColumn.** Missing iOS's filter/sort/limit/paginate/
  paginateOnScroll/reorder/empty/resultCount/swipe (`Builtins.swift:867-1136` vs
  `Builtins.kt:335-362`). → Port list feature set.
- [ ] **16. `grid` is a non-lazy chunked костыль** (`Builtins.kt:150-175`, admits
  LazyVerticalGrid would crash in outer scroll). iOS uses `LazyVGrid` in own
  ScrollView. → Rework so grid is lazy + scroll-safe (native mechanism, no hack).
- [ ] **17. `spacer` isn't flexible** (`Builtins.kt:364-370` fixed box). iOS is real
  `Spacer(minLength:)` (`Builtins.swift:1454`). → Flexible spacer in stacks.
- [ ] **18. `disclosure` styling diverges.** iOS is a rounded card w/ tinted icon,
  accent, subtitle, rotating chevron, divider, border, spring+haptic
  (`Disclosure.swift`). Android is a plain column w/ `▾` glyph (`Builtins.kt:177`),
  ignores `accent`/`icon`. → Match iOS card.
- [ ] **19. `chart` is angular Canvas.** No Catmull-Rom smoothing, ignores
  `axes`/`unit`/`interactive`, no scrub/crosshair (`DataViz.kt:159-217` vs
  `ChartView.swift`). → Smooth + axes + scrub.
- [ ] **20. `icon` finite SF→Material table** (~35 names, else puzzle-piece
  fallback, `DataViz.kt:229-285`); ignores `symbolEffect`. iOS renders any SF Symbol
  (`Builtins.swift:1675`). → Broaden map / better fallback.
- [ ] **21. `text` ignores `format`/`total`.** iOS `format:"elapsed"|"remaining"`
  → clock (`Builtins.swift:1480`). Android renders raw decimals (`Builtins.kt:386`).
- [ ] **22. `textfield` is plain.** Ignores keyboardType/status/helper/icon/
  textContentType (`Builtins.kt:126-146` vs `Builtins.swift:1722-1846`). → Add.

## P2 — minor / cosmetic
- [ ] **23. `scroll`** ignores `showsIndicators` (iOS defaults hidden) +
  collapsing/pinned/sections/behavior/hero/revealOnPull (`Builtins.kt:317` vs
  `Builtins.swift:278-737`).
- [ ] **24. `pager`** no per-page horizontal padding, no reduce-motion pause
  (`Builtins.kt:236` vs `Pager.swift:38-60`).
- [ ] **25. `toggle`** hand-built Row+Switch vs native `Toggle` metrics
  (`Builtins.kt:106`).
- [ ] **27. Hardcoded `0xFF0A84FF` accent fallback** in button/chart/rings/progress/
  slider (`Builtins.kt:435`, `DataViz.kt:126,162,375,424`) — won't follow a host
  accent. iOS uses `.accentColor`.
- [ ] **28. Screen chrome not wired:** no `onDisappear`, no immersive `chrome`, no
  pull-to-refresh around `screen.refresh`, no nav title (`SduiScreen.kt:218-251`).
- [ ] **29. contextMenu gesture conflict:** dropdown long-press +
  `onLongPress` register two detectors (`SduiModifiers.kt:134-179`). iOS uses one
  native `.contextMenu`.

## Suggested batches
1. **Images + press-feel** (#1, #5) — biggest perceived-quality jump.
2. **Modifier surface** (#2, #3, #9, #11, #12, #13) — one model+modifier PR.
3. **State correctness** (#7, #8) + **actions** (#6).
4. **Layout defaults + spacer/grid** (#14, #16, #17).
5. **Rich components** (#15 list, #19 chart, #18 disclosure, #22 textfield).
6. **Scroll chrome + screen chrome** (#23, #28) and cosmetics.

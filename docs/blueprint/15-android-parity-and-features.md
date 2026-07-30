# 15 — Android Parity & Feature Roadmap

**Status:** Actionable plan, 2026-07-30. Branch `sdui-parity-and-fixes`.
**Owner north-star:** one JSON contract → visually + behaviourally identical screens on iOS, Android, Aurora. This doc ranks every gap by *visible impact* and gives file:line + code for each fix.

Companion docs: `06-collapsing-scroll.md` (iOS jank punch-list), `14-android-bestpractices-audit.md`.

---

## 0. How to read this

Four sections, in the order you should work them:

1. **CRASHES** — latent runtime failures, fix before anything else.
2. **Parity gaps ranked by visible impact** — nav chrome, collapsing/Weather scroll, context-menu actions, card design. Each with a concrete Android **and** iOS fix.
3. **Missing components / features / actions** — prioritized backlog to grow the contract (from DivKit / Adaptive Cards / Beagle / large apps).
4. **The Apple-Weather scroll motion spec** — precise numbers, one contract → identical on both platforms.

Every code path funnels through **one file first**: `spec/schema/sdui.schema.json` (the contract), then identical interpreters in `ios/Sources/SDUIRender/` and `android/sdui/src/main/java/dev/sdui/render/`.

---

# SECTION 1 — CRASHES (fix first)

The reported *"Settings tab crashes on switch"* **does not reproduce** on the current branch (verified live on Pixel_10 emulator, `dev.sdui.demo`: Settings renders fully, picker opens, rapid tab-switching stays alive, zero `FATAL EXCEPTION` in logcat). It was resolved by the recent greedy-spacer / bottom-tab-bar / rounded-corners / inset-padding commits. The only cost is a ~10.7 s debug cold-start that can *look* like a hang.

But there is **one genuine latent crash**, currently masked only by hand-set fixed heights in the bundled JSON:

### C1 — `list` (LazyColumn) nested inside `scroll` (verticalScroll) throws

- **Where:** `android/sdui/src/main/java/dev/sdui/render/Builtins.kt:378-406` (`ListView` always emits `LazyColumn`) inside `Builtins.kt:362-376` (`ScrollView` wraps child in `Modifier.verticalScroll`).
- **Failure:** a vertical `LazyColumn` measured under `verticalScroll` throws
  `java.lang.IllegalStateException: Vertically scrollable component was measured with an infinity maximum height constraints`.
- **Why it hasn't fired:** every nested-list screen dodges it with an explicit fixed height — `table.json` list `size.height:420`, `lists.json` `460`, `gestures.json` `220`. Remove any one and that screen crashes instantly. This is a costyl guarantee that depends on every author hand-setting a height on every nested list — violates the "hard-validation, no-hacks" principle and will crash the first designer-authored screen that omits it.
- **Fix (mirror the sibling that already got it right):** `GridView` at `Builtins.kt:184` deliberately avoids `LazyVerticalGrid` (comment: *"a LazyVerticalGrid would be measured with unbounded height and crash"*) and renders a non-lazy chunked `Column`. `ListView` must do the same: when the list has **no bounded height** (no `size.height` / `frame.height`), render rows/template in a plain `Column`, not `LazyColumn`. Reserve `LazyColumn` for the root / height-bounded case. This also matches iOS, where a `list` inside a scroll lays rows into the VStack rather than nesting a second scroll view.

```kotlin
// Builtins.kt ListView — sketch
val bounded = component.sizeHasFixedHeight()   // size.height / frame.height present
if (bounded) {
    LazyColumn(state = rememberLazyListState(), modifier = ...) { /* pipeline, see F2 */ }
} else {
    Column(modifier = ...) { items.forEach { row -> ctx.registry.Render(row, ctx) } }
}
```

**Cleared on audit (no crash):** `DataViz.kt:176,178` `minOrNull()!!/maxOrNull()!!` (guarded by empty-check at :175); all parser throws (swallowed by `SduiParser.decodeOrNull` in `Playground.kt:81`); tab scaffold fallbacks (`Playground.kt:184-186`); two-way controls with missing `$state` (all coerce to a default — `Builtins.kt:141,155`, `Picker.kt:56`).

---

# SECTION 2 — PARITY GAPS (ranked by visible impact)

## P1 — Collapsing / Apple-Weather scroll: **Android has NONE of it** (biggest gap in the app)

This is the single largest parity break, and it's invisible to the parity matrix because that counts component *presence* (`scroll` exists on both), not *behaviour*.

### Evidence
- **iOS:** five hand-authored scroll bodies in `ios/Sources/SDUIRender/Builtins.swift` — `collapsingBody` (:563/:572), `sectionsBody` (:420/:429, Weather-style pinned accordion via `LazyVStack(pinnedViews:[.sectionHeaders])` :451), `pinnedBody` (:517/:526), `behaviorBody` (:635/:644, synthesized title with smoothstep `p*p*(3-2p)` at :646), `plainBody` (:329/:338). Nav-bar cross-fade in `ScrollHeader.swift:51-124`, applied at `SDUIScreenView.swift:279`.
- **Android:** `ScrollView` at `Builtins.kt:361-376` is a bare `Box(Modifier.verticalScroll(rememberScrollState()))` reading only `axis` + `child`. It **ignores** `collapsingHeader`, `pinnedHeader`, `sections`, `collapsingHero`, `lead`, `showsIndicators`, `onReachEnd`, and screen-level `scrollBehavior`. `ListView` (:379-406) is a bare `LazyColumn` with **no `stickyHeader`**. There is **no `Scaffold`/`TopAppBar` anywhere** — grep for `nestedScroll|Collapsing|LargeTopAppBar|scrollBehavior|stickyHeader|TopAppBar` across `android/` returns **zero hits**. The Android `Screen` model (`Models.kt:31-56`) has no `scrollBehavior` field at all.
- **Schema is also behind iOS:** `spec/schema/sdui.schema.json:314-332` (`ScrollProps`) documents only `collapsingHeader`; `pinnedHeader`, `sections`, `collapsingHero`, `lead`, `sectionSpacing`, `sectionRadius`, `cardColor`, `sectionHeaderColor`, `pinnedHeaderStyle`, `pinnedHeaderAlign` that iOS reads (`Builtins.swift:286-292,421-529`) are undocumented. Fix schema in the same pass.

### Architecture: mirror iOS's "delegate to framework when you can, synthesize when you can't"
iOS uses the **native** OS large-title collapse (`sduiLargeTitle`) for the plain large-title case and only hand-synthesizes when the effect needs something native can't do (`revealOnPull` search, `subtitle` under the big title). Android must make the identical split:

| Contract input | iOS path | Android path (identical result) |
|---|---|---|
| `scrollBehavior` default (`largeTitle` true, no subtitle/reveal) | native `.large`, OS collapse | `LargeTopAppBar` + `exitUntilCollapsedScrollBehavior` in `Scaffold` |
| `scrollBehavior.largeTitle:false` | inline title | `TopAppBar` + `pinnedScrollBehavior` |
| `scrollBehavior.subtitle` / `revealOnPull` | `behaviorBody` (`Builtins.swift:644`) | hand-built collapsing header inside scroll (offset-driven) |
| `pinnedHeader` | `pinnedBody` (`Builtins.swift:526`) | `LazyColumn { stickyHeader{} ; items{} }` |
| `sections` (+`collapsingHero`,`lead`) | `sectionsBody` (`Builtins.swift:429`) | `LazyColumn { lead ; sections.forEach{ stickyHeader{header}; items{content} } }` + hero in pinned top slot |
| `collapsingHeader.expanded/compact` | `collapsingBody` (`Builtins.swift:572`) | offset-driven overlay header, `graphicsLayer` scale + cross-fade |

The **load-bearing decision:** the large-title case goes through Material3 (`nestedScroll(scrollBehavior.nestedScrollConnection)` on the `Scaffold`), **not** a hand-rolled offset animation — otherwise the motion curve differs from every other Material app. Bespoke cases stay hand-built, exactly as iOS hand-builds them.

### Android build — Tier A (common case, `LargeTopAppBar`)
The `scrollBehavior` is **screen-level** (iOS injects it via `@Environment(\.sduiScrollBehavior)`). So the `Scaffold`+`TopAppBar` belongs in `SduiScreen.kt`, and the behavior reaches the inner scroll via a `CompositionLocal`:

```kotlin
val LocalScrollBehavior = compositionLocalOf<TopAppBarScrollBehavior?> { null }

// SduiScreen.kt
val behavior = screen.scrollBehavior
val topBehavior = when {
    behavior == null -> null
    behavior.largeTitle != false && behavior.subtitle == null && behavior.revealOnPull == null ->
        TopAppBarDefaults.exitUntilCollapsedScrollBehavior(rememberTopAppBarState())
    else -> null   // subtitle/reveal → synthesized in-scroll (Tier B)
}
Scaffold(
    modifier = topBehavior?.let { Modifier.nestedScroll(it.nestedScrollConnection) } ?: Modifier,
    topBar = { /* SduiTopBar, see P2 */ },
) { padding ->
    CompositionLocalProvider(LocalScrollBehavior provides topBehavior) {
        Box(Modifier.padding(padding)) { ctx.registry.Render(screen.root, ctx) }
    }
}
```
`LargeTopAppBar` expanded ≈ **152.dp**, collapsed **64.dp**; `collapsedFraction` (= `heightOffset / heightOffsetLimit`) is the `p` analog. This gives Dynamic-Type-correct, system-buttery collapse with a correct two-slot title cross-fade for free.

### Android build — Tier B (staged Weather hero, `collapsingHero` / `subtitle` / `revealOnPull`)
Direct analog of iOS `behaviorBody`/`collapsingBody`: offset → progress → per-element `graphicsLayer` (layout-free, the Compose twin of `visualEffect` — no layout pass during scroll):

```kotlin
val headerOffset = remember { mutableStateOf(0f) }          // -rangePx..0
val conn = remember { object : NestedScrollConnection {
    override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
        val prev = headerOffset.value
        headerOffset.value = (prev + available.y).coerceIn(-rangePx, 0f)
        return Offset(0f, headerOffset.value - prev)
    }
}}
// p = smoothstep(-headerOffset.value / rangePx)  — see Section 4 for the staged segments
```
`onebone/compose-collapsing-toolbar` (565★) `parallax/pin/road` map 1:1 to temp/city/condition — use as reference or dependency.

### Pinned sections & pitfalls
- Sticky: `LazyColumn { stickyHeader { HeaderCard() }; items(rows){} }` — direct twin of iOS `pinnedViews:[.sectionHeaders]`. `stickyHeader` is still `@ExperimentalFoundationApi` — add the opt-in.
- **Scaffold inset gotcha:** apply `Scaffold`'s `innerPadding` as `LazyColumn(contentPadding = …)`, not around it, or the sticky header slides under the bar ([efe budak](https://efebu.medium.com/compose-multiplatform-making-sticky-headers-play-nice-with-scaffolds-a2da267b1e78)).
- **Decode once:** iOS caches decoded slots (`Builtins.swift:206-208,318-335`); on Android `remember { component.prop(...).decode() }`, never decode inside `derivedStateOf`.
- **`derivedStateOf` for progress:** read `firstVisibleItemIndex`/`firstVisibleItemScrollOffset` inside `derivedStateOf` so recomposition fires only when the derived value changes.
- **Transparent-by-default backgrounds:** pin headers transparent unless `material`/`cardColor` set (iOS `Builtins.swift:520-525,546-552`) — no stray tinted band on dark screens.

### iOS side of this parity item
iOS *has* the mechanism but with doc-06 polish gaps: raw-linear progress on the visual paths (should be smoothstep everywhere — see Section 4), opacity-faked blur (should intensify the material), no hairline separator, no parallax, no snap, hardcoded 34/42pt. Fix by reading the shared spec numbers instead of hardcodes.

**Sources:** [exyte/ScalingHeaderScrollView ~1.5k★](https://github.com/exyte/ScalingHeaderScrollView) · [onebone/compose-collapsing-toolbar 565★](https://github.com/onebone/compose-collapsing-toolbar) · [ssamadgh/FluentCollapsingHeaderView](https://github.com/ssamadgh/FluentCollapsingHeaderView) · [barabasizsolt/ComposeCollapsingToolbar](https://github.com/barabasizsolt/ComposeCollapsingToolbar) · [Katkov — Compose header like iOS Weather](https://medium.com/@eloorus/jetpack-compose-header-animation-like-in-ios-weather-app-b65af47c7bbc) · [Android App bars (Material3)](https://developer.android.com/develop/ui/compose/components/app-bars) · [Android Lists (stickyHeader)](https://developer.android.com/develop/ui/compose/lists) · [Nishanth — Material3 collapsing toolbar](https://medium.com/@snishanthdeveloper/mastering-collapsing-toolbar-with-jetpack-compose-the-modern-way-material-3-lazycolumn-59c52c70a005) · [Katie Barnett — ProAndroidDev](https://proandroiddev.com/creating-a-collapsing-topappbar-with-jetpack-compose-d25ad19d6113) · [Azzouzi — parallax + curved motion](https://proandroiddev.com/collapsing-toolbar-with-parallax-effect-and-curve-motion-in-jetpack-compose-9ed1c3c0393f) · [AppleInsider — Weather animation](https://appleinsider.com/articles/13/06/18/inside-ios-7-apples-weather-app-gets-animated).

---

## P2 — Navigation chrome: no configurable nav bar exists on ANY platform (contract gap first)

### Evidence
- **Android nav is a hand-rolled `Row` in the demo host, not the renderer.** `android/app/.../Playground.kt:198-214`: title is **left-aligned** jammed against the word **"‹ Back"** (spelled out), **no trailing actions slot**, lives in `android/app` not `android/sdui`, no collapsing large title.
- **iOS** uses native `NavigationStack` chrome from inside the SDK (`SDUIScreenView.swift:279`, `ScrollHeader.swift:56-79`): centered inline title + back chevron + large-title collapse all free. But its only toolbar items are **hard-coded** (`fullScreenCover` "Close" `Navigation.swift:141-143`, subtitle principal `ScrollHeader.swift:110-119`).
- **Critical:** there is **no `nav`/toolbar contract at all**. Grep `spec/schema/sdui.schema.json` for `"nav"`, `leading`, `trailing`, `toolbar` at screen level → nothing. `Screen` (`spec/types/sdui.d.ts:5-35`) exposes only `title`, `chrome`, `scrollBehavior`. **Configurable trailing action icons are impossible to express in JSON on any platform today.**
- **Existing asset:** SF-Symbol→Material mapper `materialIcon(sf: String)` at `android/sdui/.../DataViz.kt:250+` (~100 symbols). Route nav icons through it.

### Precedent
**ZupIT Beagle** (`ZupIT/beagle-android`, org ~668★) validates the shape almost exactly: `Screen.navigationBar { title, showBackButton, styleId, navigationBarItems: List<{image, text, action, accessibility}> }`. Adopt its spirit. (DivKit 2.7k★ deliberately leaves chrome to the host — the fallback stance, not what we want. Epoxy 8.6k★ is list infra, no nav precedent.)

### Proposed contract (add optional `nav` to `Screen`; `title` stays as fallback)
```jsonc
"nav": {
  "title":      "$data.product.title",       // BindableString; falls back to screen.title
  "largeTitle": true,                          // collapse-on-scroll (supersedes scrollBehavior.largeTitle)
  "hidden":     false,                          // edge-to-edge
  "leading":  { "icon": "chevron.left", "label": "Back", "action": { "action": "dismiss" } },
  "trailing": [
    { "icon": "square.and.arrow.up", "action": { "action": "share", "text": "$data.product.url" }, "accessibilityLabel": "Share" },
    { "icon": "ellipsis", "action": { "action": "custom", "name": "menu" }, "accessibilityLabel": "More" }
  ]
}
```
Reuse `$defs/Action` verbatim; `icon` reuses the SF-Symbol vocabulary. Define `NavItem = { icon, label?, action?, role?, accessibilityLabel? }`. **Parity rule (document in schema):** `trailing` renders left→right in array order, right-aligned, on both platforms.

### iOS fix (small addition to `SDUIScrollHeaderChrome`)
```swift
.toolbar {
    if let leading = nav?.leading {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { dispatch(leading.action ?? .dismiss) } label: {
                Label(leading.label ?? "", systemImage: leading.icon ?? "chevron.left").labelStyle(.iconOnly)
            }
        }
    }
    ToolbarItemGroup(placement: .navigationBarTrailing) {
        ForEach(nav?.trailing ?? []) { item in
            Button(role: item.role == "destructive" ? .destructive : nil) { dispatch(item.action) }
                label: { Image(systemName: item.icon) }.accessibilityLabel(item.accessibilityLabel ?? "")
        }
    }
}
```
`nav.hidden` → `.toolbar(.hidden, for: .navigationBar)` (helper `AvailabilityCompat.swift:167`).

### Android fix (move nav INTO the renderer; delete `Playground.kt`'s `NavBar`)
```kotlin
@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun SduiTopBar(nav: NavConfig?, fallbackTitle: String, canGoBack: Boolean,
                                    onBack: () -> Unit, dispatch: (Action) -> Unit) {
    if (nav?.hidden == true) return
    val title = nav?.title ?: fallbackTitle
    val navIcon: @Composable () -> Unit = {
        when {
            nav?.leading != null -> IconButton(onClick = { nav.leading.action?.let(dispatch) ?: onBack() }) {
                Icon(materialIcon(nav.leading.icon ?: "chevron.left"), nav.leading.label, tint = colorScheme.primary) }
            canGoBack -> IconButton(onClick = onBack) {
                Icon(Icons.Filled.ChevronLeft, "Back", tint = colorScheme.primary) }   // thin chevron, NOT ArrowBack
        }
    }
    val actions: @Composable RowScope.() -> Unit = {
        nav?.trailing.orEmpty().forEach { item ->
            IconButton(onClick = { dispatch(item.action) }) {
                Icon(materialIcon(item.icon), item.accessibilityLabel, tint = colorScheme.primary) } }
    }
    if (nav?.largeTitle == true)
        LargeTopAppBar(title = { Text(title) }, navigationIcon = navIcon, actions = actions, scrollBehavior = /* hoisted */)
    else
        CenterAlignedTopAppBar(title = { Text(title, fontWeight = FontWeight.SemiBold) },   // CENTERED (fixes left-align)
                               navigationIcon = navIcon, actions = actions)
}
```
Extend Kotlin `Screen` (`Models.kt:31`) with `val nav: NavConfig? = null` + `@Serializable NavConfig(title, largeTitle, hidden, leading: NavItem?, trailing: List<NavItem> = emptyList())`, mirroring Swift/TS 1:1.

### The four fixes
| # | Gap (evidence) | Fix |
|---|---|---|
| 1 | Title left-aligned next to "Back" (`Playground.kt:212`) | `CenterAlignedTopAppBar` |
| 2 | Spelled-out "‹ Back" (`Playground.kt:207`) | `Icons.Filled.ChevronLeft` tinted `primary`, icon-only |
| 3 | No trailing actions; no `nav` in schema | Add `Screen.nav.trailing:[{icon,action}]` to schema + both models; render via `actions: RowScope` / `ToolbarItemGroup(.navigationBarTrailing)`, icons via `materialIcon()` |
| 4 | Bar in demo host; Android `Screen` has no `scrollBehavior` | Move bar into `android/sdui` `SduiScreen`; `nav.largeTitle` → `LargeTopAppBar` + `exitUntilCollapsedScrollBehavior` |

**Sources:** [Material3 TopAppBar](https://composables.com/material3/topappbar) · [CenterAlignedTopAppBar](https://composables.com/material3/centeralignedtopappbar) · [alexzh — TopAppBar variants](https://alexzh.com/visual-guide-to-topappbar-variants-in-jetpack-compose/) · [ZupIT Beagle](https://github.com/ZupIT/beagle-android) · [gitstar-ranking ZupIT](https://gitstar-ranking.com/ZupIT) · [DivKit 2.7k★](https://github.com/divkit/divkit) · [Airbnb Epoxy 8.6k★](https://github.com/airbnb/epoxy).

---

## P3 — Context-menu actions: menu often never opens (gesture-arena conflict) + item divergence

The reported *"many actions don't work on opening the context menu"* is **not** the dispatch — it's that **the menu frequently never opens**.

### Evidence
- **iOS** (`Modifiers.swift:464-476`): `.contextMenu` is backed by `UIContextMenuInteraction` at the UIKit layer — it does **not** compete in the gesture arena with `.onTapGesture`/`Button`/swipe. Renders each item with SF-Symbol icon (`Label(systemImage:)`) + destructive role (red) + haptic + floating preview.
- **Android** (`SduiModifiers.kt:387-412`): `contextMenuHost` stacks its **own** `detectTapGestures(onLongPress = { expanded = true })` on an outer `Box`, while `content` inside already carries `gestureModifier`'s **inner** `detectTapGestures(onTap, onLongPress)` (`:353-365`) and, when the node has a `swipe`, `SwipeReveal`'s drag detector.

### Defect 1 (ROOT CAUSE) — two-to-three gesture detectors on one node
Per docs, `detectTapGestures` consumes the gesture on long-press, and children are dispatched before ancestors — so the **inner** detector wins: on any node that also has `onTap`/`onLongPress` (nearly every card/row), the inner long-press fires its own callback and consumes the event, so the outer `expanded = true` **never runs**. On a node with a `swipe` (exactly `03-inbox.json:560`, which has both `swipe` **and** `contextMenu`), the drag detector competes too. Nondeterministic — "sometimes nothing, sometimes the wrong thing" — the exact reported symptom. Dispatch itself is fine (`SduiScreen.kt:232-239` uses a screen-scoped scope that outlives menu close).

### Defect 2 — item rendering diverges
`DropdownMenuItem` (`SduiModifiers.kt:402-407`) drops **both** `item.icon` and `item.role`. iOS shows the SF Symbol + red destructive text. (Compounding: Android has no SF-Symbol→Material registry in the base `icon` path either — `Builtins.kt:598-604` renders the raw symbol name as text.)

### Defect 3 — wrong anchoring, no open haptic, no preview
Material `DropdownMenu` anchors at parent top-start, not the press point; no preview; no haptic on open.

### Fix — merge the detectors into one
1. In `gestureModifier`, when `modifiers.contextMenu` is non-empty, hoist `expanded` and make the **single** `onLongPress` do: `performHapticFeedback(LongPress)` → if `contextMenu` exists `expanded = true` else dispatch `onLongPress`. Guarantees exactly one long-press owner → menu opens 100%. Prefer the community-standard `combinedClickable(onClick, onLongClick)` single-node pattern.
2. Drive the `DropdownMenu`'s `expanded` from that shared state; **remove the outer `detectTapGestures`** entirely.
3. Restore item parity: `leadingIcon = { Icon(materialIcon(item.icon), null) }`; `colors = MenuDefaults.itemColors(textColor = if (item.role=="destructive") colorScheme.error else …)`; add `contentDescription`.
4. Contract note: define precedence when a node has **both** `onLongPress` and `contextMenu` — rule: "contextMenu present ⇒ long-press opens the menu." Add a conformance fixture on a node with `contextMenu` + `onTap` + `swipe` (the `03-inbox.json:560` shape) to lock the regression.

### Related — action-vocabulary gaps (Android silently no-ops vs iOS)
Comparing `ActionInterpreter.kt:82-175` vs `ActionInterpreter.swift:128-278`:

| Verb | iOS | Android | Status |
|---|---|---|---|
| `requireVersion` | ✅ `swift:224-244` | ❌ `else → log` (`kt:174`) | **BROKEN — silent no-op** |
| `requestPermission` | ✅ `swift:246-274` (priming→prompt→resultKey→onGranted/onDenied) | ❌ silent no-op | **BROKEN — silent no-op** |

The Android `ActionHost` (`kt:23-66`) also lacks `requireVersion`/`shouldPrime`/`presentPriming`/`requestPermission` (iOS declares them `swift:95-104`, defaults `:110-116`). Any screen or menu item using these does nothing on Android; `resultKey`/`onGranted`/`onDenied` never fire. **Fix:** add both cases to `ActionInterpreter.kt` mirroring the Swift orchestration + extend the Kotlin `ActionHost` with the four methods (default no-op). Also pin a fixture that both platforms run `parallel` sequentially (`kt:89-90`, `swift:132-137`) so they can't drift.

**Files:** `android/sdui/.../SduiModifiers.kt` (merge gesture detectors ~L353+L387; add icon/role/haptic), `android/sdui/.../runtime/ActionInterpreter.kt` (add two verbs + four host methods).

**Sources:** [Android — Tap and press](https://developer.android.com/develop/ui/compose/touch-input/pointer-input/tap-and-press) · [Android — Understand gestures](https://developer.android.com/develop/ui/compose/touch-input/pointer-input/understand-gestures) · [detectTapGestures ref](https://composables.com/docs/androidx.compose.foundation/foundation/functions/detectTapGestures) · [ProAndroidDev — How Gestures Work](https://proandroiddev.com/android-touch-system-part-5-how-gestures-work-in-jetpack-compose-ef7e74703b6a) · [dev.to — Context Menu in Compose](https://dev.to/myougatheaxo/context-menu-in-compose-long-press-menu-bottomsheet-actions-selection-mode-4g21) · [openillumi — combinedClickable fix](https://openillumi.com/en/en-compose-button-long-press-combined-clickable/).

---

## P4 — Card design: four shared code paths translate identical JSON into different pixels

Compose BOM 2024.09.02 → Compose UI 1.7.x (`android/sdui/build.gradle.kts:51`). Centralize parity in **two shared helpers** — `SduiShapes.rounded(radius, pill)` and `Modifier.sduiDropShadow(shadow, radius)` — used by `SduiModifiers.kt` and every `Builtins.kt`/`DataViz.kt` call site.

### D1 — Corner shape: continuous squircle (iOS) vs circular arc (Android) — affects EVERY card
- **iOS:** `RoundedRectangle(cornerRadius:r, style:.continuous)` everywhere (`Modifiers.swift:339`; `Builtins.swift:255,678,1338,1800…`). G2-continuous superellipse.
- **Android:** `RoundedCornerShape(r)` — pure circular arc, G1 (`SduiModifiers.kt:243,256`; `ButtonView` `Builtins.kt:588`, dots :296, image clip :483).
- **Symptom:** at `radius.md=16`/`radius.lg=22` the corner shoulder is visibly tighter on Android — home Live cards, cart rows (`cart.json:162`), messenger bubbles (`cornerRadius:20`). Full-pill chips (`radius.pill=999`) unaffected.
- **Fix:** vendor a `SmoothRoundedCornerShape` (Skia superellipse) or add `racra/smooth-corner-rect-android-compose` (74★) / `c5inco/smoother` (32★). Replace `RoundedCornerShape(r)` with `SduiShapes.rounded(r)` everywhere; gate on `r >= 999 → CircleShape`.

### D2 — Shadow: offset+blur+tint drop (iOS) vs elevation approximation (Android)
- **iOS** (`Modifiers.swift:396-408`): `.shadow(color, radius, x, y)` — true colored offset soft shadow.
- **Android** (`SduiModifiers.kt:301-319`): `Modifier.shadow(elevation = blur*0.6f coerceIn 2..16, …)` — **offset dropped** (`Modifier.shadow` has no x/y; `offsetX/offsetY` read at :305-306 then never used), blur→elevation lossy+capped, tint modulated by API-28 elevation.
- **Symptom:** home Live card (`home.json:531-536`: `radius:14,y:8,color:#5B5BF033` — a blue glow pushed 8pt down) renders as symmetric grey; cart checkout bar (`cart.json:601`: `y:-6` upward lift) renders flat.
- **Fix:** hand-draw with `drawBehind` + `BlurMaskFilter(radius, NORMAL)` translated by `(x,y)` at the real color alpha, clipped to the smooth shape — map contract `radius`→sigma directly. (Comment at :308-311 blames a prior grey-blob attempt — that was untuned, not a reason to drop offsets.) Alternatively bump BOM to 1.9+ for `Modifier.dropShadow(shape, offset, blurRadius, color)`; hand-drawn gives exact parity today.

### D3 — Material/frost adaptive (iOS) vs always-white (Android) — breaks dark mode
- **iOS** (`Modifiers.swift:353-377`): real `.ultraThinMaterial….bar`, adapts light/dark + blurs backdrop.
- **Android** (`SduiModifiers.kt:268-282`): hardcoded white translucent fill + white rim, any theme.
- **Symptom:** dark mode `material` surfaces show a milky white veil vs iOS's dark pane — opposite tints.
- **Fix:** read `$env.theme` (already in `Theme`, iOS `Theme.swift:34`); use a dark translucent base in dark mode. For real blur on API 31+ layer `RenderEffect.createBlurEffect` via `graphicsLayer { renderEffect = … }`. Minimum: flip base color by theme.

### D4 — Button press: Material ripple+elevation (Android) vs spring-scale (iOS)
- **iOS:** every tappable inherits `SDUIPressableStyle` (`Modifiers.swift:414-430`): scale 0.955, brightness −0.045, spring, light haptic. No ripple.
- **Android:** `button` via Material3 `Button` (`Builtins.kt:584-596`) → ripple + tonal elevation; because `onTap` is a *prop* (not `modifiers.onTap`), the `gestureModifier` press scale/haptic **never applies**. Same ripple leak in `DropdownMenuItem` (:400), `Switch` (:144), `OutlinedTextField` (:160). (Generic cards/rows *are* consistent — Android uses `detectTapGestures` with no `clickable{}`.)
- **Fix:** render `button` as a styled `Box` with the shared smooth shape + `sduiModifiers` press (scale+haptic), or keep `Button` with `elevation = 0` + disable ripple (`LocalIndication provides null`) and overlay the shared press-scale. Option (a) is cleaner and reuses D1's helper.

### D5 — Divider thickness/color
- **iOS** `Builtins.swift:1473-1477`: hairline (~0.33pt on 3×) in system separator color.
- **Android** `Builtins.kt:417-425`: Material3 `HorizontalDivider` default 1.dp in `outlineVariant` — thicker + different default color.
- **Fix:** `thickness = Dp.Hairline`, default color `$token.color.separator` not `outlineVariant`.

**Priority within P4:** D1 + D2 (every card) → D4 (signature interaction) → D3 (dark mode) → D5.

**Sources:** [Add shadows in Compose](https://developer.android.com/develop/ui/compose/graphics/draw/shadows) · [shadow API ref](https://composables.com/docs/androidx.compose.ui/ui/modifiers/shadow) · [Practicing Shadows in Compose](https://kimmandoo.medium.com/practicing-shadows-in-jetpack-compose-elevation-drop-shadow-0999e4500acb) · [Art of Shadows](https://proandroiddev.com/the-art-of-shadows-in-jetpack-compose-63a75070882f) · [SwiftUI Continuous Corners (Sarunw)](https://sarunw.com/posts/swiftui-rounded-corners-view/) · [racra/smooth-corner-rect (74★)](https://github.com/racra/smooth-corner-rect-android-compose) · [c5inco/smoother (32★)](https://github.com/c5inco/smoother) · [wsxyeah/ContinuousRoundRect](https://github.com/wsxyeah/ContinuousRoundRect).

---

# SECTION 3 — MISSING COMPONENTS / FEATURES / ACTIONS (prioritized backlog)

Contract today (`spec/schema/sdui.schema.json`): **30 components** (:97-126), **24 actions** (:618-621), simple `$state.<key>` binding, `DataSource`/`AsyncProps`, `Condition`. **No expression language, no typed variables, no templates, no patch/partial-update.**

## F — RUNTIME FUNCTIONALITY (P0, large-app basics that are unimplemented today)

### F1 — `request` action is a NO-OP on both platforms (P0, blocks every write path)
Schema fully specifies it (`sdui.schema.json:638-639`: `source`+`onSuccess`+`onError`), `feed.json:26` uses it — but iOS `ActionInterpreter.swift:129-246` has **no `case "request"`** and Android `ActionInterpreter.kt` falls to `else → log` (~L168). Blocks form submission, server pagination, optimistic updates, retry, debounced search-to-server. **Fix (~20 lines each):** resolve `source` bindings → call existing `host.loadOne(source)` → inject response as `$data.<id>` → dispatch `onSuccess` (or `onError`).

### F2 — Android `ListView` is a raw LazyColumn; the entire list pipeline is missing (P0)
`Builtins.kt:378-406` renders **every** element — no `limit`, `paginateOnScroll`, `onReachEnd`, `empty`, `resultCount`, search/filter/sort. iOS has the full pipeline (`Builtins.swift:939-1160`: `filter→sort→paginate→hasMore→empty slot→shimmer footer→onReachEnd/loadMore`). **Fix:** port it; hoist `rememberLazyListState()`, detect end via `snapshotFlow { listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index }`, render shimmer footer + `empty` slot; optional Paging 3 path behind the same contract. (Interacts with C1 — non-lazy `Column` fallback when unbounded.)

### F3 — Android pull-to-refresh gesture missing (P0)
iOS attaches `.refreshable` when `screen.refresh != nil` (`SDUIScreenView.swift:288`). Android `SduiScreen.kt:250` renders content directly, no gesture. **Fix:** wrap in Material3 `PullToRefreshBox(isRefreshing = model.isLoading, onRefresh = { model.refresh(screen.refresh.sources) })` — `model.isLoading` already exists (`SduiScreen.kt:102`).

### F4 — No screen-level loading/error/empty/retry (P1, both platforms)
`isLoading` tracked (`SDUIScreenView.swift:38`, `SduiScreen.kt:102`) but never consumed → blank/janky first frame, failed top-level fetch shows nothing, no retry. `async` only covers sub-regions. **Fix:** add `screen.data.states:{loading,error,empty}`, expose `loadError`, branch in both screen bodies (skeleton overlay on first load; error slot with `refresh` retry).

### F5 — Pagination has no append/merge (P1)
`feed.json:26-32` "paginates" by `refresh` on the same source → **replaces** `$data.feed`. Contract can't express "fetch page N and append." **Fix (depends F1):** give `request` an `append:"$data.feed.items"` / `merge` strategy — also the substrate for optimistic updates (`setState` immediately → `request` with `onError` rollback).

### F6 — Debounced search not expressible (P2)
`textfield`/`revealOnPull.bind` write `$state` every keystroke; `filterItems` runs per keystroke; `grep debounce` = 0 hits. **Fix:** add `debounceMs` to `textfield`/search props (`snapshotFlow{query}.debounce(ms)` on Android, `Task`+`Task.sleep`+cancel on iOS).

### F7 — `openDeepLink` aliased to `openURL` (P2)
Both interpreters open the OS browser (`swift:156`, `kt:111`) — a deep link that should push an in-app SDUI screen bounces to Safari/Chrome. **Fix:** route through `host.navigate(to:params:)` with a host route parser, kept distinct from `openURL`.

### F8 — No state restoration (P2)
No `rememberSaveable`/`SceneStorage`; process death loses all `$state` (search text, toggles, pagination cursor, scroll offset). **Fix:** back `$state` with `rememberSaveable`/`SavedStateHandle` on Android, persist a snapshot on iOS; hoist a saved `LazyListState`.

**Sources:** [nowinandroid 21.4k★](https://github.com/android/nowinandroid) · [tivi 6.7k★](https://github.com/chrisbanes/tivi) · [Paging 3 codelab](https://developer.android.com/codelabs/android-paging) · [Infinite lists w/ Paging 3](https://proandroiddev.com/infinite-lists-with-paging-3-in-jetpack-compose-b095533aefe6) · [Material3 pull-to-refresh](https://developer.android.com/develop/ui/compose/components/pull-to-refresh) · [Compose loading/error/empty patterns](https://dev.to/myougatheaxo/error-handling-ui-in-compose-error-loading-empty-state-patterns-2dgh).

## T0 — ARCHITECTURAL contract capabilities (every serious competitor has these; we have zero)

### T0.1 — Expression language (P1, highest-leverage authoring win)
Only dynamic value today is `$state.<key>` literal substitution. DivKit ships `@{...}` grammar (arithmetic, comparison, boolean, ternary, string ops, stdlib: `len`, `substring`, `formatDate`, `getColorValue`…). Adaptive Cards has `${}` + `$when` + `$data`. Without it, every trivial derivation ("badge when count>0", "price×qty") round-trips to the server. **Fix:** `Expr` type (`"@{...}"`) accepted anywhere `BindableString` is, plus `visibleIf`/`enabledIf` on `Modifiers`; a **closed function catalog** in schema; identical `ExpressionEvaluator` on both platforms.

### T0.2 — Typed variables + triggers (P1)
`$state` is untyped. DivKit has typed vars (`string,integer,number,boolean,color,url,array,dict`) + triggers `{condition, actions}` that fire on variable change. **Fix:** `Screen.variables:[{name,type,default}]` + `Screen.triggers:[{condition,actions,mode}]`; type `setState`/`increment` in the validator.

### T0.3 — Patch / partial-update (P1, perf+UX ceiling)
`refresh` reloads the whole `DataSource`. DivKit `div-patch` surgically updates one node; enables append-to-list / replace-one-card without re-render (scroll-position loss, flicker today). **Fix:** `patch` action `{target:<id>, mode:"replace|append|prepend|remove|merge", value}` + `PatchResponse` on `request.onSuccess`. Uses existing `Component.id` (:92).

### T0.4 — Templates + `$data` iteration (P1, #1 designer pain + payload size)
No reuse primitive — every list row fully inlined. DivKit templates + Adaptive Cards bind one template to an array. **Fix:** `templates` map on `Screen` + `{type:"ref", template, data}` component + `$data` iteration on `list`/`grid`.

## T1 — MISSING ACTIONS (each ~a few schema lines at `:618-621`)
`copyToClipboard`, typed `setVariable`, array ops (`arrayInsert`/`arrayRemove`/`arraySet`), `dictSetValue`, `focusElement`/`clearFocus`, `showTooltip`/`hideTooltip`, `setStoredValue` (persistent — matches local-cache scope), `animatorStart`/`animatorStop`, pager control (`setCurrentItem`/`setNextItem`/`setPreviousItem` — we have `pager` but no action to drive it), `scrollBy`, form `submit` (aggregate a subtree's inputs → one POST), `toggleVisibility`, `video` control. (Our `sequence`/`parallel`/`condition`/`delay` at :641-645 is *ahead* of Adaptive Cards — keep it.)

## T2 — MISSING COMPONENTS
- **`video`** (P2) — none today; `clips` (:169) is an explicit stand-in ("stand-in for a video/photo URL" :174). Add `{sources[], poster, autoplay, muted, loop, controls}` + video action.
- **`web`** (P2) — no embedded HTML/webview for T&C/help/partner content.
- **`lottie`** (P2) — no animated-vector playback (serves "progress not spinners" design standard). `{source, loop, autoplay, speed, progressBind}`.
- **`map`** (P2) — mentioned as `custom.map` (:91) but no `MapProps`. RU-enterprise (logistics/delivery). Promote to first-class or document as official custom.
- **`tabs`** (P1) — have `pager` but no tab-strip binding a header row to page switching (DivKit `div-tabs` is one of its most-used blocks).
- **`state` container** (P1) — DivKit `div-state`: one node switches among named states (loading/empty/error/content) driven by a variable, with transitions. Backbone of reactivity.
- **Rich text `ranges`** (P2) — `TextProps` is single-style; add `ranges:[{start,end,color,weight,size,action}]` (DivKit text ranges / Adaptive `RichTextBlock`).
- **Input validation** (P1) — no `isRequired`/`regex`/`errorMessage` on `TextFieldProps`; no time picker; no number input with min/max/step. Essential for the `submit`/form story.
- **`table`** (P2) — Adaptive Cards 1.5 `Table` with typed columns for enterprise dashboards (`grid` is uniform cells only).

## T3 — RESILIENCE / LAYOUT
- **`fallback`** (P1, version-rollout must-have) — Adaptive Cards `fallback`; we blank on unknown `type`. Add `Component.fallback: Component | "drop"`. Pairs with the `requireVersion` action.
- **Per-node `requires`** (P2) — min-version/feature gate that triggers fallback (we only have a screen-level `requireVersion` action, :621).
- **`visibleIf`/`enabledIf` on modifiers** (P1, with T0.1).
- **Sizing model audit** — DivKit's explicit `match_parent`/`wrap_content`/`fixed`/`weight` vs our `Dimension` (greedy-spacer class of bug).

### Recommended contract build order
1. `request` (F1) + Android list pipeline (F2) + Android pull-to-refresh (F3) — **P0, "demo → usable".**
2. Expression language + `visibleIf` (T0.1).
3. Typed variables + triggers (T0.2).
4. Patch / partial-update (T0.3).
5. Templates + `$data` iteration (T0.4).
6. Action fills (T1) + screen states/retry (F4) + append semantics (F5).
7. `state` container + `tabs` (T2).
8. `video`/`web`/`lottie`/`map` (T2), `fallback`+`requires` (T3).
9. Rich-text ranges, input validation, `table` (T2).

**Sources:** [divkit/divkit 2,651★](https://github.com/divkit/divkit) · [DivKit div-action](https://divkit.tech/docs/en/concepts/divs/2/div-action) · [DivKit Variables](https://divkit.tech/docs/en/concepts/variables) · [DivKit div-state](https://divkit.tech/docs/en/concepts/divs/2/div-state) · [microsoft/AdaptiveCards 1,959★](https://github.com/microsoft/AdaptiveCards) · [Adaptive Cards Templating](https://github.com/microsoft/AdaptiveCards/issues/2448) · [airbnb/epoxy 8,559★](https://github.com/airbnb/epoxy) · [Lona/Lona 7,544★](https://github.com/Lona/Lona) · [ZupIT Beagle web-core](https://github.com/ZupIT/beagle-web-core) · [Airbnb SDUI deep dive](https://medium.com/airbnb-engineering).

---

# SECTION 4 — THE APPLE-WEATHER SCROLL MOTION SPEC (precise)

There is no official Apple teardown; this is reconstructed from observable behaviour + the best replications, every mechanism mapped to a citable technique. The magic is that **all effects are driven by one scalar (content offset), and each element's effect is a different piece-wise segment of that same 0→1 progress** — condition first, temp second, city promoted, material last.

### The four collapse zones (what to reproduce)
1. **Hero block** — condition + H/L fade/translate first; large temperature shrinks and rises; **city name is the survivor**, promoted to the inline nav title (not just faded).
2. **Pinned module headers** — "HOURLY"/"10-DAY" card headers stick under the nav bar while their rows scroll beneath, pushed off by the next header. Native section-header pinning.
3. **Nav-bar material** — starts transparent; frosted blur + hairline separator fade in over the *last ~20%* of the hero collapse.
4. **Rubber-band top** — pull down stretches hero + background together, springs back. Gated behind Reduce Motion.

### The driver (put these numbers in the contract, both renderers read them)
- `offset` = content scroll offset (pt/dp), 0 at rest, positive scrolling down.
- `range` = `expandedHeroHeight − collapsedBarHeight`. **Defaults: expandedHero 220, collapsedBar 64 → range = 156.**
- `p = smoothstep(clamp(offset / range, 0, 1))`, where `smoothstep(x) = x*x*(3 − 2*x)`.
- **Mandate smoothstep on BOTH platforms.** iOS `behaviorBody` already uses it (`Builtins.swift:646`); the Compose Weather clones and our other iOS visual paths use raw linear — that is the "twitchy" difference. This one easing choice is what makes the two feel the same.
- **Contract convention: `p: 0 = expanded, 1 = collapsed`.** (Normalization trap: exyte + Compose clones use `1=collapsed`; onebone uses `1=expanded`; iOS `behaviorBody` uses `1=collapsed`. Pick one, adapt each renderer, or the platforms interpolate mirror-image.)

### Staged sub-progress (piece-wise remap of `p` — the Apple staggering)
- **Condition + H/L (leaves first, ~first 55pt):**
  `pSecondary = smoothstep(clamp(offset / (range*0.35), 0, 1))`
  `alpha = 1 − pSecondary`, `translateY = −8 * pSecondary`.
- **Large temperature (shrinks + rises, ~125pt):**
  `pTemp = smoothstep(clamp(offset / (range*0.8), 0, 1))`
  `scale = lerp(1.0, 0.42, pTemp)` anchored `.top`, `translateY = −(range*0.55) * pTemp`.
- **City → nav title (promote one element):** city stays `alpha 1` until `p ≥ 0.6`, then two-slot cross-fade over `[0.6, 1.0]`:
  `navTitleAlpha = smoothstep(clamp((p − 0.6) / 0.4, 0, 1))`; in-hero city fades out on the same segment. (Exactly Material3's `collapsedFraction`-keyed title model.)
- **Frosted bar + hairline (appear late):**
  `barAlpha = smoothstep(clamp((p − 0.75) / 0.25, 0, 1))`; the 0.5pt separator uses the same `barAlpha`.
  Blur must **intensify**, not opacity-fade a material: iOS ramps `ultraThin→thin→regular` across `[0.75,1]` (or `scrollEdgeEffectStyle(.hard,for:.top)` on iOS 26+); Compose ramps a `blur`/scrim behind the `TopAppBar` or uses `TopAppBarDefaults.topAppBarColors` `scrolledContainerColor`.
- **Rubber-band (overscroll `offset < 0`):**
  `stretch = 1 + min(−offset, 120) * 0.0016` anchored `.top`, applied to hero + background together; background moves at `0.7×` the hero (parallax depth). Gate the whole stretch behind Reduce Motion → no scale. (iOS has a title-only version at `Builtins.swift:649`; extend to the hero, mirror on Android.)
- **Snap on release:** if `0 < p < 1` when the drag ends, spring `p` → `0` if `p < snapThreshold` (default 0.5) else → `1`. Contract knob `scrollBehavior.snap: "none" | "onRelease" | "afterDeceleration"` (exyte's model). iOS animates `offset` with a spring; Compose calls `scrollBehavior.state.settle` / animates `heightOffset`.

### Sticky module headers (zone 2)
Native pinning on both — iOS `LazyVStack(pinnedViews:[.sectionHeaders])` (already `sectionsBody`, `Builtins.swift:451`); Compose `LazyColumn { stickyHeader {} }`. No offset math — buttery by construction. Both fade in the same 0.5pt bottom hairline when the header pins.

### Reference numbers from the best Compose Weather clone (sanity check)
Katkov ([medium](https://medium.com/@eloorus/jetpack-compose-header-animation-like-in-ios-weather-app-b65af47c7bbc)): maxToolbarHeight **220.dp**, minToolbarHeight **60.dp** (use 64 to match `LargeTopAppBar` small height + iOS nav bar), `onPreScroll` accumulates `toolbarOffsetHeightPx` clamped `[-toolbarDelta, 0]`, list top-padding = min (60), content inset = max − min (160). We upgrade its *linear* alpha to smoothstep.

### Weather-parity recommendation ranking
1. **Build the Android collapse at all** — entirely missing (`Builtins.kt:362-372`). Tier A (`LargeTopAppBar`+`exitUntilCollapsed`+`nestedScroll`) + `stickyHeader` sections first. Highest-impact parity fix in the codebase.
2. **Encode the one shared motion spec** (`range=156`, smoothstep, four staged segments, snap, `p:0=expanded`) in the contract so both renderers read numbers, not hardcodes.
3. **Tier B staged hero on Android** (`NestedScrollConnection` + `graphicsLayer`) matching iOS `behaviorBody` element-by-element.
4. **Parallax + rubber-band + Reduce-Motion gate on both.**
5. **Intensify-blur + hairline-on-pin on both** (doc-06 weaknesses #5/#6, mirrored on Android from day one).
6. **Snap-on-release** as a contract knob.

**Sources:** [AppleInsider — Weather animation](https://appleinsider.com/articles/13/06/18/inside-ios-7-apples-weather-app-gets-animated) · [exyte/ScalingHeaderScrollView ~1.5k★](https://github.com/exyte/ScalingHeaderScrollView) · [onebone/compose-collapsing-toolbar 565★](https://github.com/onebone/compose-collapsing-toolbar) · [ssamadgh/FluentCollapsingHeaderView](https://github.com/ssamadgh/FluentCollapsingHeaderView) · [Katkov — Compose Weather header](https://medium.com/@eloorus/jetpack-compose-header-animation-like-in-ios-weather-app-b65af47c7bbc) · [Android App bars](https://developer.android.com/develop/ui/compose/components/app-bars).

---

## Appendix — Master priority ladder (all sections)

| Rank | Item | Section | Impact |
|---|---|---|---|
| 1 | C1 — guard `list`-in-`scroll` (non-lazy Column fallback) | Crash | Latent crash, masked by hand-set heights |
| 2 | F1 — implement `request` action (both platforms) | F | Unblocks every write path |
| 3 | F2 — port Android list pipeline; F3 — Android pull-to-refresh | F | "demo → usable by a large app" |
| 4 | P1 — Android collapsing/Weather scroll (Tier A + sticky) | Parity | Largest visible parity break |
| 5 | P3 — context-menu gesture-merge + `requireVersion`/`requestPermission` | Parity | "actions don't work" root cause |
| 6 | P4 — card design: D1 squircle + D2 shadow shared helpers | Parity | Every card, every screen |
| 7 | P2 — `Screen.nav` contract + centered bar + trailing icons | Parity | Makes chrome authorable at all |
| 8 | T0.1 expression language + T0.2 variables/triggers | Backlog | Authoring north-star |
| 9 | T0.3 patch, T0.4 templates, T1 action fills | Backlog | Perf + reuse + completeness |

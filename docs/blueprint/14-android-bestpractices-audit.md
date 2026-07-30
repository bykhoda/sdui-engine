# Android renderer — best-practice audit vs. high-star repos

Auditor: senior Android/Compose engineer. Scope: `android/sdui/src/main/java/dev/sdui/render/` + demo app
`android/app/src/main/java/dev/sdui/demo/`. Reference for "should look like": the iOS renderer
(`ios/Sources/SDUIRender/`). Method: for each area, the current best-practice Compose implementation was
located in a high-star repo, compared against our code (cited `file:line`), and a concrete minimal fix given.

**Read-only audit** — no renderer code was changed. Star counts captured 2026-07-30 via GitHub API.

Sources referenced throughout:
- **androidx Compose / Android Developers docs** — the canonical API owner (not "starred", but authoritative).
- [android/nowinandroid](https://github.com/android/nowinandroid) — Google's flagship Compose sample, **21.6k★**.
- [coil-kt/coil](https://github.com/coil-kt/coil) — **11.9k★**.
- [PhilJay/MPAndroidChart](https://github.com/PhilJay/MPAndroidChart) — **38.2k★** (cubic-bezier smoothing reference).
- [patrykandpatrick/vico](https://github.com/patrykandpatrick/vico) — **3.1k★** (Compose-native charts).
- [KevinnZou/compose-swipeBox](https://github.com/KevinnZou/compose-swipeBox) — **103★** (anchoredDraggable swipe-reveal reference).

---

## Prioritized findings table

| # | Area | Our code (file:line) | Issue | Best-practice fix | Source (stars, URL) |
|---|------|----------------------|-------|-------------------|---------------------|
| 1 | **Async images** | `Builtins.kt:477` `SubcomposeAsyncImage` used for every `image`; no `crossfade`, no explicit `memoryCacheKey`/`ImageRequest` | `SubcomposeAsyncImage` uses subcomposition — measurably slower than `AsyncImage`; Coil's own guidance says **avoid it in scrollable lists**. No crossfade → images "pop" instead of iOS's fade. | Use `AsyncImage` with an `ImageRequest.Builder(ctx).data(source).crossfade(true).build()`; keep `Painter`-based placeholder/error (a shimmer `Brush` painter). Reserve `SubcomposeAsyncImage` only for the `skeleton` shimmer case if a composable loader is truly needed. | Coil docs "avoid Subcompose in lists", [coil-kt/coil 11.9k★](https://github.com/coil-kt/coil); [PR #1048 "Improve AsyncImage performance"](https://github.com/coil-kt/coil/pull/1048) |
| 2 | **Bottom nav / tabs** | `Playground.kt:124-148` — single push/pop `Column`, **no tab bar at all** | iOS ships a 4-tab `TabView` (Home `house.fill`, Browse `square.grid.2x2.fill`, Design `circle.hexagongrid.fill`, Settings `gearshape.fill`) — see `ios/.../Landing.swift:30-38`. Android has none → the app doesn't match iOS and loses top-level navigation. | Wrap content in `Scaffold(bottomBar = { NavigationBar { … NavigationBarItem(selected, onClick, icon={filled/outlined}, label) } })`; keep a per-tab back stack. Filled icon when selected, outlined otherwise. | [android/nowinandroid 21.6k★](https://github.com/android/nowinandroid) `NiaNavigationBar`; [Android docs — Navigation bar](https://developer.android.com/develop/ui/compose/components/navigation-bar) |
| 3 | **Charts — smoothing** | `DataViz.kt:201-215` line built with `line.lineTo(...)` (straight segments); comment admits "iOS applies Catmull-Rom smoothing" | Straight polylines look "кривые"/jagged vs iOS's smoothed Swift-Charts curve. This is the single most visible chart gap. | Replace `lineTo` with a **monotone cubic / Catmull-Rom** path: for each segment use `path.cubicTo(cp1, cp2, p)` with control points derived from neighbour slopes (MPAndroidChart's `LineChartRenderer.drawCubicBezier` is the reference algorithm). Gate on a `smooth` prop for parity with iOS. | [MPAndroidChart 38.2k★](https://github.com/PhilJay/MPAndroidChart) cubic bezier; [Vico 3.1k★](https://github.com/patrykandpatrick/vico) spline connectors |
| 4 | **Charts — axes/grid/scale** | `DataViz.kt:173-217` no axes, no gridlines, no zero-baseline; area gradient hard-codes alpha | High-star chart libs always render a baseline + faint gridlines + min/max labels; bare canvas reads as a sketch. Bars (`:184-199`) also don't share the padded coordinate space (`slot` ignores `pad`). | Add optional light gridlines (`drawLine` at n y-fractions, `onSurface @ 0.08`), draw the area fill down to a true zero baseline when `0` is in range, and route bars through the same `px()/py()` transform. | [Vico 3.1k★](https://github.com/patrykandpatrick/vico); [MPAndroidChart 38.2k★](https://github.com/PhilJay/MPAndroidChart) |
| 5 | **Lists — keys** | `Builtins.kt:376` & `:383` `itemsIndexed(items){ _, item -> }` — **no `key`, no `contentType`** | Without stable keys Compose falls back to index → wrong-item recomposition, lost scroll position, broken item animations on data change. Google calls this the #1 lazy-list optimization. | `items(items, key = { it["id"]?.stringValue ?: it.hashCode() }, contentType = { template.type })`. Same for the static-children branch. | [Android docs — Lists (item keys)](https://developer.android.com/develop/ui/compose/lists#item-keys); [nowinandroid 21.6k★](https://github.com/android/nowinandroid) |
| 6 | **Lists — item animation** | `Builtins.kt:376` no `Modifier.animateItem()` | Insertions/removals/moves snap instead of animating. iOS list mutations animate. | Add `Modifier.animateItem()` to the template root inside `items{}` (requires the key from #5). | [Android docs — animate list items](https://developer.android.com/develop/ui/compose/lists#item-animations) |
| 7 | **Swipe-to-reveal** | `SwipeReveal.kt:64-108` hand-rolled `Animatable` + `detectHorizontalDragGestures`; **`scope.launch { snapTo() }` per drag delta** (`:103`); no velocity-aware settle; no `semantics` actions | Launching a coroutine on every drag event is wasteful and can drop frames; snap decision (`:92-93`) uses position only, ignoring **fling velocity** — so a fast flick that hasn't crossed 50 % won't open (feels sticky vs iOS). No accessibility custom actions → swipe actions are invisible to TalkBack. | Migrate to `Modifier.anchoredDraggable` + `AnchoredDraggableState` (the canonical Foundation 1.6+ API): it does velocity-based settling, `positionalThreshold`, and `velocityThreshold` for you, and drives offset without per-event coroutines. Add `Modifier.semantics { customActions = … }` exposing each action. | [Android docs — migrate to AnchoredDraggable](https://developer.android.com/develop/ui/compose/touch-input/pointer-input/migrate-swipeable); [KevinnZou/compose-swipeBox 103★](https://github.com/KevinnZou/compose-swipeBox) |
| 8 | **Press feedback / ripple** | `SduiModifiers.kt:328-367` custom `graphicsLayer` scale+alpha, fires `HapticFeedbackType.LongPress` **on every tap-down** (`:358`); no ripple/`indication` | Firing the `LongPress` haptic on a normal press is the wrong constant (heavy buzz on every tap) and un-Android; there is also **no Material ripple**, which Android users expect as the primary press affordance. iOS-style scale is a nice bonus but should not *replace* the ripple. | Keep the scale/dim, but (a) use `HapticFeedbackType.TextHandleMove`/a light constant or drop the tap haptic (reserve haptics for long-press/commit), and (b) add `Modifier.indication(interactionSource, ripple())` feeding a `MutableInteractionSource` that also drives the press scale via `collectIsPressedAsState()`. `ripple()` is now a non-composable reusable value — hoist it. | [Android docs — Indication & Ripple migration](https://developer.android.com/develop/ui/compose/touch-input/user-interactions/migrate-indication-ripple); [nowinandroid 21.6k★](https://github.com/android/nowinandroid) |
| 9 | **Typography & theming** | `Playground.kt:124` `MaterialTheme(lightColorScheme()/darkColorScheme())` — no dynamic color, **default Typography**; `Theme.kt:87-95` builds ad-hoc `TextStyle` from token size/weight only | No Material3 type scale (line-height, letter-spacing, tracking) → text metrics differ from a designed scale; no Android-12 dynamic color option; catalog uses hard-coded `sp` sizes (`Playground.kt:177,187` etc.) instead of `MaterialTheme.typography`. | Provide a real `Typography` to `MaterialTheme`; on API 31+ optionally offer `dynamicLightColorScheme(context)`/`dynamicDarkColorScheme(context)` with the current hand-tuned scheme as fallback; map token typography onto the M3 scale so line-height/tracking come along. | [Android docs — M3 theming/typography](https://developer.android.com/develop/ui/compose/designsystems/material3); [nowinandroid 21.6k★](https://github.com/android/nowinandroid) |
| 10 | **Elevation / shadows** | `SduiModifiers.kt:301-319` `Modifier.shadow(elevation, shape, clip=false, ambientColor, spotColor)` | The switch to `Modifier.shadow` is **correct** (GPU elevation shadow beats hand-drawn `setShadowLayer`). Two caveats: `ambientColor`/`spotColor` are honoured **only API 28+** (silently neutral below) and only when the shape is **opaquely filled** — fine here because background follows in the chain, but a `gradient`/transparent node with a shadow won't cast one. The `blurRadius*0.6` → 2–16 dp mapping is reasonable. | Keep it. Optionally: when there is no opaque background, still cast a shadow by adding a matching-shape `.background(Color.Transparent)` won't work — instead draw a soft shadow via `drawBehind` only for the transparent-fill case. Low priority. | [Compose `shadow` API ref](https://composables.com/compose-ui/shadow); Android `View.setOutlineAmbientShadowColor` (API 28+) |
| 11 | **Rounded corners / clipping** | `SduiModifiers.kt:241-259` background+clip; `Builtins.kt:472` image `.clip(shape)`; `DataViz.kt` gradient via `background(brush)` relies on outer clip | Mostly correct — clip-after-background and the image `.clip` fallback are the right idioms. Gap: the **gradient** component (`GradientView`, `DataViz.kt:101-103`) fills with `background(brush)` but has no intrinsic corner rounding unless a `cornerRadius` modifier is present; a hero gradient with an image over it can bleed past rounded corners if the parent doesn't clip. | Ensure any node that paints a `Brush`/gradient and declares a `cornerRadius` gets `.clip(shape)` (the `backgroundModifier` already does this at `:256`) — verify gradient goes through `Primitive`→`sduiModifiers` (it does). No change needed unless a gradient is nested without its own radius. Low priority. | Android docs — `Modifier.clip` ordering |
| 12 | **Animations** | `SduiModifiers.kt:122-131` `toFloatSpec()` maps `"spring"` → bare `spring()` (no damping/stiffness); `Builtins.kt:223` `AnimatedVisibility` default; `:295` pager dot width snaps | The contract's `spring` curve loses its character (no damping/stiffness/visibilityThreshold), and per-node transforms lack `Modifier.animateContentSize()` for size changes. Disclosure expand (`:223`) uses default fade+expand — acceptable, but pager active-dot width (`:295`) changes with no animation → visible jump. | Give `spring()` explicit `dampingRatio`/`stiffness` (e.g. `Spring.DampingRatioMediumBouncy`, `StiffnessLow`) matching iOS; animate the pager dot width with `animateDpAsState`; consider `Modifier.animateContentSize()` where nodes grow/shrink. | [Android docs — animations](https://developer.android.com/develop/ui/compose/animation/quick-guide) |

---

## Top 12 fixes, ranked by visible impact

### 1. Add the 4-tab NavigationBar (Playground.kt) — *the app currently has no tab bar; iOS has four*
Wrap the host in `Scaffold`. This is the biggest structural parity gap.

```kotlin
// Playground.kt — replace the bare Column host
enum class Tab(val title: String, val on: ImageVector, val off: ImageVector) {
    Home("Home", Icons.Filled.Home, Icons.Outlined.Home),
    Browse("Browse", Icons.Filled.GridView, Icons.Outlined.GridView),
    Design("Design", Icons.Filled.Hexagon, Icons.Outlined.Hexagon),
    Settings("Settings", Icons.Filled.Settings, Icons.Outlined.Settings),
}
var tab by rememberSaveable { mutableStateOf(Tab.Home) }
Scaffold(
    bottomBar = {
        if (stack.size <= 1) NavigationBar {           // hide when a screen is pushed
            Tab.entries.forEach { t ->
                val sel = tab == t
                NavigationBarItem(
                    selected = sel,
                    onClick = { tab = t },
                    icon = { Icon(if (sel) t.on else t.off, contentDescription = t.title) },
                    label = { Text(t.title) },
                )
            }
        }
    },
) { pad -> Box(Modifier.padding(pad)) { /* current per-tab content */ } }
```
Reference: [nowinandroid 21.6k★](https://github.com/android/nowinandroid).

### 2. Switch images to `AsyncImage` + crossfade (Builtins.kt:477)
```kotlin
// was: SubcomposeAsyncImage(model = source, loading = {...}, error = {...}, ...)
val request = ImageRequest.Builder(LocalContext.current)
    .data(source).crossfade(true).build()
AsyncImage(
    model = request,
    contentDescription = null,
    contentScale = if (fill) ContentScale.Crop else ContentScale.Fit,
    modifier = Modifier.fillMaxSize(),
    placeholder = shimmerPainter(),   // Painter, not a composable
    error = failurePainter(),
)
```
`AsyncImage` never subcomposes → smoother scrolling; crossfade matches iOS fade-in. Keep `SubcomposeAsyncImage` only if the animated shimmer must be a composable. Reference: [coil-kt/coil 11.9k★](https://github.com/coil-kt/coil), [PR #1048](https://github.com/coil-kt/coil/pull/1048).

### 3. Smooth the chart line (DataViz.kt:201-215)
```kotlin
// Catmull-Rom → cubic, replacing the lineTo loop
val pts = xs.indices.map { Offset(px(xs[it]), py(ys[it])) }
line.moveTo(pts.first().x, pts.first().y)
for (i in 0 until pts.size - 1) {
    val p0 = pts[(i - 1).coerceAtLeast(0)]
    val p1 = pts[i]; val p2 = pts[i + 1]
    val p3 = pts[(i + 2).coerceAtMost(pts.size - 1)]
    val c1 = Offset(p1.x + (p2.x - p0.x) / 6f, p1.y + (p2.y - p0.y) / 6f)
    val c2 = Offset(p2.x - (p3.x - p1.x) / 6f, p2.y - (p3.y - p1.y) / 6f)
    line.cubicTo(c1.x, c1.y, c2.x, c2.y, p2.x, p2.y)
}
```
Kills the jagged look. Reference: [MPAndroidChart 38.2k★ `drawCubicBezier`](https://github.com/PhilJay/MPAndroidChart).

### 4. Give LazyColumn stable keys + contentType + item animation (Builtins.kt:376,383)
```kotlin
items(items, key = { it["id"]?.stringValue ?: it.stableHash() },
             contentType = { template.type }) { item ->
    Box(Modifier.animateItem()) { ctx.registry.Render(template, ctx.withItem(item)) }
}
```
Fixes wrong-item recomposition + enables smooth insert/remove. Reference: [Android docs — item keys](https://developer.android.com/develop/ui/compose/lists#item-keys).

### 5. Add Material ripple + fix the press haptic (SduiModifiers.kt:328-367)
```kotlin
val interaction = remember { MutableInteractionSource() }
val pressed by interaction.collectIsPressedAsState()
val scale by animateFloatAsState(if (pressed) 0.955f else 1f, spring(0.58f, Spring.StiffnessMediumLow))
// ...graphicsLayer(scaleX = scale, ...)
.indication(interaction, ripple())                       // <- the missing Android affordance
.pointerInput(tap) { detectTapGestures(
    onPress = { val p = PressInteraction.Press(it); interaction.emit(p)
                tryAwaitRelease(); interaction.emit(PressInteraction.Release(p)) },
    onTap = { tap?.let { ctx.dispatch(it, ctx.binding) } }) }
```
Also stop firing `HapticFeedbackType.LongPress` on every tap-down (`:358`) — reserve haptics for long-press/commit. `ripple()` is a reusable non-composable value; hoist it. Reference: [Android indication/ripple migration](https://developer.android.com/develop/ui/compose/touch-input/user-interactions/migrate-indication-ripple).

### 6. Move SwipeReveal onto anchoredDraggable (SwipeReveal.kt:64-108)
Replace the `Animatable` + per-delta `scope.launch { snapTo() }` with `AnchoredDraggableState` and `Modifier.anchoredDraggable(state, Orientation.Horizontal)`, supplying `positionalThreshold = { d -> d * 0.5f }` and a `velocityThreshold` so a fast flick opens even below 50 %. Add `Modifier.semantics { customActions = actions.map { CustomAccessibilityAction(it.title) { … } } }`. Removes dropped-frame risk and matches iOS fling feel. Reference: [migrate-swipeable docs](https://developer.android.com/develop/ui/compose/touch-input/pointer-input/migrate-swipeable), [compose-swipeBox 103★](https://github.com/KevinnZou/compose-swipeBox).

### 7. Chart axes/baseline/gridlines (DataViz.kt:173-217)
Draw faint gridlines (`onSurface @ 0.08`), a true zero baseline for area fills, and route the `bar` branch through the same padded `px()/py()` transform so bars and lines share a coordinate space. Reference: [Vico 3.1k★](https://github.com/patrykandpatrick/vico).

### 8. Real Typography scale + optional dynamic color (Playground.kt:124, Theme.kt:87)
Pass a `Typography` into `MaterialTheme`; map token typography onto M3 roles so line-height/tracking come with the size. On API 31+ optionally offer `dynamicLight/DarkColorScheme(context)` with the current scheme as fallback. Replace hard-coded `sp` sizes in the catalog (`Playground.kt:177+`) with `MaterialTheme.typography.*`. Reference: [M3 theming docs](https://developer.android.com/develop/ui/compose/designsystems/material3).

### 9. Give the `spring` contract curve real physics (SduiModifiers.kt:128)
```kotlin
"spring" -> spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessLow)
```
Currently `spring()` uses defaults, so the contract's spring animations feel generic vs iOS.

### 10. Animate the pager active dot (Builtins.kt:295)
```kotlin
val w by animateDpAsState(if (i == state.currentPage) 18.dp else 6.dp, spring())
Box(Modifier.size(width = w, height = 6.dp) ...)
```
The dot currently snaps width; iOS animates it.

### 11. Bar chart corner + width polish (DataViz.kt:184-199)
Bars ignore `pad` and always round both ends; clamp `cornerRadius` to `min(barW/2, height)` and inset by `pad` so a full-height bar's bottom isn't over-rounded.

### 12. Shadow on transparent-fill nodes (SduiModifiers.kt:301-319)
`Modifier.shadow` is the right primitive — keep it. Only edge case: a `gradient`/transparent node declaring a shadow won't cast one (elevation shadows need an opaque shape). If that combination appears in content, fall back to a `drawBehind` soft shadow for that case. Lowest priority; the current switch away from hand-drawn `setShadowLayer` was correct.

---

### Cross-cutting note
Items **1 (tabs)**, **2 (AsyncImage)**, **3 (chart smoothing)**, **5 (ripple)** and **4 (list keys)** together account for most of the "кривые vs iOS" perception: they are the structural + surface-finish gaps a user notices first. Everything else is polish on an already-solid renderer — the modifier chain ordering, image clipping, and the recent `Modifier.shadow` switch are all already best-practice.

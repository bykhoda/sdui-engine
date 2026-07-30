# 22 — Mobile Techniques: A Prioritized Adoption Catalog

**Purpose.** A citation-backed catalog of the best anti-jank, anti-crash, and signature-interaction
techniques used by top-starred open-source projects and top engineering blogs, each mapped concretely
to **our** iOS SwiftUI (`ios/Sources/SDUIRender/…`) and Android Compose (`android/sdui/…`) renderers —
what to change, in which file, and the cross-platform note. Ranked by impact ÷ effort.

This extends [`04a-techniques-ledger.md`](04a-techniques-ledger.md) (which already covers the DivKit /
Beagle **contract** — templates, `div-patch`, expressions, states) and [`06-collapsing-scroll.md`](06-collapsing-scroll.md).
Where those go deep, this doc references rather than repeats, and focuses on **rendering-engine
mechanics** (recomposition, list identity, image decode, motion) that those docs don't.

Research window: July 2026. Every non-obvious claim is cited inline with a URL; star counts are
point-in-time.

---

## Reference projects (stars + URLs)

| Project | Stars | What we mine it for | URL |
|---|---:|---|---|
| DivKit (Yandex) | 2.7k | SDUI robustness: fallback nodes, `div-patch`, expression VM, cross-platform parity | https://github.com/divkit/divkit |
| Coil | 11.9k | Compose image loading: memory+disk cache, crossfade, coroutines | https://github.com/coil-kt/coil |
| Nuke (kean) | 8.6k | iOS image pipeline: off-main decode, prefetch, request coalescing | https://github.com/kean/Nuke |
| Epoxy (Airbnb) | 8.6k | Heterogeneous lists, diffing, lazy rendering, stable ids | https://github.com/airbnb/epoxy |
| skydoves/compose-performance | 801 | Curated Compose stability / strong-skipping / baseline-profile rules | https://github.com/skydoves/compose-performance |
| Airbnb Ghost Platform (blog) | — | SDUI screens/sections/actions model, deferred sections | https://medium.com/airbnb-engineering/a-deep-dive-into-airbnbs-server-driven-ui-system-842244c5f5 |

Supporting blogs cited inline: Android Developers "Compose Stability Explained"
([medium](https://medium.com/androiddevelopers/jetpack-compose-stability-explained-79c10db270c8)),
GetStream Compose-stability ([getstream.io](https://getstream.io/blog/jetpack-compose-stability/)),
Jacob's Tech Tavern "SwiftUI Scroll Performance: The 120FPS Challenge"
([blog.jacobstechtavern.com](https://blog.jacobstechtavern.com/p/swiftui-scroll-performance-the-120fps)),
fatbobman "List or LazyVStack" ([fatbobman.com](https://fatbobman.com/en/posts/list-or-lazyvstack/)),
Android Developers Shared-element transitions
([developer.android.com](https://developer.android.com/develop/ui/compose/animation/shared-elements)),
Swift with Majid "Hero animations in SwiftUI"
([swiftwithmajid.com](https://swiftwithmajid.com/2020/12/17/hero-animations-in-swiftui/)).

---

## How our engine stands today (audit)

Firsthand read of the current tree (July 2026):

- **iOS lists** use `LazyVStack`/`LazyHStack`/`LazyVGrid` (`Builtins.swift:460,532,797,803,1630`) — good —
  but most `ForEach` iterate `…indices, id: \.self` (`Builtins.swift:133,157,798,804,981,1634,1876`).
  Index identity is the classic SwiftUI reorder/insert bug + recompute source.
- **Android lists** use `LazyColumn` (`Builtins.kt:428,469`) but call `itemsIndexed(items)` / `itemsIndexed(children)`
  **without a `key = {}`** (`Builtins.kt:434,436,504`). No stable key ⇒ Compose re-keys by position ⇒ full
  subtree recomposition on any insert/reorder + lost scroll/animation state.
- **iOS images**: `ImageCache.swift` already does memory `NSCache` + `URLCache` disk + off-main decode via
  `RemoteImage` — strong, Nuke-grade. **Android**: Coil 2.7.0 (`io.coil-kt:coil-compose`) — good default,
  but no explicit disk-cache sizing / crossfade / stable cache-key policy wired.
- **Compose compiler**: `android/sdui/build.gradle.kts` has **no `composeCompiler {}` block** — strong
  skipping, a stability-config file, and compiler metrics/reports are all off. Core models
  (`core/Models.kt`) are not annotated `@Immutable`.
- **Binding resolution** is null-safe on iOS (`BindingEngine.swift:46,54` → `?? .null`, `?? ""`).
- **Unknown component type** degrades safely (iOS `EmptyView`, Android debug hint) but there is **no
  declarative `fallback`** field on a component (DivKit's key robustness primitive) — no server control
  over degradation.
- **Collapsing/parallax header** ships on iOS (`ScrollHeader.swift`, `SDUICollapseProgressKey` preference)
  — **no Android parity** (no `nestedScroll`/collapsing in `android/sdui` source).
- **Pull-to-refresh** exists on both (iOS `SDUIScreenView.swift:299` `.refreshable`; Android `SduiScreen.kt:259` twin).
- **Skeleton/shimmer** exists on both (`Skeleton.swift`; Android `Builtins.kt`/`FileCell.kt`/`Clips.kt`).
- **Haptics**: rich on iOS (6 files); on Android only 2 types in `SduiModifiers.kt:378,387`
  (`TextHandleMove`, `LongPress`) and **not contract-driven**.
- **Hero / shared-element transitions**: `matchedGeometryEffect` appears **nowhere** — unused on both.

---

## A. Anti-jank / performance

### A1. Stable list keys (both platforms) — **highest impact, low effort**
**What.** Give every lazy row a stable, content-derived identity instead of its array index.
Compose: `items(list, key = { it.stableId })`; SwiftUI: `ForEach(list, id: \.stableId)` (or `Identifiable`).
**Why.** Epoxy's entire diffing model is built on stable ids so a RecyclerView reorders/animates instead of
rebinding everything (https://github.com/airbnb/epoxy). Without keys Compose re-keys by slot position, so an
insert at the top recomposes every row and drops scroll/animation state; SwiftUI's `id: \.self` on indices
causes "incorrect animations or scroll position loss" (fatbobman, https://fatbobman.com/en/posts/list-or-lazyvstack/).
**Our engine.**
- Android `render/Builtins.kt:434,436,504`: change `itemsIndexed(items) { … }` →
  `itemsIndexed(items, key = { i, item -> stableKey(item, i) })`. Derive `stableKey` from the item's `id`
  binding (fall back to a structural hash, last-resort index). Same for the `children` branch.
- iOS `render/Builtins.swift`: where a list binds data rows, prefer the item's `id` field over `id: \.offset`.
  For static `children` (small, fixed) index identity is acceptable; for **data-bound** rows it is not.
- Contract note: add an optional `itemKey: "$item.id"` binding on list/grid components so the **author**
  names the identity field; both renderers read the same key. Cross-platform parity by construction.
**Impact/Effort:** ★★★★★ / low.

### A2. Compose stability config + `@Immutable` on contract models — **high impact, low effort**
**What.** Mark our contract types stable and feed the compiler a stability config so `Component`, `JsonValue`,
`BindingContext` and `kotlinx` collections skip instead of recomposing.
**Why.** Strong skipping is *already default-on* in our toolchain (Kotlin 2.0.20 Compose plugin), so the
remaining lever is **stability of the data we thread**, not a flag. Collections (`List`/`Map`) are *always*
inferred unstable (Android Devs, https://medium.com/androiddevelopers/jetpack-compose-stability-explained-79c10db270c8),
and our `core/Models.kt` (`Component`, `Screen`, `Modifiers`), `JsonValue.kt` (holds `Map`/`List`), and
`BindingContext` are plain `data class`es with **no `@Immutable`/`@Stable`**. Even under strong skipping, a
composable taking an unstable `Map`-backed param can't be guaranteed skippable — and our renderer threads
`Component` + `RenderContext` into *every* builder, so today almost nothing skips reliably.
**Our engine.** In `android/sdui/build.gradle.kts` add a `composeCompiler {}` block (strong skipping is already
default-on with the Kotlin 2.0.20 plugin — this block adds the stability config + metrics):
```kotlin
composeCompiler {
    stabilityConfigurationFile = rootProject.file("compose_stability.conf")
    reportsDestination = layout.buildDirectory.dir("compose_reports") // enable in CI to track skippability
}
```
Create `compose_stability.conf` listing `dev.sdui.core.JsonValue`, `dev.sdui.core.BindingContext`,
`kotlinx.collections.immutable.*`. Then annotate the effectively-immutable value types in `core/Models.kt`,
`JsonValue.kt`, and `BindingEngine.kt` (`BindingContext`) with `@Immutable`. Consider swapping raw `List`/`Map`
in hot models for `kotlinx.collections.immutable` persistent collections so they are stable without an
annotation. Wire the `compose_reports` output into CI to watch the skippable/restartable counts.
**iOS parity:** N/A (SwiftUI has no stability compiler) — the equivalent is A3.
**Impact/Effort:** ★★★★★ / low.

### A3. SwiftUI `Equatable` leaf views + minimal props — **high impact, low-med effort**
**What.** Make component subviews `Equatable` (or `.equatable()`) and pass them the *smallest* data they
need, not the whole `Component`/`JSONValue` tree.
**Why.** "Passing primitives (or small structs) to row views is the single most effective performance
optimisation for SwiftUI lists" (Jacob's Tech Tavern, https://blog.jacobstechtavern.com/p/swiftui-scroll-performance-the-120fps).
Our `ComponentRegistry.view(for:in:)` hands each builder the full `Component` + `RenderContext`; SwiftUI then
re-diffs the whole thing. **Our engine.** For hot leaf builders in `render/Builtins.swift` (`text`, `image`,
`badge`, list rows), extract a small `Equatable` struct view (e.g. `TextLeaf: Equatable { text; style }`) so
SwiftUI can short-circuit body eval. This is the SwiftUI twin of A2. **Impact/Effort:** ★★★★☆ / medium.

### A4. Deferred state reads + `derivedStateOf` for scroll-driven UI — **high impact, low effort**
**What.** Read scroll/gesture state at the *lowest* composable that needs it, and wrap derived booleans
(e.g. "is header collapsed", "show FAB") in `derivedStateOf` so they only invalidate on threshold crossings.
**Why.** "Reading state at the wrong level invalidates the whole subtree; push state reads down to the
smallest leaf" and "use `derivedStateOf` to filter redundant updates" (skydoves/compose-performance,
https://github.com/skydoves/compose-performance). A collapsing header that reads raw scroll offset in the
parent recomposes the entire screen every frame of a scroll.
**Our engine.** When we build the Android collapsing header (A9/C1), the offset→progress mapping must live in
`derivedStateOf { (offset / range).coerceIn(0,1) }` read only inside the header composable. iOS already
isolates this via the `SDUICollapseProgressKey` preference in `ScrollHeader.swift` — keep that pattern; just
ensure downstream `.animation`/opacity read the *preference*, not a top-level `@State` mutated per frame.
**Impact/Effort:** ★★★★☆ / low.

### A5. Image pipeline parity: Coil disk cache + stable keys + prefetch — **med-high impact, low effort**
**What.** Bring Android image loading to iOS's `ImageCache.swift` bar: explicit memory+disk cache sizes,
stable cache keys (so the same URL across screens is one entry), crossfade, and list prefetch.
**Why.** Images are "the most common cause of scroll stutter" and must decode off-main
(https://blog.jacobstechtavern.com/p/swiftui-scroll-performance-the-120fps); Nuke and Coil both solve this
with memory+disk caches, coalescing and prefetch (https://github.com/kean/Nuke, https://github.com/coil-kt/coil).
iOS already has this in `ImageCache.swift`; Android relies on Coil defaults.
**Our engine.** In the Android host/`SduiApp` init, configure a singleton `ImageLoader` with sized
`MemoryCache` + `DiskCache` and `crossfade(true)`; pass it via `LocalImageLoader`. For the `image` builder in
`render/Builtins.kt`, set an explicit `memoryCacheKey`/`diskCacheKey` from the resolved URL. iOS: expose the
same crossfade/placeholder policy on `RemoteImage` so both fade identically. **Impact/Effort:** ★★★★☆ / low.

### A6. Never nest a lazy list inside a scroll (already respected) — keep as a lint rule
**What.** A `LazyColumn` inside a `verticalScroll` gets infinite height and crashes; our Android code already
guards this (`Builtins.kt` comments at :112,:388,:418).
**Why/Our engine.** Promote this to a **design-lint rule** in `spec/tools` so authored JSON that would nest a
scrollable list inside a scroll container is flagged before render, on all platforms. This is robustness *and*
performance (a single flat lazy list virtualizes; nested scrolls don't). **Impact/Effort:** ★★★☆☆ / low.

---

## B. Anti-crash / robustness

### B1. Declarative `fallback` component (DivKit's core primitive) — **highest robustness impact**
**What.** Add an optional `fallback` field to every component: the node to render if the primary type is
unknown to this client, or if the node fails to build. DivKit ships exactly this so newer servers can target
older clients without blank space or crashes.
**Why.** SDUI's central risk is a server sending a `type` an old app doesn't know. Today we render nothing
(iOS) / a debug hint (Android) — safe from crashing, but the *server* has no control over degradation. A
`fallback` lets the backend say "if you can't render this rich card, render this text+button instead."
This is the single biggest expressiveness+robustness gap vs DivKit (https://github.com/divkit/divkit).
**Our engine.**
- `ios/Sources/SDUICore/Models.swift` + `android/.../core/Models.kt`: add `fallback: Component?`.
- iOS `ComponentRegistry.view(for:in:)`: replace the `guard let builder … else { unknownView }` with
  "if no builder and `component.fallback != nil`, render the fallback; else `unknownView`."
- Android `ComponentRegistry` `Render`: same branch.
- Wrap each builder invocation so a thrown/failed build also routes to `fallback` (see B2).
- Schema: `spec/schema` add `fallback` to the component definition; validator + MCP `scaffold_screen` learn it.
**Impact/Effort:** ★★★★★ / medium. **Cross-platform:** identical field, identical semantics — parity by contract.

### B2. Render isolation: one bad node never takes down the screen — **high impact**
**What.** Each component build runs inside a guard that catches failures and substitutes `fallback` (B1) or an
empty node, so a malformed subtree degrades locally instead of blanking the whole screen. Airbnb's Ghost
Platform isolates each **section** for exactly this reason (independent groups of components; a failing
section doesn't sink the screen — https://medium.com/airbnb-engineering/a-deep-dive-into-airbnbs-server-driven-ui-system-842244c5f5).
**Why/Our engine.** iOS builders return `AnyView`; wrap the call site in `ComponentRegistry` so a nil/throwing
resolution yields the fallback. Android: wrap each `Render` in a `runCatching { }`; on failure emit the
fallback and log. Add a screen-level **error boundary** at `SDUIScreenView`/`SduiScreen` that renders a
retry state if the root fails to parse. **Impact/Effort:** ★★★★☆ / medium.

### B3. Safe binding resolution everywhere (iOS done; audit Android) — **med impact**
**What.** Every `$binding` lookup returns a typed default (`""`, `0`, `false`, `.null`) on miss — never a force
unwrap. iOS `BindingEngine.swift` already does this (`?? .null`, `?? ""`). **Our engine.** Confirm the Android
`core/BindingEngine.kt` mirrors it (no `!!` on missing keys; missing token → empty/typed default). Add a unit
fixture in `spec/conformance` that feeds a screen referencing undefined `$state.foo` and asserts *both*
renderers produce the same empty-but-alive output. **Impact/Effort:** ★★★☆☆ / low.

### B4. Thread-safe action interpretation — **med impact**
**What.** Actions mutate `$state` and trigger navigation/network; those mutations must be serialized on the UI
thread. **Our engine.** iOS `RenderContext.dispatch` is already `@MainActor`. Verify `SDUIRuntime/ActionInterpreter.swift`
hops to `@MainActor` before touching state, and Android's `runtime/ActionInterpreter.kt` posts state writes
onto the main dispatcher (never a background coroutine writing `mutableStateOf`). Document the rule: **binding
reads may be off-main; state writes are main-only.** Cross-platform note: this is the one place a data race
would desync the two renderers. **Impact/Effort:** ★★★☆☆ / low.

### B5. Version/capability gating on the contract — **med impact, forward-looking**
**What.** Let a node declare a `minClientVersion` / `requires: ["blur","liveActivity"]`; clients that don't
meet it render the `fallback` (B1). Ties robustness to the capability matrix in
[`10-capability-matrix.md`](10-capability-matrix.md). **Impact/Effort:** ★★★☆☆ / medium.

---

## C. Signature interactions

### C1. Collapsing / parallax header — reach iOS parity on Android — **high impact**
**What.** The Apple-Weather-gold-standard large title that shrinks/parallaxes into a compact bar on scroll.
Ships on iOS (`ScrollHeader.swift` + `SDUICollapseProgressKey`); **absent on Android**.
**Why.** This is our stated signature interaction and a named parity gap (memory: "iOS ships collapsing
scroll, Android/Aurora must match").
**Our engine (Android).** Build a `CollapsingHeader` in a new `render/ScrollHeader.kt` using
`Modifier.nestedScroll(connection)` to track cumulative offset, mapped to a `derivedStateOf` progress 0→1
(A4), driving title scale/alpha/translation exactly like the iOS preference. Wire the same contract fields the
iOS header reads (title, `largeTitle`, `pinnedContent`, pull-to-reveal search). Keep the **maths identical**
across platforms (same collapse range, same easing) so behavior matches — see [`06-collapsing-scroll.md`](06-collapsing-scroll.md).
**Impact/Effort:** ★★★★★ / medium-high.

### C2. Haptics choreography — contract-driven, parity across platforms — **high impact, low effort**
**What.** A small, semantic haptic vocabulary on actions/gestures: `selection`, `impact(light|medium|heavy)`,
`notification(success|warning|error)`, fired on tap, toggle, swipe-commit, refresh-trigger, and error.
**Why.** Haptics are cheap polish with outsized perceived quality; Apple guidance is to match haptic weight to
visual weight and `prepare()` the generator to cut latency
(https://developer.apple.com/documentation/uikit/uiimpactfeedbackgenerator). Today iOS uses haptics ad hoc in
6 files and Android only fires 2 types in `SduiModifiers.kt` — **not authorable and not in parity.**
**Our engine.** Add an optional `haptic` field to `Action` (and to swipe/press modifiers) in `core/Models`.
iOS: central `Haptics` helper mapping the enum to `UIImpactFeedbackGenerator`/`UINotificationFeedbackGenerator`
(with `prepare()`); Android: map to `HapticFeedbackType` (`ConfirmDrag`/`LongPress`/`TextHandleMove`, plus
`View.performHapticFeedback` for the richer constants). One enum in the contract → same taps on both phones.
**Impact/Effort:** ★★★★☆ / low.

### C3. Swipe actions — unify the recipe — **med impact**
**What.** Leading/trailing swipe actions on rows (delete, archive, pin) with a commit threshold + haptic + spring
snap-back. Android has `SwipeReveal.kt`; iOS should expose the same via native `.swipeActions` where possible.
**Our engine.** Define swipe actions in the contract once (`leadingActions`/`trailingActions` with icon+tint+
action). Android renders via `anchoredDraggable` in `SwipeReveal.kt`; iOS renders via `.swipeActions` on list
rows (falling back to a drag gesture off-`List`). Fire C2 haptic on commit. **Impact/Effort:** ★★★☆☆ / medium.

### C4. Pull-to-refresh physics parity — **low effort (both exist)**
**What.** Both platforms already have pull-to-refresh (iOS `.refreshable`; Android twin). Ensure identical
trigger distance, spinner style, and that the refresh **fires C2's `notification(success)` haptic** on
completion. **Our engine.** Align the Android `SduiScreen.kt:259` threshold/indicator with iOS. **Impact/Effort:** ★★★☆☆ / low.

### C5. Skeleton / shimmer parity + auto-skeleton — **med impact**
**What.** Both platforms have skeletons; elevate to an **auto-skeleton**: while an `async`/data source loads,
render a shimmering silhouette derived from the component's own shape (SwiftUI `.redacted(reason: .placeholder)`
is the free version). **Our engine.** Standardize one shimmer animation spec (period, gradient angle) shared by
`Skeleton.swift` and Android `Clips.kt`/`FileCell.kt`, and let `async` show the skeleton of its *child* template
automatically. **Impact/Effort:** ★★★☆☆ / medium.

---

## D. Motion & polish

### D1. Shared-element / hero transitions — **high impact, medium effort** (new capability)
**What.** A tapped card grows into the detail screen; the image/title are matched between source and
destination. **Currently unused on both platforms.**
**Why.** The most "premium" transition in modern apps. SwiftUI: `matchedGeometryEffect(id:in:)` across a shared
`@Namespace` (https://swiftwithmajid.com/2020/12/17/hero-animations-in-swiftui/). Compose 1.7+:
`SharedTransitionLayout` + `Modifier.sharedElement(rememberSharedContentState("hero-$id"), scope)` with all
destinations under one layout (https://developer.android.com/develop/ui/compose/animation/shared-elements).
**Our engine.** Add a `sharedId` field to components. iOS: `SDUINavContainer` owns a `@Namespace`; any node with
`sharedId` gets `matchedGeometryEffect(id: sharedId, in: ns)`. Android: wrap the nav host in
`SharedTransitionLayout`; nodes with `sharedId` call `sharedElement` keyed `"hero-$sharedId"` (use the
`"element-${id}"` pattern to prevent cross-item matching). One `sharedId` on the source and detail nodes → the
transition just works on both. **Impact/Effort:** ★★★★☆ / medium.

### D2. One canonical spring vocabulary in the contract — **high impact, low effort**
**What.** Replace scattered ad-hoc `withAnimation`/`spring()` calls with 3–4 named springs in the contract:
`snappy` (UI response), `bouncy` (playful), `smooth` (content), matching SwiftUI's built-ins
(https://dev.to/__be2942592/swiftui-animation-guide-from-basic-to-advanced-in-2026-131b).
**Why.** Springs are duration-independent (specified by damping+stiffness), so they "adapt to different screen
sizes" and feel native everywhere (Android Devs motion). A named set guarantees iOS and Android animate with the
*same feel*. **Our engine.** Add an `animation` token set to `Theme.swift`/`Theme.kt`: map `snappy`→`.snappy`/
`spring(dampingRatio≈0.9, stiffness≈High)`, `bouncy`→`.bouncy`/`dampingRatio≈0.5`, `smooth`→`.smooth`. Components
reference the name; both renderers resolve to native springs. **Impact/Effort:** ★★★★☆ / low.

### D3. Staggered list reveal — **med impact, low effort**
**What.** On first appear, list items fade+slide in with a small per-index delay. **Our engine.** iOS: per-row
`.transition`+`.animation` with `delay(index * 0.03)`, capped. Android: `animateItem()` on lazy items +
`AnimatedVisibility` on first composition. Gate behind a contract flag `reveal: "stagger"` so authors opt in.
**Impact/Effort:** ★★★☆☆ / low.

### D4. Material / blur surfaces as a cross-platform token — **med impact**
**What.** Frosted nav bars, scrim-over-hero, blurred sheet backgrounds. **Our engine.** Expose a `material`
modifier (`thin|regular|thick`). iOS → `.background(.ultraThinMaterial)` / `.regularMaterial`; Android →
`Modifier.blur()` behind a translucent surface (or `RenderEffect` on API 31+, else a translucent scrim
fallback). Tie into `NativeCapabilities` so unsupported blur degrades to a solid scrim via B1/B5. **Impact/Effort:** ★★★☆☆ / medium.

---

## E. SDUI-specific structural techniques

### E1. Screens = sections + actions (Airbnb Ghost Platform) — **structural, high leverage**
**What.** Model a screen as an ordered list of **independent sections** (self-contained component groups),
plus a shared **actions** vocabulary. Airbnb's GP does exactly this and it's why a failing/loading section is
isolated (https://medium.com/airbnb-engineering/a-deep-dive-into-airbnbs-server-driven-ui-system-842244c5f5).
**Our engine.** We already have components + actions; formalize a `section` grouping with per-section
`fallback`/loading/error (B2) and per-section lazy loading (E2). Feeds our error-isolation story directly.
**Impact/Effort:** ★★★★☆ / medium.

### E2. Deferred / lazily-loaded sections (Beagle `lazyComponent`, GP deferred sections) — **high impact**
**What.** A section renders a placeholder immediately and fetches its real content from its own endpoint when it
scrolls near the viewport — first paint isn't blocked on the slowest data. **Our engine.** We have an `async`
component; promote it to a **section-level** deferred loader keyed by a `DataSource`, showing the C5 skeleton
until resolved. Cross-platform: same `async`/`section` contract; iOS uses `.task`, Android `LaunchedEffect`.
See [`04a-techniques-ledger.md` §2.3](04a-techniques-ledger.md). **Impact/Effort:** ★★★★☆ / medium.

### E3. `div-patch`-style partial updates — **high impact** (already specced)
**What.** Update named nodes in place without re-fetching the screen (add/replace/remove by `id`).
Fully designed in [`13-div-patch-spec.md`](13-div-patch-spec.md) and [`04a §1.2`](04a-techniques-ledger.md);
this catalog just flags it as a top-tier robustness/expressiveness technique to *implement* in both renderers.
Requires stable node ids — which A1 also gives us. **Impact/Effort:** ★★★★☆ / high.

### E4. Cross-platform conformance fixtures for behavior parity (how DivKit enforces parity) — **foundational**
**What.** DivKit keeps iOS/Android/Web in lockstep with a shared corpus of JSON→expected-render fixtures. We
have `spec/conformance` + a snapshot harness ([`20-visual-snapshot-harness.md`](20-visual-snapshot-harness.md)).
**Our engine.** Every technique above lands a fixture: stable-key reorder, unknown-type→fallback, undefined
binding, spring token, collapse progress at scroll offset X. This is how we *prove* the two renderers match.
See [`09-conformance-fixtures.md`](09-conformance-fixtures.md). **Impact/Effort:** ★★★★☆ / medium — but it's the
multiplier that makes all the others trustworthy.

### E5. Baseline Profiles (Android startup/scroll) — **med impact, low effort**
**What.** Ship a Baseline Profile so hot rendering paths are AOT-compiled, cutting jank on first scroll and
startup (skydoves/compose-performance, https://github.com/skydoves/compose-performance). **Our engine.** Add a
`baseline-prof.txt` generation step for the `:sdui` module / demo app in `android/`. iOS parity: none needed
(AOT by default). **Impact/Effort:** ★★★☆☆ / low.

---

## Prioritized adoption matrix (impact ÷ effort)

| Rank | Technique | Impact | Effort | Where |
|---:|---|:--:|:--:|---|
| 1 | A1 Stable list keys | ★★★★★ | Low | `Builtins.kt:434,436,504`; `Builtins.swift` ForEach |
| 2 | A2 Strong-skipping + stability config | ★★★★★ | Low | `android/sdui/build.gradle.kts`, new `compose_stability.conf`, `core/Models.kt` |
| 3 | B1 Declarative `fallback` node | ★★★★★ | Med | `core/Models.{swift,kt}`, both `ComponentRegistry` |
| 4 | D2 Named spring vocabulary | ★★★★☆ | Low | `Theme.swift` / `Theme.kt` |
| 5 | C2 Haptics choreography (contract) | ★★★★☆ | Low | `core/Models` Action; `Haptics` helper + `SduiModifiers.kt` |
| 6 | A4 Deferred reads + `derivedStateOf` | ★★★★☆ | Low | Android header, `ScrollHeader.swift` |
| 7 | A5 Coil disk cache + keys + prefetch | ★★★★☆ | Low | Android host `ImageLoader`, `Builtins.kt` image |
| 8 | B2 Per-node render isolation | ★★★★☆ | Med | both `ComponentRegistry`, screen error boundary |
| 9 | C1 Android collapsing header (parity) | ★★★★★ | Med-Hi | new `render/ScrollHeader.kt` |
| 10 | D1 Shared-element / hero transitions | ★★★★☆ | Med | `SDUINavContainer` + nav host, `sharedId` field |
| 11 | A3 SwiftUI Equatable leaves | ★★★★☆ | Med | `Builtins.swift` leaf builders |
| 12 | E2 Deferred sections | ★★★★☆ | Med | `async`/`section`, both renderers |
| 13 | E1 Sections + actions model | ★★★★☆ | Med | contract + both screens |
| 14 | E4 Conformance fixtures (multiplier) | ★★★★☆ | Med | `spec/conformance`, snapshot harness |
| 15 | C5 Auto-skeleton parity | ★★★☆☆ | Med | `Skeleton.swift`, `Clips.kt` |
| 16 | E5 Baseline Profile | ★★★☆☆ | Low | `android/` |
| 17 | C3 Swipe actions unify | ★★★☆☆ | Med | `SwipeReveal.kt`, iOS `.swipeActions` |
| 18 | D3 Staggered reveal | ★★★☆☆ | Low | both, `reveal` flag |
| 19 | D4 Material/blur token | ★★★☆☆ | Med | `Modifiers`, `NativeCapabilities` |
| 20 | B3/B4/B5 Binding/thread/version safety | ★★★☆☆ | Low-Med | `BindingEngine.kt`, `ActionInterpreter` |
| 21 | A6 Lazy-in-scroll lint | ★★★☆☆ | Low | `spec/tools` |
| 22 | E3 `div-patch` implementation | ★★★★☆ | High | both renderers (spec ready) |

---

## Cross-platform parity principle (the through-line)

Every technique above is designed so the **contract carries the intent** (a `key` binding, a `fallback` node,
a `haptic` enum, a named spring, a `sharedId`) and **each renderer maps it to the best native mechanism** —
never a hack, always the platform's own primitive (`Modifier.nestedScroll` vs `PreferenceKey`,
`SharedTransitionLayout` vs `matchedGeometryEffect`, `HapticFeedbackType` vs `UIFeedbackGenerator`). A shared
conformance fixture (E4) then proves the two behave the same. That is what turns a component library into a
world-class, robust SDUI engine.

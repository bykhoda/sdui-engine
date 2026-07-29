# 06 — Collapsing / Parallax Scroll: gap analysis + world-class blueprint

> **Goal.** Take our collapsing / large-title / hero-parallax scroll to "buttery,
> never stutters." This doc maps EXACTLY how the iOS reference works today
> (`file:line`), names the concrete jank sources, tables the best-in-class
> techniques with sourced URLs + star counts, gives a prioritized iOS improvement
> plan (iOS 13+ compatible with noted upgrades), and shows how the identical
> behavior ports to Android (Compose nested-scroll) and Aurora (Qt/Silica).
>
> Every external claim is cited inline. Research done July 2026.

---

## 1. How our iOS collapsing scroll works today — and where it breaks

All of it lives in **one type**: `ScrollContainer` in
`ios/Sources/SDUIRender/Builtins.swift` (struct at **:186**), plus the screen-side
chrome in `ios/Sources/SDUIRender/ScrollHeader.swift`.

### 1.1 The five divergent code paths

`ScrollContainer.body` (**Builtins.swift:296–308**) dispatches to one of **five**
separately-authored implementations based on which prop is present:

| Path | `func` @ line | Trigger | Mechanism |
|---|---|---|---|
| `collapsingBody` | :563 | `collapsingHeader` present | `.overlay` header + `.scaleEffect`, height measured once |
| `sectionsBody` | :420 | `sections` array | native `LazyVStack(pinnedViews:[.sectionHeaders])` + a `safeAreaInset` hero |
| `pinnedBody` | :517 | `pinnedHeader` present | native `pinnedViews:[.sectionHeaders]` |
| `behaviorBody` | :635 | `scrollBehavior.largeTitle != false` | **synthesized** 34pt title, smoothstep collapse |
| `plainBody` | :329 | everything else | plain `ScrollView`, optional nav cross-fade |

**Reality check on what's actually exercised.** A repo grep shows **no bundled
screen uses `collapsingHeader`, `collapsingHero`, `sections`, or `pinnedHeader`.**
`weather.json` (root `zstack`, `scrollBehavior.largeTitle:false`) drives
`plainBody`; most other screens set only a `subtitle` and hit `behaviorBody` via
the default `largeTitle:true`. So three of the five paths are **untested dead
weight** and the two live ones are the ones with the deepest problems.

### 1.2 How offset is tracked (the heart of the jank)

Every path uses the same primitive: a zero- or full-height `GeometryReader` writes
a `minY` into an `OffsetKey` `PreferenceKey` (**:269–272**); `.onPreferenceChange`
copies it into `@State var offset` (**:195**), which re-drives the whole subtree's
scale/height/opacity. Three different coordinate strategies are used across paths,
which is why they don't feel the same:

- `plainBody` / `sectionsBody`: `geo.frame(in: .global).minY` (**:342, :448**),
  then a **capture-once baseline** `scrollBaselineY` (**:198, :363, :477**) to
  turn global-space Y into a rest-relative delta.
- `collapsingBody`: `offset = outer.frame(in:.global).minY - trackerY` (**:585**).
- `behaviorBody`: a **named coordinate space** `"sduiScrollSpace"` (**:276, :714**)
  read from a real-height background reader (**:709–712**) — the cleanest of the
  three, and the comment at :705 admits the 0-height tracker "reports stale
  geometry… that's exactly why the collapse never moved."

Interpolation: `progress = clamp(offset/range)`; `behaviorBody` eases it with a
smoothstep `p*p*(3-2p)` (**:646**) — good — while `collapsingBody`/`sectionsBody`
use **raw linear** progress (twitchy). Collapse is applied via `.scaleEffect`
(**:595, :680**) + a `.frame(height:)` that shrinks (**:578, :684**). Cross-fade is
plain `.opacity` swaps (**:484–487, :681**).

### 1.3 Confirmed concrete weaknesses (the punch-list)

1. **DOUBLE title-system bug.** For a default `largeTitle:true` scroll screen (e.g.
   `actions.json`, root = `scroll`, `largeTitle` unset → defaults true):
   - `ScrollContainer.useBehavior` is `true` (**:293–294**, `(behavior?.largeTitle ?? true)`)
     → `behaviorBody` **synthesizes** its own `Text(screenTitle)` at 34pt inside the
     scroll (**:676–677**), AND
   - `SDUIScrollHeaderChrome` (**ScrollHeader.swift:57–61**, applied at
     **SDUIScreenView.swift:279**) sees `largeTitle == true` and applies the
     **native** `.navigationTitle(title).navigationBarTitleDisplayMode(.large)`.

   So the OS draws a large title in the nav bar *and* we draw a second one in the
   content. The two title systems are **not mutually exclusive** — they should be.
   Either `behaviorBody` should only run when `largeTitle == false`, or the chrome
   should switch to inline when `behaviorBody` owns the title. Right now the "engine
   primitive" large title (:618–634 doc-comment) fights Apple's own.

2. **GeometryReader-in-scroll + PreferenceKey per-frame feedback loop.** The
   `GeometryReader → PreferenceKey → @State offset → re-layout` cycle is the classic
   SwiftUI jank pattern: GeometryReader can only report geometry *after* an
   eval→layout pass, so feeding it back into layout forces an extra layout cycle
   every frame, and a preference that reports a value which alters that value is a
   measurement feedback loop. (fatbobman, "GeometryReader — Blessing or Curse?"
   [fatbobman.com](https://fatbobman.com/en/posts/geometryreader-blessing-or-curse/);
   daily.dev, "SwiftUI Under Load: GeometryReader in every row"
   [app.daily.dev](https://app.daily.dev/posts/swiftui-under-load-what-breaks-when-geometryreader-is-in-every-list-row--dgegpwhmv).)

3. **`safeAreaInset` height coupled to scroll offset** in `sectionsBody`
   (**:480–495**, `heroH = expandedH - (expandedH-compactH)*progress`, :441). Changing
   a `safeAreaInset`'s height changes the scroll view's content offset, which changes
   `offset`, which changes the inset height — an inherent feedback loop the code even
   tries to "damp" with an oversized `range` (:438). This is architectural, not
   tunable; it can bounce/jitter at the collapse boundary.

4. **`AnyView` type-erasure defeats diffing.** `ComponentRegistry.view(for:)` returns
   `AnyView` (**ComponentRegistry.swift:64**). Type erasure prevents SwiftUI's
   structural identity diffing, so an offset change re-evaluates erased subtrees
   instead of cheaply updating them — expensive in a per-frame collapse where the
   header re-renders on every scroll tick.

5. **Material collapse fakes blur with opacity.** The frosted backdrop is
   `Rectangle().fill(.bar).overlay(Color.black.opacity(0.3)).opacity(progress)`
   (**:601–604**; hero backing :492). Fading a *material's opacity* cross-dissolves
   between "no blur" and "full blur" and reads muddy — it does not *intensify* the
   blur radius. The premium effect ramps the material tier (ultraThin→thin→regular)
   or a real variable blur.

6. **No hairline separator on collapse.** None of the paths draw the 0.5pt divider
   that should fade in under the header exactly when it pins (the detail that makes a
   collapsed bar read as "attached" to the content). Absent everywhere.

7. **Hardcoded 42pt title height, 34pt font — not Dynamic Type aware.**
   `behaviorBody` fixes `titleH: CGFloat = 42` (**:637**) and
   `.font(.system(size: 34, weight: .bold))` (**:677**). At larger accessibility text
   sizes the reserved 42pt clips the title and the collapse math desyncs. The native
   large title scales with Dynamic Type; ours does not.

8. **No Reduce Motion gating.** `accessibilityReduceMotion` is honored in
   `Pager.swift:15` and `AccessibilityEnv.swift:119` but **not** in `ScrollContainer`.
   Parallax/scale/rubber-band should collapse to a plain opacity change when the user
   asks for reduced motion.

9. **Two-hop nav cross-fade latency.** The compact nav title is a manual
   `ToolbarItem(.principal)` whose opacity is driven by
   `SDUICollapseProgressKey` → `@Binding progress` (**ScrollHeader.swift:99–116**,
   :67). Scroll → preference → `@State` → toolbar opacity is a multi-frame round-trip,
   so the bar title can visibly lag the large title fading out.

10. **Rubber-band stretch is minimal / missing on heroes.** Only `behaviorBody`
    nudges the *title* scale on overscroll (`stretch = 1 + min(overscroll,120)*0.0016`,
    **:649**). The hero/`collapsingHeader` image never stretches on pull-down — the
    signature "Twitter/Apple Music" elastic header is absent from the visual paths.

11. **No true parallax depth.** `collapsingBody` `.scaleEffect`s the whole expanded
    header uniformly (**:595**); there is no layered motion (image moving slower than
    the title) that gives premium heroes their sense of depth.

12. **120Hz not addressed.** With SwiftUI's body eval on the main thread, the per-frame
    preference→state→re-render loop eats into the ~5ms usable budget at 120Hz, and
    there is no `CADisableMinimumFrameDurationOnPhone` in the Info.plist (without it
    third-party animations are capped at 60fps on ProMotion iPhones — jacobstechtavern,
    "SwiftUI Scroll Performance: the 120FPS challenge"
    [blog.jacobstechtavern.com](https://blog.jacobstechtavern.com/p/swiftui-scroll-performance-the-120fps)).

---

## 2. Best-practice techniques (sourced)

| Technique | Source (URL, ★ if repo) | Why it's better | Applicability to us |
|---|---|---|---|
| **`onScrollGeometryChange(for:of:action:)`** — read `contentOffset`, `contentSize`, `containerSize`, `contentInsets` directly from the scroll view | Apple / Swift-with-Majid [swiftwithmajid.com](https://swiftwithmajid.com/2024/06/25/mastering-scrollview-in-swiftui-scroll-geometry/); HackingWithSwift [hackingwithswift.com](https://www.hackingwithswift.com/quick-start/swiftui/how-to-read-the-size-and-position-of-a-scrollview) — **iOS 18+** | No GeometryReader, no PreferenceKey, no baseline capture, no layout feedback. Fires during scroll with the real offset. Kills weakness #2 and #3. | Replace ALL offset tracking on iOS 18+. Single source of truth for `offset`. |
| **`visualEffect { content, proxy in … }`** — transform scale/offset/blur from a view's geometry with **no layout pass** (GPU-only) | Apple "Creating visual effects" [developer.apple.com](https://developer.apple.com/documentation/SwiftUI/Creating-visual-effects-with-SwiftUI); WWDC24 #10151 [developer.apple.com](https://developer.apple.com/videos/play/wwdc2024/10151/) — **iOS 17+** | The stretchy/parallax header without a per-cell GeometryReader; effects "don't affect view layout," so no thrash. | Hero stretch + parallax + blur ramp. Fixes #10, #11, and the layout half of #2. |
| **`.scrollTransition(_:) { content, phase in … }`** — per-item effects keyed to scroll phase (`.topLeading`/`.identity`/`.bottomTrailing`) | Apple `ScrollTransitionConfiguration` [developer.apple.com](https://developer.apple.com/documentation/swiftui/scrolltransitionconfiguration) — **iOS 17+** | Declarative fade/scale as an element approaches an edge; returns a `VisualEffect` (no layout impact). | Hero title fade + compact-title cross-fade tied to position, not to a `@State` round-trip. Fixes #9 latency. |
| **`safeAreaInset(edge:.top)`** — pin a header outside the scroll content while correctly insetting the content | Apple docs; iOS-17 usage [medium.com](https://medium.com/@kkbhardwaj20/ios-17-unveiling-swiftui-scrollview-modifiers-b057fa1d6567) — **iOS 15+** | Native pinning without offset math; content scrolls under a truly-pinned bar. | Keep for the pinned bar — but **decouple its height from `offset`** (weakness #3). |
| **`LazyVStack(pinnedViews:[.sectionHeaders])`** native sticky headers | YoSwift [yoswift.dev](https://yoswift.dev/swiftui/pinnedScrollableViews/) — **iOS 14+** | Real UIKit pinning, not offset math — buttery by construction. | We already use it in `sectionsBody`/`pinnedBody` (:451, :523) — keep, it's the right call. |
| **`scrollEdgeEffectStyle(_:for:)`** — hard/soft progressive blur where content meets a bar ("Liquid Glass") | createwithswift [createwithswift.com](https://www.createwithswift.com/define-the-scroll-edge-effect-style-of-a-scroll-view-for-liquid-glass/); WWDC25 #323 [developer.apple.com](https://developer.apple.com/videos/play/wwdc2025/323/) — **iOS 26+** | The OS gives you the intensifying-blur-under-bar for free, per edge. | Adopt behind availability for the frosted collapse; fixes #5 on iOS 26. |
| **Native large-title collapse** — `navigationBarTitleDisplayMode(.large)` + `toolbarBackground(.visible, for:.navigationBar)` | Apple NavigationStack docs | The OS collapses the large title into an inline title on scroll, at 120Hz, correctly with Dynamic Type. | Make it the DEFAULT; stop synthesizing when `largeTitle` is on. Fixes #1, #7. |
| **exyte/ScalingHeaderScrollView** — offset→collapse-progress, min/max height interpolation, first-class **snap modes** + custom snap points | [github.com/exyte/ScalingHeaderScrollView](https://github.com/exyte/ScalingHeaderScrollView) — **~1.5k★** | Proven collapse+snap model; `.setHeaderSnapMode()` (immediate / after-deceleration) and `.headerSnappingPositions()` make the collapse land cleanly instead of hovering half-open. | Port the **snap** idea — we have none. Adopt its "single progress value drives everything" architecture. |
| **Classic stretchy-header** — GeometryReader `minY` in `.global`: when `minY>0`, `height = base+minY`, `.offset(y:-minY)` | Daniel Saidi [danielsaidi.com](https://danielsaidi.com/blog/2023/02/05/adding-a-stretchable-header-to-a-swiftui-scroll-view); Kavsoft Twitter-profile [kavsoft.dev](https://kavsoft.dev/twitter_profile_page) | The reference elastic-stretch mechanic; premium feel comes from coordinating image+title+avatar+blur off ONE offset. | The fallback stretch for iOS <17 (use `visualEffect` above 17). Fixes #10/#11 pre-17. |
| **`visualEffect`-based stretchy header (no GeometryReader)** | T. Østlyng [medium.com](https://medium.com/@thomasostlyng/stretchy-headers-in-swiftui-with-visualeffect-fff973568323) | Same stretch, zero layout passes. | Preferred iOS 17+ implementation. |
| **swiftui-introspect** — reach the real `UIScrollView`/`UINavigationBar` | [github.com/siteline/swiftui-introspect](https://github.com/siteline/swiftui-introspect) — **~6.4k★** | Tune bounce, content-inset, and nav-bar scroll-edge appearance where SwiftUI has no knob. | Optional escape hatch for pre-17 fine-tuning; keep off the hot path (issue #450: can drop `scrollEdgeAppearance`). |
| **`accessibilityReduceMotion`** gating | Apple Environment values | Respects the user; App Store expectation. | Gate all scale/parallax/rubber-band → opacity-only. Fixes #8. |
| **`CADisableMinimumFrameDurationOnPhone` = YES (Info.plist)** | jacobstechtavern [blog.jacobstechtavern.com](https://blog.jacobstechtavern.com/p/swiftui-scroll-performance-the-120fps); Dipendra Sharma [dipendrasharma.com](https://dipendrasharma.com/articles/swiftui-240fps-performance-guide/) | Without it, third-party animations cap at 60fps on ProMotion iPhones. | Add to the host app plist. Fixes #12. |
| **Profile hitches with Instruments (Animation Hitches / SwiftUI template)** | dev.to [dev.to](https://dev.to/sebastienlato/swiftui-performance-profiling-with-instruments-practical-guide-389b) | Measures the actual dropped frames rather than eyeballing. | Add a "no hitches on weather.json scroll" acceptance test. |

---

## 3. Prioritized iOS improvement plan (concrete, code-level)

Target: **iOS 13+ compiles**, with clearly-fenced upgrades where a newer API
materially improves feel. The north star is **one offset value → one progress →
all effects**, sourced from the scroll view itself, applied with layout-free
modifiers.

### P0 — Correctness (do first; these are bugs, not polish)

1. **Kill the double-title.** In `ScrollContainer` (**Builtins.swift:293**) change
   `useBehavior` to fire **only when `largeTitle == false`**
   (`(behavior?.largeTitle == false)`), so the synthesized title never coexists with
   the native one. Then in `SDUIScrollHeaderChrome` (**ScrollHeader.swift:57**) keep
   the native `.large` path as the default. Net: `largeTitle:true` → **native OS
   collapse only** (correct, Dynamic-Type-safe, 120Hz); `largeTitle:false` → our
   custom `behaviorBody`/`plainBody` with the nav cross-fade. This alone fixes #1 and
   #7 for the majority of screens and deletes a whole class of layout fighting.

2. **Unify offset tracking into one helper** and delete the three strategies.
   Introduce a single `View.sduiTrackScrollOffset(space:) { offset in … }`:
   - **iOS 18+:** `onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action:` — no GeometryReader, no baseline, no feedback. (Swift-with-Majid, above.)
   - **iOS 13–17 fallback:** the existing named-coordinate-space background reader
     from `behaviorBody` (:709–714) — it's the correct one; make every path use it and
     **retire `.global` + `scrollBaselineY`** (:198, :342, :448, :585). Removes #2's
     feedback for pre-17 and #3's coordinate drift.

3. **Decouple the `sectionsBody` hero from `safeAreaInset` height** (**:480–495**).
   Give the inset a **fixed** height (`expandedH`) and collapse the hero's *contents*
   with `visualEffect`/`scaleEffect` + opacity inside that fixed frame, so the scroll
   view's content offset never changes as a function of `offset`. Kills the feedback
   loop #3 without changing the visual.

### P1 — Feel (the "buttery" work)

4. **Apply the collapse with layout-free modifiers, not `.frame(height:)`
   re-layout.** Where we currently shrink reserved height every frame
   (:578, :684, :441), keep the reserved height **constant** and drive the visual with
   `visualEffect`/`scrollTransition` (iOS 17+) so no layout pass runs during scroll.
   Pre-17 fallback: keep `scaleEffect` (GPU) and animate height only at snap points,
   not continuously.

5. **Ease every path.** Move the smoothstep from `behaviorBody` (:646) into the shared
   helper so `collapsingBody`/`sectionsBody` stop tracking the finger 1:1 (removes the
   "twitch"). Expose the curve as a contract knob (`scrollBehavior.easing`).

6. **Real stretchy hero + parallax.** On pull-down (`offset < 0` / overscroll):
   - iOS 17+: `visualEffect` grows the hero (`scaleEffect(1 + overscroll/H)`, anchor
     `.top`) and moves the image at ~0.7× the title's speed for depth (Østlyng;
     Kavsoft Twitter-profile).
   - Pre-17: classic `minY>0 → height+=minY, .offset(y:-minY)` (Daniel Saidi).
   - Cap the stretch and gate it behind Reduce Motion. Fixes #10/#11.

7. **Blur that intensifies, not opacity that fades.** Replace
   `.fill(.bar).opacity(progress)` (:601–604, :492) with a **material-tier ramp**:
   below a threshold no material; then swap `ultraThinMaterial → thinMaterial →
   regularMaterial` across the collapse (or, iOS 26+, `scrollEdgeEffectStyle(.hard,
   for:.top)`). Fixes #5.

8. **Hairline on collapse.** Add a `Divider().opacity(progress)` (0.5pt, `.separator`)
   at the header's bottom edge, fading in as it pins — in the shared header wrapper so
   all paths get it. Fixes #6.

9. **Tighten the nav cross-fade.** Prefer driving the compact nav title's opacity from
   the same `scrollTransition`/`visualEffect` progress rather than the
   preference→`@Binding` round-trip (**ScrollHeader.swift:67, :99–116**). If the
   principal `ToolbarItem` must stay, at least animate its opacity with the same eased
   `progress` on the same update tick. Fixes #9.

### P2 — Robustness & performance

10. **Reduce `AnyView` on the hot path.** The header slots (`expandedC`/`compactC`/
    hero) re-render every scroll tick through `registry.view` → `AnyView`
    (**ComponentRegistry.swift:64**). Cache the built header `AnyView` in `@State`
    (we already cache the *decoded* `Component` at :309–326 — extend that to the built
    view) so scroll ticks update modifiers on a stable view rather than rebuilding an
    erased subtree. Mitigates #4.

11. **Snap.** Adopt exyte's snap model: when the drag ends between expanded and
    collapsed, animate `progress` to the nearer of {0, 1} with a spring. Expose
    `scrollBehavior.snap: "none" | "onRelease" | "afterDeceleration"`.

12. **Reduce Motion + Dynamic Type.** Gate parallax/scale/rubber-band on
    `@Environment(\.accessibilityReduceMotion)` (→ opacity-only), and derive the
    synthesized title height from a measured `Text` at the current Dynamic Type size
    instead of the hardcoded 42/34 (:637, :677). Fixes #7, #8.

13. **120Hz hygiene.** Add `CADisableMinimumFrameDurationOnPhone = YES` to the
    Playground/host Info.plist; add an Instruments "Animation Hitches" pass over
    `weather.json` as an acceptance gate (dev.to profiling guide, above).

### Availability strategy (keeps iOS 13+ building)

```
sduiCollapseEffect(progress):
  if #available(iOS 17): use visualEffect / scrollTransition        // no layout pass
  else:                  use scaleEffect + offset (GPU) + eased progress
sduiTrackOffset():
  if #available(iOS 18): onScrollGeometryChange                     // no GeometryReader
  else:                  named-coordinate-space background reader   // today's behaviorBody
sduiFrostedBar(progress):
  if #available(iOS 26): scrollEdgeEffectStyle(.hard, for:.top)
  else if #available(iOS 15): material-tier ramp (ultraThin→regular)
  else:                       solid color with opacity ramp
```
Mirror the existing helper style in `ios/Sources/SDUIRender/AvailabilityCompat.swift`
(e.g. `sduiScrollDismissesKeyboardInteractively` at :82) so the fences stay in one file.

---

## 4. Cross-platform port notes (keep it identical)

The three platforms share **one mental model: a single scalar scroll value drives
header geometry.** Encode that scalar (`progress 0→1`) and the easing/snap knobs in
the contract so every renderer computes the same collapse.

### Android — Jetpack Compose

- **Preferred (matches native large title):** Material3 app bars with a
  `TopAppBarScrollBehavior`. Create
  `TopAppBarDefaults.exitUntilCollapsedScrollBehavior(rememberTopAppBarState())`
  (or `enterAlwaysScrollBehavior` for a hero that re-expands on any scroll-down),
  attach `Modifier.nestedScroll(scrollBehavior.nestedScrollConnection)` to the
  `Scaffold`, and pass the **same** behavior to `LargeTopAppBar`. Docs:
  [App bars](https://developer.android.com/develop/ui/compose/components/app-bars),
  [nested-scroll modifiers](https://developer.android.com/develop/ui/compose/touch-input/scroll/nested-scroll-modifiers).
  Map: our `largeTitle:true` → `LargeTopAppBar` + `exitUntilCollapsed`.
- **Custom hero (matches our `behaviorBody`/hero):** implement a
  `NestedScrollConnection.onPreScroll` that accumulates a `headerOffset` state,
  `coerceIn(-headerHeightPx, 0f)`, consumes what it used, passes the rest through;
  bind the header's height/offset/alpha to that state — the direct analog of our
  `offset → progress`. Writeup: Victor Brandalise
  [victorbrandalise.com](https://victorbrandalise.com/nested-scrolling-in-jetpack-compose/).
  Community ref for parallax/pin/snap: **onebone/compose-collapsing-toolbar**
  [github.com](https://github.com/onebone/compose-collapsing-toolbar) (**~566★**) —
  its `parallax()`/`pin()`/`road()` per-child modifiers mirror the effects we want.
- **Sticky sections** = `stickyHeader { }` in a `LazyColumn` (native), matching our
  `pinnedViews:[.sectionHeaders]`.
- **Reduce Motion:** gate on `Settings.Global.ANIMATOR_DURATION_SCALE == 0`.

### Aurora OS — Qt/QML + Silica

Aurora's toolkit descends from Sailfish **Silica**, so the Silica model is the
reference. There is no Material collapsing toolbar; you drive a header from
`Flickable.contentY`:

- Put the content in a `SilicaFlickable` with `contentHeight` set; bind the header's
  `height`/`opacity` (and an image `y` for parallax) to `flickable.contentY` — shrink
  as `contentY` grows, and let overshoot (`contentY < 0`, with `boundsBehavior`
  allowing it) drive the stretch. This is the exact analog of SwiftUI `minY` and
  Compose `headerOffset`. `Flickable` docs:
  [doc.qt.io](https://doc.qt.io/qt-6/qml-qtquick-flickable.html).
- **Pull-to-reveal** (our `revealOnPull` search): use Silica `PullDownMenu` nested in
  the flickable — it reveals on overshoot and plays a bounce-back on release
  ([sailfishos.org](https://sailfishos.org/develop/docs/silica/qml-sailfishsilica-sailfish-silica-pulldownmenu.html/)).
- `PageHeader` is the title element; place it as the first scrolling item and animate
  its `opacity`/`height` off `contentY` for the collapse.
- Qt/QML animations are on the render thread, so the `contentY`-binding approach is
  smooth by construction — the win is to keep the binding pure (no JS layout in the
  handler), just like avoiding layout passes in SwiftUI.

**Contract mapping (one schema, three renderers):**

| Contract | iOS | Compose | Aurora/Silica |
|---|---|---|---|
| `scrollBehavior.largeTitle:true` | `navigationBarTitleDisplayMode(.large)` | `LargeTopAppBar` + `exitUntilCollapsed` | `PageHeader` + `contentY` height binding |
| `collapsingHero` / hero | `visualEffect` collapse (17+) / `scaleEffect` | `NestedScrollConnection.onPreScroll` header | `contentY` → header height/opacity/parallax |
| `sections` (pinning) | `pinnedViews:[.sectionHeaders]` | `LazyColumn { stickyHeader }` | `SectionHeader` in `SilicaListView` |
| `revealOnPull` | overscroll search reveal | `onPreScroll` negative offset | `PullDownMenu` |
| `snap`, `easing`, `range` | shared helper | behavior `AnimationSpec` | `Behavior`/`NumberAnimation` on binding |

---

## 5. Top 8 recommendations, ranked

1. **Fix the double-title bug** — gate `useBehavior` to `largeTitle == false`
   (Builtins.swift:293) so the synthesized title never coexists with the native OS
   large title (ScrollHeader.swift:57). Biggest correctness win; makes most screens
   use Apple's own buttery collapse. *(P0, weakness #1, #7.)*
2. **One offset source, layout-free effects** — a single
   `sduiTrackScrollOffset` (`onScrollGeometryChange` on iOS 18+, named-space reader
   below) feeding `visualEffect`/`scrollTransition` (iOS 17+). Retire `.global`
   +`scrollBaselineY` and the per-frame `.frame(height:)` re-layout. *(P0/P1, #2, #4,
   the core of "never stutters.")*
3. **Break the `safeAreaInset`↔`offset` feedback loop** in `sectionsBody` — fixed
   inset height, collapse the contents inside it. *(P0, #3.)*
4. **Real stretchy hero + parallax on overscroll**, gated by Reduce Motion — the
   signature premium motion we're missing. *(P1, #10, #11, #8.)*
5. **Intensify blur, don't fade opacity** — material-tier ramp, or
   `scrollEdgeEffectStyle` on iOS 26. *(P1, #5.)*
6. **Add the hairline-on-collapse** separator in a shared header wrapper. *(P1, #6.)*
7. **Ease + snap every path** — shared smoothstep + exyte-style snap-on-release so the
   header always lands open or closed. *(P1/P2, #10.)*
8. **120Hz + Dynamic Type hygiene** — `CADisableMinimumFrameDurationOnPhone`,
   measured title height instead of hardcoded 42/34pt, and an Instruments hitch gate on
   `weather.json`. *(P2, #7, #12.)*

---

### Appendix — key sources & star counts

- Apple: [Creating visual effects](https://developer.apple.com/documentation/SwiftUI/Creating-visual-effects-with-SwiftUI) (iOS 17), [ScrollTransitionConfiguration](https://developer.apple.com/documentation/swiftui/scrolltransitionconfiguration) (iOS 17), WWDC24 [#10151](https://developer.apple.com/videos/play/wwdc2024/10151/), WWDC25 [#323](https://developer.apple.com/videos/play/wwdc2025/323/); scroll geometry [swiftwithmajid](https://swiftwithmajid.com/2024/06/25/mastering-scrollview-in-swiftui-scroll-geometry/), [hackingwithswift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-read-the-size-and-position-of-a-scrollview).
- Jank/perf: fatbobman [GeometryReader — Blessing or Curse?](https://fatbobman.com/en/posts/geometryreader-blessing-or-curse/); jacobstechtavern [120FPS challenge](https://blog.jacobstechtavern.com/p/swiftui-scroll-performance-the-120fps); daily.dev [GeometryReader in every row](https://app.daily.dev/posts/swiftui-under-load-what-breaks-when-geometryreader-is-in-every-list-row--dgegpwhmv).
- Repos: **exyte/ScalingHeaderScrollView** [~1.5k★](https://github.com/exyte/ScalingHeaderScrollView); **siteline/swiftui-introspect** [~6.4k★](https://github.com/siteline/swiftui-introspect); **onebone/compose-collapsing-toolbar** [~566★](https://github.com/onebone/compose-collapsing-toolbar); google/accompanist [~1k★+](https://google.github.io/accompanist/).
- Technique writeups: Daniel Saidi [stretchable](https://danielsaidi.com/blog/2023/02/05/adding-a-stretchable-header-to-a-swiftui-scroll-view); Kavsoft [Twitter profile](https://kavsoft.dev/twitter_profile_page); Østlyng [visualEffect stretchy header](https://medium.com/@thomasostlyng/stretchy-headers-in-swiftui-with-visualeffect-fff973568323); YoSwift [pinned views](https://yoswift.dev/swiftui/pinnedScrollableViews/).
- Android: [App bars](https://developer.android.com/develop/ui/compose/components/app-bars), [nested scroll](https://developer.android.com/develop/ui/compose/touch-input/scroll/nested-scroll-modifiers), Brandalise [nested scrolling](https://victorbrandalise.com/nested-scrolling-in-jetpack-compose/).
- Aurora/Qt: [Flickable](https://doc.qt.io/qt-6/qml-qtquick-flickable.html), [Silica PullDownMenu](https://sailfishos.org/develop/docs/silica/qml-sailfishsilica-sailfish-silica-pulldownmenu.html/).

# 18 — Stories Player (Instagram-parity, iOS + Android)

**Goal:** an Instagram / iOS-quality **Stories player** that behaves *identically* on
iOS (SwiftUI) and Android (Jetpack Compose), driven from one contract. iOS already
ships a complete player (`StoriesPlayer`); Android has the *clips* reels feed but
**no stories player**, and the home story rings are dead on Android because the demo
host ignores the `custom{name:"story"}` action they fire.

This doc is the full anatomy, the contract shape, and the concrete build plan.

---

## 0. Where we are today

| Piece | iOS | Android |
|---|---|---|
| Home story rings (gradient orb + label) | `home.json` renders rings; tap fires `custom{name:"story", payload:{index}}` | Same `home.json`, same rings render |
| `custom{name:"story"}` handled | ✅ `PlaygroundHost.custom` → `openStoryIndex` (`ios/Sources/SDUIPlayground/PlaygroundView.swift:52`) | ❌ demo `PlaygroundHost` overrides only `navigate` (`android/app/.../Playground.kt:106`); `custom` falls through the empty default in `SduiHostDelegate` |
| Full-screen player | ✅ `StoriesPlayer` (`ios/Sources/SDUIPlayground/HomeStories.swift:161`) presented via `fullScreenCover` | ❌ does not exist |
| Story *content* source | Native Swift data (`CapabilityStory.all`) — **not** contract-driven | — |
| `clips` (reels) component | ✅ `ClipsView.swift` | ✅ `Clips.kt` (VerticalPager) — this is the *feed*, not the *stories* player |

**Net effect:** tapping a story ring on Android does nothing. The whole gap is (a) a
missing Compose `StoriesPlayer`, (b) an unwired `custom` handler, (c) a full-screen
presentation slot in `PlaygroundApp`.

Note a design smell to fix while we're here: on iOS the *ring content* is JSON
(`home.json`) but the *story pages* are hardcoded Swift (`CapabilityStory.all`). The
ring index is the only bridge. That is fine for the demo but violates the
contract-first north star — see §2 for the contract that closes it.

---

## 1. Full anatomy of an Instagram / iOS stories player

A faithful player is a stack of ~10 mechanisms. iOS `StoriesPlayer` already implements
most; this is the canonical checklist both platforms must match.

### 1.1 The ring avatars (entry point)
- Circular avatar with a **gradient stroke ring**. Unseen = vivid conic/linear
  gradient border; seen = flat grey ring. (IG uses a pink→orange→purple sweep.)
- A thin **gap ring** (background-colored) between border and cover so the cover never
  touches the gradient — the IG/Telegram look.
- Label under the orb, one line.
- Our rings live in `home.json` as `zstack` of `gradient` + `surface` circle + inner
  orb + `icon`, tap = `custom{name:"story", index}`. iOS renders a **live** ring
  (`HomeStoriesRail.bubble`) with an appear spin + staggered spring pop-in; the JSON
  ring is the cross-platform baseline, the native rail is the iOS flourish.

### 1.2 Segmented progress bars (top)
- **One segment per story page**, laid in an HStack across the top with small gaps.
- Each is a rounded track (white @ 30%) with a fill (white @ 100%).
- Fill state per segment: **past = full, future = empty, current = animating 0→1**
  over a per-segment timer (IG default ~5 s image, video = clip length).
- On auto-complete the current bar snaps full and the next begins — **no drain
  animation** and the timer must not be wrapped in an implicit animation, or the old
  bar keeps animating while the next ticks (iOS learned this: `goForward()` sets
  `progress = 0` *outside* `withAnimation`).
- iOS: `Timer.publish(every: 0.02)` + `segmentDuration = 4.0`, fill width =
  `geo.width * (i < active ? 1 : i > active ? 0 : progress)`.

### 1.3 Tap zones
- **Tap left third** → previous segment (or restart current if >~15% elapsed, IG
  behavior), crossing to previous user at the first segment.
- **Tap right two-thirds** → next segment, crossing to next user past the last.
- **Tap-and-hold anywhere** → pause the timer *and hide chrome*; release resumes. A
  hold must **never** advance on release (iOS distinguishes by press duration:
  `held < 0.28s` = tap, else hold).

### 1.4 User-to-user transition (the "cube")
- Horizontal swipe pages between *users* (each user = one story = N segments).
- IG/Snapchat use a **cube/parallax 3D rotation**: the outgoing face rotates away
  around its trailing edge while the incoming face rotates in around its leading edge,
  with a perspective + a slight brightness dip on the turning face.
- The drag must be **live** (two faces visible mid-swipe, follows the finger),
  rubber-banded at the ends, and snap on release. Swiping past the last user closes
  the player (end-of-reel).
- iOS: `rotation3DEffect(angle, axis:(0,1,0), anchor: leading/trailing, perspective:0.6)`
  where `angle = clamp(minX / width * 90, -90, 90)`, driven by a live `dragX`.

### 1.5 Drag-to-dismiss
- Vertical drag down shrinks + translates the whole player and dismisses past a
  threshold (~130 pt or predicted end). Chrome (action bar, scrim) fades with the pull.
- iOS: `dragY`, `scaleEffect(1 - min(dragY,240)/1400)`, dismiss if
  `dy > 130 || predictedEnd > 320`.

### 1.6 Per-segment media
- Each segment carries its own media: **image / video / gradient**. Video segment
  duration = clip length (progress driven by playback time, not a fixed timer);
  image/gradient = fixed duration.
- Loading = shimmering skeleton until buffered (our `clips` already does this; reuse).

### 1.7 Header, caption, reply bar
- Header row: small avatar + author + relative timestamp + close (✕) button. The close
  control is **fixed** (never rotates with the cube) and always hittable.
- Caption / body text over a legibility scrim.
- Bottom **reply bar**: a "Send message" field + like (heart) + share. In our showcase
  this is repurposed as "Copy this screen's JSON" + like + share (iOS `actionBar`).
- A generous **bottom scrim gradient** so overlays read over any media.

### 1.8 Open/close shared-element transition
- IG scales the player *out of* the tapped ring (matched-geometry). SwiftUI:
  `matchedGeometryEffect`; Compose: `SharedTransitionLayout` (or a scale/position
  animation from the ring's bounds for min-version safety — see §5). Optional polish;
  the player is fully functional with a plain fade/scale present.

### 1.9 Haptics & motion
- Segment change = selection tick; user change = soft impact; like = light impact;
  copy/success = notification success. Springs, not linear, for the cube snap and
  dismiss settle.

### Reference implementations (stars + URLs)

| Repo | Stars | Platform | What to borrow |
|---|---|---|---|
| [vipulasri/JetInstagram](https://github.com/vipulasri/JetInstagram) | **842** | Compose | Full IG clone; ExoPlayer reels, like animations, ring rail patterns |
| [teresaholfeld/Stories](https://github.com/teresaholfeld/Stories) | **106** | Android View | `StoriesProgressView` — the canonical segmented progress algorithm (per-segment timers, pause/skip). Port the math to Compose |
| [igor11191708/d3-stories-instagram](https://github.com/igor11191708/d3-stories-instagram) | **47** | SwiftUI | Long-tap pause, tap-next, per-story duration, external gesture control, dark/light |
| [raipankaj/Stories](https://github.com/raipankaj/Stories) | **31** | Compose | Minimal 5-line API: `slideDurationInSeconds`, `touchToPause`, customizable indicator colors — timer + progress pattern |
| [Xiryl/compose-stories](https://github.com/Xiryl/compose-stories) | **10** | Compose | Closest feature match: image/video (URL/URI), auto progress bar, gesture layer (tap left/right, swipe-down dismiss, long-press pause), theming |
| [jboullianne/InstagramStoryTutorial-SwiftUI](https://github.com/jboullianne/InstagramStoryTutorial-SwiftUI) | (tutorial) | SwiftUI | Step-by-step IG story recreation |

Progress-bar technique references:
- [svenjacobs — Segmented progress bar gist](https://gist.github.com/svenjacobs/5b3b4e5c28a2cbfed2007d2e2b5651d0) (Compose)
- [fvilarino — Creating a segmented progress bar in Jetpack Compose](https://fvilarino.medium.com/creating-a-segmented-progress-bar-in-jetpack-compose-40f312f8a568)

**Takeaway:** no single library is a drop-in for our cube + contract-driven segments,
but the highest-signal blend is *teresaholfeld's progress algorithm* +
*Xiryl/compose-stories' gesture layer* + *JetInstagram's polish*, ported onto our
`Component`/`RenderContext` engine so the JSON stays the source of truth.

---

## 2. How the contract should express it

### 2.1 Is `clips` enough? — No.
`clips` is a **vertical, infinite, self-paced feed** (Reels/TikTok): one media per
page, no per-page segments, no auto-advance timer, no segmented progress, no
user-to-user cube. Stories are **horizontal users × vertical-agnostic segments,
timed, auto-advancing, tap-paged**. Different interaction model → **dedicated
component**. We keep `clips` for the reels screen and add `stories`.

### 2.2 Proposed contract: a `stories` component + `story-player` presentation

Reuse existing leaf components (`gradient`, `icon`, `text`, `image`) *inside* each
segment so segment bodies are ordinary SDUI, not a bespoke schema. The `stories`
component only adds the **timing + navigation envelope**.

```jsonc
{
  "type": "stories",
  "modifiers": { "ignoresSafeArea": true },
  "autoAdvance": true,          // master switch; false = manual tap only
  "segmentDuration": 4000,      // default ms per segment (image/gradient)
  "transition": "cube",         // "cube" | "slide" | "fade" (user-to-user)
  "loop": false,                // wrap past last user back to first, or close
  "rings": [                    // the home-rail entry points (optional; mirrors home.json)
    { "label": "Server-driven", "icon": "arrow.triangle.2.circlepath",
      "tint": ["#6666F5", "#754AB5"], "seen": false }
  ],
  "stories": [                  // one entry per USER / ring
    {
      "id": "server-driven",
      "author": "Server-driven",
      "avatar": { "icon": "arrow.triangle.2.circlepath", "tint": ["#6666F5","#754AB5"] },
      "segments": [
        {
          "duration": 4000,                          // per-segment override (video: omit → clip length)
          "media": { "type": "gradient", "colors": ["#6666F5","#4A3DA3"], "direction": "diagonal" },
          // OR "media": { "type": "image", "url": "https://…" }
          // OR "media": { "type": "video", "url": "https://…" }   // duration = clip length
          "body": {                                  // ordinary SDUI, rendered over the media
            "type": "vstack", "alignment": "leading", "spacing": "$token.spacing.md",
            "children": [
              { "type": "icon", "name": "arrow.triangle.2.circlepath", "size": 46, "color": "#FFFFFF" },
              { "type": "text", "value": "Ship whole screens", "style": "$token.typography.largeTitle", "color": "#FFFFFF" },
              { "type": "text", "value": "Your backend returns JSON. The app renders it natively.", "style": "$token.typography.title3", "color": "#FFFFFFEC" }
            ]
          },
          "caption": "Ship whole screens",           // optional shorthand if no body
          "reply": { "placeholder": "Send message", "onSend": { "action": "custom", "name": "reply" } },
          "cta": { "title": "Copy this screen's JSON", "onTap": { "action": "custom", "name": "copyJSON" } }
        }
      ]
    }
  ]
}
```

**Action wiring (unchanged, already correct):** the home ring keeps firing
`custom{name:"story", payload:{index}}`. The host opens the `story-player`
presentation at `index`. This is the minimal-parity path and needs **no schema
change** — it's what iOS already does.

**Two-phase adoption:**
1. **Phase A (immediate parity, no contract change):** Android grows a `StoriesPlayer`
   fed by a Kotlin `CapabilityStory.all` twin (mirroring the iOS native data), and the
   demo host wires `custom{name:"story"}`. Ships story parity this sprint.
2. **Phase B (contract-first, the north-star answer):** promote `CapabilityStory` to
   the `stories` JSON above so the *content* is served, register `stories` in both
   `ComponentRegistry`s, and delete the native twins. Now designers author stories in
   the composer like any other screen, and iOS/Android/Aurora render one payload.

Validator/registry touchpoints for Phase B: add `stories` to `spec/` schema + the
component list surfaced by the MCP (`list_components`), add a conformance fixture
(`docs/blueprint/09-conformance-fixtures.md` pattern), and a golden JSON example under
`examples/`.

---

## 3. Android (Compose) implementation plan

Target file: `android/sdui/src/main/java/dev/sdui/render/Stories.kt` (Phase B
component) and/or `android/app/src/main/java/dev/sdui/demo/StoriesPlayer.kt` (Phase A
demo-host player). Below is the concrete Phase A player; Phase B swaps the hardcoded
`stories` list for `component.prop("stories")`.

### 3.1 State & data
```kotlin
data class StorySegment(val icon: String, val title: String, val body: String, val colors: List<Color>)
data class CapabilityStory(val label: String, val ringIcon: String, val tint: List<Color>, val segments: List<StorySegment>)
// CapabilityStory.all — Kotlin twin of ios/.../HomeStories.swift CapabilityStory.all
```

### 3.2 Segmented progress with `Animatable` + `LaunchedEffect`
Drive the *current* segment's fill with one `Animatable` restarted per segment. This
is the cleanest Compose analogue of the iOS `Timer.publish`.

```kotlin
val progress = remember { Animatable(0f) }

// Restart the timer whenever the (story, segment) changes or pause toggles.
LaunchedEffect(storyIndex, segmentIndex, paused) {
    if (paused) {
        progress.stop()                     // freeze in place
        return@LaunchedEffect
    }
    val remaining = ((1f - progress.value) * segmentDurationMs).toInt()
    progress.animateTo(
        targetValue = 1f,
        animationSpec = tween(durationMillis = remaining, easing = LinearEasing),
    )
    // animateTo returns (completes) only if not cancelled → advance.
    goForward()
}
```
`goForward()`: if `segmentIndex < last` → `segmentIndex++`; else if `storyIndex < last`
→ next story (reset segment); else close. On any manual jump set `progress.snapTo(0f)`
**before** changing indices so the bar doesn't visually rewind.

Progress bars row (port of iOS `progressBars`):
```kotlin
Row(horizontalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.fillMaxWidth()) {
    story.segments.indices.forEach { i ->
        val fill = when {
            i < segmentIndex -> 1f
            i > segmentIndex -> 0f
            else -> progress.value
        }
        Box(Modifier.weight(1f).height(3.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.3f))) {
            Box(Modifier.fillMaxHeight().fillMaxWidth(fill).clip(CircleShape).background(Color.White))
        }
    }
}
```

### 3.3 Tap zones (prev / next / pause)
Use `pointerInput` with `detectTapGestures(onTap = …, onPress = …)`. `onPress` gives a
`tryAwaitRelease()` — the exact hold-to-pause primitive:

```kotlin
Modifier.pointerInput(storyIndex, segmentIndex) {
    detectTapGestures(
        onPress = {
            paused = true
            val released = tryAwaitRelease()   // suspends until finger up/cancel
            paused = false
            // If it was a *quick* tap, detectTapGestures also fires onTap; the hold
            // path just resumes. Guard advance with a duration check if needed.
        },
        onTap = { offset ->
            if (offset.x < size.width * 0.33f) goBack() else goForward()
        },
    )
}
```
`goBack()`: if `progress.value > 0.15f` restart current; else previous segment; else
previous story. Haptics: `LocalHapticFeedback` / `view.performHapticFeedback` on
segment + story change.

### 3.4 User-to-user pager + cube transition
Use `HorizontalPager` (Compose Foundation ≥ 1.4, stable) for snap physics, and apply
the cube via `graphicsLayer` keyed off `pagerState.getOffsetFractionForPage(page)`:

```kotlin
val pagerState = rememberPagerState(initialPage = start) { stories.size }
HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
    val pageOffset = ((pagerState.currentPage - page) + pagerState.currentPageOffsetFraction)
    StoryFace(
        story = stories[page],
        modifier = Modifier.graphicsLayer {
            val angle = pageOffset * 90f                    // cube rotation
            rotationY = angle
            cameraDistance = 12f * density                  // perspective
            transformOrigin = TransformOrigin(if (pageOffset > 0) 0f else 1f, 0.5f) // leading/trailing edge
            alpha = 1f - abs(pageOffset) * 0.15f            // brightness/opacity dip
        },
    )
}
```
Bind the timed progress to `pagerState.currentPage` (settled page) so only the
foreground story ticks. Swiping past the last page → `onClose()`.

### 3.5 Drag-to-dismiss
Wrap the pager in a `Box` with vertical drag detection (separate `pointerInput` using
`detectVerticalDragGestures`, or an `AnchoredDraggable`). Translate + scale the whole
player and dismiss past threshold:

```kotlin
var dragY by remember { mutableFloatStateOf(0f) }
Modifier
    .offset { IntOffset(0, dragY.roundToInt()) }
    .graphicsLayer { scaleX = 1f - (dragY / 1400f); scaleY = scaleX }
    .pointerInput(Unit) {
        detectVerticalDragGestures(
            onVerticalDrag = { _, dy -> if (dy > 0 || dragY > 0) dragY = (dragY + dy).coerceAtLeast(0f) },
            onDragEnd = { if (dragY > 130f) onClose() else dragY = 0f /* animate back */ },
        )
    }
```
Fade the action bar + scrim by `(1 - dragY/70).coerceIn(0,1)` to mirror iOS.

### 3.6 Full-screen presentation + wiring the `custom` action
The demo `PlaygroundHost` currently overrides only `navigate`. Add `custom`:

```kotlin
// android/app/src/main/java/dev/sdui/demo/Playground.kt
private class PlaygroundHost(
    private val known: Set<String>,
    private val push: (String) -> Unit,
    private val openStory: (Int) -> Unit,          // NEW
) : SduiHostDelegate {
    override fun navigate(screen: String, params: Map<String, JsonValue>, transition: String) {
        if (screen in known) push(screen)
    }
    override fun custom(name: String, payload: JsonValue?) {   // NEW — was falling through
        if (name == "story") openStory(payload?.get("index")?.doubleValue?.toInt() ?: 0)
    }
}
```
In `PlaygroundApp`, hold the open index and render the player as a **full-screen
overlay above the Scaffold** (so the bottom nav is covered, matching iOS
`fullScreenCover`):

```kotlin
var openStoryIndex by remember { mutableStateOf<Int?>(null) }
val host = remember(playground, selected) {
    PlaygroundHost(playground.screensById.keys + CATALOG, { stack.add(it) }, { openStoryIndex = it })
}
// … existing Scaffold …
openStoryIndex?.let { start ->
    // Overlay on top of everything; consumes back.
    StoriesPlayer(stories = CapabilityStory.all, start = start, onClose = { openStoryIndex = null })
    BackHandler { openStoryIndex = null }
}
```
Put the overlay *outside* the `Scaffold`'s content padding (e.g. as a sibling in a root
`Box`) and give it `Modifier.fillMaxSize().background(Color.Black)` so it truly covers
the tab bar. Alternatively use a `Dialog(properties = DialogProperties(usePlatformDefaultWidth = false))`
for a real window-level surface — but a root-`Box` overlay keeps the shared-element
transition option open (§5) and avoids Dialog status-bar quirks.

### 3.7 Compose repos to mirror
- Progress algorithm: [teresaholfeld/Stories (106★)](https://github.com/teresaholfeld/Stories)
  `StoriesProgressView` → port to the `Animatable` loop above.
- Gesture layer & dismiss: [Xiryl/compose-stories (10★)](https://github.com/Xiryl/compose-stories).
- Overall polish / reels: [vipulasri/JetInstagram (842★)](https://github.com/vipulasri/JetInstagram).
- Minimal timer API sanity check: [raipankaj/Stories (31★)](https://github.com/raipankaj/Stories).

---

## 4. iOS side — does `StoriesPlayer` already cover it?

**Yes, `StoriesPlayer` (`ios/Sources/SDUIPlayground/HomeStories.swift:161`) is a
complete, gold-standard player.** It covers every §1 mechanism except two, and the
wiring (`custom{name:"story"}` → `fullScreenCover`) is done in two places
(`PlaygroundView.swift:52`, `NavigationDemoView.swift:62`).

Covered: segmented progress bars, tap-left/right + hold-to-pause (duration-gated),
live drag-following **cube** (`rotation3DEffect`), vertical drag-to-dismiss with
scale, per-segment content, header + close, bottom action bar + reply-style CTA, toast,
like, and all the haptics/springs.

### Gaps / follow-ups on iOS (to reach full §1 + Android parity)
1. **Per-segment media = gradient only.** `StorySegment` has no image/video field.
   To honor the §2 contract's `media: {image|video}`, add an `AsyncImage` / `AVPlayer`
   segment path (reuse the `clips` skeleton loader). Low urgency for the showcase.
2. **No shared-element open/close (§1.8).** Present is a plain `fullScreenCover`
   fade. Add `matchedGeometryEffect` from the ring for the IG "grow out of the orb"
   polish. Optional.
3. **Content is native, not contract (§2).** For Phase B, replace `CapabilityStory.all`
   with a `stories` component reading `component.prop("stories")`, registered in
   `ComponentRegistry`. This is the real parity guarantee — otherwise iOS and Android
   each carry a hand-kept native twin that can drift.
4. Minor: segment duration is a single constant (`4.0`); wire `segment.duration` /
   `autoAdvance` from the contract when Phase B lands.

So iOS needs **no work for Phase A parity** — Android just has to match what iOS
already does. iOS gaps 1–4 are the Phase B / polish backlog.

---

## 5. Min-version notes (iOS 13+ / low Android minSdk)

- **iOS 13+:** `rotation3DEffect`, `DragGesture`, `Timer.publish`, `fullScreenCover`
  (iOS 14 for `fullScreenCover` — on iOS 13 fall back to a `ZStack` overlay +
  `.transition`, which the codebase already gates elsewhere). `matchedGeometryEffect`
  is iOS 14+, so keep the shared-element transition **optional** and feature-gate it;
  the plain present works on 13.
- **Android:** `HorizontalPager`/`VerticalPager` are stable in Compose Foundation
  (androidx.compose.foundation ≥ 1.4) and run on **minSdk 21** — no version risk;
  `Clips.kt` already uses `VerticalPager`. `Animatable`, `graphicsLayer`,
  `detectTapGestures(onPress/tryAwaitRelease)`, `detectVerticalDragGestures`,
  `BackHandler` are all core Compose, minSdk-agnostic.
- **Avoid** `SharedTransitionLayout` (Compose 1.7+ / recent) for the open transition if
  you need a low Compose floor — implement the ring→player grow with a manual
  scale/offset animation from the ring's `onGloballyPositioned` bounds instead. Keep it
  optional so the base player ships everywhere.
- **No third-party dependency required** on either platform: everything above is
  first-party SwiftUI / Compose, matching the repo's zero-hack, best-practice-native
  mandate.

---

## 6. Task checklist

**Phase A — parity (this sprint):**
- [ ] `android/app/.../StoriesPlayer.kt` — Compose player (§3.1–3.6).
- [ ] `CapabilityStory.all` Kotlin twin (mirror `HomeStories.swift`).
- [ ] `Playground.kt` — `PlaygroundHost.custom` override + `openStoryIndex` overlay + `BackHandler`.
- [ ] Verify on emulator: rings tap → player opens at index, bars auto-advance, tap L/R, hold pause, cube swipe, drag-dismiss.

**Phase B — contract-first (north star):**
- [ ] `stories` component in `spec/` schema + validator + MCP `list_components` + golden `examples/` JSON.
- [ ] Register `stories` in iOS + Android `ComponentRegistry`; render `component.prop("stories")`.
- [ ] Add image/video segment media on both platforms (reuse `clips` loader/ExoPlayer).
- [ ] Delete native `CapabilityStory` twins once JSON-driven.
- [ ] Conformance fixture per `09-conformance-fixtures.md`.

---

### Sources
- [vipulasri/JetInstagram — 842★](https://github.com/vipulasri/JetInstagram)
- [teresaholfeld/Stories — 106★](https://github.com/teresaholfeld/Stories)
- [igor11191708/d3-stories-instagram — 47★](https://github.com/igor11191708/d3-stories-instagram)
- [raipankaj/Stories — 31★](https://github.com/raipankaj/Stories)
- [Xiryl/compose-stories — 10★](https://github.com/Xiryl/compose-stories)
- [jboullianne/InstagramStoryTutorial-SwiftUI](https://github.com/jboullianne/InstagramStoryTutorial-SwiftUI)
- [svenjacobs — Segmented progress bar (Compose gist)](https://gist.github.com/svenjacobs/5b3b4e5c28a2cbfed2007d2e2b5651d0)
- [fvilarino — Segmented progress bar in Jetpack Compose](https://fvilarino.medium.com/creating-a-segmented-progress-bar-in-jetpack-compose-40f312f8a568)

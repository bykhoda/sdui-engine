# 19 — Functional screens & sheets: making reels/feed do something

> Owner's ask: *"приведи пример на reels (clips). Там есть лайки, комменты, репост —
> они должны открывать какие-то модалки, как это в реальных аппках работает."*
>
> Today `clips` ([`ios/.../ClipsView.swift`](../../ios/Sources/SDUIRender/ClipsView.swift),
> [`android/.../Clips.kt`](../../android/sdui/src/main/java/dev/sdui/render/Clips.kt))
> is a beautiful **mock**: the like toggle, comment count, share and "…" are hard-coded
> Swift/Compose state that goes nowhere. Tapping the comment bubble does *nothing*; the
> like never reaches a backend. This doc turns those affordances into real,
> contract-driven behaviour — a **like that persists optimistically**, a **comments
> bottom-sheet** that is itself a server-driven screen, and a **share/repost sheet** —
> **without adding one line of feature-specific native code.**

Status: **design.** The load-bearing discovery below is that ~80% of the mechanism
already exists in the contract; the work is (1) closing three small gaps, (2) rewriting
`clips` to emit actions instead of swallowing them.

---

## 0. What already exists (so we don't reinvent it)

The action vocabulary and navigation layer are further along than the `clips` mock suggests:

| Capability | Where | State |
|---|---|---|
| `navigate` with `transition: "push" \| "sheet" \| "fullScreenCover" \| "replace"` | [`sdui.schema.json` L628–633](../../spec/schema/sdui.schema.json), both `ActionInterpreter`s | **Done.** iOS wires `sheet`→`.sheet(item:)`, `fullScreenCover`→`.fullScreenCover` in [`Navigation.swift` L128–147](../../ios/Sources/SDUIRender/Navigation.swift). |
| `dismiss` — closes a modal if one is up, else pops the stack | [`Navigation.swift` L76–78](../../ios/Sources/SDUIRender/Navigation.swift) | **Done.** `SDUINavigator.dismiss()` checks `sheet`/`cover` first. |
| Detent sheet with drag indicator + **pre-iOS-16 fallback** | [`AvailabilityCompat.swift` L96–150](../../ios/Sources/SDUIRender/AvailabilityCompat.swift): `sduiMediumDetents`, `sduiHeightDetents`, `sduiFractionDetents` | **Done but unwired** — detents are hard-coded `[.medium,.large]`; the contract can't choose them. |
| `request` with `onSuccess` / `onError` branches, response under `$data.<id>` | [schema L638–639](../../spec/schema/sdui.schema.json), both interpreters | **Done.** This is the whole optimistic-mutation engine. |
| `setState` / `increment` for client-local state | both interpreters | **Done.** |
| `share` → system share sheet, `haptic`, `showToast` | both interpreters | **Done.** |

**So the "modal" the owner wants is mostly a matter of *pointing the existing
`navigate transition:sheet` at a server-driven comments screen* — plus three gaps:**

- **G1 — detents in the contract.** `navigate transition:sheet` should carry a `sheet: { detents: [...] }` so a comments sheet can open at `large` and a repost sheet at a fitted height. The iOS compat helpers already exist; they're just not fed from JSON.
- **G2 — Android has no modal host.** The Android `ActionHost.navigate` just forwards `transition` to an app delegate ([`SduiScreen.kt` L146–147](../../android/sdui/src/main/java/dev/sdui/render/SduiScreen.kt)); the SDK ships **no** `ModalBottomSheet`. iOS presents sheets in-SDK; Android must match to keep parity.
- **G3 — `clips` swallows its taps.** `ClipsView`/`Clips.kt` own their like/comment/share state internally instead of reading per-page `onLike`/`onComment`/`onShare` actions from the JSON.

---

## 1. Interaction anatomy of real reels

Sources are teardowns + the SDUI frameworks we benchmark. Star counts are **approximate**
(GitHub API rate-limited on research date 2026-07-30, consistent with [doc 17](17-mcp-ai-authoring.md)).

TikTok's comment panel *"slides in from the bottom as a modal overlaid over ~75% of the
video, which continues to play in the background"* — keeping the user in-context is the
entire point ([TikTok vs Instagram comments UX](https://medium.com/@danielledrislane/tiktok-vs-instagram-comments-ux-analysis-8a43597937d1),
[UI Sources: TikTok comments bottom sheet](https://www.uisources.com/interaction/4-tiktok-comments)).
The right-side action rail sits in the thumb zone so every affordance is reachable one-handed
([Iterators: 5 TikTok UI choices](https://www.iteratorshq.com/blog/5-tiktok-ui-choices-that-made-the-app-successful/)).

| Affordance | What Instagram / TikTok / YT-Shorts actually do | Presentation | Our contract expresses it as |
|---|---|---|---|
| **Like (tap heart)** | Icon fills red + scales, count `+1` **instantly** (optimistic), request fires in background, rolls back on failure | **Inline** on the rail | `sequence[ setState optimistic → increment count → request(onError: rollback) ]` (§2b) |
| **Double-tap heart** | Big heart bursts centre-screen; also likes (idempotent — never un-likes) | **Inline** overlay | Same like action, guarded so it only ever *sets* liked=true |
| **Comments** | Panel slides up over the still-playing video; header shows count; scrollable list of comments (avatar, @user, text, per-row like + reply); sticky **composer** (text field + emoji + Send) pinned to the keyboard at the bottom | **Bottom sheet** (~75–90% height, video visible behind) | `navigate → screen "comments", transition:"sheet", sheet:{detents:["large"]}` — the sheet **is** a normal SDUI screen: `list` + sticky `textfield` composer (§3) |
| **Share / Repost** | Two flavours: (a) **system share sheet** (Messages, copy link, external apps); (b) an **in-app repost/send-to modal** — a horizontal row of friends/DMs + "Add to story"/"Repost" tiles | (a) system sheet · (b) **bottom sheet** | (a) `share` action · (b) `navigate transition:sheet` to a `share-sheet` screen |
| **Follow** | Inline "Follow" pill flips to "Following" optimistically | **Inline** | `setState` + `request(onError: rollback)` |
| **Save / Bookmark** | Icon fills, brief toast "Saved to collection"; sometimes a collection-picker sheet | **Inline** (+ optional sheet) | `request` + `showToast`; picker = another `sheet` |
| **"…" More menu** | Not seen interested / Report / Copy link / Manage / Why you're seeing this | **Bottom sheet** (action list) | `navigate transition:sheet` to a `clip-menu` screen (a `list` of rows, each with its own `onTap`) |
| **Sound / Mute** | Tap toggles mute; spinning audio disc opens the **audio detail** page (all clips using this sound) | Inline toggle · full-screen push for audio page | `setState` toggle · `navigate transition:push` |

**Framework precedent (cite in review):**
- **DivKit** (Yandex, ≈ 2.6k★ — [github.com/divkit/divkit](https://github.com/divkit/divkit)) models overlays declaratively with **`div-tooltip`**: fields `mode` (`{type:modal}` vs non-modal), `close_by_tap_outside` (default `true`), `position`, `animation_in`/`animation_out`, and `tap_outside_actions`; overlays are shown/hidden with **`show_tooltip` / `hide_tooltip` actions** ([div-tooltip docs](https://divkit.tech/docs/en/concepts/divs/2/div-tooltip)). The lesson: *a modal is data + a named action, never native glue.* Our analogue is `navigate transition:sheet` + `dismiss`.
- **Airbnb Ghost Platform** ([A deep dive into Airbnb's SDUI](https://medium.com/airbnb-engineering/a-deep-dive-into-airbnbs-server-driven-ui-system-842244c5f5)): *"Screens can be launched in a **modal (popup)**, in a **bottom sheet**, or as a **full screen**, depending on values included in the `screenProperties` field."* — the exact three-way presentation split we already have in `transition`. This validates presentation-as-a-property-of-navigation over a bespoke "openCommentsSheet" verb.
- **Beagle** (ZupIT, ≈ 1.5k★, archived — [github.com/ZupIT/beagle](https://github.com/ZupIT/beagle)) and **Epoxy** (Airbnb, Android ≈ 8.9k★ / [epoxy-ios](https://github.com/airbnb/epoxy-ios) ≈ 0.7k★) both drive modal presentation from a declarative route/screen model, not per-feature code.

---

## 2. How our contract expresses it (no bespoke native code)

### 2a. Sheet / presentation — extend `navigate`, don't invent `present`

We already have `navigate transition:"sheet"`. The **only** missing knob is *which detents*.
Recommendation: **keep one verb** (`navigate`) and add an optional `sheet` object, rather than
adding a parallel `present` action — one navigation concept, one code path, parity for free.
(`present`/`dismiss` as aliases were considered and rejected: they'd double the surface and
Android would need two hosts. `dismiss` already closes sheets.)

Proposed schema addition to the `navigate` branch:

```jsonc
{
  "action": "navigate",
  "to": "comments",
  "transition": "sheet",                 // push | sheet | fullScreenCover | replace  (exists)
  "params": { "clipId": "$item.id" },    // passed to the sheet screen (exists)
  "sheet": {                             // NEW — ignored unless transition == "sheet"
    "detents": ["large"],                // subset of: "small" | "medium" | "large"
                                         //   | { "fraction": 0.9 } | { "height": 320 }
    "dragIndicator": true,               // default true
    "dismissible": true,                 // tap-scrim / swipe-down to close (default true)
    "cornerRadius": 24                   // optional; platform default otherwise
  }
}
```

Mapping (all mechanisms **already present** in `AvailabilityCompat.swift`):

| `detents` value | iOS 16+ | iOS 15 fallback | Android (material3) |
|---|---|---|---|
| `["medium","large"]` | `.presentationDetents([.medium,.large])` (`sduiMediumDetents`) | full-height sheet | `ModalBottomSheet` (partial→expand) |
| `[{"fraction":0.9}]` | `sduiFractionDetents(0.9)` | full-height | `sheetState` at 90% |
| `[{"height":320}]` | `sduiHeightDetents(320)` | full-height | fixed-height sheet |
| `["large"]` | `.presentationDetents([.large])` | full-height | expanded `ModalBottomSheet` |

Dismissal stays as the existing **`dismiss`** action (the sheet screen's Close button / a
swipe-down both call it). No new dismiss verb needed.

### 2b. Optimistic like via `setState` + `request(onError:)` — exact JSON

This is the pattern the owner cares about ("как в реальных аппках"): the UI moves *now*,
the network catches up, and a failure silently reverts. Every piece already runs on both
platforms.

```json
{
  "action": "sequence",
  "actions": [
    { "action": "haptic", "style": "light" },
    { "action": "setState", "key": "liked_$item.id", "value": true },
    { "action": "increment", "key": "likes_$item.id", "by": 1 },
    {
      "action": "request",
      "source": {
        "id": "likeClip",
        "service": "feed",
        "path": "/clips/{clipId}/like",
        "method": "POST",
        "body": { "clipId": "$item.id" }
      },
      "onError": {
        "action": "sequence",
        "actions": [
          { "action": "setState", "key": "liked_$item.id", "value": false },
          { "action": "increment", "key": "likes_$item.id", "by": -1 },
          { "action": "showToast", "message": "Couldn't like — try again", "style": "error" }
        ]
      }
    }
  ]
}
```

Notes:
- `onSuccess` is optional here — the optimistic write already reflects the happy path; we
  only need `onError` to roll back. (Add `onSuccess` if the server returns the authoritative
  count in `$data.likeClip.count` and you want to reconcile.)
- **Double-tap** uses the *same* source but its client-side branch only ever sets
  `liked=true` (never toggles off), matching real apps where double-tap is idempotent.
- The rail icon/tint/count now **bind** to `$state.liked_<id>` / `$state.likes_<id>` instead
  of `ClipsView`'s private `@State`. That's gap **G3**.

### 2c. `custom` is the last resort

`custom` (both interpreters, forwarded to the host `appDelegate`) is the escape hatch for
things the closed vocabulary genuinely can't express — e.g. hooking a proprietary video
SDK's PiP, or an in-house analytics consent flow. **It must not be used for like/comment/
share**, all of which decompose into `setState`/`increment`/`request`/`navigate`/`share`
above. Rule of thumb, in order of preference:

1. **Compose existing actions** (`sequence` + `setState`/`increment`/`request`/`navigate`).
2. If a *presentation* is missing, add a **declarative field** (like `sheet.detents`) — still data.
3. Only if it needs a **native capability with no cross-platform contract** → `custom`,
   and then open a ticket to promote it into the vocabulary (the path `requestPermission`,
   `requireVersion`, `preview` already took).

---

## 3. A concrete functional `clips` screen

Three screens: the feed, the comments bottom-sheet, the share/repost bottom-sheet. All three
work the moment **G1 (sheet.detents)** and **G3 (per-page actions in `clips`)** land — no
per-feature native code.

### 3a. `clips.json` — the feed, now wired

```json
{
  "version": "0.1",
  "screen": {
    "id": "clips",
    "chrome": "immersive",
    "state": {
      "liked_c1": false, "likes_c1": 12400,
      "liked_c2": false, "likes_c2": 48100
    },
    "content": {
      "type": "clips",
      "modifiers": { "ignoresSafeArea": true, "size": { "width": { "mode": "fill" }, "height": { "mode": "fill" } } },
      "pages": [
        {
          "id": "c1",
          "colors": ["#FF6A88", "#FF99AC", "#6A3093"],
          "author": "@nova.films",
          "caption": "Golden hour over the north ridge — one take, no filter.",
          "audio": "Original audio · Nova",
          "likes": "$state.likes_c1",
          "liked": "$state.liked_c1",
          "comments": "318",
          "shares": "1.2K",
          "onLike": {
            "action": "sequence",
            "actions": [
              { "action": "haptic", "style": "light" },
              { "action": "setState", "key": "liked_c1", "value": true },
              { "action": "increment", "key": "likes_c1", "by": 1 },
              {
                "action": "request",
                "source": { "id": "likeClip", "service": "feed", "path": "/clips/c1/like", "method": "POST" },
                "onError": {
                  "action": "sequence",
                  "actions": [
                    { "action": "setState", "key": "liked_c1", "value": false },
                    { "action": "increment", "key": "likes_c1", "by": -1 },
                    { "action": "showToast", "message": "Couldn't like — try again", "style": "error" }
                  ]
                }
              }
            ]
          },
          "onComment": {
            "action": "navigate",
            "to": "comments",
            "transition": "sheet",
            "params": { "clipId": "c1" },
            "sheet": { "detents": ["large"], "dragIndicator": true }
          },
          "onShare": {
            "action": "navigate",
            "to": "share-sheet",
            "transition": "sheet",
            "params": { "clipId": "c1" },
            "sheet": { "detents": [{ "height": 320 }, "large"] }
          },
          "onMore": {
            "action": "navigate",
            "to": "clip-menu",
            "transition": "sheet",
            "params": { "clipId": "c1" },
            "sheet": { "detents": [{ "fraction": 0.5 }] }
          }
        }
      ]
    }
  }
}
```

### 3b. `comments.json` — the comments bottom-sheet is just a screen

Rendered inside the sheet by the existing `sheet` transition. It reuses ordinary components:
a `list` of comment rows + a pinned `textfield` composer (both already in the catalog). Its
rows come from a `request`/data source keyed by the `clipId` param.

```json
{
  "version": "0.1",
  "screen": {
    "id": "comments",
    "title": "Comments",
    "data": {
      "sources": [
        { "id": "comments", "service": "feed", "path": "/clips/{clipId}/comments", "method": "GET", "policy": "cacheThenNetwork" }
      ]
    },
    "content": {
      "type": "vstack",
      "modifiers": { "size": { "width": { "mode": "fill" }, "height": { "mode": "fill" } } },
      "children": [
        {
          "type": "list",
          "modifiers": { "size": { "height": { "mode": "fill" } } },
          "data": "$data.comments.items",
          "row": {
            "type": "hstack",
            "spacing": "$token.spacing.sm",
            "modifiers": { "padding": "$token.spacing.md" },
            "children": [
              { "type": "avatar", "url": "$item.avatar", "size": 36 },
              {
                "type": "vstack",
                "spacing": "$token.spacing.xs",
                "children": [
                  { "type": "text", "value": "$item.author", "style": "$token.typography.subheadlineSemibold" },
                  { "type": "text", "value": "$item.text", "style": "$token.typography.body" }
                ]
              },
              { "type": "spacer" },
              {
                "type": "vstack", "alignment": "center", "spacing": "$token.spacing.xs",
                "children": [
                  { "type": "icon", "name": "heart", "size": 16, "modifiers": {
                      "onTap": { "action": "request", "source": { "id": "likeComment", "service": "feed", "path": "/comments/{id}/like", "method": "POST", "params": { "id": "$item.id" } } } } },
                  { "type": "text", "value": "$item.likes", "style": "$token.typography.caption2" }
                ]
              }
            ]
          }
        },
        {
          "type": "hstack",
          "spacing": "$token.spacing.sm",
          "modifiers": { "padding": "$token.spacing.md", "background": "$token.color.surface" },
          "children": [
            { "type": "textfield", "placeholder": "Add a comment…", "bind": "$state.draft", "modifiers": { "size": { "width": { "mode": "fill" } } } },
            {
              "type": "button", "title": "Send", "style": "$token.button.small",
              "onTap": {
                "action": "sequence",
                "actions": [
                  {
                    "action": "request",
                    "source": { "id": "postComment", "service": "feed", "path": "/clips/{clipId}/comments", "method": "POST", "body": { "text": "$state.draft" } },
                    "onSuccess": { "action": "sequence", "actions": [
                      { "action": "setState", "key": "draft", "value": "" },
                      { "action": "refresh", "sources": ["comments"] }
                    ] },
                    "onError": { "action": "showToast", "message": "Comment failed to send", "style": "error" }
                  }
                ]
              }
            }
          ]
        }
      ]
    }
  }
}
```

### 3c. `share-sheet.json` — repost/send-to modal (+ system share)

The in-app repost modal is a fitted-height sheet (a friend row + tiles). The pure "share
externally" tile uses the existing **`share`** action → the OS share sheet.

```json
{
  "version": "0.1",
  "screen": {
    "id": "share-sheet",
    "content": {
      "type": "vstack",
      "spacing": "$token.spacing.lg",
      "modifiers": { "padding": "$token.spacing.lg" },
      "children": [
        { "type": "text", "value": "Send to", "style": "$token.typography.title3" },
        {
          "type": "hstack", "spacing": "$token.spacing.md",
          "children": [
            { "type": "button", "title": "Repost", "style": "$token.button.secondary",
              "onTap": { "action": "sequence", "actions": [
                { "action": "request", "source": { "id": "repost", "service": "feed", "path": "/clips/{clipId}/repost", "method": "POST" },
                  "onSuccess": { "action": "sequence", "actions": [ { "action": "showToast", "message": "Reposted", "style": "success" }, { "action": "dismiss" } ] },
                  "onError": { "action": "showToast", "message": "Repost failed", "style": "error" } }
              ] } },
            { "type": "button", "title": "Copy link", "style": "$token.button.secondary",
              "onTap": { "action": "share", "url": "https://app.example/clips/{clipId}" } },
            { "type": "button", "title": "More…", "style": "$token.button.secondary",
              "onTap": { "action": "share", "text": "Check this clip", "url": "https://app.example/clips/{clipId}" } }
          ]
        }
      ]
    }
  }
}
```

---

## 4. Cross-platform implementation notes

**iOS** — everything is in place; just feed `sheet.detents` into the existing helpers.
- `navigate transition:sheet` already renders through `.sheet(item: $navigator.sheet)`
  ([`Navigation.swift` L128–135](../../ios/Sources/SDUIRender/Navigation.swift)). Change the
  hard-coded `.sduiMediumDetents()` to select from the route's `sheet.detents`:
  `["large"]`→`.presentationDetents([.large])`, `{fraction}`→`sduiFractionDetents`,
  `{height}`→`sduiHeightDetents` (all in [`AvailabilityCompat.swift`](../../ios/Sources/SDUIRender/AvailabilityCompat.swift)).
- **Min version stays low.** `presentationDetents` is iOS 16+, but the compat helpers already
  no-op to a plain full-height `.sheet` on **iOS 15**, so the sheet still presents everywhere;
  only the partial-height detent is lost pre-16. Requires threading `sheet` config onto
  `SDUIRoute` (add a `sheet: SheetConfig?`).

**Android** — the real work (gap **G2**). The SDK forwards `transition` to a delegate but
ships no modal host. Add a `ModalBottomSheet` (material3, `androidx.compose.material3`) to the
navigator, mirroring iOS:
- Hold `var sheetRoute by remember { mutableStateOf<Route?>(null) }`; when
  `navigate(transition="sheet")` arrives, set it; render `ModalBottomSheet(onDismissRequest = { sheetRoute = null }) { SduiScreen(sheetRoute) }`.
- Map detents to `rememberModalBottomSheetState(skipPartiallyExpanded = …)` / a fixed-height
  `Modifier.height` for `{height}`, `fillMaxHeight(fraction)` for `{fraction}`. `dragIndicator`
  → the built-in drag handle. `material3` `ModalBottomSheet` is available from Compose Material3
  1.1 (minSdk 21), so **no min-version cost**.
- `dismiss` must clear `sheetRoute` (parity with iOS `dismissModal`).

**Aurora (Qt/QML/Silica)** — the same `transition:sheet` + `sheet.detents` maps to Silica's
bottom `Drawer` / a `Dialog` anchored to the bottom edge, or a `PanelBackground` slide-up.
Detents become drawer open-height states. No contract change — this is the third renderer
consuming identical JSON, per [doc 02](02-launch-aurora.md). Placeholder until the Aurora
renderer exists.

**Parity checklist to close before this ships:**
1. **G1** — add `sheet` object to the `navigate` branch in
   [`sdui.schema.json`](../../spec/schema/sdui.schema.json); decode into `SDUIRoute`/Kotlin `Route`.
2. **G2** — Android `ModalBottomSheet` host + `dismiss` clears it.
3. **G3** — `clips` reads per-page `onLike`/`onComment`/`onShare`/`onMore`/`liked`/`likes`
   from JSON and fires them through the interpreter, instead of owning private `@State`/`mutableStateListOf`.
4. Add `clips.json`, `comments.json`, `share-sheet.json` to the playground corpus + a
   conformance fixture ([doc 09](09-conformance-fixtures.md)) proving both platforms present
   the same sheet for the same JSON.
```

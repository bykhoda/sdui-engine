# Design notes: prior art and cross-platform rules

This engine is designed against the record of the teams who built Server-Driven
UI at scale. The goal is to take their proven ideas and avoid their documented
mistakes, so a single JSON contract renders faithfully on both SwiftUI and
Compose.

## What the field already learned

**Yandex DivKit** ([divkit.tech](https://divkit.tech/en/)) is the closest prior
art: an open JSON contract with a code-generated SDK on iOS, Android, web and
Flutter. Its best idea is an **explicit sizing model** — every node declares
`match_parent` / `wrap_content` / `fixed` with optional `min`/`max` and a
`weight` for proportional space
([layout docs](https://divkit.tech/docs/en/concepts/layout)) — and a **typed
expression language** with a fallback operator that degrades gracefully on
evaluation failure ([expressions](https://divkit.tech/docs/en/concepts/expressions)).
Its main limitation, and our opportunity: DivKit's component set is closed — you
cannot register your own native views without forking the engine
([comparison](https://nativeblocks.io/blog/nativeblocks-vs-divkit/)).

**Airbnb's Ghost Platform**
([engineering blog](https://medium.com/airbnb-engineering/a-deep-dive-into-airbnbs-server-driven-ui-system-842244c5f5))
splits the world into data-carrying **Sections** and **Screens** that place them,
and deliberately keeps *layout selection* on the client so each device picks the
right layout for its form factor. Lesson: the server owns data and composition;
the client owns device-adaptive presentation.

**Lyft** ([engineering blog](https://eng.lyft.com/the-journey-to-server-driven-ui-at-lyft-bikes-and-scooters-c19264a0378e))
found that fully *declarative* components (serialising a native view wholesale)
are hard to animate and let the payload grow without bound. They favour
**semantic** components — the server names the intent, the client owns the look.

**ZupIT Beagle** ([archived](https://github.com/zup-archive/beagle-android)) tried
to own the entire app across four platforms and became unmaintainable; its
successor Nimbus is deliberately lightweight. **Spotify HubFramework**
([archived](https://github.com/spotify/HubFramework)) went fully generic too
early and traded readability for flexibility. **Nubank**
([blog](https://building.nubank.com/server-driven-ui-framework-at-nubank/))
keeps decentralised screens consistent by validating every component against the
design system.

## Decisions this drives

1. **Small semantic core + native escape hatch.** Ship a compact set of semantic
   primitives, and let host apps register `custom.*` native components from day
   one — the thing DivKit and Beagle couldn't do cleanly. Stay lightweight and
   incrementally adoptable; never try to own the whole app.
2. **Contract is the source of truth**, code-generated per platform, with
   forward-compatible degradation: unknown components and missing bindings
   render safely rather than crashing (already implemented).
3. **Semantic over fully-declarative** components, following Lyft.
4. **Design-system enforcement** in the validator, following Nubank.

## Cross-platform rules the contract must follow

SwiftUI and Compose disagree in enough places that a neutral contract has to make
the differences *explicit fields* rather than trusting either platform's default.

- **Sizing — explicit per-axis `fixed | hug | fill | weight`** with `min`/`max`.
  Never rely on defaults. Note the mapping is not identity: Compose `weight` is
  proportional, while SwiftUI approximates it with `.frame(maxWidth: .infinity)`
  plus `layoutPriority`
  ([layoutPriority](https://www.hackingwithswift.com/quick-start/swiftui/how-to-control-layout-priority-using-layoutpriority)).
  *(Planned for v0.2 — today's `frame` modifier is the interim.)*
- **Typography** — declare line-height as an explicit multiplier and set
  `includeFontPadding=false` + `LineHeightStyle(trim=Both)` on Android so text
  metrics match SwiftUI
  ([font padding](https://medium.com/androiddevelopers/fixing-font-padding-in-compose-text-768cd232425b));
  scale sizes with Dynamic Type / `sp`; require explicit `lineLimit` and
  truncation mode.
- **Lists** — require a **stable `id` per item**. Keys drive diffing and scroll
  restoration, and `LazyVStack` and `LazyColumn` recycle differently
  ([List vs LazyVStack](https://fatbobman.com/en/posts/list-or-lazyvstack/)).
  Restore scroll position by item id, not index.
- **Images** — always carry intrinsic aspect ratio or explicit size to reserve
  space, or both `AsyncImage` and Coil cause layout jumps
  ([AsyncImage](https://swiftwithmajid.com/2021/07/07/mastering-asyncimage/)).
  *(The `image.loader.aspectRatio` field already does this.)*
- **Gestures** — a semantic `minTouchTarget` token resolving to 44pt / 48dp;
  model long-press and swipe as intents, not platform gesture APIs.
- **Navigation** — fully serialisable nav state (route + params); model
  sheets/modals as a distinct presentation layer, since both platforms keep them
  off the main back stack ([Compose backstack](https://developer.android.com/guide/navigation/backstack)).
- **Insets & keyboard** — emit intent flags (`respectsKeyboard`, safe-area
  edges): SwiftUI auto-avoids the keyboard, Compose needs explicit `imePadding()`
  ([Compose insets](https://developer.android.com/develop/ui/compose/system/insets-ui)).
- **Theming** — unitless semantic tokens with explicit light **and** dark
  palettes (dark mode is a separate palette, not an inversion).
- **Accessibility** — require explicit `role` + `label` per node; a control read
  as a button by VoiceOver is not automatically labelled for TalkBack.

## How these shape the roadmap

The interim `frame` modifier will be replaced by the explicit sizing model in
v0.2; list item identity, typography metrics, accessibility fields, and the
dark-palette token structure are folded into the same contract pass. See the
roadmap in [`README.md`](../README.md).

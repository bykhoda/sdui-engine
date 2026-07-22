# SDUI — Server-Driven UI engine for mobile

Ship whole screens from your backend as JSON. One contract renders natively on
**iOS (SwiftUI)** and **Android (Jetpack Compose)** — same payload, same
requests, no client release to change a screen.

> Status: **v0.1 — foundation.** Core contract, iOS renderer for the primitive
> component set, declarative networking, and the action interpreter are
> implemented and unit-tested. See the [roadmap](#roadmap).

## Why

Most product screens are content- and config-driven: feeds, forms, onboarding,
promos, settings, detail pages, checkouts. Those don't need a native release to
change. SDUI moves them to the backend behind a strict, versioned JSON contract,
so:

- **One payload, two platforms.** The contract is platform-neutral. `vstack` →
  `VStack` / `Column`; `$token.spacing.md` resolves from a shared token file.
  Backends ship one response; iOS and Android share requests.
- **Errors caught before render.** Every payload is validated against a JSON
  Schema (`spec/schema/sdui.schema.json`) on the backend, and decoded
  defensively on the client — an unknown component degrades to nothing, it never
  crashes.
- **Small, fully specified contract.** The whole format is described by the
  schema and one authoring guide ([`spec/docs/authoring.md`](spec/docs/authoring.md)),
  so screens are quick to write by hand or with your own tooling.
- **Lightweight, extensible.** The SDK ships a small core of primitives. Anything
  native the format can't express is registered as a `custom.*` component by the
  host app — the format stays readable, the SDK stays small.

## The core idea: four orthogonal languages in one JSON

```
Layout/Components — what to draw   (the view tree + modifiers + tokens)
Actions           — what to do     (declarative, composable side effects)
Data/Network      — where data is  (services, requests, bindings)
Navigation        — how to move    (push / sheet / cover / deep links)
```

They never mix. A button doesn't "know" how to make a request; it fires an
`action`, which the runtime interprets. This separation is what keeps the format
portable and the renderers dumb.

## Repository layout

```
spec/                         # THE SOURCE OF TRUTH (platform-neutral)
  schema/sdui.schema.json     # the contract — validates every payload
  schema/tokens.example.json  # shared design tokens
  examples/*.json             # reference screens
  docs/*.md                   # protocol + AI authoring guide

ios/                          # Swift Package (SwiftUI renderer)
  Sources/SDUICore/           # models, decoding, binding engine, conditions
  Sources/SDUINetwork/        # declarative networking (services, TaskGroup)
  Sources/SDUIRuntime/        # action interpreter (sequence/parallel/condition)
  Sources/SDUIRender/         # SwiftUI renderers + component registry
  Tests/                      # unit tests (core is fully covered)

android/                      # Compose renderer (planned — same contract)
```

## Quick start (iOS)

```swift
import SDUICore
import SDUINetwork
import SDUIRender

let document = try SDUIParser.decode(jsonData)          // structural validation
let tokens   = try JSONDecoder().decode(JSONValue.self, from: tokensData)
let loader   = DataLoader(resolver: StaticServiceResolver(
    services: ["catalog": URL(string: "https://api.example.com")!]))

SDUIScreenView(
    document: document,
    tokens: tokens,
    env: ["locale": .string("ru"), "theme": .string("light")],
    loader: loader,
    delegate: myRouter                                  // navigation, analytics
)
```

Register a native escape-hatch component:

```swift
let registry = ComponentRegistry()
registry.register("custom.map") { component, ctx in
    AnyView(MapView(latitude: component.prop("latitude")?.doubleValue ?? 0))
}
```

## Try the sandbox

A live editor that renders payloads against the reference runtime — type JSON,
watch it render, see actions fire. Two tabs: **Sandbox** and a **Navigation**
demo (a full server-driven stack via `SDUIContainerView`).

**On the iOS Simulator** — open the demo app and Run:

```bash
open ios/Examples/DemoApp/SDUIDemo.xcodeproj
# pick the SDUIDemo scheme + an iPhone simulator, then ⌘R
```

**On macOS** — no Xcode project needed:

```bash
cd ios && swift run SDUIPlaygroundApp
```

To embed the sandbox in your own iOS app, use `SDUIPlaygroundView()` from the
`SDUIPlayground` module. See [`ios/Examples/DemoApp`](ios/Examples/DemoApp).

## Navigation

For a stack of server-driven screens, host `SDUIContainerView` and give it a
provider that turns any route into a payload (a backend fetch, a cache, or a
bundled screen):

```swift
SDUIContainerView(
    root: SDUIRoute(screen: "home"),
    tokens: tokens,
    appDelegate: myRouter,                       // share/toast/analytics/custom
    provider: { route in await api.screen(route.screen, route.params) }
)
```

The contract's `navigate` action drives `push` / `sheet` / `fullScreenCover`,
`dismiss` and `dismissRoot` — no client release needed to change a flow.

## Android

The [`android/`](android) module renders the **same** contract with Jetpack
Compose, mirroring the SwiftUI reference file-for-file. See
[`android/README.md`](android/README.md).

## Prior art & cross-platform design

This engine is built against the lessons of DivKit, Airbnb, Lyft, Beagle and
Nubank, and against the concrete places SwiftUI and Compose disagree (sizing,
text metrics, list identity, insets, accessibility). The rationale and the rules
the contract follows are written up in
[`docs/design-notes.md`](docs/design-notes.md).

## How the same JSON drives Android

The contract carries nothing SwiftUI-specific. The Compose renderer will consume
the identical payload: `spec/schema/sdui.schema.json` generates the Kotlin models,
`vstack`→`Column`, `hstack`→`Row`, the binding engine and action interpreter port
1:1, and the token file is shared. Backends never branch per platform.

## Roadmap

- [x] **v0.1** Contract + core + iOS primitives + networking + actions + sandbox
- [x] **v0.2** Explicit sizing model (`fixed`/`hug`/`fill`/`weight` + min/max),
      accessibility fields, dark-mode token palette, forms
      (`textfield`/`toggle`/`picker` two-way bound to state) — see
      [design notes](docs/design-notes.md)
- [x] **v0.3** Lazy `grid`, list pagination (`onReachEnd`) — _remaining: swipe
      actions, scroll-position restoration_
- [x] **v0.4** Navigation: `push`/`sheet`/`fullScreenCover`, params, dismiss and
      dismiss-to-root via `SDUIContainerView` — _remaining: deep-link routing,
      tab bars_
- [x] **v0.6** State-driven animations, long-press context menus, shadows
- [ ] **v0.5** Device actions: file access, device storage, richer analytics
- [x] **v1.0 (in progress)** Android (Compose) renderer consuming the same
      contract ([`android/`](android)) — _remaining: parity with the newest
      components + Kotlin model codegen from the schema_

Typography metrics parity and stable list-item identity keys are the next
contract refinements before the platforms are declared feature-equal.

## License

Open source. License TBD (MIT/Apache-2.0 recommended).

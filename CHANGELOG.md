# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Platform-neutral JSON contract (`spec/schema/sdui.schema.json`).
- Shared design-token file and reference example screens.
- Zero-dependency payload validator (`spec/tools/validate.mjs`).
- iOS Swift Package:
  - `SDUICore` — models, defensive decoding, binding engine, conditions.
  - `SDUINetwork` — declarative networking with parallel/sequential execution.
  - `SDUIRuntime` — composable action interpreter.
  - `SDUIRender` — SwiftUI renderers, component registry, `SDUIScreenView`.
  - `SDUIPlayground` — live sandbox with a categorised feature catalog
    (Showcase, Layout, Typography, Components, Inputs, Actions, Gestures,
    Animation, Lists), a two-level category browser, a JSON editor sheet, light/
    dark toggle, `.json` file import, and a navigation demo.
- Explicit, platform-neutral sizing model (`fixed`/`hug`/`fill`/`weight` + min/max).
- Accessibility metadata (`label`/`value`/`hint`/`role`/`hidden`) per component.
- Form controls (`textfield`/`toggle`/`picker`) two-way bound to screen state,
  plus `grid` and `icon` components.
- Navigation: `SDUIContainerView` + `SDUINavigator` driving push/sheet/cover,
  navigation params (`$params`, `{placeholder}` path filling), dismiss-to-root.
- List pagination (`onReachEnd`), state-driven animations, swipe-to-reveal
  row actions (`modifiers.swipe`), and drag-to-reorder lists (`list.reorder`,
  saved back to `$state`).
- Dark-mode token palette resolved via `$env.theme`.
- Animated shimmer skeletons for async images; declarative `delay` action.
- Demo: Liquid Glass on iOS 26 with a material fallback for older systems,
  a Design System category (button & card variations), and a chevron back button.
- Demo: a product-style landing ("Build your app — without frontend developers")
  with a mesh-gradient hero, feature cards and a call to action into the catalog.
- Android (Jetpack Compose) renderer consuming the same contract (`android/`).
- iOS demo app (`ios/Examples/DemoApp`) that runs the sandbox and navigation demo
  on the iOS Simulator; CI builds it for the simulator on every push.
- Authoring guide (`spec/docs/authoring.md`) and prior-art / cross-platform
  design notes (`docs/design-notes.md`).

# SDUI — Android (Jetpack Compose) renderer

The Android side of the engine. It consumes the **same** platform-neutral JSON
contract as iOS (see [`../spec/`](../spec)) and renders it with Jetpack Compose,
mirroring the SwiftUI reference module file-for-file so the two SDKs read as
siblings.

> Status: **initial Compose renderer.** It covers the core primitives and the
> binding/action model. It is written to compile-ready, idiomatic Kotlin but must
> be opened in Android Studio / built with the Android SDK to verify — that
> toolchain isn't part of this repo's CI yet.

## Layout

```
android/
  settings.gradle.kts, build.gradle.kts, gradle.properties
  sdui/                                  # the library module (dev.sdui)
    build.gradle.kts
    src/main/java/dev/sdui/
      core/     JsonValue, Models, BindingEngine, SduiParser
      runtime/  ActionInterpreter
      render/   Theme, ComponentRegistry, Builtins, SduiModifiers, SduiScreen
```

## How it mirrors iOS

| Contract concern | iOS (`SDUI*`) | Android (`dev.sdui`) |
|------------------|---------------|----------------------|
| Any JSON value | `JSONValue` | `JsonValue` (kotlinx.serialization) |
| Models & decoding | `SDUICore/Models` | `core/Models` |
| Bindings (`$data`/`$token`/…) | `BindingEngine` | `core/BindingEngine` |
| Action interpreter | `ActionInterpreter` | `runtime/ActionInterpreter` |
| Component registry (+ `custom.*`) | `ComponentRegistry` | `render/ComponentRegistry` |
| Primitives | `Builtins` (SwiftUI) | `render/Builtins` (Compose) |
| Screen host | `SDUIScreenView` | `render/SduiScreen` |

`vstack` → `Column`, `hstack` → `Row`, `zstack` → `Box`, `list` → `LazyColumn`,
`scroll` → `verticalScroll`. Tokens, bindings and actions behave identically by
design — the contract is the single source of truth for both platforms.

## Dependencies

Kotlin, Jetpack Compose, and `kotlinx.serialization` only. Async image loading
is a placeholder `Box` for now (no third-party image library is pulled in); wire
your app's loader where marked `// TODO: plug in an image loader`.

## Roadmap to parity

The SwiftUI renderer is ahead on the newest contract additions (explicit sizing
model, accessibility metadata, `grid`/`icon`/form controls, navigation). Those
land here next so a single payload provably drives both platforms — tracked in
the top-level [`README.md`](../README.md) roadmap.

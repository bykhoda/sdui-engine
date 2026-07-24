# SDUI — Android (Jetpack Compose) renderer

The Android side of the engine. It consumes the **same** platform-neutral JSON
contract as iOS (see [`../spec/`](../spec)) and renders it with Jetpack Compose,
mirroring the SwiftUI reference module file-for-file so the two SDKs read as
siblings.

> Status: **initial Compose renderer.** It covers the core primitives and the
> binding/action model. CI now builds the library and runs the core unit tests on
> every push (see the `android` job in [`../.github/workflows/ci.yml`](../.github/workflows/ci.yml));
> component parity with iOS is still in progress.

## Build & test

The module targets Gradle 8.9 (pinned in `gradle/wrapper/gradle-wrapper.properties`),
AGP 8.5, Kotlin 2.0, compileSdk 34, minSdk 24. The wrapper *jar* is intentionally
not committed — generate `./gradlew` once with a system Gradle, then use it:

```bash
cd android
gradle wrapper --gradle-version 8.9   # one-time: materialise ./gradlew (or open in Android Studio)
./gradlew :sdui:assembleRelease       # compile the renderer
./gradlew :sdui:testDebugUnitTest     # run the pure-JVM core tests (BindingEngineTest)
```

CI does exactly this on `ubuntu-latest` with JDK 21 + the Android SDK.

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
  app/                                   # the demo/playground application
    build.gradle.kts                     # (Android sibling of ios/Examples/DemoApp)
    src/main/java/dev/sdui/demo/         # MainActivity + catalog browser
```

## Demo app (`:app`)

The `:app` module is the Android twin of the iOS demo. It renders the **same**
bundled catalog and screens (`catalog.json` + `screens/*.json` + `tokens.json`)
through the Compose renderer — the concrete proof of "one contract, two native
apps". The content is authored once (with the iOS demo) and copied into the app's
assets at build time by the `syncPlaygroundContent` Gradle task, so there is no
committed duplicate. Screens that use components not yet ported to Android (see
parity note below) degrade gracefully rather than crashing.

```bash
./gradlew :app:assembleDebug     # build the demo APK
./gradlew :app:installDebug      # install on a running emulator/device
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

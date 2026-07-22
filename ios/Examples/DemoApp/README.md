# SDUI Demo (iOS app)

A minimal iOS app that hosts the engine so you can run it on the **iOS
Simulator** or a device. A bare Swift Package can't deploy to the simulator —
this app target can.

## Run it

1. Open `SDUIDemo.xcodeproj`.
2. Pick the **SDUIDemo** scheme and any **iPhone simulator** in the destination
   menu (top bar).
3. Press **Run** (⌘R).

Two tabs:
- **Sandbox** — a live JSON editor; edit or open a `.json` file and watch it
  render.
- **Navigation** — a server-driven stack (push / sheet) driven entirely by JSON.

## Regenerating the project

The project is generated from [`project.yml`](project.yml) with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). If you change `project.yml`:

```bash
brew install xcodegen   # once
cd ios/Examples/DemoApp
xcodegen
```

It references the local Swift package at `../..` (relative path), so there's
nothing machine-specific in the project.

## Prefer the terminal / macOS?

From `ios/`, `swift run SDUIPlaygroundApp` runs the same sandbox as a macOS app —
no Xcode project needed.

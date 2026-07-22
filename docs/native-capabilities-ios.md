# Native iOS capabilities as contract primitives

This document designs how the SDUI engine exposes native iOS OS capabilities
through the **one platform-neutral JSON contract**, without leaking UIKit or
platform APIs into the payload. It is a design proposal, not shipped code — no
engine source is modified here.

## Where each capability plugs in

The engine has exactly two extension seams, and every capability below maps onto
one of them:

- **Actions** flow through `ActionInterpreter` → the `ActionHost` protocol
  (`ios/Sources/SDUIRuntime/ActionInterpreter.swift`). The interpreter owns
  control flow (`sequence`, `parallel`, `condition`); the host owns side effects
  (`openURL`, `share`, `preview`, `setState`, `refresh`). A *verb* — "do this
  thing to the OS now" — is a new `case` in the interpreter plus a new method on
  `ActionHost`, implemented on `SDUIScreenModel`
  (`ios/Sources/SDUIRender/SDUIScreenView.swift`).
- **Components / modifiers** are registered into `ComponentRegistry`
  (`ios/Sources/SDUIRender/Builtins.swift`) or added to the `Modifiers` block
  (`ios/Sources/SDUICore/Models.swift`, applied in
  `ios/Sources/SDUIRender/Modifiers.swift`). A *thing on screen* — a loader, a
  frosted surface — is a component or modifier.

A third seam already exists for anything the contract should not model at all:
**`custom { name, payload }`** hands off to `SDUIHostDelegate.custom`, the app's
native bridge (see `docs/native-flows.md`). Capabilities that are legally or
architecturally the host app's responsibility (see the final section) stay there.

### Design rules honoured throughout

- **No force-unwraps.** Every optional is `guard`/`if let`; every version-gated
  API sits behind `#available` with a defined fallback (usually a no-op that logs
  and, where relevant, writes a `denied`/`unavailable` value back to `$state`).
- **Contract-first.** The payload names *intent* (`requestPermission`,
  `startLiveActivity`); the client owns the platform mechanics. Nothing in the
  JSON is iOS-specific.
- **Everything configurable, sensible defaults.** Each primitive exposes every
  knob but reads well with the minimum fields set.
- **Effects reflect back into `$state`.** Permission outcomes, version-gate
  results and activity ids are written to `$state.*` so the *contract* — not
  hand-written Swift — decides what the UI does next (`condition` actions,
  `visibleWhen`). This is the single most important pattern here: the OS answers,
  the server-authored UI reacts.

Because `ActionHost` is a protocol with default-nothing behaviour possible, and
`SDUIHostDelegate` already ships default no-op extensions, adding these methods is
**source-compatible** for existing hosts: a host that ignores `startLiveActivity`
simply doesn't override it.

---

## 1. Force-update (server-driven minimum-version gate)

**Goal.** The server ships a `minVersion` in the contract; if the running app is
older, show a **non-dismissable** alert routing to the App Store.

**Best-practice API.** Read `CFBundleShortVersionString` from
`Bundle.main.infoDictionary`; compare with `minVersion` using
`String.compare(_:options: .numericSearch)` (correct semantic ordering:
`"1.10" > "1.9"`). Route with `UIApplication.open` to the App Store product URL
(`itms-apps://apps.apple.com/app/id<APPID>`, which opens the Store app directly).
All available since iOS 15 — no gating needed.

**Contract shape — a new action `requireVersion`.** Model it as an action rather
than a component so the server can fire it from `screen.onAppear` (or from a
`refresh` response) and combine it with `condition`:

```json
{
  "action": "requireVersion",
  "minVersion": "2.4.0",
  "storeId": "1234567890",
  "title": "Update required",
  "message": "This version is no longer supported. Please update to continue.",
  "confirmTitle": "Update",
  "dismissible": false,
  "resultKey": "$state.versionOK"
}
```

Knobs and defaults: `minVersion` (required), `storeId` (required — the numeric App
Store id; a full `storeURL` is also accepted as an override), `title`
("Update required"), `message`, `confirmTitle` ("Update"), `dismissible`
(`false` — a hard gate; set `true` for a soft "recommended update" nudge with a
"Later" button), `resultKey` (optional `$state` key set to `true` when current ≥
min, `false` when a gate is shown — lets the contract also hide content behind
`visibleWhen`).

Because it's declarative the server can express *soft vs hard* purely in data
(`dismissible`), and gate different screens differently.

**Info.plist / entitlements.** None. (App Store id is contract data, not a plist
key.)

**Code sketch.**

```swift
// ActionHost (SDUIRuntime)
func requireVersion(minVersion: String, storeURL: String,
                    alert: VersionAlert, resultKey: String?) async

// ActionInterpreter — new case
case "requireVersion":
    guard let minVersion = action.field("minVersion")?.stringValue else { return }
    let storeURL = resolvedString(action.field("storeURL"), ctx).isEmpty
        ? action.field("storeId")?.stringValue.map { "itms-apps://apps.apple.com/app/id\($0)" } ?? ""
        : resolvedString(action.field("storeURL"), ctx)
    let alert = VersionAlert(
        title: action.field("title")?.stringValue ?? "Update required",
        message: resolvedString(action.field("message"), ctx),
        confirmTitle: action.field("confirmTitle")?.stringValue ?? "Update",
        dismissible: action.field("dismissible")?.boolValue ?? false)
    await host.requireVersion(minVersion: minVersion, storeURL: storeURL,
                              alert: alert, resultKey: action.field("resultKey")?.stringValue)

// SDUIScreenModel (SDUIRender) — host side
func requireVersion(minVersion: String, storeURL: String,
                    alert: VersionAlert, resultKey: String?) async {
    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    // .numericSearch → "1.10" compares greater than "1.9"; .orderedAscending == outdated.
    let outdated = current.compare(minVersion, options: .numericSearch) == .orderedAscending
    if let key = resultKey { await setState(key: key, value: .bool(!outdated)) }
    guard outdated else { return }
    #if os(iOS)
    presentGate(alert, storeURL: storeURL)   // UIAlertController with .cancel removed when !dismissible
    #endif
}
```

`presentGate` builds a `UIAlertController` on the top-most presented controller:
the "Update" action calls `openURL(storeURL)` and — for a hard gate —
**re-presents itself** in the action handler so the user cannot escape by any
means but updating. When `dismissible` is `true` it adds a secondary "Later"
button that just dismisses.

---

## 2. Runtime permissions (+ priming + accessibility state)

**Goal.** Request camera, location (when-in-use / always), notifications, photos,
microphone, contacts, calendar, and App Tracking Transparency — with an optional
**priming** rationale shown *before* the system prompt — and reflect the result
into `$state`. Plus surface (read-only) accessibility state: VoiceOver, Reduce
Motion, Dynamic Type.

**Best-practice APIs & version floors.**

| Capability | Framework / API | iOS floor |
|---|---|---|
| Camera / Microphone | `AVCaptureDevice.requestAccess(for:)` | 15 |
| Location | `CLLocationManager.requestWhenInUseAuthorization()` / `requestAlwaysAuthorization()` | 15 |
| Notifications | `UNUserNotificationCenter.requestAuthorization(options:)` | 15 |
| Photos | `PHPhotoLibrary.requestAuthorization(for: .readWrite)` | 15 |
| Contacts | `CNContactStore.requestAccess(for: .contacts)` | 15 |
| Calendar | `EKEventStore.requestFullAccessToEvents` (iOS 17+), else `requestAccess(to: .event)` | 15 (17 for the newer API) |
| App Tracking Transparency | `ATTrackingManager.requestTrackingAuthorization` | 15 |
| Accessibility state | `UIAccessibility.isVoiceOverRunning` / `isReduceMotionEnabled`; Dynamic Type via `UIApplication.shared.preferredContentSizeCategory` | 15 |

Calendar is the only one needing a `#available` split (iOS 17 renamed the API); it
degrades to the pre-17 `requestAccess(to:)` on the iOS 15/16 floor.

**Contract shape — one action `requestPermission`, plus a priming slot.** A single
verb keyed by a neutral `permission` string keeps the contract closed and
identical on Android (which maps each to its own runtime permission).

```json
{
  "action": "requestPermission",
  "permission": "location",
  "level": "whenInUse",
  "priming": {
    "title": "Find deals near you",
    "message": "We use your location only while the app is open to show nearby offers.",
    "confirmTitle": "Continue",
    "cancelTitle": "Not now",
    "image": "map.fill"
  },
  "resultKey": "$state.perm.location",
  "onGranted": { "action": "refresh", "sources": ["nearby"] },
  "onDenied":  { "action": "showToast", "message": "You can enable location in Settings." }
}
```

Knobs: `permission` (one of `camera | microphone | location | notifications |
photos | contacts | calendar | tracking`), `level` (location only:
`whenInUse` (default) | `always`; photos: `readWrite` (default) | `addOnly`),
`priming` (optional — a rationale sheet shown **only on first ask**, before the OS
prompt; omit it to go straight to the system dialog), `resultKey` (set to one of
`granted | denied | restricted | notDetermined`), `onGranted` / `onDenied`
(nested actions run after the outcome — full binding-resolved `Action`s, so they
compose with everything else).

**Priming flow (best practice).** Requesting the OS prompt cold burns the one-shot
opportunity — a denial is sticky and can only be reversed in Settings. So the flow
is:

1. First time this `permission` is asked (tracked by a `UserDefaults` flag keyed
   per permission), and `priming` is present → present a **contract-authored**
   rationale sheet built from the `priming` fields.
2. User taps confirm → fire the real system request. User taps cancel → write
   `denied` to `resultKey`, run `onDenied`, and **do not** consume the system
   prompt (they can be re-primed later).
3. On any subsequent ask, skip priming and query current status; if already
   `denied`, `onDenied` typically routes to `openURL("app-settings:")`
   (`UIApplication.openSettingsURLString`).

The priming sheet is rendered by the **same SDUI registry** — it's just a small
built subtree — so it inherits the app's theme and press feel, not a system
alert.

**Accessibility state — read-only, mirrored into `$state`.** These are not
permissions; they're environment signals the server-authored UI should adapt to
(e.g. skip an animation when Reduce Motion is on). Rather than an action, expose
them as **auto-populated env/state** the engine writes on appear and refreshes on
the relevant `UIAccessibility.*DidChangeNotification`:

```
$env.a11y.voiceOver        // bool
$env.a11y.reduceMotion     // bool
$env.a11y.boldText         // bool
$env.a11y.contentSize      // "large" | "xxxLarge" | "accessibilityExtraLarge" | …
```

The contract then reacts with existing primitives — `visibleWhen`, `condition`,
and (recommended) letting the `PulseModifier` / `AnimationModifier` consult
`$env.a11y.reduceMotion` to no-op animations. This is a small, high-value addition
because the engine already leans on motion heavily.

**Info.plist keys required.** Each permission needs its usage-description string
or iOS crashes on request:

- Camera: `NSCameraUsageDescription`
- Microphone: `NSMicrophoneUsageDescription`
- Location: `NSLocationWhenInUseUsageDescription`, and for `always`
  `NSLocationAlwaysAndWhenInUseUsageDescription`
- Photos: `NSPhotoLibraryUsageDescription` (+ `NSPhotoLibraryAddUsageDescription`
  for add-only)
- Contacts: `NSContactsUsageDescription`
- Calendar: `NSCalendarsUsageDescription` (iOS 17: `NSCalendarsFullAccessUsageDescription`)
- Tracking: `NSUserTrackingUsageDescription`

Notifications need no plist key. **These strings are host-app responsibility** —
they're reviewed by Apple and cannot be server-driven (see final section). The
contract's `priming.message` is the *in-app* rationale, separate from the plist
string the OS shows.

**Code sketch.**

```swift
// ActionHost
func requestPermission(_ req: PermissionRequest) async -> PermissionOutcome

// SDUIScreenModel
func requestPermission(_ req: PermissionRequest) async -> PermissionOutcome {
    #if os(iOS)
    switch req.permission {
    case .camera:
        let ok = await AVCaptureDevice.requestAccess(for: .video)
        return ok ? .granted : .denied
    case .location:
        return await LocationAuth.shared.request(level: req.level)   // wraps the delegate callback
    case .notifications:
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        return granted ? .granted : .denied
    case .calendar:
        let store = EKEventStore()
        if #available(iOS 17.0, *) {
            let ok = (try? await store.requestFullAccessToEvents()) ?? false
            return ok ? .granted : .denied
        } else {
            let ok = await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { granted, _ in cont.resume(returning: granted) }
            }
            return ok ? .granted : .denied
        }
    case .tracking:
        let status = await ATTrackingManager.requestTrackingAuthorization()
        return status == .authorized ? .granted : .denied
    // photos, contacts, microphone: same shape
    }
    #else
    return .unavailable
    #endif
}

// Interpreter case orchestrates priming → request → resultKey → onGranted/onDenied:
case "requestPermission":
    guard let raw = action.field("permission")?.stringValue,
          let perm = PermissionRequest.Kind(rawValue: raw) else { return }
    let req = PermissionRequest(...decoded from action fields...)
    if req.priming != nil, await host.shouldPrime(perm) {
        let confirmed = await host.presentPriming(req.priming, ctx: ctx)
        guard confirmed else {
            if let key = req.resultKey { await host.setState(key: key, value: .string("denied")) }
            if let onDenied = action.field("onDenied")?.decode(Action.self) { await run(onDenied, ctx: ctx) }
            return
        }
    }
    let outcome = await host.requestPermission(req)
    if let key = req.resultKey { await host.setState(key: key, value: .string(outcome.rawValue)) }
    let branch = outcome == .granted ? "onGranted" : "onDenied"
    if let next = action.field(branch)?.decode(Action.self) { await run(next, ctx: ctx) }
```

---

## 3. Background work (BGTaskScheduler + silent push trigger)

**Goal.** The server declares which data sources should refresh in the background;
the app registers `BGAppRefreshTask` / `BGProcessingTask` for them, and a silent
(`content-available`) remote push can trigger a refresh out of band.

**Best-practice API & constraints (BackgroundTasks, iOS 15).**

- **Register launch handlers in `didFinishLaunchingWithOptions` — before launch
  completes.** This is a hard requirement; late or duplicate registration for the
  same identifier causes iOS to terminate the app. This is why background
  *registration is host-owned* (see below).
- `BGAppRefreshTaskRequest` → ~30s of runtime, for light refreshes; only 1 refresh
  task can be pending at a time. `BGProcessingTaskRequest` → minutes of runtime,
  optional `requiresNetworkConnectivity` / `requiresExternalPower`; up to 10
  pending. iOS decides *when* based on usage patterns — never guaranteed timing.
- Silent push: an APNs payload with `content-available: 1` wakes the app into
  `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`; there you
  run the same data fetch and call the completion handler with a
  `UIBackgroundFetchResult`.

**Contract shape — declared on the screen/document, executed by the host.** The
contract can *name* what to refresh, but it **cannot** register OS handlers (that
must happen at launch, before any screen exists). So the design splits cleanly:

- **Contract declares** a `backgroundRefresh` block naming task identifiers, the
  data sources to reload, and a cadence hint:

```json
"backgroundRefresh": {
  "tasks": [
    {
      "id": "com.app.refresh.feed",
      "kind": "appRefresh",
      "sources": ["feed", "badges"],
      "earliestAfterSeconds": 900
    },
    {
      "id": "com.app.process.sync",
      "kind": "processing",
      "sources": ["outbox"],
      "requiresNetwork": true,
      "requiresPower": false
    }
  ],
  "onSilentPush": { "sources": ["feed"] }
}
```

- **Host registers** these ids at launch (from a small config the app ships, whose
  ids match the contract), and when a task fires it asks the runtime to run the
  named sources through the existing `DataLoader` — the same path `refresh`
  already uses (`SDUIScreenModel.reload(sources:)`). `onSilentPush.sources` is run
  from the remote-notification handler.

This keeps the powerful part server-driven (**what** refreshes, **how often** we
ask) while respecting that **which identifiers exist** is a build-time, plist-
declared fact Apple validates.

**Info.plist / capabilities required.**

- Capability: **Background Modes** → *Background fetch* (for `appRefresh`),
  *Background processing* (for `processing`), *Remote notifications* (for silent
  push).
- `BGTaskSchedulerPermittedIdentifiers` — an array listing **every** task id used
  (`com.app.refresh.feed`, `com.app.process.sync`). The contract's `tasks[].id`
  values must be a subset of this list; the validator (below) can enforce that.
- `UIBackgroundModes` array must include `fetch`, `processing`, and
  `remote-notification` as used.

**Code sketch (host-side, driven by contract data).**

```swift
// App launch — host owns this; ids come from the app's shipped config.
func application(_ app: UIApplication,
                 didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    for id in BackgroundConfig.permittedIdentifiers {   // must match Info.plist
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            Task { await SDUIBackground.shared.run(id: id, task: task) }
        }
    }
    return true
}

// The runtime bridge — reloads the contract-named sources via the existing loader.
@MainActor final class SDUIBackground {
    static let shared = SDUIBackground()
    var plan: [String: [String]] = [:]      // task id → source ids, filled from `backgroundRefresh`
    var loader: DataLoader?

    func run(id: String, task: BGTask) async {
        scheduleNext(id)                      // re-submit BEFORE work, so cadence continues
        let sources = plan[id] ?? []
        let ok = await refreshSources(sources)
        task.setTaskCompleted(success: ok)
    }
}

// Silent push → same source list, from onSilentPush.
func application(_ app: UIApplication,
                 didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
    let ok = await SDUIBackground.shared.refreshSources(SDUIBackground.shared.silentPushSources)
    return ok ? .newData : .noData
}
```

The engine contribution is small: a `BackgroundRefresh` model in `SDUICore`, and a
`SDUIBackground` bridge in `SDUIRuntime` that turns a `tasks[]` entry into a
`reload(sources:)` call. Registration stays in the host.

---

## 4. Push notifications (registration, taps → navigation, silent)

**Goal.** Register for remote notifications, request permission, handle a
notification **tap** by navigating (using the same `navigate` vocabulary), and
handle silent pushes (§3).

**Best-practice API (UserNotifications + APNs, iOS 15).** Request auth via
`UNUserNotificationCenter` (§2, `permission: "notifications"`); on grant call
`UIApplication.shared.registerForRemoteNotifications()`; the token arrives in
`didRegisterForRemoteNotificationsWithDeviceToken` and the host forwards it to its
server. A tap is delivered to
`userNotificationCenter(_:didReceive:withCompletionHandler:)`.

**Contract shape.** Two halves:

1. **Permission + registration** reuse §2's `requestPermission` with
   `permission: "notifications"`, plus a tiny `registerForPush` action (fire in
   `onGranted`) so registration is contract-triggered:

```json
{ "action": "requestPermission", "permission": "notifications",
  "onGranted": { "action": "registerForPush" } }
```

2. **Tap → navigation is server-driven via the payload itself.** The APNs payload
   carries an `sdui` object mirroring a `navigate` action; the tap handler decodes
   it and runs it through the interpreter, so a push deep-links exactly like an
   in-app button — no bespoke routing:

```json
// APNs payload
{ "aps": { "alert": { "title": "Order shipped" } },
  "sdui": { "action": "navigate", "to": "orderDetail", "params": { "orderId": "9921" } } }
```

The host decodes `userInfo["sdui"]` into an `Action` and dispatches it (routing to
an SDUI screen or, per `docs/native-flows.md`, a native flow). Because it's a full
`Action`, a push can also `sequence` a navigate + a `setState` + analytics.

**Info.plist / entitlements / capabilities.**

- Capability: **Push Notifications** (adds the `aps-environment` entitlement).
- **Background Modes** → *Remote notifications* for silent/`content-available`.
- No plist usage string (the permission prompt is system-worded).

**Code sketch.**

```swift
// New leaf action → host.registerForPush()
case "registerForPush":
    await host.registerForPush()

func registerForPush() async {
    #if os(iOS)
    await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    #endif
}

// Host app's UNUserNotificationCenterDelegate — tap → interpreter
func userNotificationCenter(_ c: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse) async {
    let userInfo = response.notification.request.content.userInfo
    guard let sdui = userInfo["sdui"], let data = try? JSONSerialization.data(withJSONObject: sdui),
          let action = try? JSONDecoder().decode(Action.self, from: data) else { return }
    await router.dispatchTopLevel(action)   // routes via ActionInterpreter → ActionHost
}
```

`token → server` and the delegate wiring are host code; the engine provides the
`registerForPush` action and the payload→`Action` decode helper.

---

## 5. Live Activity / Dynamic Island (ActivityKit, 16.1+)

**Goal.** Start / update / end a Live Activity as **actions**, with the
compact / expanded / minimal layouts described in the contract, and a graceful
no-op below iOS 16.1.

**Reality check on what can be server-driven.** ActivityKit requires a
**compile-time** `ActivityAttributes` type and a SwiftUI `Widget` in a **Widget
Extension** — the layout code is in the app binary, not the payload. You *cannot*
ship an arbitrary Live Activity layout as JSON. What the contract *can* fully
drive is the **content/state and lifecycle**: which activity template to start,
the dynamic values in it, updates, and ending. So the design registers one (or a
few) parameterised `ActivityAttributes` in the host whose fields are a neutral
`[String: String]` / `[String: Double]` bag the contract fills — the widget maps
those slots into its compact/expanded/minimal regions. The **layout regions are
named by the contract, filled by the widget** — this is the honest,
best-practice boundary.

**Best-practice API & floors.**

- `Activity.request(attributes:content:pushType:)` to start (foreground only);
  `activity.update(_:)` to update; `activity.end(_:dismissalPolicy:)` to end. iOS
  **16.1**. Remote *start* is 17.2+; remote update via APNs `liveactivity` push
  type is 16.1+. If frequent pushes are expected, set
  `NSSupportsLiveActivitiesFrequentUpdates` = YES.
- Everything is behind `if #available(iOS 16.1, *)`; below that every action is a
  logged no-op.

**Contract shape — three actions sharing an `activityId`.**

```json
{ "action": "startLiveActivity", "template": "delivery",
  "state": { "status": "Out for delivery", "etaMinutes": "18", "progress": "0.6" },
  "staleAfterSeconds": 3600,
  "resultKey": "$state.activity.delivery" },

{ "action": "updateLiveActivity", "activityKey": "$state.activity.delivery",
  "state": { "status": "Nearby", "etaMinutes": "4", "progress": "0.9" },
  "alert": { "title": "Almost there", "body": "Your order is 4 minutes away" } },

{ "action": "endLiveActivity", "activityKey": "$state.activity.delivery",
  "state": { "status": "Delivered", "progress": "1.0" },
  "dismissAfterSeconds": 30 }
```

Knobs: `template` (names a registered `ActivityAttributes`; unknown → no-op +
log), `state` (the neutral slot bag → mapped into the widget's regions),
`staleAfterSeconds` (→ `staleDate`), `resultKey` (start writes the activity id
here so update/end can reference it via `activityKey`), `alert` (update only —
surfaces on the lock screen), `dismissAfterSeconds` (end only → `.after(date)`
dismissal, default `.default`).

The **compact / expanded / minimal** descriptions live in the widget code but are
*keyed* by the same slot names the contract uses, so authors know exactly which
`state` keys land where (documented per template).

**Info.plist / capabilities.**

- `NSSupportsLiveActivities` = YES in the app's Info.plist.
- `NSSupportsLiveActivitiesFrequentUpdates` = YES only if pushing frequently.
- A **Widget Extension** target containing the `ActivityAttributes` + widget.
- For push updates: Push Notifications capability + token-based APNs auth key.

**Code sketch.**

```swift
// ActionHost
func startLiveActivity(template: String, state: [String: JSONValue],
                       staleAfter: TimeInterval?, resultKey: String?) async
func updateLiveActivity(id: String, state: [String: JSONValue], alert: ActivityAlert?) async
func endLiveActivity(id: String, state: [String: JSONValue], dismissAfter: TimeInterval?) async

// SDUIScreenModel
func startLiveActivity(template: String, state: [String: JSONValue],
                       staleAfter: TimeInterval?, resultKey: String?) async {
    guard #available(iOS 16.1, *) else { await log("Live Activities need iOS 16.1"); return }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        if let key = resultKey { await setState(key: key, value: .null) }; return
    }
    guard let started = SDUIActivities.start(template: template, state: state, staleAfter: staleAfter) else { return }
    if let key = resultKey { await setState(key: key, value: .string(started.id)) }
}
```

`SDUIActivities` is a thin host-side registry mapping a `template` name to a
`start/update/end` closure over the concrete `ActivityAttributes` — the one place
that touches the compile-time type. Everything above it is neutral. Below 16.1 the
whole feature is a logged no-op that leaves `$state` clean, so a contract can guard
with `visibleWhen` on an `$env.iosVersion` signal if it wants to hide the button.

---

## 6. Custom pull-to-refresh and a centered custom loader

**Goal.** Let the contract provide (a) a **custom loading component** for pull-to-
refresh instead of the native `refreshControl`, and (b) a **centered custom
loader** shown while data loads.

The engine already has native `.refreshable` wired when `screen.refresh` is set
(`SDUIScreenView.content`) and an `isLoading` flag on `SDUIScreenModel`. This
extends both to be contract-styled.

**Best-practice API note.** SwiftUI's `.refreshable` owns the native spinner and
you can't replace *its* control directly on iOS 15. Two honest options, both
offered:

- **Native (default):** keep `.refreshable` — it's the platform-correct gesture
  and integrates with the scroll. This stays the default; nothing to author.
- **Custom overlay:** for a branded loader, drive an offset-tracked pull (the
  engine already tracks scroll offset in `ScrollContainer` via
  `OffsetKey`/`overscroll`) and render a **contract-provided component** in the
  reveal zone, firing `refresh` past a threshold. This reuses the exact
  overscroll machinery that powers `revealOnPull` search today.

**Contract shape.** Extend `RefreshConfig` and add a screen-level `loader` slot:

```json
"refresh": {
  "sources": ["feed"],
  "style": "custom",
  "indicator": {
    "type": "rings",
    "values": ["$state.pullProgress"],
    "colors": ["accent"]
  },
  "threshold": 90
},
"loader": {
  "component": { "type": "vstack", "alignment": "center", "children": [
    { "type": "spinner", "size": "large" },
    { "type": "text", "value": "Loading your feed…" }
  ] },
  "minDurationSeconds": 0.4
}
```

Knobs: `refresh.style` (`native` (default) | `custom`), `refresh.indicator` (any
component subtree — rendered in the pull-reveal zone; its progress can bind to a
`$state.pullProgress` the engine writes 0→1 as you pull), `refresh.threshold`
(pt past top that fires the refresh, default 90). `loader.component` (any subtree,
centered as an overlay while `isLoading`), `loader.minDurationSeconds` (keeps the
loader up a beat so a fast load doesn't flash — mirrors the list's `loadDelay`).

Loader precedence: if `loader.component` is present it replaces the default
spinner while `SDUIScreenModel.isLoading`; otherwise the default centered
`spinner` shows. Because it's a full subtree it inherits theme, `pulse`,
`material`, everything.

**iOS 15 safety.** The custom pull uses only `ScrollView` + `GeometryReader`
offset tracking already proven in `ScrollContainer` — no iOS 16 API. The native
path uses `.refreshable` (iOS 15+). No gating needed.

**Code sketch.**

```swift
// In SDUIScreenView.content — choose native vs custom, and overlay the loader.
@ViewBuilder
private func content(ctx: RenderContext, interpreter: ActionInterpreter) -> some View {
    let base = registry.view(for: screen.content, in: ctx)
    Group {
        if screen.refresh?.style == "custom" {
            base.modifier(SDUICustomRefresh(config: screen.refresh, ctx: ctx,
                                            onRefresh: { await model.reload(sources: screen.refresh?.sources ?? []) }))
        } else if screen.refresh != nil {
            base.refreshable { await model.reload(sources: screen.refresh?.sources ?? []) }
        } else {
            base
        }
    }
    .overlay { if model.isLoading, let loader = screen.loader { SDUILoaderOverlay(loader: loader, ctx: ctx) } }
}
```

`SDUICustomRefresh` reads the same overscroll preference `ScrollContainer`
publishes, writes `pullProgress` into state so the `indicator` subtree animates,
and calls `onRefresh` once `overscroll > threshold`.

---

## 7. Materials / blur as a contract modifier

**Goal.** A `blur` / material modifier mapping to `UIVisualEffect` materials
(`ultraThin … thick`, plus `bar`), iOS 15-safe.

**Best-practice API.** SwiftUI's `Material` (`.ultraThinMaterial`,
`.thinMaterial`, `.regularMaterial`, `.thickMaterial`, `.bar`) is available since
iOS 15 and maps straight onto `UIVisualEffectView`'s system materials — no UIKit
needed. The engine already uses `.ultraThinMaterial` / `.regularMaterial` /
`.bar` internally (`Modifiers.swift` `materialView`, `ScrollContainer` pinned
header). This promotes it to a first-class, fully enumerated modifier.

**Contract shape.** The `Modifiers.material` field exists (`"glass"` | `"regular"`
today). Extend its accepted values to the full system set, and add an optional
numeric `blur` for a raw Gaussian blur where a material isn't wanted:

```json
"modifiers": {
  "material": "ultraThin",
  "cornerRadius": 16
}
```

```json
"modifiers": { "blur": 8 }   // raw radius, for e.g. a blurred hero behind a sheet
```

Accepted `material` values: `ultraThin | thin | regular | thick | bar | glass`
(the existing `glass` stays as the engine's bespoke top-lit frosted pane;
`regular` stays for back-compat). Default: none. `blur` is a raw radius in points
(uses `.blur(radius:)`) — distinct from `material`, which is a translucency effect
over what's behind.

This is a **pure additive** change to the existing `BackgroundModifier.materialView`
switch — the smallest, safest item on this list, and it removes the "only glass or
regular" limitation.

**iOS 15 safety.** All `Material` cases and `.blur(radius:)` are iOS 15+. No
gating.

**Code sketch.**

```swift
// Modifiers.swift — extend materialView's switch
@ViewBuilder private func materialView<S: Shape>(_ shape: S) -> some View {
    switch material {
    case "ultraThin": shape.fill(.ultraThinMaterial)
    case "thin":      shape.fill(.thinMaterial)
    case "regular":   shape.fill(.regularMaterial)
    case "thick":     shape.fill(.thickMaterial)
    case "bar":       shape.fill(.bar)
    case "glass":     glassPane(shape)          // existing bespoke look
    default:          EmptyView()
    }
}

// A new BlurModifier composed into SDUIModifier, after background:
private struct BlurModifier: ViewModifier {
    let radius: Double?
    func body(content: Content) -> some View {
        if let r = radius, r > 0 { content.blur(radius: r) } else { content }
    }
}
```

---

## Priority ordering (value vs effort)

Ranked by value delivered per unit of effort, given the engine already exists.

| # | Capability | Value | Effort | Rationale |
|---|---|---|---|---|
| 1 | **Materials / blur modifier** (§7) | High | Trivial | Pure additive switch; removes a real limitation; zero risk, iOS 15-safe. Do first. |
| 2 | **Force-update gate** (§1) | High | Low | Every production app needs it; self-contained action; no entitlements. |
| 3 | **Accessibility state → `$env`** (part of §2) | High | Low | Lets the motion-heavy engine respect Reduce Motion / Dynamic Type; small read-only bridge. |
| 4 | **Runtime permissions + priming** (§2) | High | Medium | Broad reuse; the priming + `$state` reflection is the differentiator. Plist strings are host work. |
| 5 | **Push notifications** (§4) | High | Medium | Big product value; the payload→`Action` decode is elegant and reuses navigation. Needs entitlement + host delegate. |
| 6 | **Custom pull-to-refresh + loader** (§6) | Medium | Medium | Nice polish; reuses existing overscroll + `isLoading`. Native path already covers most needs. |
| 7 | **Background work** (§3) | Medium | High | High plumbing (launch-time registration, plist ids), and iOS controls timing so payoff is diffuse. |
| 8 | **Live Activity / Dynamic Island** (§5) | High (where relevant) | High | Highest ceiling but requires a Widget Extension + compile-time attributes; only lifecycle/content is truly server-driven. Do last, per-app. |

**Suggested sequence:** ship §7 and §1 immediately (a day), add §3-accessibility
and §2 next (the permission engine), then §4 (push), then §6, and treat §3-background
and §5 as opt-in per host that needs them.

---

## What fundamentally cannot be server-driven (host-app responsibility)

These stay with the host app by law, Apple policy, or platform architecture — the
contract can *trigger* or *react*, but cannot *own* them:

- **Info.plist usage-description strings** (`NSCameraUsageDescription`, etc.).
  Reviewed by Apple, shown by the OS, embedded in the binary — cannot be
  server-driven. The contract's `priming.message` is a *separate* in-app rationale.
- **Entitlements & capabilities** (Push Notifications, Background Modes, App
  Groups, `aps-environment`, `NSSupportsLiveActivities`). Build-time, code-signed;
  a payload can never grant itself a capability.
- **Background task registration** (`BGTaskScheduler.register` in
  `didFinishLaunchingWithOptions`, and the `BGTaskSchedulerPermittedIdentifiers`
  list). Must run before any screen exists and match a plist allow-list. The
  contract can name *which* registered task refreshes *which* sources; it cannot
  create identifiers.
- **The `ActivityAttributes` type and the Live Activity / Dynamic Island layout
  code.** Compile-time SwiftUI in a Widget Extension. The contract drives content
  and lifecycle only; the visual regions are host code keyed by contract slot names.
- **APNs device-token handling and server registration.** The token comes from a
  UIApplication delegate callback and goes to the host's own backend.
- **The actual permission decision.** The OS owns the dialog and the persisted
  grant; the app can only ask once and then route to Settings. The contract
  reflects the *outcome*, it can't override it.
- **App Store product id / update destination.** Contract *data* (fine to ship in
  `requireVersion`), but the act of opening the Store is a host `openURL`.

The clean rule: **the contract expresses intent and reacts to outcomes; the host
holds every OS grant, entitlement, and compile-time type.** Everything designed
above respects that line — which is exactly why each capability lands on an
existing seam (`ActionHost`, `ComponentRegistry`, `Modifiers`, or the `custom`
bridge) without widening the contract's trust boundary.

---

### Validator additions (recommended, following the Nubank design-system rule)

To keep these safe, the contract validator should check: `requireVersion` has a
`storeId` or `storeURL`; `requestPermission.permission` is in the known set;
`backgroundRefresh.tasks[].id` ∈ `BGTaskSchedulerPermittedIdentifiers`;
`startLiveActivity.template` names a registered attributes type; `material` ∈ the
enumerated set. Unknown values already degrade safely (the engine's
forward-compatible default), but validating at author time turns silent no-ops
into build-time errors.

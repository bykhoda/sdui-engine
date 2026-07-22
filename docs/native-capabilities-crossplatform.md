# Native capabilities across iOS · Aurora OS · Android

How the OS-level capabilities an SDUI screen may want to trigger map onto **Aurora OS**
(Sailfish-based, Qt/QML + Silica, RPM packaging, Sailjail sandbox) and **Android**
(Kotlin + Jetpack Compose), so a single platform-neutral contract primitive can resolve
on all three. iOS is covered by a separate effort; it appears here only as the reference
point and in the final "clean / partial / iOS-only" summary.

The contract principle throughout: **the JSON names an intent with knobs and defaults; the
host resolves it to native APIs and is free to no-op or degrade.** A screen must never
assume a capability succeeded — the host reports capability support back so the server can
branch. See also [`native-flows.md`](native-flows.md) for the `custom { name, payload }`
escape hatch that all of these ultimately lean on.

---

## The single most important structural difference

**Aurora/Sailfish does not have iOS/Android-style runtime permission prompts.** Sandbox
permissions are declared statically in the app's `.desktop` file under an `[X-Sailjail]`
section (`Permissions=Camera;Location;…`) and are **granted at application launch** — there
is no per-capability consent dialog the app can trigger at runtime. This inverts the model:
on iOS/Android a permission is a *runtime action* the SDUI contract can fire; on Aurora it is
a *build-time manifest fact*. The contract must treat "request permission" as an action that
**may be a no-op that simply reports the already-known grant state.**

---

## 1. Force-update (min-version gate → blocking dialog → store link)

**Aurora OS**
- No first-party in-app-update API equivalent to Play Core. The mechanism is: app calls its
  own backend for a `minVersion`, compares against its build version (read from the RPM
  package version / a compiled-in constant), and if too old shows a **blocking QML dialog**
  (a full-screen Silica `Dialog`/`Page` the user cannot dismiss past).
- Store link: apps are distributed via **Aurora Center** ("Магазин Аврора"). Deep-linking to
  a specific app page in Aurora Center is not a broadly documented public URL scheme the way
  `market://` is; the practical pattern is to open Aurora Center (or a web store URL supplied
  by the backend) via the `Qt.openUrlExternally()` / D-Bus launch of the store. Treat the
  update destination as a **server-supplied URL string**, not a platform-fixed scheme.
- Caveat: enterprise/MDM Aurora deployments often push updates centrally (MDM), so the gate
  may be advisory. Availability of a store deep-link is environment-dependent → FLAG partial.

**Android**
- Version gate: same backend-`minVersion` pattern, plus first-party **Play Core In-App
  Updates** (`com.google.android.play:app-update` / `app-update-ktx`): `AppUpdateManager`,
  `AppUpdateType.IMMEDIATE` (blocking full-screen, Google-driven) vs `FLEXIBLE` (background
  download). IMMEDIATE is the native "force update" analog.
- Store deep-link: `market://details?id=<pkg>` (Play) or `https://play.google.com/store/apps/details?id=<pkg>`.
- **RuStore** (Russia) is the parallel store: **RuStore In-app updates SDK** (requires
  Android 8.0+, RuStore app installed, user signed into RuStore) plays the same role as Play
  Core; deep-links use RuStore app-page URLs (app id is the numeric segment in the store URL).
- Caveat: Play Core paths require Google Play Services; RuStore paths require the RuStore app —
  a device can have neither. The backend-driven blocking dialog + external URL is the
  universal floor.

**Contract primitive**
```json
{
  "action": "requireMinVersion",
  "min": "2.4.0",
  "style": "blocking",              // blocking | flexible
  "storeUrl": {                     // host may override per platform
    "android": "market://details?id=dev.sdui.demo",
    "androidRustore": "https://apps.rustore.ru/app/dev.sdui.demo",
    "aurora": "https://store.auroraos.example/app/dev.sdui.demo"
  },
  "message": "Please update to continue."
}
```
Resolution: iOS → App Store link + blocking sheet; Android → Play Core IMMEDIATE/FLEXIBLE (or
RuStore SDK) falling back to `market://`; Aurora → blocking Silica dialog + `Qt.openUrlExternally(storeUrl.aurora)`.
Default `style:"blocking"`. Host reports whether an in-app-update SDK was available so the
server knows if it got IMMEDIATE semantics or just a link.

---

## 2. Runtime permissions + accessibility state

### Permissions

**Aurora OS** — declared, not requested (see structural note above). Sailjail permission names
(in `[X-Sailjail] Permissions=`): `Camera`, `Location`, `Microphone`, `Audio`, `Contacts`,
`Calendar`, `Pictures`, `Videos`, `Music`, `Documents`, `Downloads`, `Storage`/`UserDirs`,
`Bluetooth`, `NFC`, `Internet`, `MediaIndexing`, `WebView`, `Secrets`, etc. Granted **at
launch**; no runtime prompt API. There is **no advertising-ID / app-tracking-transparency
equivalent** — the platform doesn't ship an ad-id, so "tracking permission" is **N/A** → FLAG.
Notifications don't require a runtime permission (see §5). So "request permission" on Aurora
resolves to: *read current grant state from the sandbox; if missing, the only remedy is a
manifest change + reinstall* — the app can at most surface guidance.

**Android** — runtime requests via `ActivityResultContracts.RequestPermission[s]` (Compose:
`rememberLauncherForActivityResult`, or Accompanist Permissions `rememberPermissionState`).
Manifest strings + caveats:

| Capability | Manifest permission(s) | Runtime prompt? | Caveat |
|---|---|---|---|
| Camera | `CAMERA` | yes | — |
| Location | `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`; `ACCESS_BACKGROUND_LOCATION` | yes | background location separate prompt, API 29+ |
| Notifications | `POST_NOTIFICATIONS` | yes | **runtime prompt only API 33+**; auto-granted below 33 |
| Photos/media | `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` (API 33+); `READ_MEDIA_VISUAL_USER_SELECTED` (API 34+); legacy `READ_EXTERNAL_STORAGE` (≤32) | yes | **Photo Picker (`ActivityResultContracts.PickVisualMedia`) needs NO permission** — prefer it |
| Microphone | `RECORD_AUDIO` | yes | — |
| Contacts | `READ_CONTACTS` / `WRITE_CONTACTS` | yes | — |
| Calendar | `READ_CALENDAR` / `WRITE_CALENDAR` | yes | — |
| Tracking equiv. | `com.google.android.gms.permission.AD_ID` | no prompt (declared) | API 33+ gates ad-id access; the "consent" is app-level, not a system prompt like iOS ATT |

**Contract primitive**
```json
{ "action": "requestPermission", "permission": "camera", "rationale": "Scan documents" }
```
`permission ∈ {camera, location, locationBackground, notifications, photos, microphone,
contacts, calendar, tracking}`. Host returns `{ status: granted|denied|restricted|unavailable|notApplicable }`.
- iOS → native prompt.
- Android → runtime launcher (or "already granted" below the min-SDK gate; `photos` prefers
  the no-permission Photo Picker).
- Aurora → reads sandbox grant; returns `granted` if declared, else `unavailable` +
  `reason: "manifest"`. `tracking` → `notApplicable` on Aurora.
The server must handle `unavailable`/`notApplicable` — never assume a prompt will appear.

### Accessibility state (read-only signals)

| Signal | iOS | Android | Aurora |
|---|---|---|---|
| Screen reader on | VoiceOver flag | `AccessibilityManager.isEnabled` / `isTouchExplorationEnabled` (TalkBack) | Qt Accessibility / Orca present but **screen-reader UX is immature** → FLAG partial |
| Reduce motion | UIAccessibility flag | `Settings.Global.ANIMATOR_DURATION_SCALE` / `TRANSITION_ANIMATION_SCALE == 0` | no standard flag → FLAG (treat as false) |
| Font scale | Dynamic Type | `Configuration.fontScale` / Compose `LocalDensity.fontScale` | Silica `Theme.fontSizeCategory` / global font size setting |

Exposed to the contract as a read-only `$accessibility` binding (`{screenReader, reduceMotion,
fontScale}`) so components can adapt (e.g. skip animations, honor larger type). It is **state
to read, not an action to fire.** On Aurora, `reduceMotion` and reliable `screenReader` are
best-effort → default `reduceMotion:false`, `screenReader:false`.

---

## 3. Background work + silent-push-triggered refresh

**Aurora OS**
- Aurora is strict about background execution. Persistent background logic runs as a
  **systemd user service** (`.service` file in `/usr/lib/systemd/user/`, wired with
  `WantedBy=user-session.target`). Periodic wake-ups use the **nemo-keepalive** library:
  `BackgroundActivity` (C++ `keepalive/backgroundactivity.h`, QML `Nemo.KeepAlive`
  `BackgroundJob`) schedules wake-ups even in late-suspend, rounded by the IPHB daemon.
  `KeepAlive` can also prevent suspend during active work.
- There is no WorkManager-style constraint scheduler; the app composes systemd timers +
  keepalive. Battery/OOM behavior is governed by the Linux OOM killer (tune `OOMScoreAdjust`).
  → FLAG: coarser and more manual than Android WorkManager.
- Silent-push refresh: the Aurora push receiver daemon can wake on an incoming push and
  trigger a fetch (see §4).

**Android**
- **WorkManager** (`androidx.work`): `OneTimeWorkRequest` / `PeriodicWorkRequest` (min 15-min
  period), `Constraints` (network, charging, idle). The recommended deferrable-background API.
- **Foreground services**: `FOREGROUND_SERVICE` + **typed** `FOREGROUND_SERVICE_*` permissions
  (e.g. `FOREGROUND_SERVICE_LOCATION`, `_DATA_SYNC`) **required API 34+**, with a declared
  `foregroundServiceType`. Background-start of services is restricted API 26+.
- Exact alarms (`AlarmManager.setExactAndAllowWhileIdle` / `SCHEDULE_EXACT_ALARM` /
  `USE_EXACT_ALARM`) for time-critical wakeups — heavily restricted API 31+/34+.
- Silent/data-push refresh: **FCM data message** → enqueue a `WorkManager` job. Caveat: Doze
  and background-restriction can delay/coalesce data messages when the app is backgrounded or
  the user force-stopped it → not guaranteed real-time.

**Contract primitive**
```json
{ "action": "scheduleRefresh", "trigger": "periodic", "minIntervalSec": 900,
  "requiresNetwork": true, "cacheKey": "feed" }
```
- Android → WorkManager with matching constraints.
- Aurora → keepalive `BackgroundActivity` / systemd timer.
- iOS → BGTaskScheduler.
Defaults: `trigger:"periodic"`, `requiresNetwork:true`. All three enforce a **minimum
interval** and may defer — the contract documents "best-effort, not guaranteed." Silent push
is modeled as a separate server-initiated event (§4), not a client action.

---

## 4. Push notifications + silent / data pushes

**Aurora OS**
- **Aurora Push Notification Service** (operated by OMP / Open Mobile Platform) is the
  FCM-analog and a defining Aurora-vs-Sailfish differentiator. Onboarding is manual: the dev
  emails `dev-support@omp.ru` to receive config (two YAML files with `project_id`,
  `push_public_address`, `api_url`, `client_id`, `scopes`, `audience`, `token_url`, `key_id`,
  `private_key`). Reference apps: OMP GitLab `omprussia/examples/PushReceiver` and
  `PushSender`. The receiver is registered via its `.desktop` manifest.
- Data/silent push: the push receiver daemon gets the payload and can act without showing UI,
  enabling silent refresh. → FLAG: private-service onboarding (not self-serve), Russia/OMP-bound.

**Android**
- **FCM**: notification messages (system-drawn when backgrounded) vs data messages (always
  delivered to `onMessageReceived` when app is alive; deferrable when backgrounded).
- `POST_NOTIFICATIONS` runtime permission **API 33+**; **notification channels required
  API 26+** (`NotificationChannel`).
- **RuStore Push SDK** is the FCM alternative for devices without Google Play Services (Russia).
- Caveat: silent/data pushes are throttled/delayed under Doze and after force-stop → not a
  reliable real-time transport.

**Contract primitive** — push is mostly server→client, so the contract side is thin: register
intent + a `silent` flag on the payload, and let the host map to FCM / RuStore / Aurora Push.
The client-facing knob is `{ "action": "registerForPush", "silent": true|false }` returning a
token the backend forwards to whichever provider. Providers differ; the abstraction is "get me
a token and deliver payloads," with **no guarantee of real-time silent delivery**.

---

## 5. Ongoing / live notifications (the cross-platform analog of Live Activity / Dynamic Island)

**Aurora OS**
- Notifications via **Nemo Notifications** (`Nemo.Notifications` QML / `org.freedesktop.Notifications`).
  Supports persistent/ongoing-style notifications and updating an existing notification by id.
  There is **no Dynamic-Island / rich live-widget equivalent** and **no first-class progress
  style** comparable to Android 16's — updating a notification body is the ceiling. → FLAG:
  ongoing = yes (partial), live/rich = **no**.
- Notifications do **not** require a runtime permission (unlike Android 13+).

**Android**
- **Ongoing notification**: `setOngoing(true)`; **progress**: `setProgress(max, cur, indeterminate)`.
- **Live Updates (Android 16 / API 36)**: `Notification.ProgressStyle` — segmented progress
  bars, points/milestones, tracker icons; promoted with `setOngoing(true)` +
  `setRequestPromotedOngoing(true)`. This is Android's official Live-Activity analog (delivery,
  rideshare, navigation). → FLAG: rich live experience is **API 36+ only**; below that you get
  a plain ongoing + `setProgress` bar (still useful, far less rich, no island/status-chip
  treatment).

**Contract primitive**
```json
{ "action": "startLiveActivity", "id": "order-42", "template": "progress",
  "title": "Order on the way", "progress": { "current": 2, "total": 4 },
  "fallback": "ongoingNotification" }
```
- iOS → ActivityKit Live Activity / Dynamic Island.
- Android → `ProgressStyle` (API 36+) else ongoing `setProgress` notification.
- Aurora → ongoing Nemo notification, updated in place; no rich treatment.
`update`/`end` actions target the same `id`. **This is the least-portable capability** — the
contract must define a graceful `fallback` chain (`liveActivity → progressNotification →
ongoingNotification → none`) and the host reports which tier it actually rendered.

---

## 6. Custom pull-to-refresh + centered custom loaders

**Aurora OS**
- Pull-to-refresh: Silica **`PullDownMenu`** (the canonical Sailfish gesture — pull the page
  header down to reveal actions/refresh). It's menu-oriented rather than a spinner-on-drag, so
  a literal iOS/Material "rubber-band spinner" is a stylistic mismatch → FLAG partial (idiom
  differs). Centered loader: Silica **`BusyIndicator`** (sizes `Small/Medium/Large`), freely
  centerable; fully custom loaders are just QML (any animated `Item`).

**Android**
- Pull-to-refresh: **Compose Material3 `PullToRefreshBox` / `pullToRefresh` modifier** (the
  current API). Accompanist `SwipeRefresh` is **deprecated** — don't target it.
- Centered loader: `CircularProgressIndicator` (indeterminate/determinate) centered in a `Box`;
  fully custom loaders are ordinary composables/`Canvas`.

**Contract primitive**
```json
{ "component": "refreshable", "onRefresh": { "action": "reload" },
  "loader": { "style": "spinner", "size": "medium" } }
```
- Android → `PullToRefreshBox`.
- Aurora → wrap the page's `PullDownMenu` with a refresh entry (documented idiom difference).
- iOS → `.refreshable`.
Loader `style ∈ {spinner, custom}`; `custom` references a component subtree the host centers.
Maps cleanly everywhere with the caveat that Aurora's gesture idiom is a pull-down *menu*.

---

## 7. Blurs / materials

**Aurora OS**
- **Qt Graphical Effects**: `FastBlur`, `GaussianBlur`, `RecursiveBlur` (Qt 5 `QtGraphicalEffects`;
  Qt 6 reorganizes these under `Qt5Compat.GraphicalEffects` / the multi-effect item). Blur of a
  source item is achievable. No first-party "glass material" abstraction, but a blurred backdrop
  + translucent overlay reproduces the look. → FLAG: available but manual; Qt5→Qt6 module rename
  is a real caveat depending on the Aurora SDK's Qt version.

**Android**
- **`Modifier.blur(radius)`** → backed by `RenderEffect.createBlurEffect`, **API 31+**;
  **no-op below API 31** → FLAG hard min-SDK gate. Backdrop/"glass" blur of content behind a
  surface isn't first-party pre-31; the common cross-version solution is the **Haze** library.
  There is **no first-party `UIVisualEffectView`/material equivalent** — Material surfaces use
  tonal elevation/overlays, not real blur.

**Contract primitive**
```json
{ "modifier": "blur", "radius": 20, "fallback": "scrim" }
```
- iOS → `.blur` / material.
- Android → `Modifier.blur` (API 31+), else `fallback:"scrim"` (translucent overlay) or Haze.
- Aurora → `FastBlur`/`GaussianBlur`, else scrim.
Default `fallback:"scrim"` so the design degrades to a translucent dim on unsupported tiers
rather than a hard edge. Radius is a hint; hosts clamp.

---

## Summary — what maps cleanly, what's partial, what's iOS-only

| Capability | iOS | Android | Aurora | Verdict |
|---|---|---|---|---|
| Force-update (blocking + store link) | ✅ | ✅ (Play Core / RuStore SDK) | ⚠️ backend gate + URL, store deep-link env-dependent | **Clean floor**, richer on iOS/Android |
| Permissions (camera/loc/mic/photos/contacts/calendar/notif) | ✅ runtime | ✅ runtime | ⚠️ **static, install-time; no runtime prompt** | **Model mismatch** — action becomes state-read on Aurora |
| Tracking / ad-id permission | ✅ ATT | ⚠️ AD_ID (declared, no ATT-style prompt) | ❌ N/A (no ad-id) | **iOS-strong, Aurora none** |
| Accessibility state (reader/motion/fontScale) | ✅ | ✅ | ⚠️ fontScale ok; reader/reduce-motion best-effort | **Clean read on iOS/Android**, partial Aurora |
| Background work | ✅ BGTask | ✅ WorkManager (rich constraints) | ⚠️ keepalive + systemd, coarse/manual | **Clean intent**, uneven guarantees |
| Push (visible) | ✅ APNs | ✅ FCM / RuStore | ✅ Aurora Push (manual onboarding) | **Clean**, provider-specific setup |
| Silent / data push refresh | ✅ | ⚠️ FCM data, Doze-throttled | ⚠️ receiver daemon, OMP-bound | **Partial everywhere** — never guaranteed real-time |
| Live / ongoing notification | ✅ Live Activity + Dynamic Island | ⚠️ ProgressStyle (API 36+) else plain progress | ⚠️ ongoing/update only, no rich UI | **iOS-leading; degrade required** |
| Pull-to-refresh + centered loader | ✅ | ✅ PullToRefreshBox | ⚠️ PullDownMenu idiom differs; BusyIndicator fine | **Clean**, Aurora gesture idiom differs |
| Blur / material | ✅ materials | ⚠️ `Modifier.blur` API 31+, no glass material | ⚠️ FastBlur/GaussianBlur, Qt5→Qt6 caveat | **Clean-ish with fallbacks**, no true material off-iOS |

**Cleanly cross-platform:** visible push, background-refresh *intent*, pull-to-refresh +
loaders, force-update floor (backend gate + external URL).

**Partial / needs graceful degradation:** silent push (never real-time-guaranteed), blur
(min-SDK / Qt-version gated, scrim fallback), live/ongoing notifications (rich only on iOS,
Android 16+; ongoing-only on Aurora), accessibility signals on Aurora.

**Model-mismatched:** runtime permissions — the *action* the contract fires is a genuine
prompt on iOS/Android but a static grant-state read on Aurora.

**iOS-only / effectively absent elsewhere:** App-Tracking-Transparency-style tracking consent
(Aurora has no ad-id at all); Dynamic Island's status-chip presentation.

---

## Recommended contract design (degrade gracefully)

1. **Intents, not implementations.** Every capability is a JSON `action`/`modifier` naming an
   *intent* with knobs + a documented default. The host owns the native mapping and may no-op.

2. **Always carry an explicit `fallback` chain** for capabilities that tier out:
   `liveActivity → progressNotification → ongoingNotification → none`,
   `blur → scrim → none`, `inAppUpdate(immediate) → storeUrl → none`.

3. **Capabilities are queryable state, results are reported back.** Expose a read-only
   `$capabilities` binding (`{ liveActivity, blur, silentPush, backgroundRefresh,
   trackingPermission, … }` each `full | partial | none`) so the **server can branch before
   sending** a screen that assumes a capability. Every action returns a status
   (`granted/denied/unavailable/notApplicable` for permissions; the tier actually rendered for
   live/blur). **No screen may assume success.**

4. **Permissions are dual-mode.** `requestPermission` triggers a prompt where the OS has one
   (iOS/Android) and resolves to a grant-state read where it doesn't (Aurora). `tracking`
   resolves to `notApplicable` on Aurora. The server treats `unavailable`/`notApplicable` as a
   first-class branch, not an error.

5. **Store/update destinations are host-overridable per platform** (`storeUrl.{android,
   androidRustore,aurora,ios}`), because there is no universal store scheme — Play, RuStore,
   and Aurora Center each differ.

6. **Background and silent-push are "best-effort."** The contract documents minimum intervals
   and non-guaranteed delivery; screens must tolerate stale data and refresh on foreground.

7. **Anything the contract can't model → `custom { name, payload }`** (see
   [`native-flows.md`](native-flows.md)). This is the release valve for Dynamic Island polish,
   OMP push onboarding quirks, Qt-version blur specifics, and any per-app native bridge — the
   SDUI screen stays platform-neutral while the host handles the specifics.

The through-line: **model the intent once, let each host resolve or degrade, and always report
back what actually happened** so the server never ships a screen that silently depends on a
capability a device doesn't have.

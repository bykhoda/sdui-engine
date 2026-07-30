import Foundation
import SDUICore

/// A non-dismissable (or soft) version-gate alert authored entirely by the
/// contract. The confirm button routes to the App Store; a hard gate re-presents
/// itself so the only escape is updating.
public struct VersionAlert: Equatable, Sendable {
    public let title: String
    public let message: String
    public let confirmTitle: String
    /// `false` = a hard gate (no dismiss); `true` = a soft "recommended" nudge
    /// with a secondary "Later" button.
    public let dismissible: Bool

    public init(title: String, message: String, confirmTitle: String, dismissible: Bool) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.dismissible = dismissible
    }
}

/// A fully decoded, platform-neutral permission request. The `permission` kind is
/// mapped to the concrete OS framework by the host; the contract never names a
/// UIKit / AVFoundation type.
public struct PermissionRequest: Equatable, Sendable {
    /// The closed set of permissions the contract can ask for. Identical spelling
    /// on Android, which maps each to its own runtime permission.
    public enum Kind: String, Sendable {
        case camera, microphone, location, notifications, photos, contacts, calendar, tracking
    }

    public let permission: Kind
    /// Location: `whenInUse` (default) | `always`. Photos: `readWrite` (default) |
    /// `addOnly`. Ignored by permissions that have no level.
    public let level: String?
    /// The contract-authored priming rationale, shown (once) before the OS prompt.
    /// `nil` skips priming and goes straight to the system dialog.
    public let priming: PermissionPriming?
    public let resultKey: String?

    public init(permission: Kind, level: String?, priming: PermissionPriming?, resultKey: String?) {
        self.permission = permission
        self.level = level
        self.priming = priming
        self.resultKey = resultKey
    }
}

/// The `priming` object from a `requestPermission` action, carried verbatim so the
/// host can render it through the SDUI registry (it inherits the app's theme and
/// press feel, not a system alert).
public struct PermissionPriming: Equatable, Sendable {
    /// The raw `priming` JSON, so the host renders it as an SDUI subtree.
    public let raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
}

/// The outcome of an OS permission request, reflected back into `$state` as its
/// `rawValue` so the contract — not Swift — decides what happens next.
public enum PermissionOutcome: String, Sendable {
    case granted, denied, restricted, notDetermined, unavailable
}

/// Capabilities the host app provides so the interpreter can carry out leaf
/// actions. The interpreter owns control flow (`sequence`, `parallel`,
/// `condition`); the host owns side effects. This split keeps the action
/// vocabulary closed and identical across platforms while letting each app wire
/// navigation, analytics and haptics to its own stack.
///
/// `@MainActor` because most of these touch UI or navigation state.
@MainActor
public protocol ActionHost: AnyObject {
    func navigate(to screen: String, params: [String: JSONValue], transition: String) async
    func dismiss() async
    func dismissRoot() async
    func openURL(_ url: String) async
    func setState(key: String, value: JSONValue) async
    func refresh(sources: [String]) async
    /// Loads a single data source (a mutation or fetch), exposing it under
    /// `$data.<source.id>` on success. Returns whether it succeeded, so the
    /// interpreter can run the `onSuccess` / `onError` branch.
    func request(source: DataSource) async -> Bool
    func showToast(message: String, style: String?) async
    /// Scrolls the nearest scroll container to the component whose `id` matches.
    func scrollTo(id: String) async
    func haptic(_ style: String?) async
    func share(text: String?, url: String?) async
    /// Opens the system file previewer (QuickLook) on one or more resolved URLs.
    func preview(urls: [String], index: Int) async
    func log(_ message: String) async
    func track(_ tag: AnalyticsTag) async
    func custom(name: String, payload: JSONValue?) async

    // MARK: Native capabilities

    /// Force-update gate. Compares the running app's version to `minVersion`; when
    /// outdated, presents a (soft or hard) alert routing to the App Store.
    func requireVersion(minVersion: String, storeURL: String,
                        alert: VersionAlert, resultKey: String?) async
    /// `true` the first time this permission is asked (so a priming sheet is worth
    /// showing). Tracked per-permission so priming appears only once.
    func shouldPrime(_ permission: PermissionRequest.Kind) -> Bool
    /// Renders the contract-authored priming rationale through the SDUI registry
    /// and resolves to `true` when the user confirms, `false` when they decline.
    func presentPriming(_ priming: PermissionPriming) async -> Bool
    /// Requests the real OS permission and maps the result to a neutral outcome.
    func requestPermission(_ request: PermissionRequest) async -> PermissionOutcome
}

/// Source-compatible defaults: a host that predates these capabilities keeps
/// compiling — the version gate and permission verbs simply no-op cleanly and
/// write a neutral outcome so the contract's `$state` stays well-defined.
public extension ActionHost {
    func request(source: DataSource) async -> Bool { false }
    func requireVersion(minVersion: String, storeURL: String,
                        alert: VersionAlert, resultKey: String?) async {}
    func shouldPrime(_ permission: PermissionRequest.Kind) -> Bool { false }
    func presentPriming(_ priming: PermissionPriming) async -> Bool { true }
    func requestPermission(_ request: PermissionRequest) async -> PermissionOutcome { .unavailable }
}

/// Walks a declarative `Action` tree and drives the `ActionHost`.
@MainActor
public struct ActionInterpreter {
    private unowned let host: ActionHost

    public init(host: ActionHost) { self.host = host }

    public func run(_ action: Action, ctx: BindingContext) async {
        if let tag = action.analytics { await host.track(tag) }

        switch action.action {
        case "sequence":
            for child in action.actions { await run(child, ctx: ctx) }

        case "parallel":
            // Leaf actions run on the main actor (navigation, haptics, toasts),
            // where concurrent execution would race UI state. We await them in
            // order; genuinely concurrent work belongs in the data layer
            // (DataConfig.mode = parallel), which fans out off the main actor.
            for child in action.actions { await run(child, ctx: ctx) }

        case "condition":
            guard let condData = action.field("if"),
                  let cond = condData.decode(Condition.self) else { return }
            if cond.evaluate(in: ctx) {
                if let then = action.field("then")?.decode(Action.self) { await run(then, ctx: ctx) }
            } else if let els = action.field("else")?.decode(Action.self) {
                await run(els, ctx: ctx)
            }

        case "navigate":
            let to = resolvedString(action.field("to"), ctx)
            let params = resolvedParams(action.field("params"), ctx)
            let transition = action.field("transition")?.stringValue ?? "push"
            await host.navigate(to: to, params: params, transition: transition)

        case "dismiss":      await host.dismiss()
        case "dismissRoot":  await host.dismissRoot()
        case "openURL", "openDeepLink":
            await host.openURL(resolvedString(action.field("url"), ctx))

        case "setState":
            guard let key = action.field("key")?.stringValue else { return }
            let value = resolvedValue(action.field("value"), ctx)
            await host.setState(key: key, value: value)

        case "increment":
            // Add `by` (default 1) to a numeric state key — powers "load more"
            // pagination and steppers without arithmetic in the payload.
            guard let key = action.field("key")?.stringValue else { return }
            let by = action.field("by")?.doubleValue ?? 1
            let bare = key.hasPrefix("$state.") ? String(key.dropFirst("$state.".count)) : key
            let current = ctx.state[bare]?.doubleValue ?? 0
            await host.setState(key: bare, value: .number(current + by))

        case "refresh":
            let sources = action.field("sources")?.arrayValue?.compactMap { $0.stringValue } ?? []
            await host.refresh(sources: sources)

        case "showToast":
            await host.showToast(message: resolvedString(action.field("message"), ctx),
                                 style: action.field("style")?.stringValue)

        case "delay":
            // Declarative pause, mainly for use inside a `sequence`. Concurrency
            // itself stays in the runtime (async/await + TaskGroup) — the contract
            // never speaks GCD/NSOperation.
            let seconds = action.field("seconds")?.doubleValue ?? 0
            if seconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(min(seconds, 60) * 1_000_000_000))
            }

        case "scrollTo":
            await host.scrollTo(id: resolvedString(action.field("target"), ctx))

        case "haptic":
            await host.haptic(action.field("style")?.stringValue)

        case "share":
            await host.share(text: action.field("text").map { resolvedString($0, ctx) },
                             url: action.field("url").map { resolvedString($0, ctx) })

        case "preview":
            // A single `url` or an array of `urls` (swipe between them), with an
            // optional starting `index`. Every entry is binding-resolved so a
            // preview can point at `$item.file` inside a list row.
            var urls: [String] = []
            if let arr = action.field("urls")?.arrayValue {
                urls = arr.compactMap { $0.stringValue }.map { BindingEngine.resolveString($0, in: ctx) }
            } else {
                let single = resolvedString(action.field("url"), ctx)
                if !single.isEmpty { urls = [single] }
            }
            let index = action.field("index")?.doubleValue.map(Int.init) ?? 0
            await host.preview(urls: urls, index: index)

        case "log":
            await host.log(resolvedString(action.field("message"), ctx))

        case "analytics":
            break // already tracked above via action.analytics

        case "custom":
            guard let name = action.field("name")?.stringValue else { return }
            await host.custom(name: name, payload: action.field("payload").map { resolvedValue($0, ctx) })

        case "requireVersion":
            // Server-driven minimum-version gate. `minVersion` is required; the
            // store destination is either an explicit `storeURL` override or an
            // `itms-apps://` URL synthesised from the numeric `storeId`.
            guard let minVersion = action.field("minVersion")?.stringValue, !minVersion.isEmpty else { return }
            let explicitStore = resolvedString(action.field("storeURL"), ctx)
            let storeURL: String
            if !explicitStore.isEmpty {
                storeURL = explicitStore
            } else if let id = action.field("storeId")?.stringValue, !id.isEmpty {
                storeURL = "itms-apps://apps.apple.com/app/id\(id)"
            } else {
                storeURL = ""
            }
            let alert = VersionAlert(
                title: action.field("title")?.stringValue ?? "Update required",
                message: resolvedString(action.field("message"), ctx),
                confirmTitle: action.field("confirmTitle")?.stringValue ?? "Update",
                dismissible: action.field("dismissible")?.boolValue ?? false)
            await host.requireVersion(minVersion: minVersion, storeURL: storeURL,
                                      alert: alert, resultKey: action.field("resultKey")?.stringValue)

        case "requestPermission":
            // Orchestrates priming → OS request → resultKey → onGranted/onDenied.
            // The host owns the platform mechanics; the interpreter owns the flow.
            guard let raw = action.field("permission")?.stringValue,
                  let kind = PermissionRequest.Kind(rawValue: raw) else {
                await host.log("requestPermission: unknown permission '\(action.field("permission")?.stringValue ?? "")'")
                return
            }
            let priming = action.field("priming").map { PermissionPriming(raw: $0) }
            let resultKey = action.field("resultKey")?.stringValue
            let req = PermissionRequest(permission: kind,
                                        level: action.field("level")?.stringValue,
                                        priming: priming,
                                        resultKey: resultKey)
            // Priming is shown only on the first ask, before the (one-shot) OS
            // prompt is burned. Declining priming writes `denied`, runs `onDenied`,
            // and — deliberately — does NOT consume the system prompt.
            if let priming, host.shouldPrime(kind) {
                let confirmed = await host.presentPriming(priming)
                guard confirmed else {
                    if let key = resultKey { await host.setState(key: key, value: .string(PermissionOutcome.denied.rawValue)) }
                    if let onDenied = action.field("onDenied")?.decode(Action.self) { await run(onDenied, ctx: ctx) }
                    return
                }
            }
            let outcome = await host.requestPermission(req)
            if let key = resultKey { await host.setState(key: key, value: .string(outcome.rawValue)) }
            let branch = (outcome == .granted) ? "onGranted" : "onDenied"
            if let next = action.field(branch)?.decode(Action.self) { await run(next, ctx: ctx) }

        case "request":
            // Load a source (a write or fetch); on success its response is exposed as
            // `$data.<source.id>` and `onSuccess` runs, else `onError`. Powers forms,
            // pagination and retry without a client release.
            guard let source = action.field("source")?.decode(DataSource.self) else { return }
            if await host.request(source: source) {
                if let ok = action.field("onSuccess")?.decode(Action.self) { await run(ok, ctx: ctx) }
            } else if let err = action.field("onError")?.decode(Action.self) {
                await run(err, ctx: ctx)
            }

        default:
            await host.log("Unhandled action '\(action.action)'")
        }
    }

    // MARK: - Binding helpers

    private func resolvedString(_ v: JSONValue?, _ ctx: BindingContext) -> String {
        guard let s = v?.stringValue else { return "" }
        return BindingEngine.resolveString(s, in: ctx)
    }
    private func resolvedValue(_ v: JSONValue?, _ ctx: BindingContext) -> JSONValue {
        guard let v else { return .null }
        if case .string(let s) = v { return BindingEngine.resolve(s, in: ctx) }
        return v
    }
    private func resolvedParams(_ v: JSONValue?, _ ctx: BindingContext) -> [String: JSONValue] {
        guard case .object(let o)? = v else { return [:] }
        return o.mapValues { value in
            if case .string(let s) = value { return BindingEngine.resolve(s, in: ctx) }
            return value
        }
    }
}

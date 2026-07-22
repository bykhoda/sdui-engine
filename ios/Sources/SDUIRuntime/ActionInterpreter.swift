import Foundation
import SDUICore

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

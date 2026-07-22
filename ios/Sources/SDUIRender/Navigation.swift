#if canImport(SwiftUI)
import SwiftUI
import SDUICore
import SDUINetwork

/// A navigation target: a screen id, the parameters to pass it, and how to
/// present it. Fully serialisable, so navigation state can be persisted and
/// restored — a requirement the contract shares with the Android renderer.
public struct SDUIRoute: Hashable, Identifiable, Sendable {
    public enum Transition: String, Hashable, Sendable {
        case push, sheet, fullScreenCover, replace
    }

    public let screen: String
    public let params: [String: JSONValue]
    public let transition: Transition

    public init(screen: String, params: [String: JSONValue] = [:], transition: Transition = .push) {
        self.screen = screen
        self.params = params
        self.transition = transition
    }

    /// Stable identity derived from the destination and its parameters.
    public var id: String {
        let query = params.keys.sorted()
            .map { "\($0)=\(params[$0]?.stringValue ?? "")" }
            .joined(separator: "&")
        return query.isEmpty ? screen : "\(screen)?\(query)"
    }
}

/// Resolves a route to the payload that should render for it — typically a
/// backend fetch, a bundled screen, or a cache lookup. The host owns this so the
/// renderer stays transport-agnostic.
public typealias SDUIScreenProvider = @MainActor (SDUIRoute) async -> SDUIDocument?

/// Owns the navigation state for a stack of server-driven screens and acts as
/// the `ActionHost` for navigation. App-level concerns (share, toast, analytics,
/// custom actions) are forwarded to an optional `appDelegate`.
@MainActor
public final class SDUINavigator: ObservableObject, SDUIHostDelegate {
    @Published public var path: [SDUIRoute] = []
    @Published public var sheet: SDUIRoute?
    @Published public var cover: SDUIRoute?

    /// Handles the app-owned side effects the navigator itself doesn't.
    public weak var appDelegate: SDUIHostDelegate?

    public init(appDelegate: SDUIHostDelegate? = nil) {
        self.appDelegate = appDelegate
    }

    // MARK: Navigation primitives

    public func handle(_ route: SDUIRoute) {
        switch route.transition {
        case .push:            path.append(route)
        case .sheet:           sheet = route
        case .fullScreenCover: cover = route
        case .replace:
            if path.isEmpty { path.append(route) } else { path[path.count - 1] = route }
        }
    }

    public func pop() { if !path.isEmpty { path.removeLast() } }
    public func popToRoot() { path.removeAll() }
    public func dismissModal() { sheet = nil; cover = nil }

    // MARK: SDUIHostDelegate

    public func navigate(to screen: String, params: [String: JSONValue], transition: String) {
        handle(SDUIRoute(screen: screen, params: params,
                         transition: SDUIRoute.Transition(rawValue: transition) ?? .push))
    }
    public func dismiss() {
        if sheet != nil || cover != nil { dismissModal() } else { pop() }
    }
    public func dismissRoot() {
        dismissModal()
        popToRoot()
    }
    public func share(text: String?, url: String?) { appDelegate?.share(text: text, url: url) }
    public func showToast(message: String, style: String?) { appDelegate?.showToast(message: message, style: style) }
    public func track(_ tag: AnalyticsTag) { appDelegate?.track(tag) }
    public func custom(name: String, payload: JSONValue?) { appDelegate?.custom(name: name, payload: payload) }
}

/// Hosts a stack of server-driven screens. Give it a root route and a provider
/// that turns any route into a payload; it wires push, sheet and cover
/// presentation to the contract's `navigate` transitions.
public struct SDUIContainerView: View {
    private let root: SDUIRoute
    private let tokens: JSONValue
    private let env: [String: JSONValue]
    private let loader: DataLoader?
    private let registry: ComponentRegistry
    private let appDelegate: SDUIHostDelegate?
    private let provider: SDUIScreenProvider

    @StateObject private var navigator: SDUINavigator

    public init(root: SDUIRoute,
                tokens: JSONValue,
                env: [String: JSONValue] = [:],
                loader: DataLoader? = nil,
                registry: ComponentRegistry? = nil,
                appDelegate: SDUIHostDelegate? = nil,
                provider: @escaping SDUIScreenProvider) {
        self.root = root
        self.tokens = tokens
        self.env = env
        self.loader = loader
        // Built in the main-actor init body (not a nonisolated default arg) so the
        // SDK compiles under Swift 5 language mode too.
        self.registry = registry ?? ComponentRegistry()
        self.appDelegate = appDelegate
        self.provider = provider
        _navigator = StateObject(wrappedValue: SDUINavigator(appDelegate: appDelegate))
    }

    public var body: some View {
        SDUINavPathContainer(path: $navigator.path) {
            routeView(root)
        } destination: { route in
            routeView(route)
        }
        .sheet(item: $navigator.sheet) { route in
            SDUINavContainer { routeView(route) }
                #if os(iOS)
                // Present as a proper bottom sheet — a medium detent that a swipe
                // down dismisses, the modern alert / action pattern (iOS 16+).
                .sduiMediumDetents()
                #endif
        }
        #if os(iOS)
        .fullScreenCover(item: $navigator.cover) { route in
            SDUINavContainer {
                routeView(route)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { navigator.dismissModal() }
                        }
                    }
            }
        }
        #endif
    }

    private func routeView(_ route: SDUIRoute) -> some View {
        RouteScreenView(route: route, tokens: tokens, env: env, loader: loader,
                        registry: registry, delegate: navigator, provider: provider)
    }
}

/// Loads a route's payload asynchronously and renders it, showing a spinner
/// while loading and a recoverable message if the payload can't be resolved.
private struct RouteScreenView: View {
    let route: SDUIRoute
    let tokens: JSONValue
    let env: [String: JSONValue]
    let loader: DataLoader?
    let registry: ComponentRegistry
    let delegate: SDUIHostDelegate
    let provider: SDUIScreenProvider

    @State private var document: SDUIDocument?
    @State private var didFail = false

    var body: some View {
        Group {
            if let document {
                SDUIScreenView(document: document, tokens: tokens, env: env,
                               params: route.params, loader: loader,
                               registry: registry, delegate: delegate)
            } else if didFail {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundColor(.secondary)
                    Text("Couldn't load \(route.screen)").font(.headline)
                }
            } else {
                ProgressView()
            }
        }
        .task(id: route.id) {
            let loaded = await provider(route)
            document = loaded
            didFail = loaded == nil
        }
    }
}
#endif

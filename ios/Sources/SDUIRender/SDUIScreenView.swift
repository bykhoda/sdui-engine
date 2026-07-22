#if canImport(SwiftUI)
import SwiftUI
import SDUICore
import SDUINetwork
import SDUIRuntime

/// App-level concerns the SDUI runtime hands back to the host: navigation,
/// deep links, sharing, analytics and any `custom` actions the app defines.
/// State, refresh and data loading are handled inside the runtime, so a host
/// only implements what genuinely belongs to it.
@MainActor
public protocol SDUIHostDelegate: AnyObject {
    func navigate(to screen: String, params: [String: JSONValue], transition: String)
    func dismiss()
    func dismissRoot()
    func share(text: String?, url: String?)
    func showToast(message: String, style: String?)
    func track(_ tag: AnalyticsTag)
    func custom(name: String, payload: JSONValue?)
}

/// Sensible defaults so a host only overrides what it needs.
public extension SDUIHostDelegate {
    func dismiss() {}
    func dismissRoot() {}
    func share(text: String?, url: String?) {}
    func showToast(message: String, style: String?) {}
    func track(_ tag: AnalyticsTag) {}
    func custom(name: String, payload: JSONValue?) {}
}

/// Owns the live state of one rendered screen: loaded data, mutable client
/// state, and the binding context assembled from tokens + env + data + state.
/// Conforms to `ActionHost` so the interpreter can drive it.
@MainActor
public final class SDUIScreenModel: ObservableObject, ActionHost {
    @Published public private(set) var binding: BindingContext
    @Published public private(set) var isLoading = false
    /// The component id the `scrollTo` action last requested. Paired with a
    /// generation counter so repeated scrolls to the same id still fire.
    @Published public private(set) var scrollTarget: (id: String, generation: Int)?

    private let screen: Screen
    private let loader: DataLoader?
    private weak var delegate: SDUIHostDelegate?

    public init(screen: Screen,
                tokens: JSONValue,
                env: [String: JSONValue],
                params: [String: JSONValue] = [:],
                loader: DataLoader?,
                delegate: SDUIHostDelegate?) {
        self.screen = screen
        self.loader = loader
        self.delegate = delegate
        var state: [String: JSONValue] = [:]
        for (k, v) in screen.state ?? [:] { state[k] = v }
        self.binding = BindingContext(tokens: tokens, env: env, state: state, params: params)
    }

    // MARK: Lifecycle

    public func onAppear(interpreter: ActionInterpreter) async {
        await reload(sources: [])
        if let action = screen.onAppear { await interpreter.run(action, ctx: binding) }
    }

    public func reload(sources: [String]) async {
        guard let loader, let config = screen.data else { return }
        isLoading = true
        let filtered = sources.isEmpty ? config
            : DataConfig(mode: config.mode, sources: config.sources.filter { sources.contains($0.id) })
        let result = await loader.load(filtered, ctx: binding)
        for (id, value) in result { binding.data[id] = value }
        isLoading = false
    }

    /// Loads one ad-hoc source (used by the `async` component). Returns the value,
    /// or `nil` when there's no loader or the response was empty/failed.
    public func loadOne(_ source: DataSource) async -> JSONValue? {
        guard let loader else { return nil }
        let result = await loader.load(DataConfig(mode: .parallel, sources: [source]), ctx: binding)
        guard let value = result[source.id], value != .null else { return nil }
        return value
    }

    // MARK: ActionHost

    public func navigate(to screen: String, params: [String: JSONValue], transition: String) async {
        delegate?.navigate(to: screen, params: params, transition: transition)
    }
    public func dismiss() async { delegate?.dismiss() }
    public func dismissRoot() async { delegate?.dismissRoot() }
    public func openURL(_ url: String) async {
        #if os(iOS)
        if let u = URL(string: url) { await UIApplication.shared.open(u) }
        #endif
    }
    public func setState(key: String, value: JSONValue) async { binding.state[normalizedKey(key)] = value }

    /// Two-way binding into `$state` for text controls. Accepts either a raw key
    /// (`"email"`) or a `$state.email` reference.
    public func stringBinding(for key: String) -> Binding<String> {
        let k = normalizedKey(key)
        return Binding(get: { self.binding.state[k]?.stringValue ?? "" },
                       set: { self.binding.state[k] = .string($0) })
    }

    /// Two-way binding into `$state` for boolean controls (toggles).
    public func boolBinding(for key: String) -> Binding<Bool> {
        let k = normalizedKey(key)
        return Binding(get: { self.binding.state[k]?.boolValue ?? false },
                       set: { self.binding.state[k] = .bool($0) })
    }

    /// Two-way binding into `$state` for continuous controls (sliders).
    public func doubleBinding(for key: String) -> Binding<Double> {
        let k = normalizedKey(key)
        return Binding(get: { self.binding.state[k]?.doubleValue ?? 0 },
                       set: { self.binding.state[k] = .number($0) })
    }

    private func normalizedKey(_ key: String) -> String {
        key.hasPrefix("$state.") ? String(key.dropFirst("$state.".count)) : key
    }
    public func refresh(sources: [String]) async { await reload(sources: sources) }
    public func showToast(message: String, style: String?) async { delegate?.showToast(message: message, style: style) }
    public func scrollTo(id: String) async {
        scrollTarget = (id, (scrollTarget?.generation ?? 0) + 1)
    }
    public func haptic(_ style: String?) async {
        #if os(iOS)
        Haptics.play(style)
        #endif
    }
    public func share(text: String?, url: String?) async { delegate?.share(text: text, url: url) }
    public func preview(urls: [String], index: Int) async {
        #if os(iOS)
        SDUIQuickLook.shared.present(urls: urls, index: index)
        #endif
    }
    public func log(_ message: String) async { print("[SDUI] \(message)") }
    public func track(_ tag: AnalyticsTag) async { delegate?.track(tag) }
    public func custom(name: String, payload: JSONValue?) async { delegate?.custom(name: name, payload: payload) }
}

/// The view a host embeds to render a server-driven screen.
public struct SDUIScreenView: View {
    @StateObject private var model: SDUIScreenModel
    private let screen: Screen
    private let registry: ComponentRegistry
    /// Live collapse progress (0 expanded → 1 collapsed) published by the screen's
    /// scroll, used to cross-fade the compact title into the nav bar.
    @State private var collapseProgress: CGFloat = 0
    /// Kept on the view (not just the model) so a live change — e.g. the host
    /// flipping `theme` to `dark` — reaches token resolution on the next render,
    /// which a `@StateObject`'s frozen init value would not.
    private let env: [String: JSONValue]

    public init(document: SDUIDocument,
                tokens: JSONValue,
                env: [String: JSONValue] = [:],
                params: [String: JSONValue] = [:],
                loader: DataLoader? = nil,
                registry: ComponentRegistry? = nil,
                delegate: SDUIHostDelegate? = nil) {
        self.screen = document.screen
        // Construct the default registry in the (main-actor) init body rather than
        // in a default-argument expression, which is nonisolated — keeps the SDK
        // compiling in Swift 5 language mode, not just Swift 6.
        self.registry = registry ?? ComponentRegistry()
        self.env = env
        _model = StateObject(wrappedValue: SDUIScreenModel(
            screen: document.screen, tokens: tokens, env: env, params: params, loader: loader, delegate: delegate))
    }

    public var body: some View {
        let interpreter = ActionInterpreter(host: model)
        // Overlay the current env (theme/locale) onto the live binding so token
        // resolution reflects the latest host state, not the init-time value.
        var contextBinding = model.binding
        contextBinding.env = env
        let ctx = RenderContext(
            binding: contextBinding,
            registry: registry,
            dispatch: { action, bindingCtx in
                Task { await interpreter.run(action, ctx: bindingCtx) }
            },
            stringBinding: { key in model.stringBinding(for: key) },
            boolBinding: { key in model.boolBinding(for: key) },
            doubleBinding: { key in model.doubleBinding(for: key) },
            loadSource: { source in await model.loadOne(source) })
        let resolvedTitle = screen.title.map { BindingEngine.resolveString($0, in: contextBinding) } ?? ""
        return content(ctx: ctx, interpreter: interpreter)
            .environment(\.sduiScrollTarget, model.scrollTarget.map { SDUIScrollTarget(id: $0.id, generation: $0.generation) })
            // The scroll-reactive header primitive: large title collapse + nav-bar
            // cross-fade when `scrollBehavior` is set; a plain title otherwise.
            .modifier(SDUIScrollHeaderChrome(behavior: screen.scrollBehavior, title: resolvedTitle, progress: $collapseProgress))
            .task { await model.onAppear(interpreter: interpreter) }
            // Tap anywhere outside a field dismisses the keyboard — the expected
            // pattern on every screen (complements drag-to-dismiss on scrolls).
            .onAppear { sduiInstallKeyboardDismiss() }
    }

    @ViewBuilder
    private func content(ctx: RenderContext, interpreter: ActionInterpreter) -> some View {
        if screen.refresh != nil {
            registry.view(for: screen.content, in: ctx)
                .refreshable { await model.reload(sources: screen.refresh?.sources ?? []) }
        } else {
            registry.view(for: screen.content, in: ctx)
        }
    }
}

#if !os(iOS)
/// No-op on platforms without a UIKit keyboard.
@MainActor func sduiInstallKeyboardDismiss() {}
#endif

#if os(iOS)
import UIKit

/// Installs a single window-level tap recogniser that resigns the first responder
/// (dismisses the keyboard) when the user taps outside a text input. It uses
/// `cancelsTouchesInView = false` and ignores touches that land on controls or
/// text inputs, so buttons keep working and tapping a field still focuses it.
@MainActor func sduiInstallKeyboardDismiss() {
    SDUIKeyboardDismisser.shared.install()
}

@MainActor
final class SDUIKeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = SDUIKeyboardDismisser()
    private static let name = "sduiKeyboardDismiss"

    func install() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        let target = windows.first(where: { $0.isKeyWindow }) ?? windows.first
        guard let window = target else { return }
        if window.gestureRecognizers?.contains(where: { $0.name == Self.name }) == true { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.name = Self.name
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UIControl || current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

enum Haptics {
    @MainActor static func play(_ style: String?) {
        switch style {
        case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case "error":   UINotificationFeedbackGenerator().notificationOccurred(.error)
        case "heavy":   UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case "medium":  UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        default:        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
#endif
#endif

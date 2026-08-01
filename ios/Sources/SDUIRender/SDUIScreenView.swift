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
    /// Registry used to render the contract-authored permission priming subtree
    /// through the same builders as the rest of the screen, so it inherits theme
    /// and press feel rather than looking like a system alert.
    private let registry: ComponentRegistry

    public init(screen: Screen,
                tokens: JSONValue,
                env: [String: JSONValue],
                params: [String: JSONValue] = [:],
                loader: DataLoader?,
                delegate: SDUIHostDelegate?,
                registry: ComponentRegistry? = nil) {
        self.screen = screen
        self.loader = loader
        self.delegate = delegate
        self.registry = registry ?? ComponentRegistry()
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

    /// `request` action: load one source (a mutation or fetch), and on success expose its
    /// response under `$data.<source.id>` — which republishes `binding` so the screen
    /// re-renders and the action's `onSuccess` branch (and any bound view) sees it.
    public func request(source: DataSource) async -> Bool {
        guard let value = await loadOne(source) else { return false }
        binding.data[source.id] = value
        return true
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

    // MARK: ActionHost — native capabilities

    /// Force-update gate. Reads `CFBundleShortVersionString` and compares it to
    /// `minVersion` with `.numericSearch`, so "1.10" correctly orders above "1.9".
    /// When outdated, presents the (soft or hard) gate over the top-most VC.
    public func requireVersion(minVersion: String, storeURL: String,
                               alert: VersionAlert, resultKey: String?) async {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        // Numeric ordering → "1.10" correctly compares above "1.9";
        // .orderedAscending == current < min == outdated.
        let outdated = current.compare(minVersion, options: [.numeric]) == .orderedAscending
        if let key = resultKey { await setState(key: key, value: .bool(!outdated)) }
        guard outdated else { return }
        #if os(iOS)
        SDUIVersionGate.shared.present(alert: alert, storeURL: storeURL)
        #endif
    }

    /// First-ask tracking is a small `UserDefaults` flag keyed per permission, so
    /// the contract-authored priming rationale shows only once (before the OS
    /// prompt is burned). No priming to show ⇒ always straight to the request.
    public func shouldPrime(_ permission: PermissionRequest.Kind) -> Bool {
        let key = "sdui.permission.primed.\(permission.rawValue)"
        return !UserDefaults.standard.bool(forKey: key)
    }

    /// Renders the `priming` subtree via the same registry as the screen and
    /// presents it as a sheet. Resolves `true` on confirm, `false` on cancel.
    /// Marks the permission primed so it won't re-prime on a later ask.
    public func presentPriming(_ priming: PermissionPriming) async -> Bool {
        #if os(iOS)
        // The priming subtree renders in a self-contained context that shares this
        // screen's binding/state and dispatches actions through this host.
        let ctx = RenderContext(
            binding: binding,
            registry: registry,
            dispatch: { [weak self] action, bindingCtx in
                guard let self else { return }
                Task { await ActionInterpreter(host: self).run(action, ctx: bindingCtx) }
            },
            stringBinding: { [weak self] key in self?.stringBinding(for: key) ?? .constant("") },
            boolBinding: { [weak self] key in self?.boolBinding(for: key) ?? .constant(false) },
            doubleBinding: { [weak self] key in self?.doubleBinding(for: key) ?? .constant(0) },
            loadSource: { [weak self] source in await self?.loadOne(source) })
        return await SDUIPermissionPriming.shared.present(priming: priming, registry: registry, ctx: ctx)
        #else
        return true
        #endif
    }

    /// Requests the real OS permission, `#available`-gated per framework, and maps
    /// the result to a neutral `PermissionOutcome`. Marks the permission primed so
    /// a subsequent ask skips the rationale sheet.
    ///
    /// NOTE: The matching Info.plist usage-description strings
    /// (`NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`, …) are
    /// **host-app responsibility** — reviewed by Apple, embedded in the binary, and
    /// therefore never server-driven. iOS crashes on request if they're absent.
    public func requestPermission(_ request: PermissionRequest) async -> PermissionOutcome {
        UserDefaults.standard.set(true, forKey: "sdui.permission.primed.\(request.permission.rawValue)")
        #if os(iOS)
        return await SDUIPermissions.request(request)
        #else
        return .unavailable
        #endif
    }
}

/// The view a host embeds to render a server-driven screen.
public struct SDUIScreenView: View {
    @StateObject private var model: SDUIScreenModel
    private let screen: Screen
    private let registry: ComponentRegistry
    /// Live collapse progress (0 expanded → 1 collapsed) published by the screen's
    /// scroll, used to cross-fade the compact title into the nav bar.
    @State private var collapseProgress: CGFloat = 0
    /// One swipe coordinator PER screen instance — enforces "only one row open at
    /// a time" within this screen without leaking that state across stacked
    /// screens (a sheet over a list, a pushed detail). The environment's shared
    /// default is only a last-resort fallback for rows rendered outside a screen.
    @StateObject private var swipeCoordinator = SDUISwipeCoordinator()
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
        let resolvedRegistry = registry ?? ComponentRegistry()
        self.registry = resolvedRegistry
        self.env = env
        _model = StateObject(wrappedValue: SDUIScreenModel(
            screen: document.screen, tokens: tokens, env: env, params: params,
            loader: loader, delegate: delegate, registry: resolvedRegistry))
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
            // Pin the screen root to the top of the available height. Without this a
            // short, non-scrolling root (a `vstack` whose content is smaller than the
            // viewport) is sized to its intrinsic height and then SwiftUI *centers* it
            // vertically in the host's frame — while Android hosts the same screen in a
            // top-start `Box(fillMaxSize)` + `Column`, i.e. top-aligned. Filling the
            // height and anchoring `.top` makes iOS match Android. A `scroll` root
            // already greedily fills its axis, so this is a no-op for scrolling screens.
            .frame(maxHeight: .infinity, alignment: .top)
            // Paint the screen's OWN theme surface behind the content so a screen never
            // depends on (and never mismatches) whatever background the host container
            // happens to have. Resolves `surface` through the same theme logic as every
            // token, so light theme → light surface + dark text, dark → dark + light —
            // never dark-text-on-dark. `chrome: immersive` screens draw full-bleed media
            // over this, so it only shows at the safe-area edges there.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                (Theme.color("$token.color.surface", ctx: contextBinding) ?? Color.clear)
                    .ignoresSafeArea()
            )
            .environment(\.sduiScrollTarget, model.scrollTarget.map { SDUIScrollTarget(id: $0.id, generation: $0.generation) })
            .environment(\.sduiSwipeCoordinator, swipeCoordinator)
            // The scroll-reactive header primitive: large title collapse + nav-bar
            // cross-fade when `scrollBehavior` is set; a plain title otherwise.
            .modifier(SDUIScrollHeaderChrome(behavior: screen.scrollBehavior, title: resolvedTitle, progress: $collapseProgress))
            // Pinned nav-bar toolbar items (search / filter / add) — the HIG home for
            // controls that must NOT scroll away with the content. iOS 14+ placements.
            .modifier(SDUIToolbarChrome(toolbar: screen.toolbar, ctx: ctx))
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

/// Applies the screen's pinned nav-bar toolbar items (leading/trailing icon
/// buttons) via the native `.toolbar`, so search / filter / add controls live in
/// the navigation bar and never scroll away. Uses iOS 14+ placements to keep a
/// low deployment target; a no-op when there's no toolbar or off iOS.
struct SDUIToolbarChrome: ViewModifier {
    let toolbar: Screen.Toolbar?
    let ctx: RenderContext
    func body(content: Content) -> some View {
        #if os(iOS)
        let leading = toolbar?.leading ?? []
        let trailing = toolbar?.trailing ?? []
        if leading.isEmpty && trailing.isEmpty {
            content
        } else {
            // No `if` inside the ToolbarContentBuilder — buildIf is iOS 16+, and we
            // target lower. Empty groups render nothing, so emit both unconditionally.
            content.toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    ForEach(Array(leading.enumerated()), id: \.offset) { _, item in toolbarButton(item) }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    ForEach(Array(trailing.enumerated()), id: \.offset) { _, item in toolbarButton(item) }
                }
            }
        }
        #else
        content
        #endif
    }

    #if os(iOS)
    @ViewBuilder private func toolbarButton(_ item: Screen.Toolbar.Item) -> some View {
        Button {
            if let action = item.action { ctx.dispatch(action, ctx.binding) }
        } label: {
            Image(systemName: item.icon)
        }
        .accessibilityLabel(Text(item.accessibilityLabel ?? item.icon))
    }
    #endif
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

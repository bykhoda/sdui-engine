#if canImport(SwiftUI)
import SwiftUI
import SDUICore

/// Context threaded down the view tree while rendering. Carries the current
/// binding scope (which changes inside list templates as `$item` is bound) plus
/// the registry and the action dispatcher.
public struct RenderContext {
    public var binding: BindingContext
    public let registry: ComponentRegistry
    /// Fire-and-forget dispatch of a declarative action.
    public let dispatch: @MainActor (Action, BindingContext) -> Void
    /// Two-way binding into screen `$state` for form controls (text fields).
    public let stringBinding: @MainActor (String) -> Binding<String>
    /// Two-way binding into screen `$state` for boolean controls (toggles).
    public let boolBinding: @MainActor (String) -> Binding<Bool>
    /// Two-way binding into screen `$state` for continuous controls (sliders).
    public let doubleBinding: @MainActor (String) -> Binding<Double>
    /// Loads a single data source on demand (used by the `async` component to
    /// fetch-then-render). Returns the decoded value, or `nil` on failure. `nil`
    /// when the host wired no loader — `async` then shows its error slot.
    public let loadSource: (@MainActor (DataSource) async -> JSONValue?)?

    public init(binding: BindingContext,
                registry: ComponentRegistry,
                dispatch: @escaping @MainActor (Action, BindingContext) -> Void,
                stringBinding: @escaping @MainActor (String) -> Binding<String>,
                boolBinding: @escaping @MainActor (String) -> Binding<Bool>,
                doubleBinding: @escaping @MainActor (String) -> Binding<Double> = { _ in .constant(0) },
                loadSource: (@MainActor (DataSource) async -> JSONValue?)? = nil) {
        self.binding = binding
        self.registry = registry
        self.dispatch = dispatch
        self.stringBinding = stringBinding
        self.boolBinding = boolBinding
        self.doubleBinding = doubleBinding
        self.loadSource = loadSource
    }

    public func with(item: JSONValue) -> RenderContext {
        var copy = self
        copy.binding.item = item
        return copy
    }
}

/// Maps a component `type` to a SwiftUI builder. Built-in primitives are
/// registered up front; host apps register `custom.*` types to extend the
/// vocabulary without touching the SDK. Unknown types render nothing (safe
/// degradation) instead of crashing.
@MainActor
public final class ComponentRegistry {
    public typealias Builder = @MainActor (Component, RenderContext) -> AnyView
    private var builders: [String: Builder] = [:]

    public init(registerBuiltins: Bool = true) {
        if registerBuiltins { Builtins.registerAll(into: self) }
    }

    public func register(_ type: String, _ builder: @escaping Builder) {
        builders[type] = builder
    }

    public func view(for component: Component, in ctx: RenderContext) -> AnyView {
        // Respect visibleWhen before doing any work.
        if let cond = component.visibleWhen, !cond.evaluate(in: ctx.binding) {
            return AnyView(EmptyView())
        }
        guard let builder = builders[component.type] else {
            return AnyView(unknownView(for: component))
        }
        let base = builder(component, ctx)
        let modified = base.sduiModifiers(component.modifiers, ctx: ctx)
        // A declared id doubles as a scroll anchor for the `scrollTo` action.
        let anchored: AnyView = component.id.map { AnyView(modified.id($0)) } ?? AnyView(modified)
        // "View source" everywhere: long-press ANY real component to copy the exact
        // JSON that renders it — the whole app becomes a live catalog you can lift
        // from. HIG-native (a system context menu with a lifted preview, no on-screen
        // clutter). Skipped for structural nodes and for anything that already owns
        // the long-press (its own action / menu wins, no conflict).
        // A node "owns" the long-press when it has its own onLongPress or a declared
        // contextMenu; `custom.*` components handle their own gestures too.
        let ownsLongPress = component.modifiers?.onLongPress != nil
            || !(component.modifiers?.contextMenu?.isEmpty ?? true)
        // The system context-menu LIFTS a snapshot of the view as its preview. For
        // containers and interactive controls that lift renders large / mispositioned
        // (a purple bubble floating at the top — the "wtf" glitch), and it fights
        // their gestures. So restrict copy-JSON to non-interactive LEAF display nodes
        // (text/image/icon/chart/…) where the lift is small and clean.
        let containers: Set<String> = ["vstack", "hstack", "zstack", "scroll", "list", "grid"]
        let interactive = component.modifiers?.onTap != nil
            || component.modifiers?.onDoubleTap != nil
            || ownsLongPress
        let inspectable = component.type != "spacer" && component.type != "divider"
            && !component.type.hasPrefix("custom.")
            && !containers.contains(component.type)
            && !interactive
        var sourced: AnyView = inspectable
            ? AnyView(anchored.modifier(SDUICopyJSONMenu(component: component)))
            : anchored
        // Crucially, a long-press owner also SUPPRESSES the copy-JSON menu across its
        // whole subtree — otherwise a child leaf (icon/text) inside e.g. a long-press
        // "unlock" row would steal the gesture with its own menu. This is why the
        // gesture demos broke; environment propagation fixes it for any nesting.
        if ownsLongPress {
            sourced = AnyView(sourced.environment(\.sduiInspectSuppressed, true))
        }
        // `presentWhen` presents this fully-built subtree as a modal (sharing the
        // screen's state) and renders nothing inline.
        if let key = component.modifiers?.presentWhen {
            return AnyView(SDUIPresentation(content: sourced,
                                            isPresented: ctx.boolBinding(key),
                                            style: component.modifiers?.presentStyle))
        }
        return sourced
    }

    /// Unknown types degrade safely: a debug hint in DEBUG, nothing in release.
    @ViewBuilder
    private func unknownView(for component: Component) -> some View {
        #if DEBUG
        Text("⚠️ unknown '\(component.type)'").font(.caption).foregroundColor(.red)
        #else
        EmptyView()
        #endif
    }
}

/// Set true on the subtree of any node that owns the long-press, so its children
/// don't attach a competing copy-JSON menu.
private struct SDUIInspectSuppressedKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var sduiInspectSuppressed: Bool {
        get { self[SDUIInspectSuppressedKey.self] }
        set { self[SDUIInspectSuppressedKey.self] = newValue }
    }
}

/// The "view source" context menu: long-press → copy this component's JSON.
private struct SDUICopyJSONMenu: ViewModifier {
    @Environment(\.sduiInspectSuppressed) private var suppressed
    let component: Component

    @ViewBuilder func body(content: Content) -> some View {
        if suppressed {
            content
        } else {
            content.contextMenu {
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = component.sduiPrettyJSON
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
            } label: {
                Label("Copy JSON", systemImage: "curlybraces")
            }
            }
        }
    }
}

extension Component {
    /// This node's JSON, pretty-printed — the exact contract that renders it.
    var sduiPrettyJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(raw),
              let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }
}
#endif

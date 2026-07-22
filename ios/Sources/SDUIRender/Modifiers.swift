#if canImport(SwiftUI)
import SwiftUI
import SDUICore

// Disambiguate the contract types from SwiftUI.EdgeInsets / Foundation.Dimension.
private typealias EdgeInsets = SDUICore.EdgeInsets
private typealias Dimension = SDUICore.Dimension

extension View {
    /// Applies the platform-neutral `Modifiers` block to any rendered component.
    @ViewBuilder
    func sduiModifiers(_ modifiers: Modifiers?, ctx: RenderContext) -> some View {
        if let m = modifiers {
            self.modifier(SDUIModifier(modifiers: m, ctx: ctx))
        } else {
            self
        }
    }
}

private struct SDUIModifier: ViewModifier {
    let modifiers: Modifiers
    let ctx: RenderContext

    func body(content: Content) -> some View {
        content
            .modifier(PaddingModifier(insets: modifiers.padding, ctx: ctx))
            .modifier(SizeModifier(size: modifiers.size, ctx: ctx))
            .modifier(FrameModifier(frame: modifiers.frame, ctx: ctx))
            .modifier(BackgroundModifier(color: modifiers.background, material: modifiers.material, radius: modifiers.cornerRadius, ctx: ctx))
            .modifier(ShadowModifier(shadow: modifiers.shadow, ctx: ctx))
            .opacity(modifiers.opacity ?? 1)
            .modifier(ScaleModifier(scale: modifiers.scale, ctx: ctx))
            .modifier(PulseModifier(pulse: modifiers.pulse, ctx: ctx))
            .modifier(RotationModifier(rotation: modifiers.rotation, ctx: ctx))
            .modifier(AnimationModifier(spec: modifiers.animation, ctx: ctx))
            .modifier(GestureModifier(modifiers: modifiers, ctx: ctx))
            .modifier(ZoomableModifier(active: modifiers.zoomable ?? false))
            .modifier(AccessibilityModifier(spec: modifiers.accessibility, ctx: ctx))
            .modifier(CustomSwipeModifier(swipe: modifiers.swipe, ctx: ctx))
            .modifier(SafeAreaModifier(ignores: modifiers.ignoresSafeArea))
    }
}

/// Extends a node under the safe area (edge-to-edge) — for immersive backgrounds.
private struct SafeAreaModifier: ViewModifier {
    let ignores: Bool?
    func body(content: Content) -> some View {
        if ignores == true { content.ignoresSafeArea() } else { content }
    }
}

/// Uniform scale — a constant or a `$state` binding. Paired with `animation` it
/// gives a spring scale on state change (e.g. album art shrinking on pause).
private struct ScaleModifier: ViewModifier {
    let scale: JSONValue?
    let ctx: RenderContext
    func body(content: Content) -> some View {
        guard let resolved else { return AnyView(content) }
        return AnyView(content.scaleEffect(resolved))
    }
    private var resolved: CGFloat? {
        guard let scale else { return nil }
        if case .string(let s) = scale {
            return BindingEngine.resolve(s, in: ctx.binding).doubleValue.map { CGFloat($0) }
        }
        return scale.doubleValue.map { CGFloat($0) }
    }
}

/// A rhythmic auto-reversing scale "heartbeat". Reads a bool `$state` key and,
/// while true, pulses the view between 1.0 and `scale` forever (album art
/// beating to music, a live "recording" dot). Composes on top of `scale`, so a
/// paused-shrink and a playing-pulse can coexist.
private struct PulseModifier: ViewModifier {
    let pulse: JSONValue?
    let ctx: RenderContext
    @State private var pulsing = false

    func body(content: Content) -> some View {
        guard let cfg = config else { return AnyView(content) }
        return AnyView(
            content
                .scaleEffect(pulsing ? cfg.amplitude : 1)
                .onAppear { update(cfg.active) }
                .onChange(of: cfg.active) { update($0) }
        )
    }

    private func update(_ active: Bool) {
        guard let cfg = config else { return }
        if active {
            withAnimation(.easeInOut(duration: cfg.interval).repeatForever(autoreverses: true)) { pulsing = true }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { pulsing = false }
        }
    }

    private struct Config { let active: Bool; let amplitude: CGFloat; let interval: Double }

    private var config: Config? {
        guard let pulse else { return nil }
        // Shorthand: a bare bool-state key string.
        if case .string(let key) = pulse {
            return Config(active: ctx.boolBinding(key).wrappedValue, amplitude: 1.04, interval: 0.5)
        }
        // Object form: { while, scale, interval }.
        let active = pulse["while"]?.stringValue.map { ctx.boolBinding($0).wrappedValue } ?? true
        let amplitude = CGFloat(pulse["scale"]?.doubleValue ?? 1.04)
        let interval = max(0.1, pulse["interval"]?.doubleValue ?? 0.5)
        return Config(active: active, amplitude: amplitude, interval: interval)
    }
}

/// Rotation in degrees — constant or `$state` binding. With `animation` this
/// spins or flips an element on state change.
private struct RotationModifier: ViewModifier {
    let rotation: JSONValue?
    let ctx: RenderContext
    func body(content: Content) -> some View {
        guard let degrees else { return AnyView(content) }
        return AnyView(content.rotationEffect(.degrees(degrees)))
    }
    private var degrees: Double? {
        guard let rotation else { return nil }
        if case .string(let s) = rotation { return BindingEngine.resolve(s, in: ctx.binding).doubleValue }
        return rotation.doubleValue
    }
}

/// Photo-viewer gesture: pinch to zoom, two fingers to rotate, double-tap to
/// reset — a whole interaction from one `"zoomable": true` flag.
private struct ZoomableModifier: ViewModifier {
    let active: Bool
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var angle: Angle = .zero
    @State private var lastAngle: Angle = .zero

    func body(content: Content) -> some View {
        guard active else { return AnyView(content) }
        return AnyView(
            content
                .scaleEffect(scale)
                .rotationEffect(angle)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { scale = min(4, max(0.5, lastScale * $0)) }
                            .onEnded { _ in lastScale = scale },
                        RotationGesture()
                            .onChanged { angle = lastAngle + $0 }
                            .onEnded { _ in lastAngle = angle }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        scale = 1; lastScale = 1; angle = .zero; lastAngle = .zero
                    }
                }
        )
    }
}

/// Presents a concrete built subtree as a modal (full-screen cover or bottom
/// sheet) while a bool `$state` key is true — nothing renders inline. Because it
/// shares the screen's state, a filter modal drives the same list behind it, and
/// its own `setState … false` (an X button) dismisses it. Presented at the
/// registry level (a real view, not a modifier `Content` placeholder, which does
/// not render inside a detached presentation).
struct SDUIPresentation: View {
    let content: AnyView
    let isPresented: Binding<Bool>
    let style: String?

    var body: some View {
        let anchor = Color.clear.frame(width: 0, height: 0)
        #if os(iOS)
        if style == "sheet" {
            anchor.sheet(isPresented: isPresented) { content.sduiDragIndicator() }
        } else {
            anchor.fullScreenCover(isPresented: isPresented) { content }
        }
        #else
        anchor.sheet(isPresented: isPresented) { content }
        #endif
    }
}

/// Animates this node when screen `$state` changes (toggles, `setState`), using
/// the neutral curve/duration from the contract.
private struct AnimationModifier: ViewModifier {
    let spec: Modifiers.AnimationSpec?
    let ctx: RenderContext
    func body(content: Content) -> some View {
        guard let spec else { return AnyView(content) }
        return AnyView(content.animation(resolved(spec), value: ctx.binding.state))
    }
    private func resolved(_ spec: Modifiers.AnimationSpec) -> Animation {
        let duration = spec.duration ?? 0.25
        switch spec.curve {
        case "linear":  return .linear(duration: duration)
        case "easeIn":  return .easeIn(duration: duration)
        case "easeOut": return .easeOut(duration: duration)
        case "spring":  return .spring()
        default:        return .easeInOut(duration: duration)
        }
    }
}

/// Translates the neutral `SizeSpec` into SwiftUI frames. `weight` is
/// approximated with `layoutPriority`, since SwiftUI has no direct proportional
/// weight (Compose maps it exactly) — see docs/design-notes.md.
private struct SizeModifier: ViewModifier {
    let size: Modifiers.SizeSpec?
    let ctx: RenderContext
    func body(content: Content) -> some View {
        guard let size else { return AnyView(content) }
        var view = AnyView(content)
        if let width = size.width { view = AnyView(apply(view, width, axis: .horizontal)) }
        if let height = size.height { view = AnyView(apply(view, height, axis: .vertical)) }
        return view
    }

    private enum LayoutAxis { case horizontal, vertical }

    private func apply(_ view: AnyView, _ axis: Modifiers.SizeSpec.Axis, axis dir: LayoutAxis) -> some View {
        let value = axis.value.map { CGFloat($0) }
        let minValue = axis.min.map { CGFloat($0) }
        let maxValue: CGFloat? = (axis.mode == .fill || axis.mode == .weight)
            ? .infinity : axis.max.map { CGFloat($0) }

        var sized: AnyView
        switch (dir, axis.mode) {
        case (.horizontal, .fixed):
            sized = AnyView(view.frame(width: value))
        case (.vertical, .fixed):
            sized = AnyView(view.frame(height: value))
        case (.horizontal, _):
            sized = AnyView(view.frame(minWidth: minValue, maxWidth: maxValue))
        case (.vertical, _):
            sized = AnyView(view.frame(minHeight: minValue, maxHeight: maxValue))
        }
        if axis.mode == .weight, let weight = axis.value {
            sized = AnyView(sized.layoutPriority(weight))
        }
        return sized
    }
}

/// Applies neutral accessibility metadata to any node.
private struct AccessibilityModifier: ViewModifier {
    let spec: Modifiers.AccessibilitySpec?
    let ctx: RenderContext
    func body(content: Content) -> some View {
        guard let spec else { return AnyView(content) }
        var view = AnyView(content)
        if let label = spec.label {
            view = AnyView(view.accessibilityLabel(Text(BindingEngine.resolveString(label, in: ctx.binding))))
        }
        if let value = spec.value {
            view = AnyView(view.accessibilityValue(Text(BindingEngine.resolveString(value, in: ctx.binding))))
        }
        if let hint = spec.hint {
            view = AnyView(view.accessibilityHint(Text(BindingEngine.resolveString(hint, in: ctx.binding))))
        }
        if let role = spec.role {
            view = AnyView(view.accessibilityAddTraits(traits(for: role)))
        }
        if spec.hidden == true {
            view = AnyView(view.accessibilityHidden(true))
        }
        return view
    }

    private func traits(for role: String) -> AccessibilityTraits {
        switch role {
        case "button": return .isButton
        case "image": return .isImage
        case "header": return .isHeader
        case "link": return .isLink
        default: return []
        }
    }
}

private struct PaddingModifier: ViewModifier {
    let insets: EdgeInsets?
    let ctx: RenderContext
    func body(content: Content) -> some View {
        switch insets {
        case .none:
            content
        case .all(let dim):
            content.padding(Theme.cgFloat(dim, ctx: ctx.binding))
        case .specific(let top, let leading, let bottom, let trailing, let h, let v):
            content
                .padding(.top, Theme.cgFloat(top ?? v, ctx: ctx.binding))
                .padding(.bottom, Theme.cgFloat(bottom ?? v, ctx: ctx.binding))
                .padding(.leading, Theme.cgFloat(leading ?? h, ctx: ctx.binding))
                .padding(.trailing, Theme.cgFloat(trailing ?? h, ctx: ctx.binding))
        }
    }
}

private struct FrameModifier: ViewModifier {
    let frame: Modifiers.Frame?
    let ctx: RenderContext
    func body(content: Content) -> some View {
        guard let frame else { return AnyView(content) }
        let width = frame.width.map { Theme.cgFloat($0, ctx: ctx.binding) }
        let height = frame.height.map { Theme.cgFloat($0, ctx: ctx.binding) }
        if let maxW = frame.maxWidth {
            let value = Theme.cgFloat(maxW, ctx: ctx.binding, default: CGFloat.infinity)
            return AnyView(content.frame(maxWidth: value, alignment: .leading)
                .frame(width: width, height: height))
        }
        return AnyView(content.frame(width: width, height: height))
    }
}

extension View {
    /// Clips to `shape` only when `active` — so a radius-0 (rectangular) clip is
    /// skipped entirely, letting child shadows bleed instead of being cut.
    @ViewBuilder func sduiClipIfRounded<S: Shape>(_ shape: S, active: Bool) -> some View {
        if active { self.clipShape(shape) } else { self }
    }
}

private struct BackgroundModifier: ViewModifier {
    let color: String?
    let material: String?
    let radius: Dimension?
    let ctx: RenderContext
    func body(content: Content) -> some View {
        let bg = Theme.color(color, ctx: ctx.binding)
        let r = radius.map { Theme.cgFloat($0, ctx: ctx.binding) } ?? 0
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        return content
            .background { materialView(shape) }
            .background(bg?.clipShape(shape))
            // Only clip the content when there's an actual corner radius to enforce.
            // A radius-0 clip is a plain rectangle that adds nothing visually but
            // silently cuts off the shadows of any child cards — the classic
            // "shadows clipped in a container/carousel" bug. No clip = shadows bleed.
            .sduiClipIfRounded(shape, active: r > 0)
    }

    /// A frosted, visionOS-style pane with a top-lit rim when `material == "glass"`.
    @ViewBuilder private func materialView<S: Shape>(_ shape: S) -> some View {
        switch material {
        case "glass":
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.white.opacity(0.08))
                shape.stroke(
                    LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.08)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            }
        case "regular":
            shape.fill(.regularMaterial)
        default:
            EmptyView()
        }
    }
}

private struct ShadowModifier: ViewModifier {
    let shadow: Modifiers.Shadow?
    let ctx: RenderContext
    func body(content: Content) -> some View {
        guard let shadow else { return AnyView(content) }
        let c = Theme.color(shadow.color, ctx: ctx.binding) ?? Color.black.opacity(0.15)
        return AnyView(content.shadow(
            color: c,
            radius: shadow.radius.map { Theme.cgFloat($0, ctx: ctx.binding) } ?? 4,
            x: CGFloat(shadow.x ?? 0),
            y: CGFloat(shadow.y ?? 2)))
    }
}

/// The app-wide press feel — the single interaction principle every tappable
/// element inherits: a springy scale-down, a brightness/opacity dip, and a light
/// haptic tick the instant it's pressed. Applied to every `onTap` element (card,
/// row, icon, chip, button) so the whole app reacts like native controls, by HIG.
public struct SDUIPressableStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1)
            .brightness(configuration.isPressed ? -0.045 : 0)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .contentShape(Rectangle())
            // Springy release so it bounces back to life, not a flat fade.
            .animation(.spring(response: 0.3, dampingFraction: 0.58), value: configuration.isPressed)
            #if os(iOS)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
            #endif
    }
}

private struct GestureModifier: ViewModifier {
    let modifiers: Modifiers
    let ctx: RenderContext

    func body(content: Content) -> some View {
        var view = AnyView(content)
        // Hit slop: grow the tap target, then pull the layout back so nothing
        // shifts — small icons/rows become comfortably tappable.
        if let slop = modifiers.hitSlop {
            let s = CGFloat(slop)
            view = AnyView(view.padding(s).contentShape(Rectangle()).padding(-s))
        }
        // Double tap wins over a single tap when both are present.
        if let dbl = modifiers.onDoubleTap {
            view = AnyView(view.highPriorityGesture(TapGesture(count: 2).onEnded {
                ctx.dispatch(dbl, ctx.binding)
            }))
        }
        if let tap = modifiers.onTap {
            // A real Button (not a bare tap gesture) so every tappable element —
            // card, row, icon, text — springs down and dims on press. That press
            // feedback is what makes taps feel alive across the app.
            view = AnyView(
                Button { ctx.dispatch(tap, ctx.binding) } label: { view }
                    .buttonStyle(SDUIPressableStyle())
            )
        }
        if let longPress = modifiers.onLongPress {
            view = AnyView(view.onLongPressGesture {
                ctx.dispatch(longPress, ctx.binding)
            })
        }
        if let items = modifiers.contextMenu, !items.isEmpty {
            view = AnyView(view.contextMenu {
                ForEach(items.indices, id: \.self) { i in
                    let item = items[i]
                    Button(role: item.role == "destructive" ? .destructive : nil) {
                        ctx.dispatch(item.action, ctx.binding)
                    } label: {
                        Label(BindingEngine.resolveString(item.title, in: ctx.binding),
                              systemImage: item.icon ?? "circle")
                    }
                }
            })
        }
        return view
    }
}
#endif

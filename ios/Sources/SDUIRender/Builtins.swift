#if canImport(SwiftUI)
import SwiftUI
import SDUICore
#if canImport(UIKit)
import UIKit
#endif

// Disambiguate from Foundation.Dimension.
private typealias Dimension = SDUICore.Dimension

/// Registers the built-in primitive components. Each maps one contract `type`
/// to a SwiftUI view. Keeping them in the registry (rather than a switch) means
/// a host app can override any primitive or add new ones uniformly.
enum Builtins {
    @MainActor
    static func registerAll(into r: ComponentRegistry) {
        r.register("vstack") { c, ctx in AnyView(StackView(component: c, ctx: ctx, axis: .vertical)) }
        r.register("hstack") { c, ctx in AnyView(StackView(component: c, ctx: ctx, axis: .horizontal)) }
        r.register("zstack") { c, ctx in AnyView(ZStackView(component: c, ctx: ctx)) }
        r.register("scroll") { c, ctx in AnyView(ScrollContainer(component: c, ctx: ctx)) }
        r.register("list")   { c, ctx in AnyView(ListView(component: c, ctx: ctx)) }
        r.register("spacer") { c, ctx in AnyView(SpacerView(component: c, ctx: ctx)) }
        r.register("divider"){ c, ctx in AnyView(DividerView(component: c, ctx: ctx)) }
        r.register("grid")   { c, ctx in AnyView(GridView(component: c, ctx: ctx)) }
        r.register("text")   { c, ctx in AnyView(TextView(component: c, ctx: ctx)) }
        r.register("icon")   { c, ctx in AnyView(IconView(component: c, ctx: ctx)) }
        r.register("image")  { c, ctx in AnyView(ImageView(component: c, ctx: ctx)) }
        r.register("button") { c, ctx in AnyView(ButtonView(component: c, ctx: ctx)) }
        r.register("textfield") { c, ctx in AnyView(TextFieldView(component: c, ctx: ctx)) }
        r.register("toggle") { c, ctx in AnyView(ToggleView(component: c, ctx: ctx)) }
        r.register("picker") { c, ctx in AnyView(PickerView(component: c, ctx: ctx)) }
        r.register("progress") { c, ctx in AnyView(ProgressBarView(component: c, ctx: ctx)) }
        r.register("gradient") { c, ctx in AnyView(GradientView(component: c, ctx: ctx)) }
        r.register("rings")    { c, ctx in AnyView(RingsView(component: c, ctx: ctx)) }
        r.register("spinner")  { c, ctx in AnyView(SpinnerView(component: c, ctx: ctx)) }
        r.register("async")    { c, ctx in AnyView(AsyncView(component: c, ctx: ctx)) }
        r.register("slider")   { c, ctx in AnyView(SliderView(component: c, ctx: ctx)) }
        r.register("roadmap")  { c, ctx in AnyView(RoadmapView(component: c, ctx: ctx)) }
        r.register("disclosure") { c, ctx in AnyView(DisclosureView(component: c, ctx: ctx)) }
        r.register("ticker") { c, ctx in AnyView(TickerView(component: c, ctx: ctx)) }
        r.register("datepicker") { c, ctx in AnyView(DatePickerView(component: c, ctx: ctx)) }
        r.register("calendar") { c, ctx in AnyView(CalendarGridView(component: c, ctx: ctx)) }
        r.register("clips") { c, ctx in AnyView(ClipsView(component: c, ctx: ctx)) }
        r.register("filecell") { c, ctx in AnyView(FileCellView(component: c, ctx: ctx)) }
        #if canImport(Charts)
        if #available(iOS 16, macOS 13, *) {
            r.register("chart") { c, ctx in AnyView(SDUIChartView(component: c, ctx: ctx)) }
        }
        #endif
    }
}

/// A gradient fill — for immersive backgrounds (Weather-style skies) as a base
/// layer in a zstack, or any decorative surface.
private struct GradientView: View {
    let component: Component
    let ctx: RenderContext
    var body: some View {
        let colors = (component.prop("colors")?.arrayValue ?? [])
            .compactMap { Theme.color($0.stringValue, ctx: ctx.binding) }
        let (start, end) = endpoints(component.prop("direction")?.stringValue ?? "vertical")
        return LinearGradient(colors: colors.isEmpty ? [.blue, .purple] : colors,
                              startPoint: start, endPoint: end)
    }
    private func endpoints(_ direction: String) -> (UnitPoint, UnitPoint) {
        switch direction {
        case "horizontal": return (.leading, .trailing)
        case "diagonal":   return (.topLeading, .bottomTrailing)
        default:            return (.top, .bottom)
        }
    }
}

/// Concentric progress rings (Apple Fitness "activity rings" idiom). Each value in
/// `values` (0…1) draws one ring, outermost first, over a faint track of the same hue.
private struct RingsView: View {
    let component: Component
    let ctx: RenderContext
    var body: some View {
        let values = (component.prop("values")?.arrayValue ?? []).compactMap { $0.doubleValue }
        let colors = (component.prop("colors")?.arrayValue ?? []).compactMap { Theme.color($0.stringValue, ctx: ctx.binding) }
        let lineWidth = CGFloat(component.prop("lineWidth")?.doubleValue ?? 16)
        let gap = CGFloat(component.prop("gap")?.doubleValue ?? 6)
        GeometryReader { geo in
            // Inset by the stroke width so the rounded caps never clip at the edges.
            let side = min(geo.size.width, geo.size.height) - lineWidth
            ZStack {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let color = index < colors.count ? colors[index] : Color.accentColor
                    let inset = CGFloat(index) * (lineWidth + gap)
                    let dim = side - inset * 2
                    ZStack {
                        Circle()
                            .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        Circle()
                            .trim(from: 0, to: min(max(value, 0), 1))
                            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: max(dim, 0), height: max(dim, 0))
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Layout primitives

private struct StackView: View {
    let component: Component
    let ctx: RenderContext
    enum Axis { case vertical, horizontal }
    let axis: Axis

    var body: some View {
        let spacing = component.prop("spacing").flatMap { $0.decode(Dimension.self) }
        let gap = spacing.map { Theme.cgFloat($0, ctx: ctx.binding) }
        let align = component.prop("alignment")?.stringValue
        Group {
            switch axis {
            case .vertical:
                VStack(alignment: hAlign(align), spacing: gap) { childrenBody }
            case .horizontal:
                HStack(alignment: vAlign(align), spacing: gap) { childrenBody }
            }
        }
    }

    @ViewBuilder private var childrenBody: some View {
        ForEach(component.children.indices, id: \.self) { i in
            ctx.registry.view(for: component.children[i], in: ctx)
        }
    }

    private func hAlign(_ s: String?) -> HorizontalAlignment {
        switch s { case "leading": return .leading; case "trailing": return .trailing; default: return .center }
    }
    private func vAlign(_ s: String?) -> VerticalAlignment {
        switch s {
        case "top": return .top
        case "bottom": return .bottom
        case "firstTextBaseline": return .firstTextBaseline
        case "lastTextBaseline": return .lastTextBaseline
        default: return .center
        }
    }
}

private struct ZStackView: View {
    let component: Component
    let ctx: RenderContext
    var body: some View {
        ZStack {
            ForEach(component.children.indices, id: \.self) { i in
                ctx.registry.view(for: component.children[i], in: ctx)
            }
        }
    }
}

/// The `scrollTo` action's current request, published by the screen model.
/// The generation counter lets repeated scrolls to the same id re-fire.
public struct SDUIScrollTarget: Equatable, Sendable {
    public let id: String
    public let generation: Int
    public init(id: String, generation: Int) {
        self.id = id
        self.generation = generation
    }
}

private struct SDUIScrollTargetKey: EnvironmentKey {
    static let defaultValue: SDUIScrollTarget? = nil
}

public extension EnvironmentValues {
    var sduiScrollTarget: SDUIScrollTarget? {
        get { self[SDUIScrollTargetKey.self] }
        set { self[SDUIScrollTargetKey.self] = newValue }
    }
}

private struct ScrollContainer: View {
    let component: Component
    let ctx: RenderContext
    @Environment(\.sduiScrollTarget) private var scrollTarget
    /// The screen-level scroll-reactive header config (inherited from the screen).
    @Environment(\.sduiScrollBehavior) private var behavior
    /// The screen title, used to synthesize the large collapsing header.
    @Environment(\.sduiScreenTitle) private var screenTitle
    /// Content offset (0 at rest, grows as you scroll down). Drives the collapse.
    @State private var offset: CGFloat = 0
    /// Rest-position of the scroll tracker, captured on first layout, so `offset`
    /// is a robust 0 at rest regardless of coordinate-space quirks.
    @State private var scrollBaselineY: CGFloat?
    /// Overscroll past the top (pt) — drives the Telegram-style search reveal.
    @State private var overscroll: CGFloat = 0
    /// Whether the pulled-open search field is latched open.
    @State private var searchOpen = false
    /// Slots decoded ONCE (JSON→Component is costly; re-decoding every scroll frame
    /// is what made the collapsing header stutter). Cached on first appearance.
    @State private var childC: Component?
    @State private var expandedC: Component?
    @State private var compactC: Component?
    /// The sticky header slot (`pinnedHeader`) — starts in the scroll flow, then
    /// pins to the top while the rest of the content scrolls under it.
    @State private var pinnedC: Component?
    /// Optional hero above the sticky header: it scrolls up and away, giving the
    /// header the travel it needs to visibly pin (and un-pin on the way back).
    @State private var leadC: Component?
    /// Multi-section accordion: each section's header pins to the top and its
    /// content tucks under it, then the next section's header takes over.
    @State private var sectionsC: [DecodedSection] = []
    /// A hero above the accordion that collapses from `expanded` (big, in the
    /// scroll) into `compact` (a one-line bar pinned at the very top) on scroll.
    @State private var heroExpandedC: Component?
    @State private var heroCompactC: Component?
    /// Live top-Y of each section header (in the scroll's coordinate space), so the
    /// overlay can pin them as a stack — later covers earlier, none pushed out.
    @State private var headerYs: [Int: CGFloat] = [:]
    @State private var decoded = false

    /// Collects each section header's top-Y, keyed by section index.
    private struct HeaderYKey: PreferenceKey {
        static let defaultValue: [Int: CGFloat] = [:]
        static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    /// One decoded accordion section: a pinning header and the content beneath it.
    private struct DecodedSection: Identifiable {
        let id: Int
        let header: Component?
        let content: Component?
    }

    /// Rounds only the top OR bottom corners, so a pinned header (top-rounded) and
    /// its content (bottom-rounded) read as ONE continuous card even though they
    /// are laid out — and pinned — separately. iOS 15-safe (UIBezierPath); other
    /// platforms fall back to all-corners rounding.
    private struct SectionCardClip: ViewModifier {
        let radius: CGFloat
        let top: Bool
        func body(content: Content) -> some View {
            #if os(iOS)
            content.clipShape(Corners(radius: radius, corners: top ? [.topLeft, .topRight] : [.bottomLeft, .bottomRight]))
            #else
            content.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            #endif
        }
        #if os(iOS)
        private struct Corners: Shape {
            let radius: CGFloat
            let corners: UIRectCorner
            func path(in rect: CGRect) -> Path {
                Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                                  cornerRadii: CGSize(width: radius, height: radius)).cgPath)
            }
        }
        #endif
    }
    /// Natural (unscaled) height of the collapsing header, measured once.
    @State private var headerHeight: CGFloat = 220

    private struct OffsetKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }

    /// Name of the scroll's own coordinate space, in which the top-of-content
    /// tracker reads minY = 0 at rest — the clean baseline for the collapse.
    private static let space = "sduiScrollSpace"

    var body: some View {
        let horizontal = component.prop("axis")?.stringValue == "horizontal"
        // Scroll indicators are hidden by default across the app (opt back in per
        // scroll with "showsIndicators": true) — cleaner, Apple-content style.
        let shows = component.prop("showsIndicators")?.boolValue ?? false
        let header = component.prop("collapsingHeader")
        // A sticky title that travels with the content, then pins to the top while
        // everything else scrolls under it (native `pinnedViews` section header).
        let pinned = component.prop("pinnedHeader")
        // A multi-section accordion (Apple-Weather style): a stack of sections
        // whose headers pin in turn while their content tucks under them.
        let sections = component.prop("sections")?.arrayValue
        // A screen-level `scrollBehavior` synthesizes the collapsing large title
        // from the screen's own title — no hand-authored header per screen. An
        // explicit `collapsingHeader` (bespoke expanded/compact views) still wins.
        let useBehavior = header == nil && pinned == nil && sections == nil && !horizontal
            && behavior != nil && (behavior?.largeTitle ?? true) && !screenTitle.isEmpty

        Group {
            if header != nil {
                collapsingBody(shows: shows, header: header)
            } else if let sections, !sections.isEmpty, !horizontal {
                sectionsBody(shows: shows)
            } else if pinned != nil && !horizontal {
                pinnedBody(shows: shows)
            } else if useBehavior {
                behaviorBody(shows: shows)
            } else {
                plainBody(horizontal: horizontal, shows: shows)
            }
        }
        .onAppear {
            guard !decoded else { return }
            decoded = true
            childC = component.prop("child")?.decode(Component.self)
            expandedC = header?["expanded"]?.decode(Component.self)
            compactC = header?["compact"]?.decode(Component.self)
            pinnedC = component.prop("pinnedHeader")?.decode(Component.self)
            leadC = component.prop("lead")?.decode(Component.self)
            if let arr = component.prop("sections")?.arrayValue {
                sectionsC = arr.enumerated().map { i, s in
                    DecodedSection(id: i, header: s["header"]?.decode(Component.self), content: s["content"]?.decode(Component.self))
                }
            }
            if let hero = component.prop("collapsingHero") {
                heroExpandedC = hero["expanded"]?.decode(Component.self)
                heroCompactC = hero["compact"]?.decode(Component.self)
            }
        }
    }

    @ViewBuilder private func plainBody(horizontal: Bool, shows: Bool) -> some View {
        // When the screen declares a `scrollBehavior` (but not a large title), track
        // the scroll and publish a 0→1 collapse progress; the header chrome uses it
        // to cross-fade a compact title + subtitle into the nav bar (e.g. the weather
        // hero's city/temp slides up into the navigation bar). `range` is tunable.
        let navScroll = !horizontal && behavior != nil
        let threshold = CGFloat(behavior?.range ?? 150)
        let progress = navScroll ? min(max((offset - 60) / max(threshold - 60, 1), 0), 1) : 0
        ScrollViewReader { proxy in
            ScrollView(horizontal ? .horizontal : .vertical, showsIndicators: shows) {
                VStack(spacing: 0) {
                    if navScroll {
                        GeometryReader { geo in
                            Color.clear.preference(key: OffsetKey.self, value: geo.frame(in: .global).minY)
                        }
                        .frame(height: 0)
                    }
                    if let child = childC ?? component.prop("child")?.decode(Component.self) {
                        LazyScrollContent(child: child, ctx: ctx, horizontal: horizontal)
                            // A `ScrollView` clips to its bounds, so a card WITH a shadow
                            // inside a horizontal carousel gets its shadow sliced at the
                            // edges. Reserve a little symmetric room so those shadows
                            // bleed instead of being cut (paired with a negative outer
                            // inset so non-shadowed carousels look unchanged).
                            .sduiScrollShadowRoom(horizontal: horizontal)
                    }
                }
            }
            .sduiScrollShadowRoomOuter(horizontal: horizontal)
            // Drag anywhere to dismiss the keyboard — the expected iOS behaviour
            // (iOS 16+; a no-op on iOS 15).
            .sduiScrollDismissesKeyboardInteractively()
            .onPreferenceChange(OffsetKey.self) { y in
                guard navScroll else { return }
                if scrollBaselineY == nil { scrollBaselineY = y }
                offset = max(0, (scrollBaselineY ?? y) - y)
            }
            .background(Color.clear.preference(key: SDUICollapseProgressKey.self, value: progress))
            .onChange(of: scrollTarget) { target in
                guard let target else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    proxy.scrollTo(target.id, anchor: .center)
                }
            }
        }
    }

    /// The accordion primitive (`sections`): a stack of sections whose headers pin
    /// in turn — each section's content tucks *under* its own header, and the next
    /// section's header pushes the previous one up as it arrives. This is the
    /// native `pinnedViews: [.sectionHeaders]` mechanic (iOS 14+), the exact
    /// Apple-Weather / Music / Contacts behaviour.
    ///
    /// Each header gets a solid occluding backing (`.bar` material by default, or
    /// whatever background the header component declares on top) so content slides
    /// *cleanly under* it instead of showing through. An optional `lead` hero
    /// scrolls away above the first section.
    /// The shared card backing for a section's header + content: a `.bar` material
    /// (so content tucks cleanly under the pinned header) tinted by the optional
    /// `cardColor`, giving both pieces one continuous surface.
    @ViewBuilder private func sectionCardBackground() -> some View {
        if let c = Theme.color(component.prop("cardColor")?.stringValue, ctx: ctx.binding) {
            Rectangle().fill(c)
        } else {
            Rectangle().fill(.bar)
        }
    }

    /// One section header rendered as the top of its card: shared backing, top
    /// corners rounded, opaque so content tucks cleanly under it.
    @ViewBuilder private func sectionHeaderCard(_ header: Component?, radius: CGFloat) -> some View {
        if let header {
            ctx.registry.view(for: header, in: ctx)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { sectionHeaderBackground() }
                .modifier(SectionCardClip(radius: radius, top: true))
        }
    }

    /// Backing for the PINNED header specifically — defaults to an opaque
    /// `sectionHeaderColor` (falling back to `cardColor`) over a `.bar` base, so
    /// content slides fully UNDER it instead of showing through as it scrolls up.
    @ViewBuilder private func sectionHeaderBackground() -> some View {
        if let c = Theme.color(component.prop("sectionHeaderColor")?.stringValue
                                ?? component.prop("cardColor")?.stringValue, ctx: ctx.binding) {
            Rectangle().fill(c)
        } else {
            Rectangle().fill(.bar)
        }
    }

    @ViewBuilder private func sectionsBody(shows: Bool) -> some View {
        let decoded = sectionsC.isEmpty
            ? (component.prop("sections")?.arrayValue ?? []).enumerated().map { i, s in
                DecodedSection(id: i, header: s["header"]?.decode(Component.self), content: s["content"]?.decode(Component.self)) }
            : sectionsC
        let gap = CGFloat(component.prop("sectionSpacing")?.doubleValue ?? 14)
        // Collapsing hero (optional): lives in a PERMANENT top zone (a top safe-area
        // inset), so it is ALWAYS at the top and never scrolls away. It shrinks from
        // `expanded` (full block) to `compact` (one line) as you scroll — height
        // eased from `expandedHeight` → `compactHeight` and the two views cross-fade.
        // The section headers pin directly UNDER it and push each other up. `range`
        // is kept larger than the shrink distance so the inset↔offset coupling stays
        // damped (no snap). Every value is contract-tunable.
        let hero = component.prop("collapsingHero")
        let heroExpanded = heroExpandedC ?? hero?["expanded"]?.decode(Component.self)
        let heroCompact = heroCompactC ?? hero?["compact"]?.decode(Component.self)
        let expandedH = CGFloat(hero?["expandedHeight"]?.doubleValue ?? 200)
        let compactH = CGFloat(hero?["compactHeight"]?.doubleValue ?? 48)
        let range = CGFloat(hero?["range"]?.doubleValue ?? Double(max(expandedH - compactH, 1) * 1.6))
        let hasHero = heroExpanded != nil || heroCompact != nil
        let progress = hasHero ? min(max(offset / range, 0), 1) : 0
        let heroH = hasHero ? expandedH - (expandedH - compactH) * progress : 0
        let radius = CGFloat(component.prop("sectionRadius")?.doubleValue ?? 18)
        GeometryReader { outer in
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: shows) {
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        Color.clear.preference(key: OffsetKey.self, value: geo.frame(in: .global).minY)
                    }
                    .frame(height: 0)
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if let lead = leadC ?? component.prop("lead")?.decode(Component.self) {
                            LazyScrollContent(child: lead, ctx: ctx, horizontal: false)
                        }
                        ForEach(decoded) { section in
                            Section {
                                VStack(spacing: 0) {
                                    if let content = section.content {
                                        LazyScrollContent(child: content, ctx: ctx, horizontal: false)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background { sectionCardBackground() }
                                            .modifier(SectionCardClip(radius: radius, top: false))
                                    }
                                    Color.clear.frame(height: gap)
                                }
                            } header: {
                                sectionHeaderCard(section.header, radius: radius)
                            }
                        }
                    }
                }
            }
            .onPreferenceChange(OffsetKey.self) { trackerY in
                // Capture the tracker's rest Y once, then measure how far it has
                // scrolled up from there — 0 at rest, growing as you scroll (drives
                // the collapse). Baseline-relative, so it ignores coordinate quirks.
                if scrollBaselineY == nil { scrollBaselineY = trackerY }
                offset = max(0, (scrollBaselineY ?? trackerY) - trackerY)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if hasHero {
                    ZStack {
                        if let heroExpanded {
                            ctx.registry.view(for: heroExpanded, in: ctx).opacity(Double(1 - progress))
                        }
                        if let heroCompact {
                            ctx.registry.view(for: heroCompact, in: ctx).opacity(Double(progress))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: heroH, alignment: .center)
                    .background(sectionCardBackground().opacity(Double(progress)))
                    .clipped()
                }
            }
            .sduiScrollDismissesKeyboardInteractively()
            .onChange(of: scrollTarget) { target in
                guard let target else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    proxy.scrollTo(target.id, anchor: .center)
                }
            }
        }
        }
    }

    /// The sticky-header primitive: `pinnedHeader` rides in the scroll flow, then
    /// pins to the top the moment it reaches it while everything below keeps
    /// scrolling *under* it — the native `pinnedViews: [.sectionHeaders]` mechanic
    /// (iOS 14+), so the motion is real UIKit pinning, not offset math.
    ///
    /// Background is TRANSPARENT by default so the header blends into the screen
    /// (no stray tinted band on a dark backdrop). Opt into a frosted backing —
    /// which visibly blurs content sliding beneath, right for light screens — with
    /// `"pinnedHeaderStyle": "material"`. A header with its own `background`
    /// modifier keeps that regardless.
    @ViewBuilder private func pinnedBody(shows: Bool) -> some View {
        let material = component.prop("pinnedHeaderStyle")?.stringValue == "material"
        let centered = component.prop("pinnedHeaderAlign")?.stringValue == "center"
        let headerAlign: Alignment = centered ? .center : .leading
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: shows) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    // Hero above the sticky header: scrolls up and off, so the header
                    // travels to the top and pins — then reverses on the way back down.
                    if let lead = leadC ?? component.prop("lead")?.decode(Component.self) {
                        LazyScrollContent(child: lead, ctx: ctx, horizontal: false)
                    }
                    Section {
                        if let child = childC ?? component.prop("child")?.decode(Component.self) {
                            LazyScrollContent(child: child, ctx: ctx, horizontal: false)
                        }
                    } header: {
                        if let pinned = pinnedC ?? component.prop("pinnedHeader")?.decode(Component.self) {
                            ctx.registry.view(for: pinned, in: ctx)
                                .frame(maxWidth: .infinity, alignment: headerAlign)
                                .background {
                                    if material {
                                        Rectangle().fill(.ultraThinMaterial)
                                    } else {
                                        Color.clear
                                    }
                                }
                        }
                    }
                }
            }
            .sduiScrollDismissesKeyboardInteractively()
            .onChange(of: scrollTarget) { target in
                guard let target else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    proxy.scrollTo(target.id, anchor: .center)
                }
            }
        }
    }

    /// Apple-Weather collapse done with ONE element: the `expanded` header is
    /// pinned at the top and shrinks in place as you scroll — it never leaves,
    /// there is no separate bar. Content reserves the header's full height, and
    /// the collapse range is tuned so the content slides up to sit right under the
    /// shrunk title. A frosted backdrop fades in only once it's collapsing.
    @ViewBuilder private func collapsingBody(shows: Bool, header: JSONValue?) -> some View {
        let collapsedScale: CGFloat = 0.44
        // Fall back to a sensible height until the header measures itself.
        let range = max(headerHeight * (1 - collapsedScale), 1)
        let progress = min(max(offset / range, 0), 1)
        let scale = 1 - (1 - collapsedScale) * progress
        GeometryReader { outer in
            let topInset = outer.safeAreaInsets.top
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: shows) {
                    VStack(spacing: 0) {
                        GeometryReader { geo in
                            Color.clear.preference(key: OffsetKey.self, value: geo.frame(in: .global).minY)
                        }
                        .frame(height: 0)
                        Color.clear.frame(height: headerHeight)   // reserve the header's space
                        if let child = childC {
                            LazyScrollContent(child: child, ctx: ctx, horizontal: false)
                        }
                    }
                }
                .onPreferenceChange(OffsetKey.self) { trackerY in
                    offset = outer.frame(in: .global).minY - trackerY
                }
                .overlay(alignment: .top) {
                    if let expanded = expandedC {
                        ctx.registry.view(for: expanded, in: ctx)
                            .background(
                                GeometryReader { g in
                                    Color.clear.onAppear { headerHeight = g.size.height }
                                }
                            )
                            .scaleEffect(scale, anchor: .top)
                            .frame(maxWidth: .infinity)
                            .padding(.top, topInset)
                            .background {
                                // Transparent while expanded; a frosted top appears
                                // as it collapses so the pinned title stays legible.
                                Rectangle().fill(.bar)
                                    .overlay(Color.black.opacity(0.3))
                                    .opacity(Double(progress))
                                    .ignoresSafeArea(edges: .top)
                            }
                    }
                }
                .onChange(of: scrollTarget) { target in
                    guard let target else { return }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        proxy.scrollTo(target.id, anchor: .center)
                    }
                }
            }
        }
    }

    /// The engine primitive: a large title derived from the SCREEN title that
    /// shrinks and fades as you scroll, handing off to the nav-bar title, with an
    /// optional Telegram-style search revealed by pulling down. Same offset
    /// tracking as the bespoke header, so the motion is identical everywhere and
    /// no screen has to hand-author its own header.
    ///
    /// Motion (tuned to feel like — or better than — Apple's large-title collapse):
    /// • The raw scroll delta is turned into an eased 0…1 `progress` with a
    ///   smoothstep curve, so nothing starts or stops abruptly.
    /// • The title shrinks (scale) and its reserved height collapses on the SAME
    ///   eased curve, anchored bottom-leading, so it slides straight up under the
    ///   bar with no diagonal drift and no content jump.
    /// • The large title stays fully opaque for most of the travel and only fades
    ///   over the last third, exactly as the nav-bar title fades IN (see
    ///   `navProgress`) — a clean hand-off instead of a muddy 50/50 cross-dissolve.
    /// • At the very top, a pull rubber-bands the title slightly larger for the
    ///   classic elastic stretch.
    @ViewBuilder private func behaviorBody(shows: Bool) -> some View {
        let minScale = CGFloat(behavior?.minScale ?? 0.58)
        let titleH: CGFloat = 42
        // Collapse over the title's own shrink distance plus a little runway, so it
        // completes at a natural, unhurried scroll — never too twitchy, never lazy.
        let range = CGFloat(behavior?.range ?? max(Double(titleH) * (1 - Double(minScale)) + 34, 44))
        let debugOffset = ProcessInfo.processInfo.environment["SDUI_DEBUG_OFFSET"].flatMap { Double($0) }.map { CGFloat($0) }
        let effOffset = debugOffset ?? offset
        // Eased progress: linear 0…1, then smoothstep so the motion accelerates and
        // settles gently instead of tracking the finger 1:1 (which reads as jitter).
        let linear = min(max(effOffset / range, 0), 1)
        let progress = linear * linear * (3 - 2 * linear)
        // Rubber-band: a pull at the top gently enlarges the title (capped), giving
        // the elastic feel of Apple's large title without distorting layout.
        let stretch = 1 + min(overscroll, 120) * 0.0016
        let scale = (1 - (1 - minScale) * progress) * stretch
        // The large title holds, then fades over the last third; the reserved height
        // collapses on the full eased curve so content rises smoothly to meet the bar.
        let titleFade = 1 - Double(min(max((progress - 0.55) / 0.45, 0), 1))
        let reveal = behavior?.revealOnPull
        let threshold = CGFloat(reveal?.threshold ?? 52)
        let searchH: CGFloat = reveal == nil ? 0 : (searchOpen ? 44 : min(overscroll, 44))

        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: shows) {
                VStack(alignment: .leading, spacing: 0) {
                    if let reveal, searchH > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField(reveal.placeholder ?? "Search",
                                      text: reveal.bind.map { ctx.stringBinding($0) } ?? .constant(""))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, 20)
                        .frame(height: searchH, alignment: .center)
                        .opacity(Double(min(searchH / 36, 1)))
                        .clipped()
                    }

                    Text(screenTitle)
                        .font(.system(size: 34, weight: .bold))
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .scaleEffect(scale, anchor: .bottomLeading)
                        .opacity(titleFade)
                        // Reserved height collapses smoothly from full → 0 on the eased
                        // curve, so the content below rises to meet the nav bar cleanly.
                        .frame(height: max(titleH * (1 - progress), 0), alignment: .bottomLeading)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    if let sub = behavior?.subtitle {
                        Text(BindingEngine.resolveString(sub, in: ctx.binding))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            // The subtitle fades a touch ahead of the title so the two
                            // don't collide as they compress toward the bar.
                            .opacity(1 - Double(min(progress * 1.4, 1)))
                            .frame(height: max(20 * (1 - progress), 0), alignment: .topLeading)
                            .padding(.horizontal, 20)
                            .padding(.top, 2)
                    }

                    if let child = childC {
                        LazyScrollContent(child: child, ctx: ctx, horizontal: false)
                            .padding(.top, 12)
                    }
                }
                // A REAL-HEIGHT background reader (a 0-height tracker reports stale
                // geometry — that's exactly why the collapse never moved) measured in
                // the scroll's OWN named coordinate space: minY is 0 at rest and goes
                // negative as you scroll down, positive when you pull the top down.
                .background(GeometryReader { geo in
                    Color.clear.preference(key: OffsetKey.self,
                                           value: geo.frame(in: .named(Self.space)).minY)
                })
            }
            .coordinateSpace(name: Self.space)
            .sduiScrollDismissesKeyboardInteractively()
            .onPreferenceChange(OffsetKey.self) { minY in
                offset = max(0, -minY)
                overscroll = max(0, minY)
                if reveal != nil {
                    if overscroll > threshold { searchOpen = true }
                    else if offset > 8 { searchOpen = false }
                }
            }
            // Publish the LATE-timed nav hand-off (title has faded → bar title fades
            // in over the same window) so the cross-fade is clean, not a 50/50 blur.
            .background(Color.clear.preference(key: SDUICollapseProgressKey.self,
                                               value: CGFloat(1 - titleFade)))
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: searchOpen)
            .onChange(of: scrollTarget) { target in
                guard let target else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    proxy.scrollTo(target.id, anchor: .center)
                }
            }
        }
    }
}

/// Renders a scroll's immediate child lazily when it is a matching-axis stack,
/// so long feeds/discover/gallery screens build rows on demand instead of all at
/// once — the fix for the lag on collection-heavy scrolls. When the child is a
/// vertical `vstack` (in a vertical scroll) or a horizontal `hstack` (in a
/// horizontal scroll), its children are flattened directly into a
/// `LazyVStack`/`LazyHStack` that carries over the stack's `spacing`, `alignment`
/// and its own `modifiers` (padding/size/background/…), so the result is
/// pixel-identical — just lazy. Anything else renders exactly as before.
///
/// Zero-config: this is automatic. A stack or scroll can opt back out of laziness
/// with `"lazy": false` (kept eager). Flattening is skipped for any stack that
/// carries a `visibleWhen`/`presentWhen` (whose semantics live at the registry
/// level) so behaviour never changes.
private struct LazyScrollContent: View {
    let child: Component
    let ctx: RenderContext
    let horizontal: Bool

    var body: some View {
        if let stack = lazyStack {
            lazyContainer(for: stack)
        } else {
            ctx.registry.view(for: child, in: ctx)
        }
    }

    /// The child stack to flatten lazily, or `nil` to render eagerly as before.
    private var lazyStack: Component? {
        // Explicit opt-out on either the scroll or the stack keeps it eager.
        if child.prop("lazy")?.boolValue == false { return nil }
        // Only a stack whose axis matches the scroll's is safe to flatten:
        // a vstack in a vertical scroll, an hstack in a horizontal scroll.
        let wantsType = horizontal ? "hstack" : "vstack"
        guard child.type == wantsType else { return nil }
        // These carry registry-level semantics (conditional render / modal
        // presentation) — leave them on the normal path so nothing changes.
        if child.visibleWhen != nil || child.modifiers?.presentWhen != nil { return nil }
        return child
    }

    @ViewBuilder private func lazyContainer(for stack: Component) -> some View {
        let spacing = stack.prop("spacing").flatMap { $0.decode(Dimension.self) }
        let gap = spacing.map { Theme.cgFloat($0, ctx: ctx.binding) }
        let align = stack.prop("alignment")?.stringValue
        let children = stack.children
        // The stack's own modifiers must ride on the lazy container so padding,
        // size, background, id, etc. land exactly where the eager stack put them.
        Group {
            if horizontal {
                LazyHStack(alignment: vAlign(align), spacing: gap) {
                    ForEach(children.indices, id: \.self) { i in
                        ctx.registry.view(for: children[i], in: ctx)
                    }
                }
            } else {
                LazyVStack(alignment: hAlign(align), spacing: gap) {
                    ForEach(children.indices, id: \.self) { i in
                        ctx.registry.view(for: children[i], in: ctx)
                    }
                }
            }
        }
        .sduiModifiers(stack.modifiers, ctx: ctx)
        .modifier(OptionalIDModifier(id: stack.id))
    }

    private func hAlign(_ s: String?) -> HorizontalAlignment {
        switch s { case "leading": return .leading; case "trailing": return .trailing; default: return .center }
    }
    private func vAlign(_ s: String?) -> VerticalAlignment {
        switch s {
        case "top": return .top
        case "bottom": return .bottom
        case "firstTextBaseline": return .firstTextBaseline
        case "lastTextBaseline": return .lastTextBaseline
        default: return .center
        }
    }
}

/// Re-attaches the flattened stack's `id` (its `scrollTo` anchor) to the lazy
/// container, mirroring what the registry does for a normally-rendered node.
private struct OptionalIDModifier: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id { content.id(id) } else { content }
    }
}

/// The symmetric room reserved around horizontal scroll content so a card's
/// shadow bleeds past the scroll's clip instead of being sliced. Sized for a
/// typical card shadow (radius ~8–12, y-offset ~4–6). Applied inside the scroll
/// and cancelled by the outer helper so nothing moves.
private let sduiScrollShadowRoomInset: CGFloat = 18

extension View {
    /// Inner half of the shadow-room trick: pads the scrolled content on every
    /// edge so its shadows have space inside the scroll's clip bounds. A no-op for
    /// vertical scrolls, which don't clip card shadows on their scroll axis and
    /// already let cross-axis shadows bleed to the screen edges.
    @ViewBuilder func sduiScrollShadowRoom(horizontal: Bool) -> some View {
        if horizontal {
            self.padding(.all, sduiScrollShadowRoomInset)
        } else {
            self
        }
    }

    /// Outer half of the trick: an equal negative inset on the `ScrollView` itself,
    /// so the extra room added inside doesn't shift the carousel's resting position
    /// or grow its footprint — it only enlarges the clip bounds the shadows draw in.
    @ViewBuilder func sduiScrollShadowRoomOuter(horizontal: Bool) -> some View {
        if horizontal {
            self.padding(.all, -sduiScrollShadowRoomInset)
        } else {
            self
        }
    }
}

/// A data-bound row with a stable identity, so reordering animates instead of
/// jumping. Falls back to the index only when the item has no id/title.
private struct IdentifiedItem: Identifiable {
    let id: String
    let index: Int
    let value: JSONValue
}

private struct ListView: View {
    let component: Component
    let ctx: RenderContext

    /// Set while the mocked delay runs so the shimmer footer shows and repeated
    /// end-hits are ignored until the page has actually landed.
    @State private var loadingMore = false

    private var spacing: CGFloat {
        component.prop("spacing").flatMap { $0.decode(Dimension.self) }
            .map { Theme.cgFloat($0, ctx: ctx.binding) } ?? 8
    }

    /// When `reorder` is set and `items` binds to a `$state.<key>` array, rows can
    /// be dragged to reorder; the new order is written straight back to state.
    private var reorderRef: String? {
        guard component.prop("reorder")?.boolValue == true,
              let ref = component.prop("items")?.stringValue,
              ref.hasPrefix("$state.") else { return nil }
        return ref
    }

    /// The `$state.<key>` a numeric `limit` binds to, if any — the pagination
    /// cursor we grow to reveal more rows.
    private var limitStateKey: String? {
        guard let ref = component.prop("limit")?.stringValue,
              ref.hasPrefix("$state.") else { return nil }
        return String(ref.dropFirst("$state.".count))
    }

    /// Infinite scroll is on when the contract asks for it explicitly, or — as a
    /// good default — whenever a list paginates off a `$state` limit. An explicit
    /// `"paginateOnScroll": false` always wins so a list can keep a manual button.
    private var paginateOnScroll: Bool {
        if let flag = component.prop("paginateOnScroll")?.boolValue { return flag }
        return limitStateKey != nil
    }

    /// How long the shimmer footer lingers before the next page appears, so the
    /// load reads as real work rather than an instant jump. Tunable per list.
    private var loadDelay: Double {
        component.prop("loadDelay")?.doubleValue ?? 0.6
    }

    /// The `$state.<key>` the filtered-total is mirrored into, if any. Lets the
    /// contract show a live "128 people" count and drive an empty state without
    /// re-implementing the filter — the engine writes the number it just computed.
    private var resultCountKey: String? {
        guard let ref = component.prop("resultCount")?.stringValue,
              ref.hasPrefix("$state.") else { return nil }
        return String(ref.dropFirst("$state.".count))
    }

    var body: some View {
        listContent
        #if os(iOS)
            // Reordering needs edit mode active; leave other lists untouched.
            .environment(\.editMode, .constant(reorderRef == nil ? .inactive : .active))
        #endif
    }

    // A real SwiftUI List so swipe actions, reordering, separators and scrolling
    // are native and buttery — styling stripped so our cards show.
    private var listContent: some View {
        List {
            if let itemsRef = component.prop("items")?.stringValue,
               let template = component.prop("template")?.decode(Component.self) {
                // Search → sort → paginate, all from state, so a data table filters
                // live without a round-trip. (Do it on the backend instead by
                // binding `items` to a query result — the contract doesn't care.)
                let all = sortItems(filterItems(BindingEngine.resolve(itemsRef, in: ctx.binding).arrayValue ?? []))
                let items = paginate(all)
                let hasMore = paginateOnScroll && items.count < all.count
                // Mirror the filtered-total into $state (once per change) so the
                // contract can show a live count and switch to its empty state.
                Color.clear.frame(height: 0)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .onAppear { publishCount(all.count) }
                    .onChange(of: all.count) { publishCount($0) }
                if all.isEmpty, let empty = component.prop("empty")?.decode(Component.self) {
                    // No matches — render the contract's empty slot centred in the row area.
                    ctx.registry.view(for: empty, in: ctx)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    // Stable per-item identity (id/title, else index) — index-based ids
                    // make reordering jump and lag because identity changes on a move.
                    let rows = items.enumerated().map { i, v in
                        IdentifiedItem(id: v["id"]?.stringValue ?? v["title"]?.stringValue ?? "row-\(i)", index: i, value: v)
                    }
                    ForEach(rows) { r in
                        row(template, in: ctx.with(item: r.value), index: r.index, count: rows.count, hasMore: hasMore)
                    }
                    .onMove(perform: reorderRef == nil ? nil : { source, destination in
                        move(items, ref: itemsRef, from: source, to: destination)
                    })
                    if hasMore && loadingMore {
                        paginationFooter
                    }
                }
            } else {
                ForEach(component.children.indices, id: \.self) { i in
                    row(component.children[i], in: ctx, index: i, count: component.children.count, hasMore: false)
                }
            }
        }
        .listStyle(.plain)
        .sduiHiddenScrollBackground()
        .environment(\.defaultMinListRowHeight, 1)
    }

    /// Two or three pulsing placeholder rows that mirror the app's shimmer style —
    /// rendered automatically while a page loads, so a growing list feels like it
    /// is streaming in rather than snapping.
    private var paginationFooter: some View {
        ForEach(0..<3, id: \.self) { _ in
            HStack(spacing: 12) {
                SkeletonView(cornerRadius: 19)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonView(cornerRadius: 5).frame(width: 150, height: 12)
                    SkeletonView(cornerRadius: 5).frame(width: 90, height: 10)
                }
                Spacer()
            }
            .frame(height: 44)
            .listRowInsets(EdgeInsets(top: spacing / 2, leading: 16, bottom: spacing / 2, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .transition(.opacity)
    }

    /// Reaching the last row triggers a page load: show the shimmer, wait out the
    /// mocked delay, then advance the cursor. Guarded so it fires once per page —
    /// never while already loading, and never once every item is on screen.
    private func loadMore() {
        guard paginateOnScroll, !loadingMore else { return }
        withAnimation(.easeInOut(duration: 0.2)) { loadingMore = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, loadDelay) * 1_000_000_000))
            advanceCursor()
            withAnimation(.easeInOut(duration: 0.35)) { loadingMore = false }
        }
    }

    /// Writes the current filtered-total into the `resultCount` state key, but
    /// only when it actually changed and always off the current update cycle, so
    /// SwiftUI never warns about mutating state mid-render.
    private func publishCount(_ count: Int) {
        guard let key = resultCountKey else { return }
        let current = BindingEngine.resolve("$state.\(key)", in: ctx.binding).doubleValue.map(Int.init)
        guard current != count else { return }
        Task { @MainActor in
            let payload = JSONValue.object(["action": .string("setState"), "key": .string(key), "value": .number(Double(count))])
            if let action = payload.decode(Action.self) { ctx.dispatch(action, ctx.binding) }
        }
    }

    /// Prefer the contract's own `onReachEnd` action; otherwise synthesise an
    /// increment on the limit's state key so a plain `limit` list still paginates.
    private func advanceCursor() {
        if let action = component.prop("onReachEnd")?.decode(Action.self) {
            ctx.dispatch(action, ctx.binding)
        } else if let key = limitStateKey {
            let payload = JSONValue.object(["action": .string("increment"), "key": .string(key), "by": .number(6)])
            if let action = payload.decode(Action.self) { ctx.dispatch(action, ctx.binding) }
        }
    }

    /// Full filtering: a text query over fields, an exact category match, and a
    /// numeric min/max range — every criterion bindable to `$state`, so a search
    /// box, chips and amount fields all narrow the same table live.
    private func filterItems(_ items: [JSONValue]) -> [JSONValue] {
        guard let filter = component.prop("filter") else { return items }
        var result = items

        let query = BindingEngine.resolveString(filter["query"]?.stringValue ?? "", in: ctx.binding)
            .trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            let fields = filter["fields"]?.arrayValue?.compactMap { $0.stringValue } ?? []
            result = result.filter { item in
                fields.contains { (item[$0]?.stringValue ?? "").lowercased().contains(query) }
            }
        }
        if let eq = filter["equals"], let field = eq["field"]?.stringValue {
            let value = BindingEngine.resolveString(eq["value"]?.stringValue ?? "", in: ctx.binding)
            if !value.isEmpty && value.lowercased() != "all" {
                result = result.filter { ($0[field]?.stringValue ?? "") == value }
            }
        }
        if let mn = filter["min"], let field = mn["field"]?.stringValue,
           let v = Double(BindingEngine.resolveString(mn["value"]?.stringValue ?? "", in: ctx.binding)), v > 0 {
            result = result.filter { ($0[field]?.doubleValue ?? 0) >= v }
        }
        if let mx = filter["max"], let field = mx["field"]?.stringValue,
           let v = Double(BindingEngine.resolveString(mx["value"]?.stringValue ?? "", in: ctx.binding)), v > 0 {
            result = result.filter { ($0[field]?.doubleValue ?? 0) <= v }
        }
        return result
    }

    /// Sort by a (bindable) field key; numeric when both sides parse, else string.
    private func sortItems(_ items: [JSONValue]) -> [JSONValue] {
        guard let sort = component.prop("sort") else { return items }
        let by = BindingEngine.resolveString(sort["by"]?.stringValue ?? "", in: ctx.binding)
        guard !by.isEmpty else { return items }
        let desc = BindingEngine.resolveString(sort["order"]?.stringValue ?? "asc", in: ctx.binding) == "desc"
        return items.sorted { a, b in
            if let ad = a[by]?.doubleValue, let bd = b[by]?.doubleValue { return desc ? ad > bd : ad < bd }
            let asv = a[by]?.stringValue ?? "", bsv = b[by]?.stringValue ?? ""
            return desc ? asv > bsv : asv < bsv
        }
    }

    /// Show only the first `limit` rows (a number or a `$state` binding) — the
    /// front-end half of pagination; pair with an `increment` action to load more.
    private func paginate(_ items: [JSONValue]) -> [JSONValue] {
        guard let limitProp = component.prop("limit") else { return items }
        let limit: Int
        if let s = limitProp.stringValue {
            limit = Int(BindingEngine.resolveString(s, in: ctx.binding)) ?? items.count
        } else {
            limit = limitProp.doubleValue.map(Int.init) ?? items.count
        }
        return limit > 0 ? Array(items.prefix(limit)) : items
    }

    private func move(_ items: [JSONValue], ref: String, from source: IndexSet, to destination: Int) {
        let key = String(ref.dropFirst("$state.".count))
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        // Persist the new order by dispatching a setState with the moved array.
        let payload = JSONValue.object(["action": .string("setState"), "key": .string(key), "value": .array(reordered)])
        if let action = payload.decode(Action.self) {
            ctx.dispatch(action, ctx.binding)
        }
    }

    @ViewBuilder
    private func row(_ comp: Component, in rowCtx: RenderContext, index: Int, count: Int, hasMore: Bool) -> some View {
        // The List clips its content to its own top/bottom edge, so a card's soft
        // shadow gets sliced off on the very first and last rows (it shows fine
        // between rows). Give those two edges a little extra breathing room —
        // enough to clear the shadow's blur — while keeping the inter-row gap even.
        ctx.registry.view(for: comp, in: rowCtx)
            .listRowInsets(EdgeInsets(
                top: index == 0 ? max(spacing / 2, 12) : spacing / 2,
                leading: 16,
                bottom: index == count - 1 ? max(spacing / 2, 16) : spacing / 2,
                trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .modifier(SwipeActionsModifier(swipe: comp.modifiers?.swipe, ctx: rowCtx))
            .onAppear {
                guard index == count - 1 else { return }
                if paginateOnScroll {
                    // Auto-load: only when more rows remain, and never twice in flight.
                    if hasMore { loadMore() }
                } else if let action = component.prop("onReachEnd")?.decode(Action.self) {
                    // Legacy hook for lists that opted out of infinite scroll.
                    ctx.dispatch(action, ctx.binding)
                }
            }
    }
}

/// Applies native SwiftUI `.swipeActions` to a `List` row from the contract's
/// swipe config, so rows behave exactly like Apple Mail / Telegram: a smooth
/// reveal of colored actions (SF Symbol + label), and a full swipe past the
/// threshold that fires the edge's PRIMARY (first) action with a haptic.
///
/// Native mechanics we lean on (iOS 15+):
/// • `.swipeActions(edge:allowsFullSwipe:)` handles the drag, the rubber-band,
///   and the expand-to-fire animation for free — no custom gesture.
/// • The FIRST `Button` declared on an edge is the one a full swipe triggers,
///   so we keep the contract's first action as the primary (Delete on trailing).
/// • `allowsFullSwipe: true` whenever an edge has any actions, matching Mail —
///   a single action OR the outermost of several fires on a long swipe.
/// • A `Button(role: .destructive)` renders red and gets Mail's destructive
///   full-swipe treatment; any other action is tinted via `.tint(color)`.
private struct SwipeActionsModifier: ViewModifier {
    let swipe: Modifiers.SwipeConfig?
    let ctx: RenderContext

    func body(content: Content) -> some View {
        // `style: "custom"` opts into the drag-revealed circular swipe (applied by
        // the general modifier chain), so the native path steps aside for it.
        if let swipe, swipe.style != "custom" {
            content
                .swipeActions(edge: .leading, allowsFullSwipe: !(swipe.leading?.isEmpty ?? true)) {
                    buttons(swipe.leading ?? [])
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: !(swipe.trailing?.isEmpty ?? true)) {
                    buttons(swipe.trailing ?? [])
                }
        } else {
            content
        }
    }

    @ViewBuilder
    private func buttons(_ actions: [Modifiers.SwipeConfig.SwipeAction]) -> some View {
        ForEach(actions.indices, id: \.self) { i in
            let action = actions[i]
            let title = BindingEngine.resolveString(action.title ?? "", in: ctx.binding)
            let destructive = action.role == "destructive"
            Button(role: destructive ? .destructive : nil) {
                // Fire the contract action, with a haptic that matches the weight
                // of the gesture: a firmer notch for a destructive action (Mail's
                // delete "thunk"), a light tick otherwise.
                #if canImport(UIKit)
                Haptics.play(destructive ? "medium" : "light")
                #endif
                ctx.dispatch(action.action, ctx.binding)
            } label: {
                // A plain SF Symbol + label — the exact Mail/Telegram idiom. Native
                // `.swipeActions` draws the colored full-height track and animates
                // the full-swipe expansion around this Label; a custom container
                // would fight that, so we let the system own the chrome.
                Label(title.isEmpty ? " " : title, systemImage: action.icon ?? "circle")
            }
            // Destructive already reads red; a non-destructive action takes its
            // contract tint (Flag orange, Archive accent/blue, …) or the app accent.
            .tint(tint(action, destructive: destructive))
        }
    }

    private func tint(_ action: Modifiers.SwipeConfig.SwipeAction, destructive: Bool) -> Color {
        if let raw = action.tint, let color = Theme.color(raw, ctx: ctx.binding) { return color }
        return destructive ? .red : .accentColor
    }
}

/// Only one custom-swipe row stays open at a time (Mail/Telegram): opening one
/// closes the rest. A single shared coordinator suffices — at most one is open.
final class SDUISwipeCoordinator: ObservableObject {
    @Published var openId: UUID?
}
private struct SDUISwipeCoordinatorKey: EnvironmentKey {
    static let defaultValue = SDUISwipeCoordinator()
}
extension EnvironmentValues {
    var sduiSwipeCoordinator: SDUISwipeCoordinator {
        get { self[SDUISwipeCoordinatorKey.self] }
        set { self[SDUISwipeCoordinatorKey.self] = newValue }
    }
}

private struct SwipeRowWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A clean, dependency-free swipe state machine — the Mail / Telegram idiom, no
/// hacks: coloured CIRCLE actions revealed by dragging any row/card; only ONE row
/// open at a time (shared coordinator); velocity-aware snapping (a quick flick
/// back closes, a long drag past the other edge opens that side); and full-swipe,
/// where a long drag stretches the edge-most action to fill the row and fires it
/// on release (`fullSwipe:false` disables). Opt in with `swipe.style:"custom"`.
struct CustomSwipeModifier: ViewModifier {
    let swipe: Modifiers.SwipeConfig?
    let ctx: RenderContext
    @Environment(\.sduiSwipeCoordinator) private var coordinator

    @State private var offset: CGFloat = 0     // live drag position
    @State private var settled: CGFloat = 0    // rest: 0 | +openLead | -openTrail
    @State private var width: CGFloat = 360    // measured row width
    @State private var axisLock: Bool?
    @State private var rowID = UUID()

    private var slot: CGFloat { CGFloat(swipe?.actionWidth ?? 74) }
    private var allowFull: Bool { swipe?.fullSwipe ?? true }
    private var isCustom: Bool {
        swipe?.style == "custom"
            && ((swipe?.leading?.isEmpty == false) || (swipe?.trailing?.isEmpty == false))
    }

    private enum Side { case leading, trailing }

    func body(content: Content) -> some View {
        if isCustom, let swipe {
            let leading = swipe.leading ?? []
            let trailing = swipe.trailing ?? []
            let openLead = CGFloat(leading.count) * slot
            let openTrail = CGFloat(trailing.count) * slot
            let trigger = max(width * 0.62, slot + 96)     // full-swipe arm distance
            let armedLead = allowFull && !leading.isEmpty && offset >= trigger
            let armedTrail = allowFull && !trailing.isEmpty && offset <= -trigger
            ZStack {
                // Only the side being revealed is shown; opacity fades smoothly
                // through zero so switching sides never flashes both trays.
                tray(leading, side: .leading, total: max(0, offset), armed: armedLead)
                    .opacity(Double(min(1, max(0, offset / 22))))
                tray(trailing, side: .trailing, total: max(0, -offset), armed: armedTrail)
                    .opacity(Double(min(1, max(0, -offset / 22))))
                content
                    .background(GeometryReader { g in
                        Color.clear.preference(key: SwipeRowWidthKey.self, value: g.size.width)
                    })
                    .offset(x: offset)
                    .highPriorityGesture(drag(leading: leading, trailing: trailing,
                                              openLead: openLead, openTrail: openTrail, trigger: trigger))
            }
            .onPreferenceChange(SwipeRowWidthKey.self) { if $0 > 0 { width = $0 } }
            .onReceive(coordinator.$openId) { id in
                if id != rowID, settled != 0 {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { offset = 0; settled = 0 }
                }
            }
        } else {
            content
        }
    }

    // MARK: Trays — buttons grow from the edge with the drag; the edge one
    // stretches to a pill once armed for full-swipe.

    @ViewBuilder
    private func tray(_ actions: [Modifiers.SwipeConfig.SwipeAction], side: Side, total: CGFloat, armed: Bool) -> some View {
        let count = max(actions.count, 1)
        HStack(spacing: 0) {
            if side == .trailing { Spacer(minLength: 0) }
            ForEach(actions.indices, id: \.self) { i in
                let isEdge = side == .trailing ? (i == actions.count - 1) : (i == 0)
                let w = armed ? (isEdge ? total : 0) : min(slot, total / CGFloat(count))
                swipeButton(actions[i], width: w, expanded: armed && isEdge)
            }
            if side == .leading { Spacer(minLength: 0) }
        }
    }

    private func swipeButton(_ a: Modifiers.SwipeConfig.SwipeAction, width w: CGFloat, expanded: Bool) -> some View {
        let destructive = a.role == "destructive"
        let tint = a.tint.flatMap { Theme.color($0, ctx: ctx.binding) } ?? (destructive ? .red : .accentColor)
        return Button {
            fire(a)
        } label: {
            ZStack {
                if expanded {
                    // The edge action's tinted "pill" stretched to fill the row —
                    // inset a touch so it floats clear of the cell edge, not glued.
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(tint)
                        .padding(.vertical, 7).padding(.horizontal, 7)
                }
                VStack(spacing: 5) {
                    ZStack {
                        if !expanded { Circle().fill(tint).frame(width: 46, height: 46) }
                        Image(systemName: a.icon ?? "circle")
                            .font(.system(size: 19, weight: .semibold)).foregroundColor(.white)
                    }
                    if !expanded {
                        Text(BindingEngine.resolveString(a.title ?? "", in: ctx.binding))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .frame(width: max(w, 0))
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .clipped()
        }
        .buttonStyle(.plain)
        .opacity(w < 2 ? 0 : 1)
    }

    // MARK: Gesture

    private func fire(_ a: Modifiers.SwipeConfig.SwipeAction) {
        #if os(iOS)
        Haptics.play(a.role == "destructive" ? "medium" : "light")
        #endif
        if coordinator.openId == rowID { coordinator.openId = nil }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { offset = 0; settled = 0 }
        ctx.dispatch(a.action, ctx.binding)
    }

    private func drag(leading: [Modifiers.SwipeConfig.SwipeAction],
                      trailing: [Modifiers.SwipeConfig.SwipeAction],
                      openLead: CGFloat, openTrail: CGFloat, trigger: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                if axisLock == nil { axisLock = abs(v.translation.width) > abs(v.translation.height) }
                guard axisLock == true else { return }
                if coordinator.openId != rowID { coordinator.openId = rowID }   // claim single-open
                var new = settled + v.translation.width
                if leading.isEmpty, new > 0 { new *= 0.2 }        // rubber-band a missing edge
                if trailing.isEmpty, new < 0 { new *= 0.2 }
                if new > width { new = width + (new - width) * 0.2 }     // resistance past the row
                if new < -width { new = -width + (new + width) * 0.2 }
                offset = new
            }
            .onEnded { v in
                defer { axisLock = nil }
                guard axisLock == true else { return }
                let release = offset
                let projected = settled + v.predictedEndTranslation.width   // velocity-aware target
                if allowFull, release <= -trigger, let edge = trailing.last { fire(edge); return }
                if allowFull, release >= trigger, let edge = leading.last { fire(edge); return }
                withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                    if settled > 0 {
                        // Leading was open: a short flick back closes; only a LONG drag
                        // fully past the trailing open flips to the other side.
                        if !trailing.isEmpty, projected < -openTrail { settled = -openTrail }
                        else if projected > openLead * 0.5 { settled = openLead }
                        else { settled = 0 }
                    } else if settled < 0 {
                        if !leading.isEmpty, projected > openLead { settled = openLead }
                        else if projected < -openTrail * 0.5 { settled = -openTrail }
                        else { settled = 0 }
                    } else {
                        // Was closed: open the dragged side once past half its width.
                        if !leading.isEmpty, projected > openLead * 0.5 { settled = openLead }
                        else if !trailing.isEmpty, projected < -openTrail * 0.5 { settled = -openTrail }
                        else { settled = 0 }
                    }
                    offset = settled
                }
                if settled == 0, coordinator.openId == rowID { coordinator.openId = nil }
            }
    }
}

private struct SpacerView: View {
    let component: Component
    let ctx: RenderContext
    var body: some View {
        let min = component.prop("minLength").flatMap { $0.decode(Dimension.self) }
            .map { Theme.cgFloat($0, ctx: ctx.binding) }
        Spacer(minLength: min)
    }
}

private struct DividerView: View {
    let component: Component
    let ctx: RenderContext
    var body: some View {
        Divider().background(Theme.color(component.prop("color")?.stringValue, ctx: ctx.binding))
    }
}

// MARK: - Content primitives

private struct TextView: View {
    let component: Component
    let ctx: RenderContext
    var body: some View {
        let value = component.prop("value")?.stringValue ?? ""
        let raw = BindingEngine.resolveString(value, in: ctx.binding)
        let text = Self.formatted(raw,
                                  as: component.prop("format")?.stringValue,
                                  total: component.prop("total")?.doubleValue ?? 1)
        Text(text)
            .font(Theme.font(component.prop("style")?.stringValue, ctx: ctx.binding))
            .foregroundColor(Theme.color(component.prop("color")?.stringValue, ctx: ctx.binding))
            .lineLimit(component.prop("lineLimit").flatMap { $0.doubleValue.map(Int.init) })
            .multilineTextAlignment(alignment)
    }
    private var alignment: TextAlignment {
        switch component.prop("alignment")?.stringValue {
        case "center": return .center
        case "trailing": return .trailing
        default: return .leading
        }
    }

    /// Optional value formatting. `elapsed`/`remaining` turn a 0…1 progress into a
    /// clock (`total` = track length in seconds) — so a ticking `$state` reads out
    /// as `1:14` / `-2:49`. No `format` → the resolved string is shown as-is.
    static func formatted(_ raw: String, as format: String?, total: Double) -> String {
        guard let format else { return raw }
        let progress = Double(raw) ?? 0
        func clock(_ seconds: Double) -> String {
            let s = max(0, Int(seconds.rounded()))
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        switch format {
        case "elapsed":   return clock(progress * total)
        case "remaining": return "-" + clock(max(0, total - progress * total))
        default:          return raw
        }
    }
}

private struct ImageView: View {
    let component: Component
    let ctx: RenderContext
    var body: some View {
        let source = BindingEngine.resolveString(component.prop("source")?.stringValue ?? "", in: ctx.binding)
        let loader = component.prop("loader")
        let ratio = loader?["aspectRatio"]?.doubleValue
        let fill = (loader?["contentMode"]?.stringValue ?? "fill") == "fill"
        let kind = loader?["placeholder"]?.stringValue ?? "skeleton"

        Group {
            if let url = URL(string: source), source.hasPrefix("http") {
                #if canImport(UIKit)
                // Cached (memory + disk) so scrolling a list never re-fetches or
                // flickers — the main fix for laggy image-heavy tables.
                RemoteImage(url: url, fill: fill, loading: { loadingView(kind) }, failure: { failureView })
                #else
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.3))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: fill ? .fill : .fit).transition(.opacity)
                    case .failure: failureView
                    default: loadingView(kind)
                    }
                }
                #endif
            } else {
                loadingView(kind)
            }
        }
        .aspectRatio(ratio.map { CGFloat($0) }, contentMode: fill ? .fill : .fit)
        .clipped()
    }

    @ViewBuilder private func loadingView(_ kind: String) -> some View {
        switch kind {
        case "spinner":
            ZStack { Color.gray.opacity(0.10); ProgressView() }
        case "none":
            Color.clear
        default:
            SkeletonView()
        }
    }

    private var failureView: some View {
        ZStack {
            Color.gray.opacity(0.12)
            Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
        }
    }
}

private struct ButtonView: View {
    let component: Component
    let ctx: RenderContext

    private var fillsWidth: Bool {
        switch component.modifiers?.size?.width?.mode {
        case .fill, .weight: return true
        default: return false
        }
    }

    var body: some View {
        let title = BindingEngine.resolveString(component.prop("title")?.stringValue ?? "", in: ctx.binding)
        let style = component.prop("style")?.stringValue
        let styleNode = style.map { BindingEngine.resolve($0, in: ctx.binding) }
        let enabled = component.prop("enabledWhen")?.decode(Condition.self)?.evaluate(in: ctx.binding) ?? true

        Button {
            if let action = component.prop("onTap")?.decode(Action.self) {
                ctx.dispatch(action, ctx.binding)
            }
        } label: {
            HStack {
                if let icon = component.prop("icon")?.stringValue, !icon.isEmpty {
                    Image(systemName: BindingEngine.resolveString(icon, in: ctx.binding))
                }
                if !title.isEmpty { Text(title) }
            }
            .padding(.vertical, Theme.cgFloat(styleNode?["paddingV"]?.decode(Dimension.self), ctx: ctx.binding, default: 12))
            .padding(.horizontal, Theme.cgFloat(styleNode?["paddingH"]?.decode(Dimension.self), ctx: ctx.binding, default: 16))
            // Stretch the filled label (so its background fills) only when the
            // button is asked to fill width; otherwise it hugs its content.
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background(Theme.color(styleNode?["background"]?.stringValue, ctx: ctx.binding) ?? .accentColor)
            .foregroundColor(Theme.color(styleNode?["foreground"]?.stringValue, ctx: ctx.binding) ?? .white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cgFloat(styleNode?["radius"]?.decode(Dimension.self), ctx: ctx.binding, default: 12)))
        }
        .disabled(!enabled)
        .buttonStyle(SDUIPressableStyle())
    }
}

// MARK: - Grid & icon

private struct GridView: View {
    let component: Component
    let ctx: RenderContext
    var body: some View {
        let columns = max(1, Int(component.prop("columns")?.doubleValue ?? 2))
        let gap = component.prop("spacing").flatMap { $0.decode(Dimension.self) }
            .map { Theme.cgFloat($0, ctx: ctx.binding) } ?? 8
        let layout = Array(repeating: GridItem(.flexible(), spacing: gap), count: columns)
        ScrollView {
            LazyVGrid(columns: layout, spacing: gap) {
                if let itemsRef = component.prop("items")?.stringValue,
                   let template = component.prop("template")?.decode(Component.self) {
                    let items = BindingEngine.resolve(itemsRef, in: ctx.binding).arrayValue ?? []
                    ForEach(items.indices, id: \.self) { i in
                        ctx.registry.view(for: template, in: ctx.with(item: items[i]))
                    }
                } else {
                    ForEach(component.children.indices, id: \.self) { i in
                        ctx.registry.view(for: component.children[i], in: ctx)
                    }
                }
            }
        }
    }
}

/// A draggable continuous control, two-way bound to `$state.<bind>` (0…1). Thin
/// track + fill + white thumb — the Apple scrubber / volume idiom. Drag anywhere
/// on the track to set the value.
private struct SliderView: View {
    let component: Component
    let ctx: RenderContext
    var body: some View {
        let key = component.prop("bind")?.stringValue ?? ""
        let tint = Theme.color(component.prop("color")?.stringValue, ctx: ctx.binding) ?? .accentColor
        let trackH = component.prop("height")?.doubleValue.map { CGFloat($0) } ?? 6
        let thumb = component.prop("thumb")?.boolValue ?? true
        let thumbD = trackH + 8
        let binding = ctx.doubleBinding(key)
        return GeometryReader { geo in
            let w = geo.size.width
            let v = min(max(binding.wrappedValue, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.22)).frame(height: trackH)
                Capsule().fill(tint).frame(width: max(0, v * w), height: trackH)
                if thumb {
                    Circle().fill(.white)
                        .frame(width: thumbD, height: thumbD)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .offset(x: min(max(v * w - thumbD / 2, 0), w - thumbD))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in binding.wrappedValue = min(max(g.location.x / w, 0), 1) }
            )
        }
        .frame(height: max(trackH, thumbD))
    }
}

private struct IconView: View {
    let component: Component
    let ctx: RenderContext
    var body: some View {
        let name = BindingEngine.resolveString(component.prop("name")?.stringValue ?? "", in: ctx.binding)
        let size = component.prop("size")?.doubleValue.map { CGFloat($0) }
        Image(systemName: name)
            .font(size.map { Font.system(size: $0) })
            .foregroundColor(Theme.color(component.prop("color")?.stringValue, ctx: ctx.binding))
            .modifier(SymbolEffectModifier(name: component.prop("symbolEffect")?.stringValue))
    }
}

/// A repeating SF Symbol animation (iOS 17+): bounce, pulse, variableColor, and
/// (iOS 18+) wiggle, rotate, breathe. A no-op on older systems, so the same
/// contract stays safe everywhere.
private struct SymbolEffectModifier: ViewModifier {
    let name: String?
    func body(content: Content) -> some View {
        if #available(iOS 17, macOS 14, *), let name, !name.isEmpty {
            applied(content, name)
        } else {
            content
        }
    }
    @available(iOS 17, macOS 14, *)
    @ViewBuilder private func applied(_ content: Content, _ name: String) -> some View {
        switch name {
        case "pulse":         content.symbolEffect(.pulse, options: .repeating)
        case "variableColor": content.symbolEffect(.variableColor, options: .repeating)
        default:
            // bounce/wiggle/rotate/breathe repeat only on iOS 18+.
            if #available(iOS 18, macOS 15, *) {
                switch name {
                case "bounce":  content.symbolEffect(.bounce, options: .repeating)
                case "wiggle":  content.symbolEffect(.wiggle, options: .repeating)
                case "rotate":  content.symbolEffect(.rotate, options: .repeating)
                case "breathe": content.symbolEffect(.breathe, options: .repeating)
                default:        content
                }
            } else { content }
        }
    }
}

// MARK: - Form controls (two-way bound to $state)

private struct TextFieldView: View {
    let component: Component
    let ctx: RenderContext
    @FocusState private var focused: Bool

    private var accent: Color { Color(.sRGB, red: 0.357, green: 0.357, blue: 0.941, opacity: 1) }
    private var successColor: Color { Color(.sRGB, red: 0.13, green: 0.68, blue: 0.42, opacity: 1) }
    private var errorColor: Color { Color(.sRGB, red: 0.86, green: 0.24, blue: 0.29, opacity: 1) }

    var body: some View {
        let key = component.prop("bind")?.stringValue ?? ""
        let placeholder = BindingEngine.resolveString(component.prop("placeholder")?.stringValue ?? "", in: ctx.binding)
        let kind = component.prop("keyboardType")?.stringValue
        // Explicit visual state so a payload can show validation UI declaratively:
        // "error" | "success" | "disabled". Absent = a normal (focus-aware) field.
        let status = component.prop("status")?.stringValue
        let disabled = status == "disabled"
        let helper = component.prop("helper")?.stringValue.map { BindingEngine.resolveString($0, in: ctx.binding) }
        let leadingIcon = component.prop("icon")?.stringValue
        let label = component.prop("label")?.stringValue.map { BindingEngine.resolveString($0, in: ctx.binding) }
        let hasRich = status != nil || helper != nil || leadingIcon != nil || label != nil

        let field = Group {
            if component.prop("secure")?.boolValue == true {
                SecureField(placeholder, text: ctx.stringBinding(key))
            } else {
                TextField(placeholder, text: ctx.stringBinding(key))
            }
        }
        .textFieldStyle(.plain)
        .font(.body)
        .focused($focused)
        .disabled(disabled)
        #if canImport(UIKit)
        .keyboardType(Self.keyboard(kind))
        .textInputAutocapitalization(kind == "email" || kind == "url" ? .never : .sentences)
        .autocorrectionDisabled(kind == "email" || kind == "url")
        .textContentType(Self.contentType(component.prop("textContentType")?.stringValue))
        .submitLabel(.done)
        #endif

        if hasRich {
            let border: Color = disabled ? Color.primary.opacity(0.08)
                : status == "error" ? errorColor
                : status == "success" ? successColor
                : focused ? accent
                : Color.primary.opacity(0.09)
            let borderWidth: CGFloat = (focused || status == "error" || status == "success") ? 1.6 : 1
            let helperColor: Color = status == "error" ? errorColor : status == "success" ? successColor : .secondary

            VStack(alignment: .leading, spacing: 6) {
                if let label {
                    Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    if let leadingIcon {
                        Image(systemName: leadingIcon).font(.body)
                            .foregroundStyle(focused ? accent : Color.secondary).frame(width: 20)
                    }
                    field
                    if status == "error" {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(errorColor)
                            .transition(.scale.combined(with: .opacity))
                    } else if status == "success" {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(successColor)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 15).padding(.vertical, 13)
                .background(Color.primary.opacity(disabled ? 0.03 : 0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(border, lineWidth: borderWidth))
                .opacity(disabled ? 0.55 : 1)
                // Smoothly animate focus (border lifts to accent) and any state
                // change (error / success / disabled) — nothing snaps.
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: focused)
                .animation(.easeOut(duration: 0.22), value: status)
                if let helper {
                    Text(helper).font(.caption).foregroundStyle(helperColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.22), value: status)
                }
            }
        } else if component.modifiers?.background == nil {
            // Plain style (no stacked rounded border). When the payload gives no
            // background, wrap in a clean modern field; otherwise the payload's
            // background/cornerRadius IS the field — one box, not a box-in-a-box.
            field
                .padding(.horizontal, 15).padding(.vertical, 13)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? accent : Color.primary.opacity(0.09), lineWidth: focused ? 1.6 : 1))
                .animation(.easeOut(duration: 0.16), value: focused)
        } else {
            field
        }
    }

    #if canImport(UIKit)
    /// Maps a contract keyboard name to the native keyboard — so a business owner
    /// can show an email, number or phone pad without touching native code.
    static func keyboard(_ k: String?) -> UIKeyboardType {
        switch k {
        case "email": return .emailAddress
        case "number": return .numberPad
        case "decimal": return .decimalPad
        case "phone": return .phonePad
        case "url": return .URL
        case "numbersAndPunctuation": return .numbersAndPunctuation
        default: return .default
        }
    }
    static func contentType(_ t: String?) -> UITextContentType? {
        switch t {
        case "email": return .emailAddress
        case "password": return .password
        case "newPassword": return .newPassword
        case "name": return .name
        case "username": return .username
        case "oneTimeCode": return .oneTimeCode
        case "telephone": return .telephoneNumber
        default: return nil
        }
    }
    #endif
}

private struct ToggleView: View {
    let component: Component
    let ctx: RenderContext
    var body: some View {
        let key = component.prop("bind")?.stringValue ?? ""
        let title = BindingEngine.resolveString(component.prop("title")?.stringValue ?? "", in: ctx.binding)
        Toggle(title, isOn: ctx.boolBinding(key))
    }
}

private struct PickerView: View {
    let component: Component
    let ctx: RenderContext
    var body: some View {
        let key = component.prop("bind")?.stringValue ?? ""
        let title = BindingEngine.resolveString(component.prop("title")?.stringValue ?? "", in: ctx.binding)
        let options = component.prop("options")?.arrayValue ?? []
        let style = component.prop("style")?.stringValue
        let picker = Picker(title, selection: ctx.stringBinding(key)) {
            ForEach(options.indices, id: \.self) { i in
                let label = BindingEngine.resolveString(options[i]["label"]?.stringValue ?? "", in: ctx.binding)
                let value = options[i]["value"]?.stringValue ?? ""
                Text(label).tag(value)
            }
        }
        return Group {
            switch style {
            case "segmented": picker.pickerStyle(.segmented)
            case "wheel":
                #if os(iOS)
                picker.pickerStyle(.wheel)
                #else
                picker.pickerStyle(.menu)
                #endif
            case "inline":    picker.pickerStyle(.inline)
            default:          picker.pickerStyle(.menu)
            }
        }
    }
}

/// Linear determinate progress (`value` 0…1) or an indeterminate spinner when
/// no value is given. Mirrors a design system's ProgressBar.
/// A slim, rounded progress bar. Determinate (`value` 0…1) fills with a subtle
/// gradient and springs to new values; indeterminate (no `value`) runs a light
/// sweep across the track — a modern loading affordance, not a dated spinner.
private struct ProgressBarView: View {
    let component: Component
    let ctx: RenderContext
    @State private var sweep = false

    var body: some View {
        let tint = Theme.color(component.prop("color")?.stringValue, ctx: ctx.binding) ?? .accentColor
        let height = component.prop("height")?.doubleValue.map { CGFloat($0) } ?? 6
        let value = resolvedValue

        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(tint.opacity(0.16))
                if let value {
                    Capsule(style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.8), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, min(1, value)) * w)
                        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: value)
                } else {
                    Capsule(style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0), tint, tint.opacity(0)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * 0.4)
                        .offset(x: sweep ? w * 0.6 : -w * 0.4)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false), value: sweep)
                }
            }
            .clipShape(Capsule(style: .continuous))
        }
        .frame(height: height)
        .onAppear { sweep = true }
    }

    private var resolvedValue: Double? {
        guard let raw = component.prop("value") else { return nil }
        if case .string(let string) = raw {
            return BindingEngine.resolve(string, in: ctx.binding).doubleValue
        }
        return raw.doubleValue
    }
}
#endif

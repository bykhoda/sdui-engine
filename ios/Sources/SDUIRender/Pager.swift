#if canImport(SwiftUI)
import SwiftUI
import Combine
import SDUICore

/// A paging carousel — one child page at a time, page dots, optional auto-advance.
/// Powers the rotating hero banners on the home. Manual swipe always works; the
/// timer pauses under Reduce Motion (HIG). The Android/Aurora renderers grow the
/// same `pager` from the shared contract.
struct PagerView: View {
    let component: Component
    let ctx: RenderContext

    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let ticker: Publishers.Autoconnect<Timer.TimerPublisher>

    init(component: Component, ctx: RenderContext) {
        self.component = component
        self.ctx = ctx
        let ms = component.prop("autoAdvanceMs")?.doubleValue ?? 0
        // A long idle interval when auto-advance is off, so we don't spin a fast timer.
        let seconds = ms > 0 ? ms / 1000 : 3600
        self.ticker = Timer.publish(every: seconds, on: .main, in: .common).autoconnect()
    }

    private var pages: [Component] { component.children }
    private var pageHeight: CGFloat { CGFloat(component.prop("height")?.doubleValue ?? 200) }
    private var autoMs: Double { component.prop("autoAdvanceMs")?.doubleValue ?? 0 }
    private var showDots: Bool { (component.prop("indicator")?.stringValue ?? "dots") != "none" }
    private var accent: Color { Theme.color("$token.color.primary", ctx: ctx.binding) ?? .accentColor }

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $index) {
                ForEach(pages.indices, id: \.self) { i in
                    ctx.registry.view(for: pages[i], in: ctx)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .tag(i)
                }
            }
            .sduiPageTabStyle()
            .frame(height: pageHeight)

            if showDots && pages.count > 1 {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == index ? accent : Color.secondary.opacity(0.28))
                            .frame(width: i == index ? 18 : 6, height: 6)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
            }
        }
        .onReceive(ticker) { _ in
            guard autoMs > 0, !reduceMotion, pages.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.5)) { index = (index + 1) % pages.count }
        }
    }
}

private extension View {
    /// The swipe-paged `TabView` style. `PageTabViewStyle` is iOS/tvOS/watchOS-only;
    /// on the macOS build host (used for `swift build`/`swift test`, not the real UI)
    /// it's unavailable, so fall back to the default `TabView` there — keeps the
    /// package compiling cross-platform without a hack.
    @ViewBuilder func sduiPageTabStyle() -> some View {
        #if os(iOS) || os(tvOS) || os(watchOS)
        self.tabViewStyle(.page(indexDisplayMode: .never))
        #else
        self
        #endif
    }
}
#endif

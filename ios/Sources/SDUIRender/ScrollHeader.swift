#if canImport(SwiftUI)
import SwiftUI
import SDUICore

// MARK: - Environment plumbing for the scroll-reactive header primitive
//
// The screen owns the `scrollBehavior` config and the resolved title; the scroll
// container (deep in the tree) is what actually tracks the offset and draws the
// collapsing header. We pass the config down via the environment so ANY scroll on
// the screen inherits the behaviour without threading props through every node —
// and the container publishes its collapse progress back up via a preference so
// the screen can cross-fade the compact title into the nav bar.

struct SDUIScrollBehaviorKey: EnvironmentKey {
    static let defaultValue: ScrollBehavior? = nil
}

struct SDUIScreenTitleKey: EnvironmentKey {
    static let defaultValue: String = ""
}

extension EnvironmentValues {
    /// The screen's declarative scroll-reactive header config, if any.
    var sduiScrollBehavior: ScrollBehavior? {
        get { self[SDUIScrollBehaviorKey.self] }
        set { self[SDUIScrollBehaviorKey.self] = newValue }
    }

    /// The screen's resolved title, used to synthesize the large header.
    var sduiScreenTitle: String {
        get { self[SDUIScreenTitleKey.self] }
        set { self[SDUIScreenTitleKey.self] = newValue }
    }
}

/// 0 while the large title is fully expanded → 1 once it has collapsed under the
/// nav bar. Published by the scroll container, read by the screen to drive the
/// nav-bar title cross-fade. `reduce` keeps the max so a nested scroll can't reset it.
struct SDUICollapseProgressKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The screen-side half of the primitive: injects the config + title into the
/// environment (so any scroll on the screen inherits it), reads the published
/// collapse progress, and cross-fades a compact title into the nav bar exactly as
/// it slides under it. When there's no behaviour (or `largeTitle: false`) it just
/// applies the plain navigation title — fully backwards compatible.
struct SDUIScrollHeaderChrome: ViewModifier {
    let behavior: ScrollBehavior?
    let title: String
    @Binding var progress: CGFloat

    func body(content: Content) -> some View {
        // Mirror ScrollContainer's `synthesize`: when the scroll body draws its OWN
        // large title (revealOnPull search, or a subtitle under the big title), the
        // nav bar must NOT also show a native large title — otherwise TWO titles
        // render. So the native `.large` path is used only for the plain default; the
        // synthesized case gets an inline bar (with the weather-style subtitle
        // cross-fade when a subtitle exists).
        let synthesize = behavior?.revealOnPull != nil || !((behavior?.subtitle ?? "").isEmpty)
        if let behavior, behavior.largeTitle ?? true, !synthesize {
            // Native iOS large title — the OS COLLAPSES it into the nav bar on scroll,
            // reliably and smoothly (the real "collapsable header"). `largeTitle:false`
            // opts a screen out and keeps a plain inline title.
            content.navigationTitle(title).sduiLargeTitle()
        } else if let behavior, let subtitle = behavior.subtitle, !subtitle.isEmpty, !title.isEmpty {
            // Nav title + subtitle that cross-fades INTO the nav bar as the content
            // (e.g. the weather hero) scrolls up past it — driven by the scroll's
            // published collapse progress.
            content
                .onPreferenceChange(SDUICollapseProgressKey.self) { progress = $0 }
                .sduiNavScrollTitle(title, subtitle: subtitle, progress: progress)
        } else {
            content.sduiInlineTitle(title)
        }
    }
}

extension View {
    /// An inline navigation title (so the large title lives in the scroll, not the
    /// bar); iOS pins it inline, other platforms just set the title.
    @ViewBuilder func sduiInlineTitle(_ title: String) -> some View {
        #if os(iOS)
        self.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        #else
        self.navigationTitle(title)
        #endif
    }

    /// The system large title that collapses natively on scroll (iOS); a plain
    /// title elsewhere.
    @ViewBuilder func sduiLargeTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    /// A compact title + subtitle in the nav bar (principal placement) that fades
    /// in with `progress` (0 hidden → 1 shown) as the content scrolls up — the
    /// weather-style hand-off of the hero into the navigation bar. iOS 15-safe.
    @ViewBuilder func sduiNavScrollTitle(_ title: String, subtitle: String, progress: CGFloat) -> some View {
        #if os(iOS)
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(title).font(.headline)
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                    }
                    .opacity(Double(min(max(progress, 0), 1)))
                    .accessibilityElement(children: .combine)
                }
            }
        #else
        self.navigationTitle(title)
        #endif
    }
}
#endif

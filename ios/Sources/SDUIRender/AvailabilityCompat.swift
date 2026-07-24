#if canImport(SwiftUI)
import SwiftUI

/// Availability shims that keep the SDK compiling and running on iOS 15 /
/// macOS 12 while giving iOS 16+ the full modern behaviour. Each helper is a
/// no-op (or the closest legacy equivalent) on old systems, so call sites stay
/// free of `#available` noise.
public extension Color {
    /// A grouped-list secondary background that resolves to the native colour on
    /// each platform — so cross-platform demo views compile and look right on the
    /// macOS dev host as well as on iOS.
    static var sduiSecondaryGroupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color.gray.opacity(0.12)
        #endif
    }
}

public extension View {

    /// Hides a scroll view's / `TextEditor`'s system background on iOS 16+; a
    /// no-op on iOS 15 (the default background shows through).
    @ViewBuilder func sduiHiddenScrollBackground() -> some View {
        if #available(iOS 16, macOS 13, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    /// Hides the bottom tab bar for a pushed screen (iOS 16+), so drilling in from
    /// a tab goes full-height — the standard detail-screen behaviour. No-op on iOS 15.
    @ViewBuilder func sduiHiddenTabBar() -> some View {
        #if os(iOS)
        if #available(iOS 16, *) {
            self.toolbar(.hidden, for: .tabBar)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Hides the system row separator inside a `List` on iOS 15 / macOS 13+;
    /// a no-op on macOS 12 (the API is unavailable there, so the default
    /// separator shows — acceptable on the macOS dev host).
    @ViewBuilder func sduiHiddenListRowSeparator() -> some View {
        if #available(iOS 15, macOS 13, *) {
            self.listRowSeparator(.hidden)
        } else {
            self
        }
    }

    /// Applies a font weight on iOS 16+; on iOS 15 the text keeps its font's
    /// default weight (a negligible visual difference).
    @ViewBuilder func sduiFontWeight(_ weight: Font.Weight) -> some View {
        if #available(iOS 16, macOS 13, *) {
            self.fontWeight(weight)
        } else {
            self
        }
    }

    /// Hides scroll indicators on iOS 16+; a no-op on iOS 15.
    @ViewBuilder func sduiHiddenScrollIndicators() -> some View {
        if #available(iOS 16, macOS 13, *) {
            self.scrollIndicators(.hidden)
        } else {
            self
        }
    }

    /// `scrollDismissesKeyboard(.interactively)` on iOS 16+, no-op on iOS 15.
    @ViewBuilder func sduiScrollDismissesKeyboardInteractively() -> some View {
        #if os(iOS)
        if #available(iOS 16, *) {
            self.scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// A half-height detent sheet with a drag indicator on iOS 16+; on iOS 15
    /// the sheet still presents, just full-height without detents.
    @ViewBuilder func sduiMediumDetents() -> some View {
        #if os(iOS)
        if #available(iOS 16, *) {
            self.presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// A drag indicator on the sheet (iOS 16+); no-op on iOS 15.
    @ViewBuilder func sduiDragIndicator() -> some View {
        #if os(iOS)
        if #available(iOS 16, *) {
            self.presentationDragIndicator(.visible)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Two custom detents (a fitted height and large) with a drag indicator on
    /// iOS 16+; on iOS 15 the sheet presents full-height without detents.
    @ViewBuilder func sduiHeightDetents(_ height: CGFloat) -> some View {
        #if os(iOS)
        if #available(iOS 16, *) {
            self.presentationDetents([.height(height), .large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// A fraction+large detent set with a drag indicator on iOS 16+; on iOS 15
    /// the sheet presents full-height without detents.
    @ViewBuilder func sduiFractionDetents(_ fraction: CGFloat) -> some View {
        #if os(iOS)
        if #available(iOS 16, *) {
            self.presentationDetents([.fraction(fraction), .large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if os(iOS)
public extension View {
    /// Shows/hides the tab bar for a pushed detail (iOS 16+); no-op on iOS 15,
    /// where a pushed screen keeps the tab bar visible.
    @ViewBuilder func sduiTabBar(_ visibility: Visibility) -> some View {
        if #available(iOS 16, *) {
            self.toolbar(visibility, for: .tabBar)
        } else {
            self
        }
    }

    /// Hides the navigation-bar background so an immersive screen shows through
    /// (iOS 16+); no-op on iOS 15 (the bar keeps its default appearance).
    @ViewBuilder func sduiHiddenNavBarBackground() -> some View {
        if #available(iOS 16, *) {
            self.toolbarBackground(.hidden, for: .navigationBar)
        } else {
            self
        }
    }

    /// Forces a dark color scheme on the navigation bar (iOS 16+); no-op on
    /// iOS 15.
    @ViewBuilder func sduiDarkNavBar() -> some View {
        if #available(iOS 16, *) {
            self.toolbarColorScheme(.dark, for: .navigationBar)
        } else {
            self
        }
    }
}
#endif
#endif

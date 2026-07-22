#if canImport(SwiftUI)
import SwiftUI

/// A navigable catalog destination — either a single screen or a category of
/// screens. Modeled as one value type so navigation (both tap-driven and
/// programmatic) works through a single mechanism on iOS 16 and iOS 15 alike.
enum CatalogDestination: Hashable {
    case example(PlaygroundExample)
    case category(PlaygroundCategory)
}

/// A catalog navigation stack that pushes ``CatalogDestination`` values.
///
/// - iOS 16+: a real `NavigationStack(path:)` with `navigationDestination`, so
///   deep paths push and restore normally.
/// - iOS 15: a `NavigationView` (stack style). Tap navigation uses
///   `NavigationLink(destination:)` via ``catalogLink(_:label:)``; programmatic
///   navigation uses the top of `path` through a hidden `NavigationLink`.
///
/// Degradation on iOS 15: only the **top** route of a programmatic path is
/// pushed (single level). Tap-driven pushes work normally and can go one level
/// deep at a time. In this catalog the deepest real path is two levels
/// (category → screen), reached by tapping, which iOS 15 handles fine; the only
/// simplification is that a programmatic multi-level restore collapses to its
/// last route.
struct CatalogStack<Root: View>: View {
    @Binding var path: [CatalogDestination]
    @ViewBuilder let root: () -> Root

    var body: some View {
        if #available(iOS 16, macOS 13, *) {
            NavigationStack(path: $path) {
                root()
                    .navigationDestination(for: CatalogDestination.self) { dest in
                        CatalogDestinationView(destination: dest)
                    }
            }
        } else {
            legacy
        }
    }

    private var legacy: some View {
        let active = Binding<Bool>(
            get: { !path.isEmpty },
            set: { if !$0 { path.removeAll() } }
        )
        return NavigationView {
            ZStack {
                root()
                NavigationLink(isActive: active) {
                    if let top = path.last {
                        CatalogDestinationView(destination: top)
                    } else {
                        EmptyView()
                    }
                } label: { EmptyView() }
                .opacity(0)
                .accessibilityHidden(true)
            }
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
    }
}

/// Resolves a ``CatalogDestination`` to its detail view. Reads the catalog's
/// tokens once so both navigation paths render identically.
struct CatalogDestinationView: View {
    let destination: CatalogDestination
    private let tokens = ScreenLibrary.tokens()

    var body: some View {
        switch destination {
        case .example(let example):
            ScreenDetailView(example: example, tokens: tokens)
        case .category(let category):
            CategoryScreensView(category: category, tokens: tokens)
        }
    }
}

extension View {
    /// A navigation link to a ``CatalogDestination``.
    ///
    /// On iOS 16+ this is a value link that appends to the `NavigationStack`
    /// path. On iOS 15 it is a `NavigationLink(destination:)` that pushes the
    /// resolved view directly inside the `NavigationView` — the working legacy
    /// equivalent, since value links require iOS 16.
    @ViewBuilder func catalogLink<Label: View>(
        _ destination: CatalogDestination,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if #available(iOS 16, macOS 13, *) {
            NavigationLink(value: destination, label: label)
        } else {
            NavigationLink(destination: CatalogDestinationView(destination: destination), label: label)
        }
    }
}
#endif

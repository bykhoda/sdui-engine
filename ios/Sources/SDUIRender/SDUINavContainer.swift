#if canImport(SwiftUI)
import SwiftUI

/// A navigation container that uses `NavigationStack` on iOS 16 / macOS 13 and
/// above, and gracefully falls back to `NavigationView` on iOS 15 / macOS 12.
///
/// This is the single place the SDK decides between the modern and legacy
/// navigation containers, so `#available` checks don't leak into every call
/// site. Modern systems get the full `NavigationStack` experience; older
/// systems get a working `NavigationView` (stack style) with the same content.
///
/// Use this for *stackless* roots (no programmatic path). For a value-driven
/// stack, see ``SDUINavPathContainer``.
public struct SDUINavContainer<Content: View>: View {
    @ViewBuilder private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        if #available(iOS 16, macOS 13, tvOS 16, watchOS 9, *) {
            NavigationStack(root: content)
        } else {
            NavigationView(content: content)
            #if os(iOS)
                .navigationViewStyle(.stack)
            #endif
        }
    }
}

/// A value-driven navigation container. On iOS 16+ it is a real
/// `NavigationStack(path:)` with `navigationDestination(for:)`, so the whole
/// path pushes and restores. On iOS 15 there is no `navigationDestination`, so
/// it degrades to a `NavigationView` that shows the **top** route of the path
/// via a programmatic `NavigationLink(isActive:)`.
///
/// Degradation on iOS 15: deep multi-level path restore collapses to a
/// single-level push of the last route. Pushing still works (tap → the top
/// route shows); popping the link clears the path. This keeps navigation
/// functional on iOS 15 without crashing, at the cost of intermediate stack
/// levels not being individually visible.
public struct SDUINavPathContainer<Data: Hashable, Root: View, Destination: View>: View {
    @Binding private var path: [Data]
    @ViewBuilder private let root: () -> Root
    private let destination: (Data) -> Destination

    public init(path: Binding<[Data]>,
                @ViewBuilder root: @escaping () -> Root,
                @ViewBuilder destination: @escaping (Data) -> Destination) {
        self._path = path
        self.root = root
        self.destination = destination
    }

    public var body: some View {
        if #available(iOS 16, macOS 13, tvOS 16, watchOS 9, *) {
            NavigationStack(path: $path) {
                root()
                    .navigationDestination(for: Data.self, destination: destination)
            }
        } else {
            legacyBody
        }
    }

    /// iOS 15 fallback: a NavigationView whose top route is pushed through a
    /// single programmatic link. Popping the link empties the path.
    private var legacyBody: some View {
        let isActive = Binding<Bool>(
            get: { !path.isEmpty },
            set: { active in if !active { path.removeAll() } }
        )
        return NavigationView {
            ZStack {
                root()
                NavigationLink(isActive: isActive) {
                    // Show the deepest route; that's the screen the user just
                    // navigated to. Intermediate levels are skipped on iOS 15.
                    if let top = path.last {
                        destination(top)
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
#endif

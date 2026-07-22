#if canImport(SwiftUI)
import SwiftUI
import SDUICore
import SDUIRender

/// A runnable demo of `SDUIContainerView`: a stack of server-driven screens
/// whose push/sheet transitions are driven entirely by the bundled JSON. The
/// route provider resolves each `navigate` target to a bundled screen by id,
/// standing in for a backend fetch.
public struct SDUINavigationDemoView: View {
    private let tokens: JSONValue
    @StateObject private var host = PlaygroundHost()

    public init(tokens: JSONValue = ScreenLibrary.tokens()) {
        self.tokens = tokens
    }

    public var body: some View {
        SDUIContainerView(
            root: SDUIRoute(screen: "nav_home"),
            tokens: tokens,
            env: ["locale": .string("en")],
            appDelegate: host,
            provider: { route in ScreenLibrary.document(withId: route.screen) })
        .overlay(alignment: .top) {
            if let event = host.lastEvent {
                Text(event)
                    .font(.callout.weight(.bold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        host.lastEvent = nil
                    }
            }
        }
    }
}
#endif

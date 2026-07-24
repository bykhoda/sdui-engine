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

/// The app's home/catalog — now itself a server-driven screen (`home.json`,
/// generated from catalog.json). Rendered by the engine and navigable entirely
/// from JSON, so the SAME chrome renders identically on iOS, Android and Aurora.
public struct SDUIHomeView: View {
    private let tokens: JSONValue
    @StateObject private var host = PlaygroundHost()

    public init(tokens: JSONValue = ScreenLibrary.tokens()) {
        self.tokens = tokens
    }

    public var body: some View {
        SDUIContainerView(
            root: SDUIRoute(screen: "home"),
            tokens: tokens,
            env: ["locale": .string("en"), "platform": .string("ios")],
            appDelegate: host,
            provider: { route in ScreenLibrary.document(withId: route.screen) })
        #if os(iOS)
        // Tapping a home story bubble opens the real segmented, swipeable stories
        // player full-screen (the legitimate immersive case — tab bar hidden).
        .fullScreenCover(isPresented: Binding(
            get: { host.openStoryIndex != nil },
            set: { if !$0 { host.openStoryIndex = nil } })
        ) {
            StoriesPlayer(stories: CapabilityStory.all, start: host.openStoryIndex ?? 0) {
                host.openStoryIndex = nil
            }
        }
        #endif
    }
}
#endif

#if canImport(SwiftUI)
import SwiftUI
import SDUIPlayground

/// Runnable host for the sandbox on macOS: `swift run SDUIPlaygroundApp`.
/// On iOS, embed `SDUIPlaygroundView()` in your own app to use it in the
/// simulator.
struct SDUIPlaygroundApp: App {
    var body: some Scene {
        WindowGroup("SDUI") {
            SDUIDemoRootView()
        }
    }
}

SDUIPlaygroundApp.main()
#endif

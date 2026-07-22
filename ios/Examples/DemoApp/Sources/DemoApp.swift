import SwiftUI
import SDUIPlayground

/// A tiny iOS host so the engine can be run on the simulator (or a device).
/// It embeds the reusable views from the `SDUIPlayground` module:
/// - **Sandbox** — a live JSON editor that renders payloads and can open a
///   `.json` file from the Files app.
/// - **Navigation** — a full server-driven stack (push / sheet) driven by JSON.
@main
struct SDUIDemoApp: App {
    var body: some Scene {
        WindowGroup {
            SDUIDemoRootView()
        }
    }
}

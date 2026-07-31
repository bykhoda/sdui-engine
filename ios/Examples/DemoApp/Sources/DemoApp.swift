import SwiftUI
import UIKit
import SDUIPlayground // re-exports SDUICore (SDUIParser/JSONValue) + SDUIRender (SDUIScreenView)

/// A tiny iOS host so the engine can be run on the simulator (or a device).
/// It embeds the reusable views from the `SDUIPlayground` module:
/// - **Sandbox** — a live JSON editor that renders payloads and can open a
///   `.json` file from the Files app.
/// - **Navigation** — a full server-driven stack (push / sheet) driven by JSON.
///
/// It doubles as the iOS leg of the visual snapshot suite: launched with the env
/// `SDUI_SNAPSHOT=1`, it renders every fixture from the shared manifest to PNG and exits
/// (see `Snapshotter`). Because it is a real foreground app it HAS a render server, so the
/// content actually draws — unlike a headless SPM test bundle.
@main
struct SDUIDemoApp: App {
    private var snapshotMode: Bool { ProcessInfo.processInfo.environment["SDUI_SNAPSHOT"] != nil }

    var body: some Scene {
        WindowGroup {
            if snapshotMode {
                SnapshotRunnerView()
            } else {
                SDUIDemoRootView()
            }
        }
    }
}

// MARK: - Visual snapshot leg (spec/snapshots)

/// Root shown in snapshot mode: kicks off the capture loop, then exits the process.
struct SnapshotRunnerView: View {
    var body: some View {
        Color.black
            .ignoresSafeArea()
            .task { @MainActor in
                await Snapshotter.run()
                exit(0)
            }
    }
}

/// Renders every fixture in spec/snapshots/manifest.json through the REAL SDUIScreenView and
/// writes {fixture}.ios.{scheme}.png into spec/snapshots/__out__ — the iOS analogue of the
/// Android Roborazzi and Aurora `--snapshot` legs. `SDUI_REPO` points at the repo root; the
/// simulator shares the host filesystem, so it reads the shared corpus and writes results there.
enum Snapshotter {
    struct Fixture { let id: String; let url: URL }

    @MainActor
    static func run() async {
        guard let repoPath = ProcessInfo.processInfo.environment["SDUI_REPO"] else {
            NSLog("[SDUI-SNAP] SDUI_REPO not set"); return
        }
        let repo = URL(fileURLWithPath: repoPath)
        let out = repo.appendingPathComponent("spec/snapshots/__out__")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let tokens = loadTokens(repo)
        let fixtures = loadFixtures(repo)
        let size = CGSize(width: 390, height: 844)
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene

        var written = 0
        for scheme in ["light", "dark"] {
            for fx in fixtures {
                guard let text = try? String(contentsOf: fx.url, encoding: .utf8),
                      let doc = try? SDUIParser.decode(text) else { continue }
                let view = SDUIScreenView(
                    document: doc,
                    tokens: tokens,
                    env: ["locale": .string("en"), "theme": .string(scheme), "platform": .string("ios")]
                )
                .frame(width: size.width, height: size.height)

                // A real on-screen window in the foreground app → the content actually renders.
                let host = UIHostingController(rootView: view)
                let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(origin: .zero, size: size))
                window.frame = CGRect(origin: .zero, size: size)
                window.overrideUserInterfaceStyle = scheme == "dark" ? .dark : .light
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.frame = CGRect(origin: .zero, size: size)
                host.view.layoutIfNeeded()

                try? await Task.sleep(nanoseconds: 300_000_000) // let SwiftUI populate + draw

                let format = UIGraphicsImageRendererFormat()
                format.scale = 3
                let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
                }
                if let png = image.pngData() {
                    try? png.write(to: out.appendingPathComponent("\(fx.id).ios.\(scheme).png"))
                    written += 1
                }
                window.isHidden = true
            }
        }
        NSLog("[SDUI-SNAP] wrote \(written) iOS PNG(s) → \(out.path)")
    }

    private static func loadTokens(_ repo: URL) -> JSONValue {
        let url = repo.appendingPathComponent("ios/Sources/SDUIPlayground/Content/tokens.json")
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .object([:]) }
        return value
    }

    private static func loadFixtures(_ repo: URL) -> [Fixture] {
        let manifestURL = repo.appendingPathComponent("spec/snapshots/manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        func entries(_ key: String) -> [[String: Any]] { (root[key] as? [[String: Any]]) ?? [] }
        var out: [Fixture] = []
        for fx in entries("screens") + entries("components") {
            guard let id = fx["id"] as? String, let source = fx["source"] as? String else { continue }
            let url: URL
            if source.hasPrefix("content/screens/") {
                url = repo.appendingPathComponent("ios/Sources/SDUIPlayground/Content/screens/")
                    .appendingPathComponent(String(source.dropFirst("content/screens/".count)))
            } else if source.hasPrefix("snapshots/components/") {
                url = repo.appendingPathComponent("spec/snapshots/")
                    .appendingPathComponent(String(source.dropFirst("snapshots/".count)))
            } else {
                url = repo.appendingPathComponent(source)
            }
            if FileManager.default.fileExists(atPath: url.path) { out.append(Fixture(id: id, url: url)) }
        }
        return out
    }
}

// The iOS leg of the visual snapshot suite (spec/snapshots). Iterates the SAME
// manifest.json every platform iterates, renders each fixture through the REAL
// SDUIScreenView, and writes a PNG per fixture/scheme into spec/snapshots/__out__ named
// {fixture}.ios.{scheme}.png — the counterpart of the Android Roborazzi and Aurora
// Snapshotter legs. Rendering is offscreen via SwiftUI's `ImageRenderer` (no external
// dependency, no host app), so `xcodebuild test` on any iOS 16+ simulator produces the set.
//
// Mechanics (swipe/scrub/…) are captured on Android today; the iOS leg captures the resting
// screens (ImageRenderer has no gesture surface — mechanic seeding is a follow-up).
//
// KNOWN ISSUE — ImageRenderer captures only the screen BACKGROUND, not the content subtree:
// SDUIScreenView's scroll-reactive header/content doesn't resolve in ImageRenderer's single
// synchronous pass, so PNGs come out blank. FIX (next): host the view in a UIWindow via
// UIHostingController, force layout, and snapshot with
// `UIGraphicsImageRenderer.image { _ in view.drawHierarchy(afterScreenUpdates: true) }`,
// which drives a real render pass. The leg wiring/manifest walk below is correct and stays.
//
// Run via spec/snapshots/capture-ios.sh (or `node spec/snapshots/run.mjs --ios`).
import XCTest
import SwiftUI
import SDUICore
@testable import SDUIRender

final class SnapshotTests: XCTestCase {

    @MainActor
    func testCaptureAll() throws {
        guard #available(iOS 16.0, *) else {
            throw XCTSkip("ImageRenderer needs iOS 16 — run on a 16+ simulator.")
        }
        let repo = Self.repoRoot()
        let out = repo.appendingPathComponent("spec/snapshots/__out__")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let tokens = Self.tokens(repo)
        let fixtures = Self.fixtures(repo)
        XCTAssertFalse(fixtures.isEmpty, "no fixtures resolved from manifest.json")

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
                .frame(width: 390, height: 844)
                .environment(\.colorScheme, scheme == "dark" ? .dark : .light)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 3
                guard let image = renderer.uiImage, let png = image.pngData() else { continue }
                let dest = out.appendingPathComponent("\(fx.id).ios.\(scheme).png")
                try? png.write(to: dest)
                written += 1
            }
        }
        print("[SDUI-SNAP] wrote \(written) iOS PNG(s) → \(out.path)")
        XCTAssertGreaterThan(written, 0)
    }

    // MARK: - manifest / corpus resolution (filesystem, shared with the other legs)

    /// Ascend from this source file to the repo root (…/ios/Tests/SDUISnapshotTests/x.swift).
    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SDUISnapshotTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repo
    }

    private static func tokens(_ repo: URL) -> JSONValue {
        let url = repo.appendingPathComponent("ios/Sources/SDUIPlayground/Content/tokens.json")
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .object([:])
        }
        return value
    }

    /// (id, url) for every screen + component card in the manifest, mapped to disk.
    private static func fixtures(_ repo: URL) -> [(id: String, url: URL)] {
        let manifestURL = repo.appendingPathComponent("spec/snapshots/manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        func entries(_ key: String) -> [[String: Any]] { (root[key] as? [[String: Any]]) ?? [] }

        var out: [(String, URL)] = []
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
            if FileManager.default.fileExists(atPath: url.path) { out.append((id, url)) }
        }
        return out
    }
}

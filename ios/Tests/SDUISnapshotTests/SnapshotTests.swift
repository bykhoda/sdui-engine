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
// KNOWN ISSUE — the PNGs render the screen BACKGROUND but not the content subtree. Root
// cause: an SPM test bundle has NO host application, so there is no render server — both
// ImageRenderer AND UIHostingController+`drawHierarchy(afterScreenUpdates:true)` (below)
// come back with the content blank. The leg wiring / manifest walk is correct; what's
// missing is a rendering host. FIX (next, an architectural step not a tweak): give the
// snapshot test a HOST APP (a tiny SwiftUI app target the test drives), or make this an
// XCUITest that launches that host and uses XCUIScreenshot — either provides the render
// server the content needs. Until then the iOS column stays an honest gap in the gallery.
//
// Run via spec/snapshots/capture-ios.sh (or `node spec/snapshots/run.mjs --ios`).
import XCTest
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
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

        // The bitmap capture below needs UIKit. Off iOS (e.g. macOS `swift test`)
        // there is no UIKit, so compile it out — the fixture/manifest resolution
        // above is still exercised, and the capture runs on the iOS simulator leg.
        #if canImport(UIKit)
        let size = CGSize(width: 390, height: 844)
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

                guard let image = Self.snapshot(view, size: size, dark: scheme == "dark"),
                      let png = image.pngData() else { continue }
                let dest = out.appendingPathComponent("\(fx.id).ios.\(scheme).png")
                try? png.write(to: dest)
                written += 1
            }
        }
        print("[SDUI-SNAP] wrote \(written) iOS PNG(s) → \(out.path)")
        XCTAssertGreaterThan(written, 0)
        #endif
    }

    /// Host the SwiftUI view in a real key window and capture with drawHierarchy — unlike
    /// ImageRenderer's single synchronous pass, this drives an actual render/layout cycle so
    /// the whole content subtree (scroll header, cards, charts) draws, not just the background.
    #if canImport(UIKit)
    @MainActor
    private static func snapshot(_ view: some View, size: CGSize, dark: Bool) -> UIImage? {
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        // Let SwiftUI populate its content + resolve layout before capturing.
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        window.isHidden = true
        return image
    }
    #endif

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

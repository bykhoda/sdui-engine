// swift-tools-version: 5.9
import PackageDescription

// Root manifest so the engine installs straight from the repository URL:
//
//     .package(url: "https://github.com/bykhoda/sdui-engine.git", from: "0.1.0")
//
// SwiftPM requires Package.swift at the repository root and does not support a
// sub-path for remote dependencies. The Swift sources live under ios/Sources
// (the repo keeps iOS / Android / Aurora side by side), so every target points
// there via `path:`. The self-contained package used for local iOS development
// lives at ios/Package.swift; keep the two target lists in sync.
let package = Package(
    name: "SDUI",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        // Pure model + binding layer. No UI. Portable, fully unit-tested.
        .library(name: "SDUICore", targets: ["SDUICore"]),
        // Declarative networking driven by the DataSource contract.
        .library(name: "SDUINetwork", targets: ["SDUINetwork"]),
        // Runtime: component/action registries, screen store, interpreter.
        .library(name: "SDUIRuntime", targets: ["SDUIRuntime"]),
        // SwiftUI renderers. Depends on everything above.
        .library(name: "SDUIRender", targets: ["SDUIRender"]),
        // Live sandbox view for assembling screens against the renderer.
        .library(name: "SDUIPlayground", targets: ["SDUIPlayground"])
    ],
    targets: [
        .target(name: "SDUICore", path: "ios/Sources/SDUICore"),
        .target(name: "SDUINetwork", dependencies: ["SDUICore"], path: "ios/Sources/SDUINetwork"),
        .target(name: "SDUIRuntime", dependencies: ["SDUICore", "SDUINetwork"], path: "ios/Sources/SDUIRuntime"),
        .target(name: "SDUIRender", dependencies: ["SDUICore", "SDUIRuntime", "SDUINetwork"], path: "ios/Sources/SDUIRender"),
        .target(
            name: "SDUIPlayground",
            dependencies: ["SDUICore", "SDUIRender", "SDUINetwork"],
            path: "ios/Sources/SDUIPlayground",
            // Folder is named "Content" (not "Resources") on purpose: a folder
            // literally named "Resources" inside the generated .bundle trips a
            // codesign bug (SR-12303 — "bundle format unrecognized") on iOS.
            resources: [.copy("Content")]
        ),
        // Runnable macOS host so `swift run SDUIPlaygroundApp` opens the sandbox.
        .executableTarget(name: "SDUIPlaygroundApp", dependencies: ["SDUIPlayground"], path: "ios/Sources/SDUIPlaygroundApp"),
        .testTarget(name: "SDUICoreTests", dependencies: ["SDUICore"], path: "ios/Tests/SDUICoreTests"),
        .testTarget(name: "SDUIPlaygroundTests", dependencies: ["SDUIPlayground"], path: "ios/Tests/SDUIPlaygroundTests"),
        // Runs the SHARED conformance corpus (spec/conformance/fixtures) through the
        // native engine, proving the Swift BindingEngine/Condition/ActionInterpreter
        // agree with the JS reference (check.mjs) — the "identical everywhere" gate.
        .testTarget(name: "SDUIConformanceTests", dependencies: ["SDUICore", "SDUIRuntime"], path: "ios/Tests/SDUIConformanceTests"),
        // The iOS leg of the visual snapshot suite: renders every fixture in
        // spec/snapshots/manifest.json through SDUIScreenView via ImageRenderer and writes
        // PNGs for the cross-platform gallery. See spec/snapshots/capture-ios.sh.
        .testTarget(name: "SDUISnapshotTests", dependencies: ["SDUIRender", "SDUICore"], path: "ios/Tests/SDUISnapshotTests")
    ]
)

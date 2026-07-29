// swift-tools-version: 5.9
import PackageDescription

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
        .target(name: "SDUICore"),
        .target(name: "SDUINetwork", dependencies: ["SDUICore"]),
        .target(name: "SDUIRuntime", dependencies: ["SDUICore", "SDUINetwork"]),
        .target(name: "SDUIRender", dependencies: ["SDUICore", "SDUIRuntime", "SDUINetwork"]),
        .target(
            name: "SDUIPlayground",
            dependencies: ["SDUICore", "SDUIRender", "SDUINetwork"],
            // Folder is named "Content" (not "Resources") on purpose: a folder
            // literally named "Resources" inside the generated .bundle trips a
            // codesign bug (SR-12303 — "bundle format unrecognized") on iOS.
            resources: [.copy("Content")]
        ),
        // Runnable macOS host so `swift run SDUIPlaygroundApp` opens the sandbox.
        .executableTarget(name: "SDUIPlaygroundApp", dependencies: ["SDUIPlayground"]),
        .testTarget(name: "SDUICoreTests", dependencies: ["SDUICore"]),
        .testTarget(name: "SDUIPlaygroundTests", dependencies: ["SDUIPlayground"]),
        // Runs the SHARED conformance corpus (spec/conformance/fixtures) through the
        // native engine, proving the Swift BindingEngine/Condition/ActionInterpreter
        // agree with the JS reference (check.mjs) — the "identical everywhere" gate.
        .testTarget(name: "SDUIConformanceTests", dependencies: ["SDUICore", "SDUIRuntime"])
    ]
)

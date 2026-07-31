// SDUIPlayground is the umbrella host module — anything embedding it (the DemoApp, the
// SwiftPM app runner) almost always also needs the renderer entry point (SDUIScreenView)
// and the contract types (SDUIParser / JSONValue / SDUIDocument). Re-export them so a
// single `import SDUIPlayground` is enough, rather than forcing every host to link the
// lower layers directly.
@_exported import SDUICore
@_exported import SDUIRender

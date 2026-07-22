import Foundation
import SDUICore

/// A named starter payload shown in the catalog.
public struct PlaygroundExample: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let screenId: String
    public let name: String
    public let subtitle: String
    public let json: String

    public init(screenId: String, name: String, subtitle: String, json: String) {
        self.screenId = screenId
        self.name = name
        self.subtitle = subtitle
        self.json = json
    }
}

/// A group of showcase screens with a gradient identity for its icon tile.
public struct PlaygroundCategory: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let name: String
    public let icon: String
    /// Two (or more) hex stops used for the category's gradient icon tile.
    public let colors: [String]
    public let examples: [PlaygroundExample]

    public init(name: String, icon: String, colors: [String], examples: [PlaygroundExample]) {
        self.name = name
        self.icon = icon
        self.colors = colors
        self.examples = examples
    }

    public static func == (lhs: PlaygroundCategory, rhs: PlaygroundCategory) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Loads the catalog's bundled screens, tokens and manifest from `Content/`.
///
/// Loading is deliberately fault-tolerant: a missing or invalid resource is
/// skipped rather than crashing, so every entry point returns a usable value.
public enum ScreenLibrary {

    // MARK: Public API

    public static func catalog() -> [PlaygroundCategory] { catalog(in: .module) }

    public static func bundledExamples() -> [PlaygroundExample] {
        catalog().flatMap(\.examples)
    }

    public static func tokens() -> JSONValue { tokens(in: .module) }

    public static func document(withId id: String) -> SDUIDocument? {
        documents(in: .module).first { $0.screen.id == id }
    }

    /// Raw JSON for any bundled screen (showcase or nav), by `screen.id`. Used by
    /// the debug snapshot hook so every screen is reachable, not just catalog ones.
    public static func rawJSON(withId id: String) -> String? {
        let bundle = Bundle.module
        for dir in ["Content/screens", "Content/nav"] {
            for url in bundle.urls(forResourcesWithExtension: "json", subdirectory: dir) ?? [] {
                guard let data = try? Data(contentsOf: url),
                      let doc = try? SDUIParser.decode(data), doc.screen.id == id else { continue }
                return String(decoding: data, as: UTF8.self)
            }
        }
        return nil
    }

    // MARK: Loading

    private struct Manifest: Decodable {
        struct ScreenRef: Decodable { let id: String; let subtitle: String? }
        struct Category: Decodable { let name: String; let icon: String; let colors: [String]; let screens: [ScreenRef] }
        let categories: [Category]
    }

    static func catalog(in bundle: Bundle) -> [PlaygroundCategory] {
        let byId = screensById(in: bundle)
        guard
            let url = bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "Content"),
            let data = try? Data(contentsOf: url),
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else {
            let examples = byId
                .map { PlaygroundExample(screenId: $0.key, name: $0.value.name, subtitle: "", json: $0.value.json) }
                .sorted { $0.name < $1.name }
            return examples.isEmpty ? [] : [PlaygroundCategory(name: "Screens", icon: "square.grid.2x2.fill", colors: ["#8E8E93", "#636366"], examples: examples)]
        }
        return manifest.categories.compactMap { category in
            let examples = category.screens.compactMap { ref -> PlaygroundExample? in
                guard let base = byId[ref.id] else { return nil }
                return PlaygroundExample(screenId: ref.id, name: base.name, subtitle: ref.subtitle ?? "", json: base.json)
            }
            return examples.isEmpty ? nil : PlaygroundCategory(name: category.name, icon: category.icon, colors: category.colors, examples: examples)
        }
    }

    /// Maps every screen's `screen.id` to its display name and raw JSON. Invalid
    /// files are skipped with a logged diagnostic.
    private static func screensById(in bundle: Bundle) -> [String: (name: String, json: String)] {
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Content/screens") else { return [:] }
        var result: [String: (name: String, json: String)] = [:]
        for url in urls {
            do {
                let data = try Data(contentsOf: url)
                let document = try SDUIParser.decode(data)
                let name = document.screen.title ?? prettify(document.screen.id)
                result[document.screen.id] = (name, String(decoding: data, as: UTF8.self))
            } catch {
                print("[SDUIPlayground] Skipping \(url.lastPathComponent): \(error)")
            }
        }
        return result
    }

    /// Turns a screen id into a display name when the payload sets no title —
    /// "document" → "Document", "nav_home" → "Nav Home".
    private static func prettify(_ id: String) -> String {
        id.replacingOccurrences(of: "_", with: " ")
          .replacingOccurrences(of: "-", with: " ")
          .split(separator: " ")
          .map { $0.prefix(1).uppercased() + $0.dropFirst() }
          .joined(separator: " ")
    }

    static func tokens(in bundle: Bundle) -> JSONValue {
        guard
            let url = bundle.url(forResource: "tokens", withExtension: "json", subdirectory: "Content"),
            let data = try? Data(contentsOf: url),
            let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            return .object([:])
        }
        return value
    }

    /// All bundled screens (showcase + navigation), used by the route provider.
    static func documents(in bundle: Bundle) -> [SDUIDocument] {
        let screens = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Content/screens") ?? []
        let nav = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Content/nav") ?? []
        return (screens + nav).compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? SDUIParser.decode(data)
        }
    }
}

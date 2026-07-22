import Foundation

/// On-device port of `spec/tools/figma-tokens.mjs`: converts a Figma / W3C
/// design-token export into the SDUI `tokens.json` shape. Paste your Figma
/// variables, get tokens, and every screen re-themes — no build step, no engineer.
///
/// Auto-detects both leaf shapes: W3C (`$value`/`$type`) and Tokens Studio
/// (`value`/`type`), and resolves `{a.b}` aliases.
enum FigmaTokens {
    private struct Leaf { let type: String?; let value: Any }

    /// Returns the pretty-printed tokens.json and the number of tokens converted,
    /// or `nil` if the input isn't a token object.
    static func convert(_ json: String) -> (tokens: String, count: Int)? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var flat: [(String, Leaf)] = []
        flatten(root, prefix: "", out: &flat)
        guard !flat.isEmpty else { return nil }
        let map = flat.reduce(into: [String: Leaf]()) { $0[$1.0] = $1.1 }

        var out: [String: Any] = [:]
        for (path, leaf) in flat {
            insert(&out, path: path.split(separator: ".").map(String.init),
                   value: primitive(leaf.type, leaf.value, map))
        }
        guard let outData = try? JSONSerialization.data(
                withJSONObject: out, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let str = String(data: outData, encoding: .utf8)
        else { return nil }
        return (str, flat.count)
    }

    /// Deep-merges converted tokens over a base object (converted wins), so the
    /// Figma colours/type layer onto the app's button/composite tokens for preview.
    static func merge(base: Any, over overrides: Any) -> Any {
        guard let b = base as? [String: Any], let o = overrides as? [String: Any] else { return overrides }
        var result = b
        for (k, v) in o {
            result[k] = b[k].map { merge(base: $0, over: v) } ?? v
        }
        return result
    }

    // MARK: - Port of the Node script

    private static func flatten(_ node: Any, prefix: String, out: inout [(String, Leaf)]) {
        guard let dict = node as? [String: Any] else { return }
        if let value = dict["$value"] ?? dict["value"] {
            out.append((prefix, Leaf(type: (dict["$type"] ?? dict["type"]) as? String, value: value)))
            return
        }
        for (key, child) in dict where !(key.hasPrefix("$") || key == "type" || key == "description") {
            flatten(child, prefix: prefix.isEmpty ? key : "\(prefix).\(key)", out: &out)
        }
    }

    private static func resolveAlias(_ raw: Any, _ map: [String: Leaf], depth: Int = 0) -> Any {
        guard let s = raw as? String, depth < 16,
              s.hasPrefix("{"), s.hasSuffix("}") else { return raw }
        let key = s.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        return map[key].map { resolveAlias($0.value, map, depth: depth + 1) } ?? raw
    }

    private static func primitive(_ type: String?, _ value: Any, _ map: [String: Leaf]) -> Any {
        let resolved = resolveAlias(value, map)
        switch (type ?? "").lowercased() {
        case "color":
            return (resolved as? String)?.uppercased() ?? resolved
        case "dimension", "spacing", "borderradius", "sizing", "number":
            return number(resolved) ?? resolved
        case "typography":
            let t = resolved as? [String: Any] ?? [:]
            var obj: [String: Any] = ["weight": weight(t["fontWeight"] ?? t["weight"])]
            if let size = number(t["fontSize"] ?? t["size"] ?? 0) { obj["size"] = size }
            return obj
        default:
            return resolved
        }
    }

    private static func number(_ any: Any) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s.filter { "0123456789.-".contains($0) }) }
        return nil
    }

    private static func weight(_ w: Any?) -> String {
        if let n = number(w ?? "") {
            switch n {
            case 700...: return "bold"
            case 600...: return "semibold"
            case 500...: return "medium"
            case ...300: return "light"
            default:     return "regular"
            }
        }
        return (w as? String)?.lowercased() ?? "regular"
    }

    private static func insert(_ obj: inout [String: Any], path: [String], value: Any) {
        guard let first = path.first else { return }
        if path.count == 1 { obj[first] = value; return }
        var child = obj[first] as? [String: Any] ?? [:]
        insert(&child, path: Array(path.dropFirst()), value: value)
        obj[first] = child
    }
}

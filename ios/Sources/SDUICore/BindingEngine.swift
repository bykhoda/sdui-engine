import Foundation

/// The evaluation context a binding expression resolves against.
///
/// Namespaces map to fields here:
/// `$data.<id>.<path>` → `data`, `$token.<group>.<name>` → `tokens`,
/// `$env.<key>` → `env`, `$state.<key>` → `state`, `$item.<path>` → `item`.
public struct BindingContext: Sendable, Equatable {
    public var data: [String: JSONValue]
    public var tokens: JSONValue
    public var env: [String: JSONValue]
    public var state: [String: JSONValue]
    /// Navigation parameters passed to this screen (e.g. `productId`). Bindable
    /// as `$params.<key>` and used to fill `{key}` placeholders in request paths.
    public var params: [String: JSONValue]
    public var item: JSONValue?

    public init(data: [String: JSONValue] = [:],
                tokens: JSONValue = .object([:]),
                env: [String: JSONValue] = [:],
                state: [String: JSONValue] = [:],
                params: [String: JSONValue] = [:],
                item: JSONValue? = nil) {
        self.data = data
        self.tokens = tokens
        self.env = env
        self.state = state
        self.params = params
        self.item = item
    }
}

/// Resolves binding expressions against a `BindingContext`.
///
/// Two shapes are supported:
/// 1. A whole-string binding (`"$data.product.title"`) resolves to a full
///    `JSONValue` — which may be an object or array, not just text.
/// 2. Interpolation (`"Hello, $data.user.name"`) resolves every `$…` token to
///    its string form and splices it into the surrounding literal text.
public enum BindingEngine {

    /// Resolves a bindable string to a concrete `JSONValue`.
    public static func resolve(_ input: String, in ctx: BindingContext) -> JSONValue {
        // Whole-string binding: return the resolved node with its real type.
        if let token = wholeBindingToken(input) {
            return resolveToken(token, in: ctx, depth: 0) ?? .null
        }
        // Interpolated / literal string.
        return .string(interpolate(input, in: ctx))
    }

    /// Convenience: resolve straight to a display string (empty when null).
    public static func resolveString(_ input: String, in ctx: BindingContext) -> String {
        resolve(input, in: ctx).stringValue ?? ""
    }

    /// Fills `{key}` placeholders in a request path, looking up each key in
    /// params, then state, then env. Unmatched placeholders are left untouched
    /// so a missing value is visible rather than silently dropped.
    public static func fillPlaceholders(_ path: String, in ctx: BindingContext) -> String {
        let chars = Array(path)
        var result = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "{", let close = chars[i...].firstIndex(of: "}") {
                let key = String(chars[(i + 1)..<close])
                let value = ctx.params[key] ?? ctx.state[key] ?? ctx.env[key]
                if let value, let string = value.stringValue {
                    result += string
                    i = close + 1
                    continue
                }
            }
            result.append(chars[i])
            i += 1
        }
        return result
    }

    /// Returns the string itself when it is a single `$…` binding end to end,
    /// otherwise `nil` (meaning it is literal text or an interpolation).
    private static func wholeBindingToken(_ s: String) -> String? {
        let chars = Array(s)
        guard let end = scanToken(chars, from: 0), end == chars.count else { return nil }
        return s
    }

    /// Replaces every `$…` token in the string with its resolved string value,
    /// leaving surrounding literal text untouched. A lone `$` stays verbatim.
    private static func interpolate(_ s: String, in ctx: BindingContext) -> String {
        let chars = Array(s)
        var result = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "$", let end = scanToken(chars, from: i) {
                result += resolveToken(String(chars[i..<end]), in: ctx, depth: 0)?.stringValue ?? ""
                i = end
            } else {
                result.append(chars[i])
                i += 1
            }
        }
        return result
    }

    /// Scans one `$identifier(.segment)*` token starting at `start` (which must
    /// point at `$`). Returns the index just past the token, or `nil` when the
    /// characters at `start` are not a valid binding. Grammar mirrors the
    /// contract: `$`, an ASCII letter/underscore, then letters/digits/underscores,
    /// then any number of `.`-separated segments of letters/digits/underscores.
    private static func scanToken(_ chars: [Character], from start: Int) -> Int? {
        guard start < chars.count, chars[start] == "$" else { return nil }
        var i = start + 1
        guard i < chars.count, isIdentifierHead(chars[i]) else { return nil }
        i += 1
        while i < chars.count, isIdentifierBody(chars[i]) { i += 1 }
        while i < chars.count, chars[i] == "." {
            let beforeDot = i
            i += 1
            guard i < chars.count, isIdentifierBody(chars[i]) else { return beforeDot }
            while i < chars.count, isIdentifierBody(chars[i]) { i += 1 }
        }
        return i
    }

    private static func isIdentifierHead(_ c: Character) -> Bool {
        c == "_" || (c.isASCII && c.isLetter)
    }
    private static func isIdentifierBody(_ c: Character) -> Bool {
        c == "_" || (c.isASCII && (c.isLetter || c.isNumber))
    }

    /// Resolves a single `$namespace.path` token. Token refs that themselves
    /// resolve to another binding (e.g. a button style pointing at a color token)
    /// are followed, bounded by `depth` to prevent cycles.
    private static func resolveToken(_ token: String, in ctx: BindingContext, depth: Int) -> JSONValue? {
        guard depth < 8 else { return .string(token) }
        var parts = token.dropFirst().split(separator: ".").map(String.init) // drop '$'
        guard let namespace = parts.first else { return nil }
        parts.removeFirst()

        let resolved: JSONValue?
        switch namespace {
        case "data":
            guard let sourceId = parts.first else { resolved = nil; break }
            resolved = ctx.data[sourceId]?.value(at: Array(parts.dropFirst())) ?? (parts.count == 1 ? ctx.data[sourceId] : nil)
        case "token":
            resolved = ctx.tokens.value(at: parts)
        case "env":
            guard let key = parts.first else { resolved = nil; break }
            resolved = ctx.env[key]?.value(at: Array(parts.dropFirst())) ?? (parts.count == 1 ? ctx.env[key] : nil)
        case "state":
            guard let key = parts.first else { resolved = nil; break }
            resolved = ctx.state[key]?.value(at: Array(parts.dropFirst())) ?? (parts.count == 1 ? ctx.state[key] : nil)
        case "params":
            guard let key = parts.first else { resolved = nil; break }
            resolved = ctx.params[key]?.value(at: Array(parts.dropFirst())) ?? (parts.count == 1 ? ctx.params[key] : nil)
        case "item":
            resolved = ctx.item?.value(at: parts) ?? (parts.isEmpty ? ctx.item : nil)
        default:
            return nil
        }
        // Follow chained token references (e.g. a button style pointing at a color).
        if case .string(let s)? = resolved, wholeBindingToken(s) != nil {
            return resolveToken(s, in: ctx, depth: depth + 1)
        }
        return resolved
    }
}

// MARK: - Condition evaluation

public extension Condition {
    /// Evaluates the condition against a binding context.
    func evaluate(in ctx: BindingContext) -> Bool {
        switch self {
        case .equals(let a, let b):
            return BindingEngine.resolveString(a, in: ctx) == BindingEngine.resolveString(b, in: ctx)
        case .notEquals(let a, let b):
            return BindingEngine.resolveString(a, in: ctx) != BindingEngine.resolveString(b, in: ctx)
        case .exists(let ref):
            let v = BindingEngine.resolve(ref, in: ctx)
            if case .null = v { return false }
            return v.stringValue?.isEmpty == false || v.arrayValue?.isEmpty == false
        case .not(let inner):
            return !inner.evaluate(in: ctx)
        case .and(let list):
            return list.allSatisfy { $0.evaluate(in: ctx) }
        case .or(let list):
            return list.contains { $0.evaluate(in: ctx) }
        }
    }
}

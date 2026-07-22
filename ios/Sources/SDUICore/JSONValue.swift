import Foundation

/// A type-safe representation of any JSON value.
///
/// The SDUI contract is intentionally open at the leaves: request bodies, list
/// item payloads, screen state and `custom.*` component props can hold arbitrary
/// JSON. `JSONValue` lets us carry that through the pipeline without losing type
/// information and without resorting to `Any`, so the whole model stays `Sendable`
/// and `Equatable`.
public enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? container.decode(Double.self) {
            self = .number(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b):   try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a):  try c.encode(a)
        case .null:          try c.encodeNil()
        }
    }
}

// MARK: - Ergonomic access

public extension JSONValue {
    /// Subscript into an object member. Returns `nil` for non-objects or missing keys.
    subscript(_ key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    /// Subscript into an array index. Returns `nil` when out of range or not an array.
    subscript(_ index: Int) -> JSONValue? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s): return ["true", "1", "yes"].contains(s.lowercased())
        default: return nil
        }
    }

    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Round-trips this value into any `Decodable` type. Used to lazily decode
    /// type-specific component props and modifiers without a giant enum.
    func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Navigates a dotted key path, e.g. "product.title" or "items.0.id".
    func value(at path: [String]) -> JSONValue? {
        var current: JSONValue? = self
        for segment in path {
            guard let node = current else { return nil }
            if let index = Int(segment) {
                current = node[index]
            } else {
                current = node[segment]
            }
        }
        return current
    }
}

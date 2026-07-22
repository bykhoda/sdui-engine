import Foundation

/// Entry point for turning raw JSON bytes into a validated `SDUIDocument`.
///
/// This is the *structural* gate: decoding fails loudly with a readable message
/// pointing at the offending key path, so a malformed payload never reaches a
/// renderer. Full contract validation (enum ranges, required-by-type props) is
/// done against `spec/schema/sdui.schema.json` on the backend before shipping;
/// this layer guarantees the client degrades safely rather than crashing.
public enum SDUIParser {

    public struct ParseError: Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    public static func decode(_ data: Data) throws -> SDUIDocument {
        do {
            return try JSONDecoder().decode(SDUIDocument.self, from: data)
        } catch let DecodingError.keyNotFound(key, ctx) {
            throw ParseError(message: "Missing key '\(key.stringValue)' at \(path(ctx)).")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw ParseError(message: "Type mismatch at \(path(ctx)): \(ctx.debugDescription)")
        } catch let DecodingError.valueNotFound(_, ctx) {
            throw ParseError(message: "Null where a value was required at \(path(ctx)).")
        } catch let DecodingError.dataCorrupted(ctx) {
            throw ParseError(message: "Corrupted data at \(path(ctx)): \(ctx.debugDescription)")
        } catch {
            throw ParseError(message: "Failed to decode SDUI document: \(error)")
        }
    }

    public static func decode(_ string: String) throws -> SDUIDocument {
        guard let data = string.data(using: .utf8) else {
            throw ParseError(message: "Payload is not valid UTF-8.")
        }
        return try decode(data)
    }

    private static func path(_ ctx: DecodingError.Context) -> String {
        let p = ctx.codingPath.map(\.stringValue).joined(separator: ".")
        return p.isEmpty ? "<root>" : p
    }
}

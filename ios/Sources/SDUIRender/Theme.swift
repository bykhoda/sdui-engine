#if canImport(SwiftUI)
import SwiftUI
import SDUICore

/// Resolves contract values (`Dimension`, hex colors, typography tokens) into
/// native SwiftUI types, using the shared token table carried by the binding
/// context. All the platform-specific mapping lives here so the renderers stay
/// declarative.
public enum Theme {

    // MARK: Dimensions

    public static func cgFloat(_ dim: SDUICore.Dimension?, ctx: BindingContext, default def: CGFloat = 0) -> CGFloat {
        guard let dim else { return def }
        switch dim {
        case .points(let p): return CGFloat(p)
        case .infinity:      return .infinity
        case .token(let ref):
            return CGFloat(BindingEngine.resolve(ref, in: ctx).doubleValue ?? Double(def))
        }
    }

    // MARK: Colors

    /// Accepts a token ref (`$token.color.primary`), a hex string, or a binding.
    /// When `$env.theme` is `dark`, a `$token.color.*` ref prefers its
    /// `$token.colorDark.*` counterpart if one exists — dark mode is a separate
    /// palette, not an inversion (see docs/design-notes.md).
    public static func color(_ raw: String?, ctx: BindingContext) -> Color? {
        guard let raw, !raw.isEmpty else { return nil }
        return hexColor(resolveThemed(raw, ctx: ctx))
    }

    private static func resolveThemed(_ raw: String, ctx: BindingContext) -> String {
        if ctx.env["theme"]?.stringValue == "dark", raw.hasPrefix("$token.color.") {
            let darkRef = raw.replacingOccurrences(of: "$token.color.", with: "$token.colorDark.")
            let darkValue = BindingEngine.resolveString(darkRef, in: ctx)
            if !darkValue.isEmpty { return darkValue }
        }
        return BindingEngine.resolveString(raw, in: ctx)
    }

    static func hexColor(_ hex: String) -> Color? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        guard let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        case 8:
            r = Double((value & 0xFF000000) >> 24) / 255
            g = Double((value & 0x00FF0000) >> 16) / 255
            b = Double((value & 0x0000FF00) >> 8) / 255
            a = Double(value & 0x000000FF) / 255
        default:
            return nil
        }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    // MARK: Typography

    /// Resolves a `$token.typography.*` ref into a SwiftUI `Font`.
    public static func font(_ styleRef: String?, ctx: BindingContext) -> Font? {
        guard let styleRef else { return nil }
        let node = BindingEngine.resolve(styleRef, in: ctx)
        guard let size = node["size"]?.doubleValue else { return nil }
        let weight = fontWeight(node["weight"]?.stringValue)
        return .system(size: size, weight: weight)
    }

    private static func fontWeight(_ name: String?) -> Font.Weight {
        switch name {
        case "bold": return .bold
        case "semibold": return .semibold
        case "medium": return .medium
        case "light": return .light
        default: return .regular
        }
    }
}
#endif

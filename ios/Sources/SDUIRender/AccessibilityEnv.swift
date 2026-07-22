#if canImport(SwiftUI)
import SwiftUI
import SDUICore

/// Read-only accessibility state surfaced into the contract as `$env.a11y.*`, so a
/// server-authored payload can branch on the user's OS accessibility settings —
/// `visibleWhen`, `condition`, or letting a `pulse` / `animation` no-op — without
/// any iOS API leaking into the JSON. This is the view-layer half of the design in
/// `docs/native-capabilities-ios.md` §2: the engine reads the platform signals and
/// mirrors them into `$env`; the contract reacts with primitives it already has.
///
/// Exposed keys (all under the `a11y` object):
/// ```
/// $env.a11y.voiceOver     // bool — VoiceOver is running
/// $env.a11y.reduceMotion  // bool — Reduce Motion is enabled
/// $env.a11y.boldText      // bool — Bold Text is enabled
/// $env.a11y.dynamicType   // string — the Dynamic Type size, e.g. "large",
///                         //          "xxxLarge", "accessibilityExtraLarge"
/// $env.a11y.contentSize   // string — alias of dynamicType (design-doc name)
/// ```
public enum SDUIA11yEnv {

    /// The env key the accessibility object is written under (`$env.a11y.*`).
    public static let key = "a11y"

    /// Builds the `a11y` env object from a resolved snapshot. Kept pure (no UIKit
    /// reads) so it is testable and callable from any actor; the live values are
    /// gathered by `SDUIAccessibilityScreen` / `sduiAccessibilityEnv`.
    public static func object(voiceOver: Bool,
                              reduceMotion: Bool,
                              boldText: Bool,
                              dynamicType: String) -> JSONValue {
        .object([
            "voiceOver": .bool(voiceOver),
            "reduceMotion": .bool(reduceMotion),
            "boldText": .bool(boldText),
            "dynamicType": .string(dynamicType),
            // `contentSize` mirrors the name used in the design doc; `dynamicType`
            // is the shorter everyday alias. Both point at the same value so a
            // contract can use either.
            "contentSize": .string(dynamicType)
        ])
    }

    /// Merges the `a11y` object into a copy of `env` under `SDUIA11yEnv.key`,
    /// leaving every other entry untouched. Host code that assembles `env`
    /// manually can call this to add accessibility state to any dictionary.
    public static func merged(into env: [String: JSONValue],
                              voiceOver: Bool,
                              reduceMotion: Bool,
                              boldText: Bool,
                              dynamicType: String) -> [String: JSONValue] {
        var copy = env
        copy[key] = object(voiceOver: voiceOver,
                           reduceMotion: reduceMotion,
                           boldText: boldText,
                           dynamicType: dynamicType)
        return copy
    }
}

// MARK: - Dynamic Type naming

extension DynamicTypeSize {
    /// A stable, platform-neutral name for a Dynamic Type size, matching the values
    /// documented for `$env.a11y.dynamicType`. Independent of the OS enum's raw
    /// value so a contract can compare against a known string.
    var sduiName: String {
        switch self {
        case .xSmall: return "xSmall"
        case .small: return "small"
        case .medium: return "medium"
        case .large: return "large"
        case .xLarge: return "xLarge"
        case .xxLarge: return "xxLarge"
        case .xxxLarge: return "xxxLarge"
        case .accessibility1: return "accessibilityMedium"
        case .accessibility2: return "accessibilityLarge"
        case .accessibility3: return "accessibilityExtraLarge"
        case .accessibility4: return "accessibilityExtraExtraLarge"
        case .accessibility5: return "accessibilityExtraExtraExtraLarge"
        @unknown default: return "large"
        }
    }
}

// MARK: - Live env injection (host-facing)

/// Wraps content and keeps the accessibility `$env.a11y.*` snapshot live: it reads
/// the current VoiceOver / Reduce Motion / Bold Text / Dynamic Type values from the
/// SwiftUI environment (which SwiftUI re-invalidates when the user changes any of
/// them, including at runtime) and hands the merged `env` to a builder closure.
///
/// Because the accessibility values live in `@Environment`, the body re-runs
/// automatically on any change — no manual `UIAccessibility.*DidChangeNotification`
/// observers needed — so a contract that hides an animation behind
/// `$env.a11y.reduceMotion` updates the instant the setting flips.
///
/// Typical host use — build an `SDUIScreenView` with accessibility state injected:
/// ```swift
/// SDUIAccessibilityScreen(env: baseEnv) { env in
///     SDUIScreenView(document: doc, tokens: tokens, env: env, ...)
/// }
/// ```
public struct SDUIAccessibilityScreen<Content: View>: View {
    private let baseEnv: [String: JSONValue]
    private let content: ([String: JSONValue]) -> Content

    /// - Parameters:
    ///   - env: the host's base env (theme, locale, platform, …). The `a11y`
    ///     object is merged on top; any existing `a11y` key is replaced.
    ///   - content: a builder handed the env with live accessibility state merged.
    public init(env: [String: JSONValue] = [:],
                @ViewBuilder content: @escaping ([String: JSONValue]) -> Content) {
        self.baseEnv = env
        self.content = content
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // SwiftUI surfaces Bold Text as a heavier `legibilityWeight` rather than a
    // dedicated bool env key, so `.bold` here means the OS Bold Text setting is on.
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public var body: some View {
        content(SDUIA11yEnv.merged(into: baseEnv,
                                   voiceOver: Self.voiceOverRunning,
                                   reduceMotion: reduceMotion,
                                   boldText: legibilityWeight == .bold,
                                   dynamicType: dynamicTypeSize.sduiName))
    }

    /// VoiceOver has no SwiftUI `@Environment` key, so read it from UIAccessibility
    /// (iOS 15+). Off-iOS it is always `false`.
    private static var voiceOverRunning: Bool {
        #if os(iOS)
        return UIAccessibility.isVoiceOverRunning
        #else
        return false
        #endif
    }
}

public extension View {
    /// Convenience wrapper for the common case where the *whole* subtree should see
    /// live accessibility env. Reads the current accessibility state and re-provides
    /// `env` to `build`, then renders it in place. Equivalent to using
    /// `SDUIAccessibilityScreen` directly.
    @ViewBuilder
    func sduiAccessibilityEnv<V: View>(base env: [String: JSONValue] = [:],
                                       @ViewBuilder build: @escaping ([String: JSONValue]) -> V) -> some View {
        SDUIAccessibilityScreen(env: env, content: build)
    }
}
#endif

import Foundation

/// Top-level payload: `{ "version": "0.1", "screen": { ... } }`.
public struct SDUIDocument: Decodable, Equatable, Sendable {
    public let version: String
    public let screen: Screen
}

public struct Screen: Decodable, Equatable, Sendable {
    public let id: String
    public let title: String?
    public let analytics: AnalyticsTag?
    public let data: DataConfig?
    public let state: [String: JSONValue]?
    public let onAppear: Action?
    public let onDisappear: Action?
    public let refresh: RefreshConfig?
    public let content: Component
    /// How the host frames the screen. `"immersive"` = edge-to-edge, no nav bar,
    /// fixed theme (the screen draws its own background and chrome). Absent /
    /// `"standard"` = a normal navigation-bar screen.
    public let chrome: String?
    /// An optional interactive-teaching prompt: a one-line "try this" task that
    /// onboards a newcomer by having them cause a real, immediate change.
    public let teach: Teach?
    /// Scroll-reactive chrome for the whole screen: a large title that shrinks and
    /// pins as you scroll, cross-fading into the nav bar, plus optional pull-to-
    /// reveal search. An engine primitive — set it once per screen and every scroll
    /// gets Apple-grade behaviour; the header is derived from `title`, not hand-
    /// authored per screen. Absent = a plain screen (fully backwards compatible).
    public let scrollBehavior: ScrollBehavior?

    public struct RefreshConfig: Decodable, Equatable, Sendable {
        public let sources: [String]?
    }

    public struct Teach: Decodable, Equatable, Sendable {
        /// What this screen demonstrates, in a few words.
        public let title: String
        /// A concrete micro-task the user can do right now for an instant result.
        public let task: String
    }
}

/// Declarative scroll-reactive header behaviour. All fields optional so the
/// defaults give the expected large-title collapse with nothing configured.
public struct ScrollBehavior: Decodable, Equatable, Sendable {
    /// Show a large title (from the screen's `title`) that collapses on scroll.
    /// Default `true`. Set `false` for a plain inline title with just the extras.
    public let largeTitle: Bool?
    /// An optional one-line subtitle under the large title (bindable).
    public let subtitle: String?
    /// How small the title shrinks before it hands off to the nav bar, as a
    /// fraction of full size. Default `0.58`.
    public let minScale: Double?
    /// Scroll distance (pt) over which the collapse completes. Default: derived
    /// from the header's own height, so it feels natural at any title length.
    public let range: Double?
    /// Keep a pinned, frosted compact title after collapse and cross-fade it into
    /// the nav bar. Default `true`.
    public let pinTitle: Bool?
    /// Telegram-style search that hides above the title and is revealed by pulling
    /// down at the top; absent = no search.
    public let revealOnPull: RevealOnPull?

    public struct RevealOnPull: Decodable, Equatable, Sendable {
        /// Placeholder text for the search field.
        public let placeholder: String?
        /// A `$state.*` key the query is written to, so content can filter live.
        public let bind: String?
        /// Pull distance (pt) past the top that keeps the field open. Default `52`.
        public let threshold: Double?
    }
}

/// A node in the view tree.
///
/// Common fields (`type`, `id`, `modifiers`, `visibleWhen`) are decoded eagerly;
/// everything else stays in `raw` so renderers — including host-registered
/// `custom.*` components — can read type-specific props on demand. This keeps the
/// model open for extension without a closed enum of every component kind.
public struct Component: Decodable, Equatable, Sendable {
    public let type: String
    public let id: String?
    public let modifiers: Modifiers?
    public let visibleWhen: Condition?
    /// The entire node as decoded JSON, for type-specific property access.
    public let raw: JSONValue

    public init(from decoder: Decoder) throws {
        self.raw = try JSONValue(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decode(String.self, forKey: .type)
        self.id = try c.decodeIfPresent(String.self, forKey: .id)
        self.modifiers = try c.decodeIfPresent(Modifiers.self, forKey: .modifiers)
        self.visibleWhen = try c.decodeIfPresent(Condition.self, forKey: .visibleWhen)
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, modifiers, visibleWhen
    }

    /// Reads a type-specific property, e.g. `prop("value")` on a text node.
    public func prop(_ key: String) -> JSONValue? { raw[key] }

    /// Decodes the child list found under `children`.
    public var children: [Component] {
        raw["children"]?.decode([Component].self) ?? []
    }

    /// The bare `$state` key behind a `bind` prop, tolerating both `"day"` and
    /// `"$state.day"`. Android already strips the `$state.` prefix, so normalising here
    /// keeps an authored `bind` identical across platforms (parity #34).
    public var bindKey: String {
        let raw = prop("bind")?.stringValue ?? ""
        return raw.hasPrefix("$state.") ? String(raw.dropFirst(7)) : raw
    }
}

// MARK: - Modifiers

public struct Modifiers: Decodable, Equatable, Sendable {
    public let padding: EdgeInsets?
    public let background: String?
    /// A translucent material behind the node. One of the enumerated system
    /// materials — `"ultraThin" | "thin" | "regular" | "thick" | "bar"` — which map
    /// straight onto the platform's system blur materials, or `"glass"` (the
    /// engine's bespoke frosted, visionOS-style pane with a top-lit rim). Renders
    /// natively on every platform, so one payload keeps the same spatial look on
    /// iOS, Android and Aurora. Absent = no material.
    public let material: String?
    /// A raw Gaussian blur radius in points applied to the node itself (distinct
    /// from `material`, which frosts what is *behind* the node). Use for e.g. a
    /// blurred hero image behind a sheet. Absent / `0` = no blur.
    public let blur: Double?
    public let cornerRadius: Dimension?
    public let opacity: Double?
    public let frame: Frame?
    public let size: SizeSpec?
    public let shadow: Shadow?
    /// Uniform scale multiplier. A number (`0.85`) or a binding (`"$state.artScale"`)
    /// — combine with `animation` for a spring scale on state change.
    public let scale: JSONValue?
    /// Rotation in degrees — a constant or a `$state` binding (pairs with
    /// `animation` for a spinning / flipping element).
    public let rotation: JSONValue?
    /// A rhythmic auto-reversing scale "heartbeat" — a bool `$state` key (pulses
    /// while true) or an object `{ "while": "$state.playing", "scale": 1.04,
    /// "interval": 0.5 }`. Perfect for album art beating to music or a live dot.
    public let pulse: JSONValue?
    /// Make the element interactively pinch-to-zoom, two-finger-rotate and drag,
    /// double-tap to reset — a photo-viewer gesture from one flag.
    public let zoomable: Bool?
    /// Present this subtree as a modal when the given bool `$state` key is true —
    /// it shares the screen's state, so a filter sheet drives the same list. Set
    /// `presentStyle` to "fullScreen" (default) or "sheet".
    public let presentWhen: String?
    public let presentStyle: String?
    /// When true, this node extends under the safe area (edge-to-edge). Use on an
    /// immersive background so a gradient/image fills to the screen edges.
    public let ignoresSafeArea: Bool?
    public let onTap: Action?
    public let onDoubleTap: Action?
    public let onLongPress: Action?
    public let contextMenu: [ContextMenuItem]?
    /// Extra invisible tap padding so small controls stay comfortably tappable.
    public let hitSlop: Double?
    public let swipe: SwipeConfig?
    public let animation: AnimationSpec?
    public let accessibility: AccessibilitySpec?

    /// Swipe-to-reveal actions on a row/card. Leading actions reveal on a
    /// left-to-right swipe, trailing on a right-to-left swipe.
    public struct SwipeConfig: Decodable, Equatable, Sendable {
        public let leading: [SwipeAction]?
        public let trailing: [SwipeAction]?
        /// "native" (default): system `.swipeActions` — only inside a `List`.
        /// "custom": a drag-revealed, fully stylable Telegram-style swipe that
        /// works on ANY row/card, so a payload can pick per surface.
        public let style: String?
        /// Custom-style only: a long drag past the trigger threshold expands the
        /// edge-most action and fires it on release (Mail/Telegram full-swipe).
        /// Defaults to true; set false to require an explicit button tap.
        public let fullSwipe: Bool?
        /// Custom-style only: width reserved per action button (default 74).
        public let actionWidth: Double?

        public struct SwipeAction: Decodable, Equatable, Sendable {
            public let title: String?
            public let icon: String?
            public let role: String?      // "destructive" | "default"
            public let tint: String?      // token/hex; defaults by role
            public let action: Action
        }
    }

    public struct Frame: Decodable, Equatable, Sendable {
        public let width: Dimension?
        public let height: Dimension?
        public let maxWidth: Dimension?
    }

    /// Explicit, platform-neutral sizing. Every renderer maps the same modes so
    /// a payload lays out identically on SwiftUI and Compose instead of relying
    /// on each platform's defaults — the single most important cross-platform
    /// rule (see docs/design-notes.md).
    public struct SizeSpec: Decodable, Equatable, Sendable {
        public let width: Axis?
        public let height: Axis?

        public struct Axis: Decodable, Equatable, Sendable {
            /// `fixed` = exact points; `hug` = size to content; `fill` = take all
            /// available space; `weight` = share available space proportionally.
            public enum Mode: String, Decodable, Sendable { case fixed, hug, fill, weight }
            public let mode: Mode
            public let value: Double?
            public let min: Double?
            public let max: Double?
        }
    }

    /// Accessibility metadata. Required to be explicit because a control read as
    /// a button by VoiceOver is not automatically labelled for TalkBack.
    public struct AccessibilitySpec: Decodable, Equatable, Sendable {
        public let label: String?
        public let value: String?
        public let hint: String?
        /// `button` / `image` / `header` / `link` / `none`.
        public let role: String?
        public let hidden: Bool?
    }
    public struct Shadow: Decodable, Equatable, Sendable {
        public let color: String?
        public let radius: Dimension?
        public let x: Double?
        public let y: Double?
    }
    public struct ContextMenuItem: Decodable, Equatable, Sendable {
        public let title: String
        public let icon: String?
        public let role: String?
        public let action: Action
    }
    public struct AnimationSpec: Decodable, Equatable, Sendable {
        public let curve: String?
        public let duration: Double?
    }
}

/// A length that is either a raw point value or a token reference string.
public enum Dimension: Decodable, Equatable, Sendable {
    case points(Double)
    case token(String)      // e.g. "$token.spacing.md"
    case infinity

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) {
            self = .points(d)
        } else {
            let s = try c.decode(String.self)
            self = (s == "infinity") ? .infinity : .token(s)
        }
    }
}

/// Padding: a single value for all edges or per-edge values.
public enum EdgeInsets: Decodable, Equatable, Sendable {
    case all(Dimension)
    case specific(top: Dimension?, leading: Dimension?, bottom: Dimension?, trailing: Dimension?, horizontal: Dimension?, vertical: Dimension?)

    public init(from decoder: Decoder) throws {
        if let dim = try? Dimension(from: decoder) {
            self = .all(dim)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self = .specific(
            top: try c.decodeIfPresent(Dimension.self, forKey: .top),
            leading: try c.decodeIfPresent(Dimension.self, forKey: .leading),
            bottom: try c.decodeIfPresent(Dimension.self, forKey: .bottom),
            trailing: try c.decodeIfPresent(Dimension.self, forKey: .trailing),
            horizontal: try c.decodeIfPresent(Dimension.self, forKey: .horizontal),
            vertical: try c.decodeIfPresent(Dimension.self, forKey: .vertical))
    }
    private enum CodingKeys: String, CodingKey {
        case top, leading, bottom, trailing, horizontal, vertical
    }
}

// MARK: - Data / Network contract

public struct DataConfig: Decodable, Equatable, Sendable {
    public enum Mode: String, Decodable, Sendable { case parallel, sequential }
    public let mode: Mode?
    public let sources: [DataSource]

    public init(mode: Mode?, sources: [DataSource]) {
        self.mode = mode
        self.sources = sources
    }
}

public struct DataSource: Decodable, Equatable, Sendable {
    public enum Method: String, Decodable, Sendable { case GET, POST, PUT, PATCH, DELETE }
    public enum Policy: String, Decodable, Sendable { case networkOnly, cacheFirst, cacheThenNetwork }

    public let id: String
    public let service: String
    public let path: String
    public let method: Method?
    public let query: [String: String]?
    public let body: JSONValue?
    public let headers: [String: String]?
    public let dependsOn: [String]?
    public let policy: Policy?
}

// MARK: - Actions

/// A declarative action. Kept open like `Component`: the `action` kind and any
/// analytics tag are eager, and kind-specific fields live in `raw`.
public struct Action: Decodable, Equatable, Sendable {
    public let action: String
    public let analytics: AnalyticsTag?
    public let raw: JSONValue

    public init(from decoder: Decoder) throws {
        self.raw = try JSONValue(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.action = try c.decode(String.self, forKey: .action)
        self.analytics = try c.decodeIfPresent(AnalyticsTag.self, forKey: .analytics)
    }
    private enum CodingKeys: String, CodingKey { case action, analytics }

    public func field(_ key: String) -> JSONValue? { raw[key] }

    /// Child actions for `sequence` / `parallel`.
    public var actions: [Action] { raw["actions"]?.decode([Action].self) ?? [] }
}

public struct AnalyticsTag: Decodable, Equatable, Sendable {
    public let event: String?
    public let screenName: String?
    public let params: [String: String]?
}

// MARK: - Conditions

public indirect enum Condition: Decodable, Equatable, Sendable {
    case equals(String, String)
    case notEquals(String, String)
    case exists(String)
    case not(Condition)
    case and([Condition])
    case or([Condition])

    private enum CodingKeys: String, CodingKey {
        case equals, notEquals, exists, not, and, or
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let pair = try c.decodeIfPresent([String].self, forKey: .equals), pair.count == 2 {
            self = .equals(pair[0], pair[1])
        } else if let pair = try c.decodeIfPresent([String].self, forKey: .notEquals), pair.count == 2 {
            self = .notEquals(pair[0], pair[1])
        } else if let s = try c.decodeIfPresent(String.self, forKey: .exists) {
            self = .exists(s)
        } else if let inner = try c.decodeIfPresent(Condition.self, forKey: .not) {
            self = .not(inner)
        } else if let list = try c.decodeIfPresent([Condition].self, forKey: .and) {
            self = .and(list)
        } else if let list = try c.decodeIfPresent([Condition].self, forKey: .or) {
            self = .or(list)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .exists, in: c,
                debugDescription: "Condition must have exactly one operator")
        }
    }
}

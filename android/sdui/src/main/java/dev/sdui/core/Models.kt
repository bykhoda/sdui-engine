package dev.sdui.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Top-level payload: `{ "version": "0.1", "screen": { ... } }`.
 *
 * The Kotlin models mirror the iOS `SDUICore` types one-to-one so the two SDKs
 * read as siblings and both decode the exact same JSON produced from
 * `spec/schema/sdui.schema.json`.
 */
@Serializable
data class SduiDocument(
    /** Contract version this payload targets, e.g. `"0.1"`. */
    val version: String,
    /** The single screen this document describes. */
    val screen: Screen,
)

/** A full screen: its data dependencies, its content tree and lifecycle hooks. */
@Serializable
data class Screen(
    /** Stable screen id, used for navigation targets, deep links and analytics. */
    val id: String,
    /** Navigation-bar title; may itself be a binding such as `$data.product.title`. */
    val title: String? = null,
    /** Optional screen-level analytics tag. */
    val analytics: AnalyticsTag? = null,
    /** Declarative networking config; sources are exposed under `$data.<id>`. */
    val data: DataConfig? = null,
    /** Client-only initial state, referenced as `$state.<key>`. */
    val state: Map<String, JsonValue>? = null,
    /** Action run once the screen becomes visible. */
    val onAppear: Action? = null,
    /** Action run when the screen disappears. */
    val onDisappear: Action? = null,
    /** Pull-to-refresh behaviour. */
    val refresh: RefreshConfig? = null,
    /** How the host frames the screen: `"immersive"` = edge-to-edge, no app bar. */
    val chrome: String? = null,
    /** The single root component of the view tree. */
    val content: Component,
) {
    /** Names the data sources a pull-to-refresh gesture reloads (empty = all). */
    @Serializable
    data class RefreshConfig(val sources: List<String>? = null)
}

/**
 * A node in the view tree.
 *
 * Common fields (`type`, `id`, `modifiers`, `visibleWhen`) are decoded eagerly;
 * everything else stays in [raw] so renderers — including host-registered
 * `custom.*` components — can read type-specific props on demand. This keeps the
 * model open for extension without a closed enum of every component kind, exactly
 * as the Swift `Component` does with its `raw: JSONValue`.
 */
@Serializable(with = ComponentSerializer::class)
data class Component(
    /** Discriminator, e.g. `vstack`, `text`, `image`, `custom.map`. */
    val type: String,
    /** Optional stable id; required for scroll-to targets and diffed list items. */
    val id: String? = null,
    /** Platform-neutral visual modifiers applied to this node. */
    val modifiers: Modifiers? = null,
    /** When present and false, the node and its subtree are not rendered. */
    val visibleWhen: Condition? = null,
    /** The entire node as decoded JSON, for type-specific property access. */
    val raw: JsonValue,
) {
    /** Reads a type-specific property, e.g. `prop("value")` on a text node. */
    fun prop(key: String): JsonValue? = raw[key]

    /** The child list found under `children`, or empty when absent. */
    val children: List<Component>
        get() = raw["children"]?.decode<List<Component>>() ?: emptyList()
}

/**
 * Custom deserializer for [Component]. It first captures the whole node as a
 * [JsonValue] (so nothing is lost), then pulls the eager common fields out of the
 * same object. This is the Kotlin translation of the Swift `init(from:)` that
 * assigns `raw` before reading the keyed container.
 */
object ComponentSerializer : KSerializer<Component> {
    override val descriptor: SerialDescriptor =
        buildClassSerialDescriptor("dev.sdui.core.Component")

    override fun deserialize(decoder: Decoder): Component {
        val input = decoder as? JsonDecoder
            ?: throw IllegalStateException("Component can only be read from JSON.")
        val element = input.decodeJsonElement()
        val obj = element as? JsonObject
            ?: throw IllegalStateException("Component must be a JSON object.")
        val raw = JsonValue.fromJsonElement(element)
        return Component(
            type = obj["type"]?.jsonPrimitive?.content
                ?: throw IllegalStateException("Component is missing required 'type'."),
            id = raw["id"]?.stringValue,
            modifiers = raw["modifiers"]?.decode<Modifiers>(),
            visibleWhen = raw["visibleWhen"]?.decode<Condition>(),
            raw = raw,
        )
    }

    override fun serialize(encoder: Encoder, value: Component) {
        JsonValueSerializer.serialize(encoder, value.raw)
    }
}

// MARK: - Modifiers

/** Platform-neutral visual modifiers applied to any component. */
@Serializable
data class Modifiers(
    /** Inner padding: one value for all edges or per-edge values. */
    val padding: EdgeInsets? = null,
    /** Background colour token/hex ref. */
    val background: String? = null,
    /** Translucent material behind the node: `"glass"` / `"regular"`. */
    val material: String? = null,
    /** Corner radius applied to the background and clip. */
    val cornerRadius: Dimension? = null,
    /** Opacity in the range `0..1`. */
    val opacity: Double? = null,
    /** Fixed / max size constraints. */
    val frame: Frame? = null,
    /** Drop shadow spec. */
    val shadow: Shadow? = null,
    /** Uniform scale — a number or a `$state` binding; pair with `animation`. */
    val scale: JsonValue? = null,
    /** Extend under the safe area (edge-to-edge). Host-level on Android. */
    val ignoresSafeArea: Boolean? = null,
    /** Tap gesture over the whole component. */
    val onTap: Action? = null,
    /** Long-press gesture; commonly opens a context menu. */
    val onLongPress: Action? = null,
    /** Menu items shown on long-press. */
    val contextMenu: List<ContextMenuItem>? = null,
    /** Animation applied when this node's inputs change. */
    val animation: AnimationSpec? = null,
) {
    /** Fixed width/height plus an optional `maxWidth` ("infinity" fills the axis). */
    @Serializable
    data class Frame(
        val width: Dimension? = null,
        val height: Dimension? = null,
        val maxWidth: Dimension? = null,
    )

    /** Drop-shadow descriptor. */
    @Serializable
    data class Shadow(
        val color: String? = null,
        val radius: Dimension? = null,
        val x: Double? = null,
        val y: Double? = null,
    )

    /** One entry in a long-press context menu. */
    @Serializable
    data class ContextMenuItem(
        val title: String,
        val icon: String? = null,
        val role: String? = null,
        val action: Action,
    )

    /** Animation curve + duration for input-driven transitions. */
    @Serializable
    data class AnimationSpec(
        val curve: String? = null,
        val duration: Double? = null,
    )
}

/**
 * A length that is either a raw point value or a token reference string.
 * Mirrors the Swift `Dimension` enum; `"infinity"` is called out so frames can
 * request "fill the axis".
 */
@Serializable(with = DimensionSerializer::class)
sealed class Dimension {
    /** A concrete length in density-independent points. */
    data class Points(val value: Double) : Dimension()

    /** A token reference such as `$token.spacing.md`, resolved at render time. */
    data class Token(val ref: String) : Dimension()

    /** The sentinel `"infinity"`, used by `frame.maxWidth`. */
    data object Infinity : Dimension()
}

/** Decodes a [Dimension] from either a JSON number or a token/`"infinity"` string. */
object DimensionSerializer : KSerializer<Dimension> {
    override val descriptor: SerialDescriptor =
        buildClassSerialDescriptor("dev.sdui.core.Dimension")

    override fun deserialize(decoder: Decoder): Dimension {
        val input = decoder as? JsonDecoder
            ?: throw IllegalStateException("Dimension can only be read from JSON.")
        val primitive = input.decodeJsonElement().jsonPrimitive
        primitive.doubleOrNull?.let { return Dimension.Points(it) }
        val s = primitive.content
        return if (s == "infinity") Dimension.Infinity else Dimension.Token(s)
    }

    override fun serialize(encoder: Encoder, value: Dimension) {
        when (value) {
            is Dimension.Points -> encoder.encodeDouble(value.value)
            is Dimension.Token -> encoder.encodeString(value.ref)
            Dimension.Infinity -> encoder.encodeString("infinity")
        }
    }
}

/**
 * Padding: a single value applied to all edges, or explicit per-edge values.
 * Mirrors the Swift `EdgeInsets` enum.
 */
@Serializable(with = EdgeInsetsSerializer::class)
sealed class EdgeInsets {
    /** The same length on every edge. */
    data class All(val value: Dimension) : EdgeInsets()

    /**
     * Per-edge lengths. `horizontal`/`vertical` act as fallbacks for the
     * corresponding pair when the specific edge is absent.
     */
    data class Specific(
        val top: Dimension? = null,
        val leading: Dimension? = null,
        val bottom: Dimension? = null,
        val trailing: Dimension? = null,
        val horizontal: Dimension? = null,
        val vertical: Dimension? = null,
    ) : EdgeInsets()
}

/** Decodes [EdgeInsets] from either a bare [Dimension] or a per-edge object. */
object EdgeInsetsSerializer : KSerializer<EdgeInsets> {
    override val descriptor: SerialDescriptor =
        buildClassSerialDescriptor("dev.sdui.core.EdgeInsets")

    override fun deserialize(decoder: Decoder): EdgeInsets {
        val input = decoder as? JsonDecoder
            ?: throw IllegalStateException("EdgeInsets can only be read from JSON.")
        val value = JsonValue.fromJsonElement(input.decodeJsonElement())
        // A single number or token string means "all edges".
        val asDimension = value.toJsonElement().let {
            runCatching { JsonValue.CODEC.decodeFromJsonElement(DimensionSerializer, it) }.getOrNull()
        }
        if (value !is JsonValue.Obj && asDimension != null) {
            return EdgeInsets.All(asDimension)
        }
        return EdgeInsets.Specific(
            top = value["top"]?.decodeDimension(),
            leading = value["leading"]?.decodeDimension(),
            bottom = value["bottom"]?.decodeDimension(),
            trailing = value["trailing"]?.decodeDimension(),
            horizontal = value["horizontal"]?.decodeDimension(),
            vertical = value["vertical"]?.decodeDimension(),
        )
    }

    override fun serialize(encoder: Encoder, value: EdgeInsets) {
        throw UnsupportedOperationException("EdgeInsets is decode-only in this renderer.")
    }

    private fun JsonValue.decodeDimension(): Dimension? =
        runCatching { JsonValue.CODEC.decodeFromJsonElement(DimensionSerializer, toJsonElement()) }
            .getOrNull()
}

// MARK: - Data / Network contract

/** Declarative networking configuration for a screen. */
@Serializable
data class DataConfig(
    /** `parallel` (default) fetches concurrently; `sequential` awaits in order. */
    val mode: Mode? = null,
    /** The requests to run. */
    val sources: List<DataSource>,
) {
    /** Execution parallelism, matched exactly to the iOS `DataConfig.Mode`. */
    @Serializable
    enum class Mode { parallel, sequential }
}

/** A single network request described declaratively. */
@Serializable
data class DataSource(
    /** Referenced as `$data.<id>`. */
    val id: String,
    /** Logical service name the host resolves to a base URL + auth. */
    val service: String,
    /** Path template; `{param}` segments are filled from `query` or bindings. */
    val path: String,
    /** HTTP method; defaults to GET when absent. */
    val method: Method? = null,
    /** Query items; values may be bindings. */
    val query: Map<String, String>? = null,
    /** Request body for write methods. */
    val body: JsonValue? = null,
    /** Extra headers; values may be bindings. */
    val headers: Map<String, String>? = null,
    /** IDs that must resolve first, forcing ordering even in parallel mode. */
    val dependsOn: List<String>? = null,
    /** Caching strategy. */
    val policy: Policy? = null,
) {
    /** HTTP verbs allowed by the contract. */
    @Serializable
    enum class Method { GET, POST, PUT, PATCH, DELETE }

    /** Caching policies allowed by the contract. */
    @Serializable
    enum class Policy { networkOnly, cacheFirst, cacheThenNetwork }
}

// MARK: - Actions

/**
 * A declarative action.
 *
 * Kept open like [Component]: the `action` kind and any analytics tag are eager,
 * and kind-specific fields live in [raw]. This mirrors the Swift `Action` and
 * keeps the vocabulary closed while allowing new fields without model churn.
 */
@Serializable(with = ActionSerializer::class)
data class Action(
    /** The action kind, e.g. `navigate`, `sequence`, `setState`. */
    val action: String,
    /** Optional analytics event emitted when this action fires. */
    val analytics: AnalyticsTag? = null,
    /** The whole action node, for kind-specific field access. */
    val raw: JsonValue,
) {
    /** Reads a kind-specific field, e.g. `field("to")` on a navigate action. */
    fun field(key: String): JsonValue? = raw[key]

    /** Child actions for `sequence` / `parallel`. */
    val actions: List<Action>
        get() = raw["actions"]?.decode<List<Action>>() ?: emptyList()
}

/** Custom deserializer for [Action], mirroring [ComponentSerializer]. */
object ActionSerializer : KSerializer<Action> {
    override val descriptor: SerialDescriptor =
        buildClassSerialDescriptor("dev.sdui.core.Action")

    override fun deserialize(decoder: Decoder): Action {
        val input = decoder as? JsonDecoder
            ?: throw IllegalStateException("Action can only be read from JSON.")
        val element = input.decodeJsonElement()
        val obj = element as? JsonObject
            ?: throw IllegalStateException("Action must be a JSON object.")
        val raw = JsonValue.fromJsonElement(element)
        return Action(
            action = obj["action"]?.jsonPrimitive?.content
                ?: throw IllegalStateException("Action is missing required 'action'."),
            analytics = raw["analytics"]?.decode<AnalyticsTag>(),
            raw = raw,
        )
    }

    override fun serialize(encoder: Encoder, value: Action) {
        JsonValueSerializer.serialize(encoder, value.raw)
    }
}

/** Optional analytics metadata carried by screens and actions. */
@Serializable
data class AnalyticsTag(
    val event: String? = null,
    val screenName: String? = null,
    val params: Map<String, String>? = null,
)

// MARK: - Conditions

/**
 * Boolean expression over bindings, used by `visibleWhen`, `enabledWhen` and the
 * `condition` action. Exactly one operator key is expected. Modelled as a sealed
 * hierarchy mirroring the Swift `indirect enum Condition`.
 */
@Serializable(with = ConditionSerializer::class)
sealed class Condition {
    /** True when both refs resolve to the same string. */
    data class Equals(val lhs: String, val rhs: String) : Condition()

    /** True when the two refs resolve to different strings. */
    data class NotEquals(val lhs: String, val rhs: String) : Condition()

    /** True when the ref resolves to a present, non-empty value. */
    data class Exists(val ref: String) : Condition()

    /** Logical negation. */
    data class Not(val inner: Condition) : Condition()

    /** True when every child is true. */
    data class And(val conditions: List<Condition>) : Condition()

    /** True when any child is true. */
    data class Or(val conditions: List<Condition>) : Condition()
}

/**
 * Decodes a [Condition] by inspecting which single operator key is present.
 * Mirrors the Swift `Condition.init(from:)` decode order.
 */
object ConditionSerializer : KSerializer<Condition> {
    override val descriptor: SerialDescriptor =
        buildClassSerialDescriptor("dev.sdui.core.Condition")

    override fun deserialize(decoder: Decoder): Condition {
        val input = decoder as? JsonDecoder
            ?: throw IllegalStateException("Condition can only be read from JSON.")
        val value = JsonValue.fromJsonElement(input.decodeJsonElement())

        value["equals"]?.pair()?.let { return Condition.Equals(it.first, it.second) }
        value["notEquals"]?.pair()?.let { return Condition.NotEquals(it.first, it.second) }
        value["exists"]?.stringValue?.let { return Condition.Exists(it) }
        value["not"]?.decode<Condition>()?.let { return Condition.Not(it) }
        value["and"]?.decode<List<Condition>>()?.let { return Condition.And(it) }
        value["or"]?.decode<List<Condition>>()?.let { return Condition.Or(it) }

        throw IllegalStateException("Condition must have exactly one operator key.")
    }

    override fun serialize(encoder: Encoder, value: Condition) {
        throw UnsupportedOperationException("Condition is decode-only in this renderer.")
    }

    /** Reads a two-element `[a, b]` array of bindable strings, or `null`. */
    private fun JsonValue.pair(): Pair<String, String>? {
        val list = arrayValue ?: return null
        if (list.size != 2) return null
        val a = list[0].stringValue ?: return null
        val b = list[1].stringValue ?: return null
        return a to b
    }
}

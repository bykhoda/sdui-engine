package dev.sdui.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.doubleOrNull

/**
 * A type-safe representation of any JSON value — the Kotlin counterpart of the
 * iOS `JSONValue`.
 *
 * The SDUI contract is intentionally open at the leaves: request bodies, list
 * item payloads, screen state and `custom.*` component props can hold arbitrary
 * JSON. Modelling that as a sealed hierarchy (rather than `Any?`) lets us carry
 * the value through the whole pipeline without losing type information, keeps the
 * model comparable via [equals], and gives us the ergonomic accessors below so
 * the binding engine never has to reach for casts.
 */
@Serializable(with = JsonValueSerializer::class)
sealed class JsonValue {
    /** A JSON string leaf. */
    data class Str(val value: String) : JsonValue()

    /** A JSON number leaf, always stored as [Double] to match the contract. */
    data class Num(val value: Double) : JsonValue()

    /** A JSON boolean leaf. */
    data class Bool(val value: Boolean) : JsonValue()

    /** A JSON object; key order is preserved for deterministic rendering. */
    data class Obj(val value: Map<String, JsonValue>) : JsonValue()

    /** A JSON array. */
    data class Arr(val value: List<JsonValue>) : JsonValue()

    /** JSON `null`. Modelled explicitly so "present but null" differs from absent. */
    data object Null : JsonValue()

    // MARK: - Ergonomic access

    /**
     * Object-member access. Returns `null` for non-objects or missing keys so
     * callers can chain safely — this is the Kotlin analogue of the Swift
     * `subscript(key:)`.
     */
    operator fun get(key: String): JsonValue? = (this as? Obj)?.value?.get(key)

    /**
     * Array-index access. Returns `null` when out of range or not an array,
     * mirroring the Swift `subscript(index:)`.
     */
    operator fun get(index: Int): JsonValue? =
        (this as? Arr)?.value?.getOrNull(index)

    /**
     * The value coerced to a display string, or `null` when it cannot be. Whole
     * numbers render without a trailing `.0` so ids and counts read cleanly.
     */
    val stringValue: String?
        get() = when (this) {
            is Str -> value
            is Num -> if (value == kotlin.math.floor(value) && !value.isInfinite())
                value.toLong().toString() else value.toString()
            is Bool -> if (value) "true" else "false"
            else -> null
        }

    /** The value coerced to a [Double], or `null`. Strings and bools are parsed leniently. */
    val doubleValue: Double?
        get() = when (this) {
            is Num -> value
            is Str -> value.toDoubleOrNull()
            is Bool -> if (value) 1.0 else 0.0
            else -> null
        }

    /** The value coerced to a [Boolean], or `null`. Accepts `1/yes/true` in strings. */
    val boolValue: Boolean?
        get() = when (this) {
            is Bool -> value
            is Num -> value != 0.0
            is Str -> value.lowercase() in setOf("true", "1", "yes")
            else -> null
        }

    /** The underlying list when this is an array, otherwise `null`. */
    val arrayValue: List<JsonValue>?
        get() = (this as? Arr)?.value

    /** True when this is the explicit [Null] leaf. */
    val isNull: Boolean
        get() = this is Null

    /**
     * Navigates a dotted key path, e.g. `["product", "title"]` or
     * `["items", "0", "id"]`. Numeric segments index into arrays. Returns `null`
     * as soon as any segment is missing — a missing binding is never an error.
     */
    fun valueAt(path: List<String>): JsonValue? {
        var current: JsonValue? = this
        for (segment in path) {
            val node = current ?: return null
            current = segment.toIntOrNull()?.let { node[it] } ?: node[segment]
        }
        return current
    }

    /**
     * Decodes this value into any [@Serializable] type by round-tripping through
     * a [JsonElement]. Used to lazily decode type-specific component props and
     * modifiers without a closed enum of every component kind — the direct
     * analogue of the Swift `decode(_:)`.
     */
    inline fun <reified T> decode(): T? =
        runCatching { CODEC.decodeFromJsonElement<T>(toJsonElement()) }.getOrNull()

    /** Converts this value back into a kotlinx [JsonElement] for encoding/decoding. */
    fun toJsonElement(): JsonElement = when (this) {
        is Str -> JsonPrimitive(value)
        is Num -> JsonPrimitive(value)
        is Bool -> JsonPrimitive(value)
        is Obj -> JsonObject(value.mapValues { it.value.toJsonElement() })
        is Arr -> JsonArray(value.map { it.toJsonElement() })
        Null -> JsonNull
    }

    companion object {
        /**
         * A lenient JSON codec shared by [decode] and the parser. `ignoreUnknownKeys`
         * lets payloads carry fields a given renderer version does not model yet
         * (forward compatibility), and `isLenient` tolerates minor server quirks.
         */
        val CODEC: Json = Json {
            ignoreUnknownKeys = true
            isLenient = true
            explicitNulls = false
        }

        /** Builds a [JsonValue] tree from a kotlinx [JsonElement]. */
        fun fromJsonElement(element: JsonElement): JsonValue = when (element) {
            is JsonNull -> Null
            is JsonObject -> Obj(element.mapValues { fromJsonElement(it.value) })
            is JsonArray -> Arr(element.map { fromJsonElement(it) })
            is JsonPrimitive -> when {
                !element.isString && element.booleanOrNull != null -> Bool(element.booleanOrNull == true)
                !element.isString && element.doubleOrNull != null -> Num(element.doubleOrNull ?: 0.0)
                else -> Str(element.content)
            }
        }
    }
}

/**
 * Bridges [JsonValue] to kotlinx.serialization. It defers to the built-in
 * [JsonElement] serializer (both directions go through the JSON AST), so the
 * sealed type composes with every other `@Serializable` model without a hand
 * written encode/decode per case — the Kotlin equivalent of the Swift
 * `singleValueContainer` implementation.
 */
object JsonValueSerializer : KSerializer<JsonValue> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

    override fun deserialize(decoder: Decoder): JsonValue {
        val input = decoder as? JsonDecoder
            ?: throw IllegalStateException("JsonValue can only be read from JSON.")
        return JsonValue.fromJsonElement(input.decodeJsonElement())
    }

    override fun serialize(encoder: Encoder, value: JsonValue) {
        JsonElement.serializer().serialize(encoder, value.toJsonElement())
    }
}

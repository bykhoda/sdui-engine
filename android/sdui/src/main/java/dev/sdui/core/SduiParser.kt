package dev.sdui.core

import kotlinx.serialization.SerializationException

/**
 * Entry point for turning raw JSON into a validated [SduiDocument].
 *
 * This is the *structural* gate: decoding fails with a readable [ParseError] so a
 * malformed payload never reaches a renderer. Full contract validation (enum
 * ranges, required-by-type props) runs against `spec/schema/sdui.schema.json` on
 * the backend before shipping; this layer guarantees the client degrades safely
 * rather than crashing — the same contract as the iOS `SDUIParser`.
 */
object SduiParser {

    /** A human-readable decoding failure. Its [message] names what went wrong. */
    class ParseError(message: String, cause: Throwable? = null) : Exception(message, cause)

    /**
     * Decodes UTF-8 bytes into an [SduiDocument]. Throws [ParseError] with a
     * readable message on malformed input.
     */
    @Throws(ParseError::class)
    fun decode(bytes: ByteArray): SduiDocument = decode(bytes.decodeToString())

    /**
     * Decodes a JSON string into an [SduiDocument]. Throws [ParseError] with a
     * readable message on malformed input.
     */
    @Throws(ParseError::class)
    fun decode(json: String): SduiDocument =
        try {
            JsonValue.CODEC.decodeFromString(SduiDocument.serializer(), json)
        } catch (e: SerializationException) {
            throw ParseError("Failed to decode SDUI document: ${e.message}", e)
        } catch (e: IllegalStateException) {
            // Our custom serializers throw IllegalStateException for missing
            // discriminators (e.g. a component without a 'type').
            throw ParseError("Invalid SDUI document: ${e.message}", e)
        }

    /**
     * Decodes without throwing, returning `null` on failure. Handy for feeds and
     * previews where one bad payload should not take down the surrounding UI.
     */
    fun decodeOrNull(json: String): SduiDocument? =
        runCatching { decode(json) }.getOrNull()
}

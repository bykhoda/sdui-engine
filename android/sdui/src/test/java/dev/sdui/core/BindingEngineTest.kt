package dev.sdui.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Unit tests for the pure-Kotlin binding engine — the Android counterpart of the
 * iOS `SDUICoreTests`. These run on the JVM (`testDebugUnitTest`), no device or
 * Compose runtime needed, so cross-platform binding parity is verified in CI.
 */
class BindingEngineTest {

    private val tokens = JsonValue.Obj(
        mapOf(
            "color" to JsonValue.Obj(mapOf("primary" to JsonValue.Str("#0A84FF"))),
            "spacing" to JsonValue.Obj(mapOf("md" to JsonValue.Num(12.0))),
        ),
    )

    private fun ctx(
        state: Map<String, JsonValue> = emptyMap(),
        data: Map<String, JsonValue> = emptyMap(),
    ) = BindingContext(tokens = tokens, state = state, data = data)

    @Test fun resolvesTokenLeaf() {
        assertEquals("#0A84FF", BindingEngine.resolveString("\$token.color.primary", ctx()))
    }

    @Test fun interpolatesStateIntoLiteralText() {
        val c = ctx(state = mapOf("name" to JsonValue.Str("Ann")))
        assertEquals("Hi, Ann", BindingEngine.resolveString("Hi, \$state.name", c))
    }

    @Test fun wholeBindingPreservesNumericType() {
        val c = ctx(state = mapOf("count" to JsonValue.Num(3.0)))
        val v = BindingEngine.resolve("\$state.count", c)
        assertTrue(v is JsonValue.Num, "whole-string binding should keep its JSON type")
        assertEquals(3.0, (v as JsonValue.Num).value)
    }

    @Test fun missingBindingResolvesToEmptyString() {
        assertEquals("", BindingEngine.resolveString("\$state.nope", ctx()))
    }

    @Test fun traversesNestedDataPath() {
        val c = ctx(data = mapOf("user" to JsonValue.Obj(mapOf("name" to JsonValue.Str("Lee")))))
        assertEquals("Lee", BindingEngine.resolveString("\$data.user.name", c))
    }
}

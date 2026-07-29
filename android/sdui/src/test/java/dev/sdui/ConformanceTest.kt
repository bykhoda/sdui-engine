package dev.sdui

import dev.sdui.core.Action
import dev.sdui.core.AnalyticsTag
import dev.sdui.core.BindingContext
import dev.sdui.core.BindingEngine
import dev.sdui.core.Condition
import dev.sdui.core.JsonValue
import dev.sdui.core.evaluate
import dev.sdui.runtime.ActionHost
import dev.sdui.runtime.ActionInterpreter
import kotlinx.coroutines.runBlocking
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * Runs the SHARED conformance corpus (spec/conformance/fixtures) through the real Kotlin
 * engine — the Android counterpart of iOS `SDUIConformanceTests` and the JS `check.mjs`.
 * Same fixtures, three languages: bindings / conditions / effects must resolve identically,
 * so "identical on every platform" is a JVM unit test, not a claim. See doc 09.
 */
class ConformanceTest {

    private val fixturesDir: File by lazy {
        var d: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (d != null) {
            val f = File(d, "spec/conformance/fixtures")
            if (f.isDirectory) return@lazy f
            d = d.parentFile
        }
        error("could not locate spec/conformance/fixtures from ${System.getProperty("user.dir")}")
    }
    private val defaultTokens: File by lazy {
        File(fixturesDir.parentFile?.parentFile, "schema/tokens.example.json")
    }

    private fun parse(f: File): JsonValue =
        JsonValue.CODEC.decodeFromString(JsonValue.serializer(), f.readText())

    private fun obj(v: JsonValue?): Map<String, JsonValue> = (v as? JsonValue.Obj)?.value ?: emptyMap()

    private fun fixtures(): List<Pair<String, File>> =
        fixturesDir.listFiles { f -> f.isDirectory }!!.sortedBy { it.name }.map { it.name to it }

    private fun ctxFor(dir: File): BindingContext {
        val tokens = parse(if (File(dir, "tokens.json").exists()) File(dir, "tokens.json") else defaultTokens)
        val s = if (File(dir, "state.json").exists()) obj(parse(File(dir, "state.json"))) else emptyMap()
        return BindingContext(
            data = obj(s["data"]), tokens = tokens, env = obj(s["env"]),
            state = obj(s["state"]), params = obj(s["params"]), item = s["item"],
        )
    }

    @Test fun bindings() {
        for ((id, dir) in fixtures()) {
            val expect = parse(File(dir, "expect.json"))
            val binds = (expect["bindings"] as? JsonValue.Obj)?.value ?: continue
            val ctx = ctxFor(dir)
            for ((input, want) in binds) {
                assertEquals(want.stringValue, BindingEngine.resolveString(input, ctx), "[$id] binding \"$input\"")
            }
        }
    }

    @Test fun conditions() {
        for ((id, dir) in fixtures()) {
            val expect = parse(File(dir, "expect.json"))
            val conds = (expect["conditions"] as? JsonValue.Arr)?.value ?: continue
            val ctx = ctxFor(dir)
            conds.forEachIndexed { i, entry ->
                val cond = entry["expr"]?.decode<Condition>() ?: fail("[$id] condition[$i] malformed expr")
                val want = entry["value"]?.boolValue ?: fail("[$id] condition[$i] malformed value")
                assertEquals(want, cond.evaluate(ctx), "[$id] condition[$i]")
            }
        }
    }

    @Test fun effects() = runBlocking {
        for ((id, dir) in fixtures()) {
            val expect = parse(File(dir, "expect.json"))
            val want = (expect["effects"] as? JsonValue.Arr)?.value ?: continue
            val action = parse(File(dir, "action.json")).decode<Action>() ?: fail("[$id] bad action.json")
            val host = RecordingHost()
            ActionInterpreter(host).run(action, ctxFor(dir))
            assertEquals(want.size, host.effects.size, "[$id] effect count — got ${host.effects}")
            want.forEachIndexed { i, exp ->
                assertTrue(subset(exp, host.effects[i]), "[$id] effect[$i] = ${host.effects[i]}, expected ⊇ $exp")
            }
        }
    }

    /** `expected` (a JsonValue.Obj) is an ordered subset of `actual` (extra keys allowed). */
    private fun subset(expected: JsonValue, actual: JsonValue): Boolean = when (expected) {
        is JsonValue.Obj -> actual is JsonValue.Obj &&
            expected.value.all { (k, v) -> actual.value[k]?.let { subset(v, it) } ?: false }
        else -> expected == actual
    }
}

/** Records each interpreted side effect as a JsonValue, mirroring action.mjs / iOS RecordingHost. */
private class RecordingHost : ActionHost {
    val effects = mutableListOf<JsonValue>()
    private fun push(type: String, extra: Map<String, JsonValue> = emptyMap()) {
        effects.add(JsonValue.Obj(linkedMapOf("type" to JsonValue.Str(type)) + extra))
    }
    override suspend fun track(tag: AnalyticsTag) = push("analytics", mapOf("event" to JsonValue.Str(tag.event ?: "")))
    override suspend fun navigate(screen: String, params: Map<String, JsonValue>, transition: String) =
        push("navigate", mapOf("to" to JsonValue.Str(screen), "transition" to JsonValue.Str(transition)))
    override suspend fun dismiss() = push("dismiss")
    override suspend fun dismissRoot() = push("dismissRoot")
    override suspend fun openUrl(url: String) = push("openURL", mapOf("url" to JsonValue.Str(url)))
    override suspend fun setState(key: String, value: JsonValue) = push("setState", mapOf("key" to JsonValue.Str(key), "value" to value))
    override suspend fun refresh(sources: List<String>) = push("refresh", mapOf("sources" to JsonValue.Arr(sources.map { JsonValue.Str(it) })))
    override suspend fun showToast(message: String, style: String?) =
        push("showToast", if (style != null) mapOf("message" to JsonValue.Str(message), "style" to JsonValue.Str(style)) else mapOf("message" to JsonValue.Str(message)))
    override suspend fun scrollTo(id: String) = push("scrollTo", mapOf("target" to JsonValue.Str(id)))
    override suspend fun haptic(style: String?) = push("haptic", if (style != null) mapOf("style" to JsonValue.Str(style)) else emptyMap())
    override suspend fun share(text: String?, url: String?) {
        val e = LinkedHashMap<String, JsonValue>()
        if (text != null) e["text"] = JsonValue.Str(text)
        if (url != null) e["url"] = JsonValue.Str(url)
        push("share", e)
    }
    override suspend fun log(message: String) = push("log", mapOf("message" to JsonValue.Str(message)))
    override suspend fun custom(name: String, payload: JsonValue?) =
        push("custom", if (payload != null) mapOf("name" to JsonValue.Str(name), "payload" to payload) else mapOf("name" to JsonValue.Str(name)))
    override suspend fun preview(urls: List<String>, index: Int) =
        push("preview", mapOf("urls" to JsonValue.Arr(urls.map { JsonValue.Str(it) }), "index" to JsonValue.Num(index.toDouble())))
}

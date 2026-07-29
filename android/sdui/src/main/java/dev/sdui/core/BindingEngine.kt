package dev.sdui.core

/**
 * The evaluation context a binding expression resolves against.
 *
 * Namespaces map to fields here, exactly as on iOS:
 * `$data.<id>.<path>` → [data], `$token.<group>.<name>` → [tokens],
 * `$env.<key>` → [env], `$state.<key>` → [state], `$item.<path>` → [item].
 *
 * It is an immutable value type so a list template can cheaply derive a scoped
 * copy per row via [withItem] without mutating the parent scope.
 */
data class BindingContext(
    /** Loaded network responses, keyed by data-source id. */
    val data: Map<String, JsonValue> = emptyMap(),
    /** The shared design-token table (the parsed `tokens.json`). */
    val tokens: JsonValue = JsonValue.Obj(emptyMap()),
    /** Runtime environment: locale, theme, platform, etc. */
    val env: Map<String, JsonValue> = emptyMap(),
    /** Client-local screen state. */
    val state: Map<String, JsonValue> = emptyMap(),
    /** Navigation parameters passed to this screen, bindable as `$params.<key>`
     *  (mirrors the iOS `BindingContext.params`). */
    val params: Map<String, JsonValue> = emptyMap(),
    /** The current element inside a `list` template, exposed as `$item`. */
    val item: JsonValue? = null,
) {
    /** Returns a copy scoped to a new `$item`, used when rendering list rows. */
    fun withItem(item: JsonValue): BindingContext = copy(item = item)

    /** Returns a copy with one state key updated. */
    fun withState(key: String, value: JsonValue): BindingContext =
        copy(state = state + (key to value))

    /** Returns a copy with a data source's result merged in. */
    fun withData(id: String, value: JsonValue): BindingContext =
        copy(data = data + (id to value))
}

/**
 * Resolves binding expressions against a [BindingContext].
 *
 * Two shapes are supported, identical to the Swift `BindingEngine`:
 * 1. A whole-string binding (`"$data.product.title"`) resolves to a full
 *    [JsonValue] — which may be an object or array, not just text.
 * 2. Interpolation (`"Hello, $data.user.name"`) resolves every `$…` token to its
 *    string form and splices it into the surrounding literal text.
 *
 * A missing binding always resolves to [JsonValue.Null] / empty — never an error.
 */
object BindingEngine {

    /** Resolves a bindable string to a concrete [JsonValue]. */
    fun resolve(input: String, ctx: BindingContext): JsonValue {
        // Whole-string binding: return the resolved node with its real type.
        wholeBindingToken(input)?.let { token ->
            return resolveToken(token, ctx, depth = 0) ?: JsonValue.Null
        }
        // Interpolated / literal string.
        return JsonValue.Str(interpolate(input, ctx))
    }

    /** Convenience: resolve straight to a display string (empty when null). */
    fun resolveString(input: String, ctx: BindingContext): String =
        resolve(input, ctx).stringValue ?: ""

    /**
     * Returns the string itself when it is a single `$…` binding end to end,
     * otherwise `null` (meaning it is literal text or an interpolation).
     */
    private fun wholeBindingToken(s: String): String? {
        val end = scanToken(s, 0) ?: return null
        return if (end == s.length) s else null
    }

    /**
     * Replaces every `$…` token in the string with its resolved string value,
     * leaving surrounding literal text untouched. A lone `$` stays verbatim.
     */
    private fun interpolate(s: String, ctx: BindingContext): String {
        val result = StringBuilder()
        var i = 0
        while (i < s.length) {
            val end = if (s[i] == '$') scanToken(s, i) else null
            if (end != null) {
                result.append(resolveToken(s.substring(i, end), ctx, depth = 0)?.stringValue ?: "")
                i = end
            } else {
                result.append(s[i])
                i += 1
            }
        }
        return result.toString()
    }

    /**
     * Scans one `$identifier(.segment)*` token starting at [start] (which must
     * point at `$`). Returns the index just past the token, or `null` when the
     * characters at [start] are not a valid binding. The grammar mirrors the
     * contract: `$`, an ASCII letter/underscore, then letters/digits/underscores,
     * then any number of `.`-separated segments.
     */
    private fun scanToken(chars: String, start: Int): Int? {
        if (start >= chars.length || chars[start] != '$') return null
        var i = start + 1
        if (i >= chars.length || !isIdentifierHead(chars[i])) return null
        i += 1
        while (i < chars.length && isIdentifierBody(chars[i])) i += 1
        while (i < chars.length && chars[i] == '.') {
            val beforeDot = i
            i += 1
            if (i >= chars.length || !isIdentifierBody(chars[i])) return beforeDot
            while (i < chars.length && isIdentifierBody(chars[i])) i += 1
        }
        return i
    }

    private fun isIdentifierHead(c: Char): Boolean =
        c == '_' || (c.code < 128 && c.isLetter())

    private fun isIdentifierBody(c: Char): Boolean =
        c == '_' || (c.code < 128 && c.isLetterOrDigit())

    /**
     * Resolves a single `$namespace.path` token. Token refs that themselves
     * resolve to another binding (e.g. a button style pointing at a colour token)
     * are followed, bounded by [depth] to prevent cycles — matching the iOS
     * depth-8 guard.
     */
    private fun resolveToken(token: String, ctx: BindingContext, depth: Int): JsonValue? {
        if (depth >= 8) return JsonValue.Str(token)
        val parts = token.removePrefix("$").split(".").filter { it.isNotEmpty() }
        val namespace = parts.firstOrNull() ?: return null
        val rest = parts.drop(1)

        val resolved: JsonValue? = when (namespace) {
            "data" -> {
                val sourceId = rest.firstOrNull()
                if (sourceId == null) null
                else ctx.data[sourceId]?.valueAt(rest.drop(1))
                    ?: (if (rest.size == 1) ctx.data[sourceId] else null)
            }
            "token" -> ctx.tokens.valueAt(rest)
            "env" -> {
                val key = rest.firstOrNull()
                if (key == null) null
                else ctx.env[key]?.valueAt(rest.drop(1))
                    ?: (if (rest.size == 1) ctx.env[key] else null)
            }
            "state" -> {
                val key = rest.firstOrNull()
                if (key == null) null
                else ctx.state[key]?.valueAt(rest.drop(1))
                    ?: (if (rest.size == 1) ctx.state[key] else null)
            }
            "params" -> {
                val key = rest.firstOrNull()
                if (key == null) null
                else ctx.params[key]?.valueAt(rest.drop(1))
                    ?: (if (rest.size == 1) ctx.params[key] else null)
            }
            "item" -> ctx.item?.valueAt(rest) ?: (if (rest.isEmpty()) ctx.item else null)
            else -> return null
        }

        // Follow chained token references (e.g. a button style pointing at a colour).
        if (resolved is JsonValue.Str && wholeBindingToken(resolved.value) != null) {
            return resolveToken(resolved.value, ctx, depth + 1)
        }
        return resolved
    }
}

/**
 * Evaluates this condition against a [BindingContext]. Behaviour is identical to
 * the Swift `Condition.evaluate(in:)` — `exists` treats missing, null and empty
 * as false; string/array emptiness is the truthiness test.
 */
fun Condition.evaluate(ctx: BindingContext): Boolean = when (this) {
    is Condition.Equals ->
        BindingEngine.resolveString(lhs, ctx) == BindingEngine.resolveString(rhs, ctx)

    is Condition.NotEquals ->
        BindingEngine.resolveString(lhs, ctx) != BindingEngine.resolveString(rhs, ctx)

    is Condition.Exists -> {
        val v = BindingEngine.resolve(ref, ctx)
        when {
            v is JsonValue.Null -> false
            v.stringValue?.isNotEmpty() == true -> true
            v.arrayValue?.isNotEmpty() == true -> true
            else -> false
        }
    }

    is Condition.Not -> !inner.evaluate(ctx)
    is Condition.And -> conditions.all { it.evaluate(ctx) }
    is Condition.Or -> conditions.any { it.evaluate(ctx) }
}

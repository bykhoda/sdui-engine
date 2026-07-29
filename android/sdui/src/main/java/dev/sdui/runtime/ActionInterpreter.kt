package dev.sdui.runtime

import dev.sdui.core.Action
import dev.sdui.core.AnalyticsTag
import dev.sdui.core.BindingContext
import dev.sdui.core.BindingEngine
import dev.sdui.core.Condition
import dev.sdui.core.JsonValue
import dev.sdui.core.evaluate

/**
 * Capabilities the host app provides so the interpreter can carry out leaf
 * actions.
 *
 * The interpreter owns control flow (`sequence`, `parallel`, `condition`); the
 * host owns side effects. This split — a direct port of the iOS `ActionHost`
 * protocol — keeps the action vocabulary closed and identical across platforms
 * while letting each app wire navigation, analytics and haptics to its own stack.
 *
 * Methods are `suspend` so a host can await genuinely asynchronous work
 * (navigation animations, network writes) without blocking the caller.
 */
interface ActionHost {
    /** Navigate to a screen id / route with resolved params and a transition. */
    suspend fun navigate(screen: String, params: Map<String, JsonValue>, transition: String)

    /** Dismiss the current screen. */
    suspend fun dismiss()

    /** Dismiss the whole navigation stack. */
    suspend fun dismissRoot()

    /** Open an external URL or deep link. */
    suspend fun openUrl(url: String)

    /** Mutate one key of client-local screen state. */
    suspend fun setState(key: String, value: JsonValue)

    /** Reload the named data sources (empty = all). */
    suspend fun refresh(sources: List<String>)

    /** Show a transient message. */
    suspend fun showToast(message: String, style: String?)

    /** Scrolls the nearest scroll container to the component whose id matches. */
    suspend fun scrollTo(id: String)

    /** Emit haptic feedback of the given style. */
    suspend fun haptic(style: String?)

    /** Present the system share sheet. */
    suspend fun share(text: String?, url: String?)

    /** Write a diagnostic log line. */
    suspend fun log(message: String)

    /** Emit an analytics event. */
    suspend fun track(tag: AnalyticsTag)

    /** Handle a host-defined `custom` action. */
    suspend fun custom(name: String, payload: JsonValue?)

    /** Present a quick-look/gallery of one or more urls (default no-op, like iOS's
     *  default ActionHost) so a host that predates it keeps compiling. */
    suspend fun preview(urls: List<String>, index: Int) {}
}

/**
 * Walks a declarative [Action] tree and drives an [ActionHost].
 *
 * A faithful port of the iOS `ActionInterpreter`: it interprets the composable
 * control-flow actions (`sequence`, `parallel`, `condition`) itself and delegates
 * every leaf action to the host, so both platforms interpret the same JSON the
 * same way.
 */
class ActionInterpreter(private val host: ActionHost) {

    /** Runs [action] against the binding [ctx], firing any attached analytics tag first. */
    suspend fun run(action: Action, ctx: BindingContext) {
        action.analytics?.let { host.track(it) }

        when (action.action) {
            "sequence" ->
                for (child in action.actions) run(child, ctx)

            // Leaf actions touch UI/navigation state that must not race, so — as
            // on iOS — we await them in order. Genuinely concurrent work belongs
            // in the data layer (DataConfig.mode = parallel), not here.
            "parallel" ->
                for (child in action.actions) run(child, ctx)

            "condition" -> {
                val cond = action.field("if")?.decode<Condition>() ?: return
                if (cond.evaluate(ctx)) {
                    action.field("then")?.decode<Action>()?.let { run(it, ctx) }
                } else {
                    action.field("else")?.decode<Action>()?.let { run(it, ctx) }
                }
            }

            "navigate" -> {
                val to = resolvedString(action.field("to"), ctx)
                val params = resolvedParams(action.field("params"), ctx)
                val transition = action.field("transition")?.stringValue ?: "push"
                host.navigate(to, params, transition)
            }

            "dismiss" -> host.dismiss()
            "dismissRoot" -> host.dismissRoot()

            "openURL", "openDeepLink" ->
                host.openUrl(resolvedString(action.field("url"), ctx))

            "setState" -> {
                val key = action.field("key")?.stringValue ?: return
                host.setState(key, resolvedValue(action.field("value"), ctx))
            }

            "refresh" -> {
                val sources = action.field("sources")?.arrayValue
                    ?.mapNotNull { it.stringValue } ?: emptyList()
                host.refresh(sources)
            }

            "showToast" ->
                host.showToast(
                    message = resolvedString(action.field("message"), ctx),
                    style = action.field("style")?.stringValue,
                )

            "scrollTo" -> host.scrollTo(resolvedString(action.field("target"), ctx))
            "haptic" -> host.haptic(action.field("style")?.stringValue)

            "share" ->
                host.share(
                    text = action.field("text")?.let { resolvedString(it, ctx) },
                    url = action.field("url")?.let { resolvedString(it, ctx) },
                )

            "log" -> host.log(resolvedString(action.field("message"), ctx))

            "preview" -> {
                // A single `url` or an array of `urls`, each binding-resolved, with an
                // optional starting `index` — mirrors the iOS interpreter.
                val urls = action.field("urls")?.arrayValue?.map { resolvedString(it, ctx) }
                    ?: resolvedString(action.field("url"), ctx).let { if (it.isEmpty()) emptyList() else listOf(it) }
                host.preview(urls, action.field("index")?.doubleValue?.toInt() ?: 0)
            }

            // Already tracked above via action.analytics.
            "analytics" -> Unit

            "custom" -> {
                val name = action.field("name")?.stringValue ?: return
                host.custom(name, action.field("payload")?.let { resolvedValue(it, ctx) })
            }

            "delay" -> {
                // Declarative pause, mainly inside a `sequence`. Clamped to 60s.
                val seconds = action.field("seconds")?.doubleValue ?: 0.0
                if (seconds > 0) kotlinx.coroutines.delay((seconds.coerceAtMost(60.0) * 1000).toLong())
            }

            "increment" -> {
                // Add `by` (default 1) to a numeric state key — powers "load more"
                // and steppers without arithmetic in the payload.
                val key = action.field("key")?.stringValue ?: return
                val by = action.field("by")?.doubleValue ?: 1.0
                val bare = key.removePrefix("\$state.")
                val current = ctx.state[bare]?.doubleValue ?: 0.0
                host.setState(bare, JsonValue.Num(current + by))
            }

            else -> host.log("Unhandled action '${action.action}'")
        }
    }

    // MARK: - Binding helpers

    private fun resolvedString(v: JsonValue?, ctx: BindingContext): String {
        val s = v?.stringValue ?: return ""
        return BindingEngine.resolveString(s, ctx)
    }

    private fun resolvedValue(v: JsonValue?, ctx: BindingContext): JsonValue {
        v ?: return JsonValue.Null
        return if (v is JsonValue.Str) BindingEngine.resolve(v.value, ctx) else v
    }

    private fun resolvedParams(v: JsonValue?, ctx: BindingContext): Map<String, JsonValue> {
        val obj = (v as? JsonValue.Obj)?.value ?: return emptyMap()
        return obj.mapValues { (_, value) ->
            if (value is JsonValue.Str) BindingEngine.resolve(value.value, ctx) else value
        }
    }
}

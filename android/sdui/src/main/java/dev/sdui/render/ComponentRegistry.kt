package dev.sdui.render

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.unit.sp
import dev.sdui.core.Action
import dev.sdui.core.BindingContext
import dev.sdui.core.Component
import dev.sdui.core.JsonValue
import dev.sdui.core.evaluate

/**
 * Context threaded down the view tree while rendering.
 *
 * Carries the current binding scope (which changes inside list templates as
 * `$item` is bound), the registry used to recurse into children, and the action
 * dispatcher. The Compose analogue of the iOS `RenderContext` struct.
 */
data class RenderContext(
    /** The binding scope for the current subtree. */
    val binding: BindingContext,
    /** The registry used to render child components. */
    val registry: ComponentRegistry,
    /**
     * Fire-and-forget dispatch of a declarative action. The host wires this to an
     * [dev.sdui.runtime.ActionInterpreter] running on a coroutine scope.
     */
    val dispatch: (Action, BindingContext) -> Unit,
    /**
     * Optional host hook mapping a contract icon name (SF Symbol vocabulary) to an
     * Android [androidx.compose.ui.graphics.painter.Painter]. Absent, icons render
     * their name as text so authoring intent stays visible.
     */
    val iconResolver: ((String) -> androidx.compose.ui.graphics.painter.Painter?)? = null,
    /**
     * Loads a single data source on demand (used by the `async` component to
     * fetch-then-render). Returns the decoded value, or `null` on failure / when
     * the host wired no loader. The direct counterpart of the iOS
     * `RenderContext.loadSource`.
     */
    val loadSource: (suspend (dev.sdui.core.DataSource) -> JsonValue?)? = null,
    /** Writes a value into screen `$state` (used by two-way controls like `slider`). */
    val setState: ((String, JsonValue) -> Unit)? = null,
) {
    /** Returns a context scoped to a new `$item`, used when rendering list rows. */
    fun withItem(item: JsonValue): RenderContext =
        copy(binding = binding.withItem(item))
}

/**
 * A composable that renders one component type into the current [RenderContext].
 * The Compose replacement for the iOS `ComponentRegistry.Builder` closure that
 * returned an `AnyView`.
 */
typealias ComponentBuilder = @Composable (Component, RenderContext) -> Unit

/**
 * Maps a component `type` to a Composable builder.
 *
 * Built-in primitives are registered up front; host apps register `custom.*`
 * types to extend the vocabulary without touching the SDK. Unknown types render
 * safely (a debug hint, nothing in release) instead of crashing — the same
 * safe-degradation contract as the iOS registry.
 */
class ComponentRegistry(registerBuiltins: Boolean = true) {
    private val builders: MutableMap<String, ComponentBuilder> = mutableMapOf()

    init {
        if (registerBuiltins) Builtins.registerAll(this)
    }

    /** Registers (or overrides) the builder for a component [type]. */
    fun register(type: String, builder: ComponentBuilder) {
        builders[type] = builder
    }

    /**
     * Renders [component] in [ctx]. Honours `visibleWhen` before doing any work
     * and falls back safely for unknown types.
     *
     * Modifiers (padding, background, gestures, context menu...) are applied by the
     * built-ins themselves, which wrap their root node with [sduiModifiers] and
     * [contextMenuHost]. Unlike SwiftUI — where a modifier can be appended to an
     * `AnyView` after the fact — a Compose `Modifier` must be threaded into the
     * node as it is created, so the builder owns that step.
     */
    @Composable
    fun Render(component: Component, ctx: RenderContext) {
        // Respect visibleWhen before doing any work.
        component.visibleWhen?.let { if (!it.evaluate(ctx.binding)) return }

        val builder = builders[component.type]
        if (builder == null) {
            UnknownComponent(component)
            return
        }
        builder(component, ctx)
    }

    /**
     * Unknown types degrade safely. In a debug build we surface a red hint so
     * authoring mistakes are obvious; in release nothing is drawn.
     */
    @Composable
    private fun UnknownComponent(component: Component) {
        if (BuildFlags.DEBUG) {
            Text(
                text = "⚠️ unknown '${component.type}'",
                color = Color.Red,
                fontSize = 12.sp,
                fontStyle = FontStyle.Italic,
            )
        }
    }
}

/**
 * A tiny indirection so the registry's debug behaviour is testable and does not
 * depend on generated `BuildConfig` (which is host-app specific). Hosts may flip
 * [DEBUG] if they want the "unknown component" hint in a particular build.
 */
object BuildFlags {
    /** When true, unknown components render a visible hint instead of nothing. */
    var DEBUG: Boolean = true
}

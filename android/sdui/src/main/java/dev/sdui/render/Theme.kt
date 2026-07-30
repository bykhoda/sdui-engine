package dev.sdui.render

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.sdui.core.BindingContext
import dev.sdui.core.BindingEngine
import dev.sdui.core.Dimension

/**
 * Resolves contract values (`Dimension`, hex colours, typography tokens) into
 * native Compose types, using the shared token table carried by the binding
 * context.
 *
 * All platform-specific mapping lives here so the renderers stay declarative —
 * the Compose counterpart of the iOS `Theme` enum. Where SwiftUI returns
 * `CGFloat`/`Color`/`Font`, this returns `Dp`/`Color`/`TextStyle`.
 */
object Theme {

    /** The Compose sentinel meaning "fill the available space" for a [Dimension]. */
    val INFINITY: Dp = Dp.Infinity

    // MARK: Dimensions

    /**
     * Resolves a [Dimension] to a Compose [Dp]. Token refs are looked up in the
     * binding context; a missing token falls back to [default]. `infinity` maps
     * to [Dp.Infinity] so `frame.maxWidth = "infinity"` fills the axis.
     */
    fun dp(dim: Dimension?, ctx: BindingContext, default: Dp = 0.dp): Dp = when (dim) {
        null -> default
        is Dimension.Points -> dim.value.dp
        Dimension.Infinity -> Dp.Infinity
        is Dimension.Token ->
            (BindingEngine.resolve(dim.ref, ctx).doubleValue ?: default.value.toDouble()).dp
    }

    // MARK: Colors

    /**
     * Resolves a colour reference to a Compose [Color], or `null` when it cannot
     * be parsed. Accepts a token ref (`$token.color.primary`), a hex string
     * (`#RRGGBB` / `#RRGGBBAA`), or a binding — resolving through the token table
     * exactly like the iOS `Theme.color`.
     */
    fun color(raw: String?, ctx: BindingContext): Color? {
        if (raw.isNullOrEmpty()) return null
        val resolved = BindingEngine.resolveString(raw, ctx)
        return hexColor(resolved)
    }

    /**
     * The app's accent — the design token `color.primary`, resolved fresh so a live theme
     * swap re-tints everything. This is the single fallback for every default a component
     * needs where iOS draws with SwiftUI's `.accentColor`, replacing the scattered
     * hardcoded blues/purples that diverged from the theme (parity #35).
     */
    fun accent(ctx: BindingContext): Color = color("\$token.color.primary", ctx) ?: Color(0xFF5B5BF0)

    /** Parses `#RRGGBB` or `#RRGGBBAA` into a [Color], or `null` when malformed. */
    fun hexColor(hex: String): Color? {
        val s = hex.trim()
        if (!s.startsWith("#")) return null
        val body = s.substring(1)
        val value = body.toLongOrNull(16) ?: return null
        return when (body.length) {
            6 -> {
                val r = ((value and 0xFF0000) shr 16) / 255.0
                val g = ((value and 0x00FF00) shr 8) / 255.0
                val b = (value and 0x0000FF) / 255.0
                Color(r.toFloat(), g.toFloat(), b.toFloat(), 1f)
            }
            8 -> {
                val r = ((value and 0xFF000000) shr 24) / 255.0
                val g = ((value and 0x00FF0000) shr 16) / 255.0
                val b = ((value and 0x0000FF00) shr 8) / 255.0
                val a = (value and 0x000000FF) / 255.0
                Color(r.toFloat(), g.toFloat(), b.toFloat(), a.toFloat())
            }
            else -> null
        }
    }

    // MARK: Typography

    /**
     * Resolves a `$token.typography.*` ref into a Compose [TextStyle], or `null`
     * when the token has no `size`. Mirrors the iOS `Theme.font`, mapping the
     * shared `{size, weight}` descriptor to a system font.
     */
    fun textStyle(styleRef: String?, ctx: BindingContext): TextStyle? {
        styleRef ?: return null
        val node = BindingEngine.resolve(styleRef, ctx)
        val size = node["size"]?.doubleValue ?: return null
        return TextStyle(
            fontSize = size.sp,
            fontWeight = fontWeight(node["weight"]?.stringValue),
        )
    }

    private fun fontWeight(name: String?): FontWeight = when (name) {
        "bold" -> FontWeight.Bold
        "semibold" -> FontWeight.SemiBold
        "medium" -> FontWeight.Medium
        "light" -> FontWeight.Light
        else -> FontWeight.Normal
    }
}

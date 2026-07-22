package dev.sdui.render

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.graphicsLayer
import dev.sdui.core.JsonValue
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.sdui.core.BindingEngine
import dev.sdui.core.Dimension
import dev.sdui.core.EdgeInsets
import dev.sdui.core.Modifiers

/**
 * Applies the platform-neutral [Modifiers] block to any component's root
 * `Modifier`. This is the Compose translation of the iOS `View.sduiModifiers`
 * extension: it composes padding, frame, background+clip, shadow, opacity and
 * gestures in the same order so both platforms lay out identically.
 *
 * The long-press context menu is NOT handled here — it needs a hoisted composable
 * (a [DropdownMenu]) and is applied by [contextMenuHost] instead.
 */
fun Modifier.sduiModifiers(modifiers: Modifiers?, ctx: RenderContext): Modifier {
    val m = modifiers ?: return this
    return this
        .then(paddingModifier(m.padding, ctx))
        .then(frameModifier(m.frame, ctx))
        .then(backgroundModifier(m.background, m.material, m.cornerRadius, ctx))
        .then(shadowModifier(m.shadow, m.cornerRadius, ctx))
        .then(if (m.opacity != null) Modifier.alpha(m.opacity.toFloat()) else Modifier)
        .then(scaleModifier(m.scale, ctx))
        .then(gestureModifier(m, ctx))
}

/** Uniform scale — a number or a `$state` binding (0…). */
private fun scaleModifier(scale: JsonValue?, ctx: RenderContext): Modifier {
    val value = when {
        scale == null -> null
        scale.stringValue != null -> BindingEngine.resolve(scale.stringValue!!, ctx.binding).doubleValue
        else -> scale.doubleValue
    } ?: return Modifier
    return Modifier.graphicsLayer(scaleX = value.toFloat(), scaleY = value.toFloat())
}

private fun paddingModifier(insets: EdgeInsets?, ctx: RenderContext): Modifier = when (insets) {
    null -> Modifier
    is EdgeInsets.All -> Modifier.padding(Theme.dp(insets.value, ctx.binding))
    is EdgeInsets.Specific -> {
        // `horizontal`/`vertical` act as fallbacks for the matching edge pair.
        fun d(dim: Dimension?, fallback: Dimension?): Dp =
            Theme.dp(dim ?: fallback, ctx.binding)
        Modifier.padding(
            start = d(insets.leading, insets.horizontal),
            end = d(insets.trailing, insets.horizontal),
            top = d(insets.top, insets.vertical),
            bottom = d(insets.bottom, insets.vertical),
        )
    }
}

private fun frameModifier(frame: Modifiers.Frame?, ctx: RenderContext): Modifier {
    frame ?: return Modifier
    var result: Modifier = Modifier
    frame.width?.let { result = result.width(Theme.dp(it, ctx.binding)) }
    frame.height?.let { result = result.height(Theme.dp(it, ctx.binding)) }
    frame.maxWidth?.let {
        val max = Theme.dp(it, ctx.binding, default = Dp.Infinity)
        result = result.widthIn(max = max)
    }
    return result
}

private fun backgroundModifier(color: String?, material: String?, radius: Dimension?, ctx: RenderContext): Modifier {
    val r = radius?.let { Theme.dp(it, ctx.binding) } ?: 0.dp
    val shape = RoundedCornerShape(r)
    // Translucent "glass": Compose has no cross-version backdrop blur, so we
    // approximate visionOS glass with a bright translucent fill + hairline rim.
    // A host on API 31+ can layer a real RenderEffect blur behind this.
    if (material == "glass") {
        var m = Modifier
            .background(androidx.compose.ui.graphics.Color(0x24FFFFFF), shape)
            .then(Modifier.border(1.dp, androidx.compose.ui.graphics.Color(0x59FFFFFF), shape))
        Theme.color(color, ctx.binding)?.let { m = Modifier.background(it, shape).then(m) }
        return m.clip(shape)
    }
    val bg = Theme.color(color, ctx.binding) ?: return Modifier
    return Modifier.background(bg, shape).clip(shape)
}

private fun shadowModifier(shadow: Modifiers.Shadow?, radius: Dimension?, ctx: RenderContext): Modifier {
    shadow ?: return Modifier
    val elevation = shadow.radius?.let { Theme.dp(it, ctx.binding) } ?: 4.dp
    val cornerRadius = radius?.let { Theme.dp(it, ctx.binding) } ?: 0.dp
    return Modifier.shadow(elevation = elevation, shape = RoundedCornerShape(cornerRadius))
}

private fun gestureModifier(modifiers: Modifiers, ctx: RenderContext): Modifier {
    val tap = modifiers.onTap
    val longPress = modifiers.onLongPress
    if (tap == null && longPress == null) return Modifier
    return Modifier.pointerInput(tap, longPress) {
        detectTapGestures(
            onTap = tap?.let { action -> { ctx.dispatch(action, ctx.binding) } },
            onLongPress = longPress?.let { action -> { ctx.dispatch(action, ctx.binding) } },
        )
    }
}

/**
 * Wraps [content] with a long-press context menu when the modifiers declare one.
 *
 * A context menu needs hoisted open/closed state and an anchored [DropdownMenu],
 * so — unlike the pure-`Modifier` chain above — it must be a composable wrapper.
 * When no menu is declared, [content] is emitted directly with zero overhead.
 */
@Composable
fun contextMenuHost(modifiers: Modifiers?, ctx: RenderContext, content: @Composable () -> Unit) {
    val items = modifiers?.contextMenu
    if (items.isNullOrEmpty()) {
        content()
        return
    }
    var expanded by remember { mutableStateOf(false) }
    androidx.compose.foundation.layout.Box(
        modifier = Modifier.pointerInput(items) {
            detectTapGestures(onLongPress = { expanded = true })
        },
    ) {
        content()
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            items.forEach { item ->
                DropdownMenuItem(
                    text = { Text(BindingEngine.resolveString(item.title, ctx.binding)) },
                    onClick = {
                        expanded = false
                        ctx.dispatch(item.action, ctx.binding)
                    },
                )
            }
        }
    }
}

package dev.sdui.render

import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.EaseIn
import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.sdui.core.BindingEngine
import dev.sdui.core.Dimension
import dev.sdui.core.EdgeInsets
import dev.sdui.core.JsonValue
import dev.sdui.core.Modifiers

/**
 * Applies the platform-neutral [Modifiers] block to any component's root
 * `Modifier`. This is the Compose translation of the iOS `View.sduiModifiers`
 * extension: it composes padding, frame, background+material, blur, shadow, the
 * state-driven transform (opacity/scale/rotation + `animation`), `pulse`, gestures
 * (with press feedback) and safe-area handling in the same order so both platforms
 * lay out and animate identically.
 *
 * It is `@Composable` because several pieces — the pulse heartbeat, the animated
 * transform and the press feedback — read animation state; the only caller is the
 * `@Composable` [Primitive] wrapper, so this stays a well-formed composition.
 *
 * The long-press context menu is NOT handled here — it needs a hoisted composable
 * (a [DropdownMenu]) and is applied by [contextMenuHost] instead.
 */
@Composable
fun Modifier.sduiModifiers(modifiers: Modifiers?, ctx: RenderContext): Modifier {
    val m = modifiers ?: return this
    return this
        .then(sizeModifier(m.size))
        .then(frameModifier(m.frame, ctx))
        // Shadow BEFORE background so it's cast behind the filled/clipped shape.
        .then(shadowModifier(m.shadow, m.cornerRadius, ctx))
        .then(backgroundModifier(m.background, m.material, m.cornerRadius, ctx))
        // Padding is applied AFTER the background+clip so content is inset WITHIN the
        // filled shape — the SwiftUI `.padding().background()` visual. (In Compose the
        // same order would instead shrink the background inside the padding, which made
        // rounded bubbles clip their first character.)
        .then(paddingModifier(m.padding, ctx))
        .then(blurModifier(m.blur))
        .then(transformModifier(m.scale, m.rotation, m.opacity, m.animation, ctx))
        .then(pulseModifier(m.pulse, ctx))
        .then(gestureModifier(m, ctx))
        .then(safeAreaModifier(m.ignoresSafeArea))
}

/**
 * The state-driven transform: uniform `scale`, `rotation` (degrees) and `opacity`,
 * each a constant or a `$state` binding. When an [Modifiers.AnimationSpec] is
 * present every change animates with the contract's curve/duration (a spring scale
 * on pause, a flipping chevron) — the counterpart of the iOS `AnimationModifier`
 * that animates the view on `$state` change. With no `animation` the values snap.
 */
@Composable
private fun transformModifier(
    scale: JsonValue?,
    rotation: JsonValue?,
    opacity: Double?,
    animation: Modifiers.AnimationSpec?,
    ctx: RenderContext,
): Modifier {
    if (scale == null && rotation == null && opacity == null) return Modifier
    val scaleTarget = resolveNumber(scale, ctx)?.toFloat() ?: 1f
    val rotationTarget = resolveNumber(rotation, ctx)?.toFloat() ?: 0f
    val alphaTarget = opacity?.toFloat()?.coerceIn(0f, 1f) ?: 1f
    val spec = animation?.toFloatSpec()
    val s = if (spec != null) animateFloatAsState(scaleTarget, spec, label = "sdui-scale").value else scaleTarget
    val r = if (spec != null) animateFloatAsState(rotationTarget, spec, label = "sdui-rotation").value else rotationTarget
    val a = if (spec != null) animateFloatAsState(alphaTarget, spec, label = "sdui-opacity").value else alphaTarget
    return Modifier.graphicsLayer(scaleX = s, scaleY = s, rotationZ = r, alpha = a)
}

/** Maps the neutral animation curve/duration onto a Compose float animation spec. */
private fun Modifiers.AnimationSpec.toFloatSpec(): AnimationSpec<Float> {
    val durationMs = ((duration ?: 0.25) * 1000.0).toInt().coerceAtLeast(0)
    return when (curve) {
        "linear" -> tween(durationMs, easing = LinearEasing)
        "easeIn" -> tween(durationMs, easing = EaseIn)
        "easeOut" -> tween(durationMs, easing = EaseOut)
        "spring" -> spring()
        else -> tween(durationMs, easing = EaseInOut) // easeInOut and the default
    }
}

/**
 * A rhythmic auto-reversing scale "heartbeat" (album art beating to music, a live
 * "recording" dot). While the bound bool state is true it breathes between 1.0 and
 * `scale` forever; when false it rests at 1.0. Composes on top of
 * [transformModifier], so a paused-shrink and a playing-pulse coexist — matching the
 * iOS `PulseModifier`.
 */
@Composable
private fun pulseModifier(pulse: JsonValue?, ctx: RenderContext): Modifier {
    // `pulse` presence is stable for a node, so this early return never changes the
    // composition shape across recompositions (only `active`, read below, changes).
    val cfg = pulseConfig(pulse, ctx) ?: return Modifier
    val transition = rememberInfiniteTransition(label = "sdui-pulse")
    val scale by transition.animateFloat(
        initialValue = 1f,
        targetValue = if (cfg.active) cfg.amplitude else 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(
                durationMillis = (cfg.interval * 1000.0).toInt().coerceAtLeast(100),
                easing = EaseInOut,
            ),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "sdui-pulse-scale",
    )
    return Modifier.graphicsLayer(scaleX = scale, scaleY = scale)
}

private class PulseConfig(val active: Boolean, val amplitude: Float, val interval: Double)

/** Reads the `pulse` shorthand (a bool-state key) or object (`{ while, scale, interval }`). */
private fun pulseConfig(pulse: JsonValue?, ctx: RenderContext): PulseConfig? {
    pulse ?: return null
    // Shorthand: a bare bool-state key string.
    pulse.stringValue?.let {
        return PulseConfig(active = resolveBool(it, ctx), amplitude = 1.04f, interval = 0.5)
    }
    // Object form: { while, scale, interval }.
    val active = pulse["while"]?.stringValue?.let { resolveBool(it, ctx) } ?: true
    val amplitude = (pulse["scale"]?.doubleValue ?: 1.04).toFloat()
    val interval = (pulse["interval"]?.doubleValue ?: 0.5).coerceAtLeast(0.1)
    return PulseConfig(active, amplitude, interval)
}

/** Uniform scale — a number or a `$state` binding (0…). */
private fun resolveNumber(value: JsonValue?, ctx: RenderContext): Double? = when {
    value == null -> null
    value.stringValue != null -> BindingEngine.resolve(value.stringValue!!, ctx.binding).doubleValue
    else -> value.doubleValue
}

/**
 * Resolves a bool `$state` key to its current value, accepting the key with or
 * without the `$state.` prefix — mirroring the iOS `boolBinding` `normalizedKey`.
 */
private fun resolveBool(key: String, ctx: RenderContext): Boolean {
    val ref = if (key.startsWith("$")) key else "\$state.$key"
    return BindingEngine.resolve(ref, ctx.binding).boolValue ?: false
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

/** The explicit per-axis `size` modifier: fixed points or fill the axis. */
private fun sizeModifier(size: Modifiers.Size?): Modifier {
    size ?: return Modifier
    var m: Modifier = Modifier
    when (size.width?.mode) {
        "fixed" -> size.width.value?.let { m = m.width(it.toFloat().dp) }
        "fill" -> m = m.fillMaxWidth()
    }
    when (size.height?.mode) {
        "fixed" -> size.height.value?.let { m = m.height(it.toFloat().dp) }
        "fill" -> m = m.fillMaxHeight()
    }
    return m
}

private fun frameModifier(frame: Modifiers.Frame?, ctx: RenderContext): Modifier {
    frame ?: return Modifier
    var result: Modifier = Modifier
    frame.width?.let { result = result.width(Theme.dp(it, ctx.binding)) }
    frame.height?.let { result = result.height(Theme.dp(it, ctx.binding)) }
    frame.maxWidth?.let {
        // `"infinity"` stretches to fill the axis (like SwiftUI `maxWidth: .infinity`);
        // a finite value is an upper bound only.
        result = if (it is Dimension.Infinity) {
            result.fillMaxWidth()
        } else {
            result.widthIn(max = Theme.dp(it, ctx.binding, default = Dp.Infinity))
        }
    }
    return result
}

private fun backgroundModifier(color: String?, material: String?, radius: Dimension?, ctx: RenderContext): Modifier {
    val r = radius?.let { Theme.dp(it, ctx.binding) } ?: 0.dp
    val shape = RoundedCornerShape(r)
    val frost = materialFrost(material, shape)
    if (frost != null) {
        // An explicit background colour sits *under* the translucent frosting.
        var m: Modifier = frost
        Theme.color(color, ctx.binding)?.let { m = Modifier.background(it, shape).then(m) }
        return m.clip(shape)
    }
    val bg = Theme.color(color, ctx.binding)
    return when {
        bg != null -> Modifier.background(bg, shape).clip(shape)
        // Clip to the rounded shape even with no fill colour, so a `gradient` component or
        // an `image` with a `cornerRadius` gets rounded corners instead of a hard square.
        r > 0.dp -> Modifier.clip(shape)
        else -> Modifier
    }
}

/**
 * Translucent frosted surface approximating the native blur materials. Compose has
 * no cross-version backdrop blur, so each tier is a brighter translucent fill plus a
 * hairline top-lit rim; a host on API 31+ can layer a real RenderEffect blur behind
 * this. Returns null for absent / unknown values so plain backgrounds are untouched.
 * Mirrors the iOS `materialView` tiers (ultraThin…bar) plus the bespoke `glass`.
 */
private fun materialFrost(material: String?, shape: Shape): Modifier? {
    // (fillAlpha, rimAlpha) as 0…255 — more opaque as the material thickens.
    val (fill, rim) = when (material) {
        "ultraThin" -> 0x1F to 0x3D
        "thin" -> 0x2E to 0x47
        "regular" -> 0x40 to 0x52
        "thick" -> 0x59 to 0x5C
        "bar" -> 0xB3 to 0x40
        "glass" -> 0x24 to 0x59
        else -> return null
    }
    return Modifier
        .background(Color(1f, 1f, 1f, fill / 255f), shape)
        .border(1.dp, Color(1f, 1f, 1f, rim / 255f), shape)
}

/**
 * A raw Gaussian blur on the node's own content (`"blur": 8`) — distinct from
 * `material`, which frosts what is *behind* the node. `Modifier.blur` renders on
 * API 31+ and is a silent no-op below, so an unset/zero value never softens a view.
 */
private fun blurModifier(radius: Double?): Modifier {
    if (radius == null || radius <= 0) return Modifier
    return Modifier.blur(radius.dp)
}

/**
 * A coloured, offset drop shadow honouring `shadow.color` (default black @0.15),
 * `radius` (blur, default 4) and `x`/`y` (default 0/2) — matching the iOS
 * `ShadowModifier`. Compose's built-in `Modifier.shadow` is elevation-only and can
 * neither offset nor fully colour, so we draw the shadow ourselves with a blurred
 * paint behind the node (a standard Compose idiom, no host dependency).
 */
private fun shadowModifier(shadow: Modifiers.Shadow?, radius: Dimension?, ctx: RenderContext): Modifier {
    shadow ?: return Modifier
    val color = Theme.color(shadow.color, ctx.binding) ?: Color.Black.copy(alpha = 0.15f)
    val blurRadius = shadow.radius?.let { Theme.dp(it, ctx.binding) } ?: 4.dp
    val offsetX = (shadow.x ?: 0.0).dp
    val offsetY = (shadow.y ?: 2.0).dp
    val cornerRadius = radius?.let { Theme.dp(it, ctx.binding) } ?: 0.dp
    // Canonical Compose shadow: a GPU-composited elevation shadow clipped to the shape —
    // far cleaner than a hand-drawn setShadowLayer, which read as a big grey blob. The
    // contract's blur radius maps to a capped elevation; colour tints the spot/ambient.
    val elevation = (blurRadius.value * 0.6f).coerceIn(2f, 16f).dp
    return Modifier.shadow(
        elevation = elevation,
        shape = RoundedCornerShape(cornerRadius),
        clip = false,
        ambientColor = color,
        spotColor = color,
    )
}

/**
 * Tap / long-press dispatch plus the app-wide press feel: every `onTap` element
 * springs down (~0.955), dims slightly and fires a light haptic the instant it is
 * pressed — the Compose counterpart of the iOS `SDUIPressableStyle`. Long-press-only
 * nodes dispatch without the scale feedback, exactly as on iOS.
 */
@Composable
private fun gestureModifier(modifiers: Modifiers, ctx: RenderContext): Modifier {
    val tap = modifiers.onTap
    val longPress = modifiers.onLongPress
    if (tap == null && longPress == null) return Modifier

    val haptics = LocalHapticFeedback.current
    var pressed by remember { mutableStateOf(false) }
    // Only `onTap` elements get the springy press feedback (iOS wraps them in a
    // Button); a long-press-only node dispatches without scaling.
    val feedback = tap != null
    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.955f else 1f,
        animationSpec = spring(dampingRatio = 0.58f, stiffness = Spring.StiffnessMediumLow),
        label = "sdui-press-scale",
    )
    val alpha by animateFloatAsState(
        targetValue = if (pressed) 0.9f else 1f,
        animationSpec = spring(dampingRatio = 0.58f, stiffness = Spring.StiffnessMediumLow),
        label = "sdui-press-alpha",
    )
    val press = if (feedback) {
        Modifier.graphicsLayer(scaleX = scale, scaleY = scale, alpha = alpha)
    } else {
        Modifier
    }
    return press.pointerInput(tap, longPress) {
        detectTapGestures(
            onPress = {
                if (feedback) {
                    pressed = true
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    tryAwaitRelease()
                    pressed = false
                }
            },
            onTap = tap?.let { action -> { ctx.dispatch(action, ctx.binding) } },
            onLongPress = longPress?.let { action -> { ctx.dispatch(action, ctx.binding) } },
        )
    }
}

/**
 * Extends an immersive background edge-to-edge: consuming the safe-drawing insets
 * tells descendants those insets are already handled, so nested `windowInsetsPadding`
 * stops re-insetting — the Compose analogue of SwiftUI `.ignoresSafeArea()`. The host
 * still enables edge-to-edge at the window level (see `Screen.chrome == "immersive"`).
 */
@Composable
private fun safeAreaModifier(ignores: Boolean?): Modifier =
    if (ignores == true) Modifier.consumeWindowInsets(WindowInsets.safeDrawing) else Modifier

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

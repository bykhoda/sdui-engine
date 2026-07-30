package dev.sdui.render

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.sdui.core.BindingEngine
import dev.sdui.core.Modifiers
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * Swipe-to-reveal row actions — the Android counterpart of the iOS `CustomSwipeModifier`
 * (Telegram-style drag-reveal that works on any row/card, not just list cells). Built on
 * the stable `pointerInput` + `Animatable` primitives (world-class manual-anchor approach,
 * portable across Compose versions) so the physics match iOS: drag reveals the leading /
 * trailing tray, a release past half-open snaps open, and a long full-swipe past the
 * threshold fires the edge-most action. One side commits per gesture. Buttons carry the
 * action's tint/role, icon and title and dispatch on tap.
 */
@Composable
internal fun SwipeReveal(swipe: Modifiers.SwipeConfig, ctx: RenderContext, content: @Composable () -> Unit) {
    val leading = swipe.leading.orEmpty()
    val trailing = swipe.trailing.orEmpty()
    if (leading.isEmpty() && trailing.isEmpty()) { content(); return }

    val density = LocalDensity.current
    val slot = with(density) { (swipe.actionWidth ?: 74.0).dp.toPx() }
    val armPad = with(density) { 96.dp.toPx() }
    val openLead = leading.size * slot
    val openTrail = trailing.size * slot
    val allowFull = swipe.fullSwipe ?: true
    val scope = rememberCoroutineScope()
    // The settled/animated offset. During an active drag we bypass this and track the finger
    // with a plain float (`drag`), so a moving finger never waits on a queued coroutine — the
    // snapTo-per-frame launch was the source of the lag that made the row jump.
    val offset = remember { Animatable(0f) }
    var drag by remember { mutableStateOf<Float?>(null) }
    val shown = drag ?: offset.value
    var rowW by remember { mutableStateOf(0f) }
    val snap = spring<Float>(dampingRatio = 0.86f, stiffness = Spring.StiffnessMediumLow)

    fun close() { drag = null; scope.launch { offset.animateTo(0f, snap) } }
    fun fire(a: Modifiers.SwipeAction) { ctx.dispatch(a.action, ctx.binding); close() }

    Box(Modifier.clipToBounds().onSizeChanged { rowW = it.width.toFloat() }) {
        if (leading.isNotEmpty()) {
            SwipeTray(leading, shown.coerceAtLeast(0f), ctx, ::fire, Modifier.align(Alignment.CenterStart))
        }
        if (trailing.isNotEmpty()) {
            SwipeTray(trailing, (-shown).coerceAtLeast(0f), ctx, ::fire, Modifier.align(Alignment.CenterEnd))
        }
        Box(
            Modifier
                .offset { IntOffset(shown.roundToInt(), 0) }
                // Key on Unit — NOT on the leading/trailing lists, which are fresh List
                // instances every recomposition and would restart the detector mid-drag
                // (the jank the user saw). The tray contents can't change for a row's life.
                .pointerInput(Unit) {
                    val trigger = { maxOf(rowW * 0.62f, slot + armPad) }
                    val lo = { if (trailing.isEmpty()) 0f else -openTrail - slot * 0.5f }
                    val hi = { if (leading.isEmpty()) 0f else openLead + slot * 0.5f }
                    detectHorizontalDragGestures(
                        onDragStart = { drag = offset.value },
                        onDragEnd = {
                            val o = drag ?: offset.value
                            drag = null
                            val t = trigger()
                            scope.launch {
                                offset.snapTo(o)
                                when {
                                    allowFull && leading.isNotEmpty() && o >= t -> { offset.animateTo(rowW, snap); fire(leading.first()) }
                                    allowFull && trailing.isNotEmpty() && -o >= t -> { offset.animateTo(-rowW, snap); fire(trailing.first()) }
                                    leading.isNotEmpty() && o > openLead * 0.5f -> offset.animateTo(openLead, snap)
                                    trailing.isNotEmpty() && -o > openTrail * 0.5f -> offset.animateTo(-openTrail, snap)
                                    else -> offset.animateTo(0f, snap)
                                }
                            }
                        },
                        onDragCancel = { close() },
                        onHorizontalDrag = { change, dragAmount ->
                            change.consume()
                            // Synchronous — no coroutine per frame. The finger and the row move
                            // together, so the drag can never fall behind onto the next row.
                            drag = ((drag ?: offset.value) + dragAmount).coerceIn(lo(), hi())
                        },
                    )
                },
        ) { content() }
    }
}

@Composable
private fun SwipeTray(
    actions: List<Modifiers.SwipeAction>,
    revealed: Float,
    ctx: RenderContext,
    onFire: (Modifiers.SwipeAction) -> Unit,
    modifier: Modifier,
) {
    if (revealed <= 0f) return
    val wDp = with(LocalDensity.current) { revealed.toDp() }
    Row(modifier.width(wDp).fillMaxHeight(), horizontalArrangement = Arrangement.End) {
        for (a in actions) {
            val destructive = a.role == "destructive"
            val tint = Theme.color(a.tint, ctx.binding)
                ?: if (destructive) Color(0xFFFF3B30) else Color(0xFF0A84FF)
            Box(
                Modifier.weight(1f).fillMaxHeight().background(tint).clickable { onFire(a) },
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    a.icon?.let {
                        Icon(materialIcon(it), contentDescription = null, tint = Color.White, modifier = Modifier.size(20.dp))
                    }
                    a.title?.takeIf { it.isNotEmpty() }?.let {
                        Text(
                            BindingEngine.resolveString(it, ctx.binding),
                            color = Color.White,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.padding(horizontal = 2.dp, vertical = 2.dp),
                        )
                    }
                }
            }
        }
    }
}

package dev.sdui.demo

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.sdui.render.materialIcon
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

// ── Story model — the Kotlin twin of ios/Sources/SDUIPlayground/HomeStories.swift.
//    Phase B replaces this hardcoded set with a `stories` component reading contract JSON
//    (see docs/blueprint/18-stories-player.md §3.3). ─────────────────────────────────────

/** One segment (one "page" of a story), auto-advanced by the segment timer. */
data class StorySegment(val icon: String, val title: String, val body: String)

/** One user's story: a labelled ring and an ordered list of segments over a tint gradient. */
data class CapabilityStory(
    val label: String,
    val ringIcon: String,
    val tint: List<Color>,
    val segments: List<StorySegment>,
) {
    companion object {
        private fun c(r: Float, g: Float, b: Float) = Color(red = r, green = g, blue = b)

        /** Verbatim content parity with iOS `CapabilityStory.all`. */
        val all: List<CapabilityStory> = listOf(
            CapabilityStory(
                label = "Server-driven", ringIcon = "arrow.triangle.2.circlepath",
                tint = listOf(c(0.40f, 0.40f, 0.96f), c(0.46f, 0.29f, 0.71f)),
                segments = listOf(
                    StorySegment("arrow.triangle.2.circlepath", "Ship whole screens",
                        "Your backend returns JSON. The app renders it natively — no App Store release."),
                    StorySegment("bolt.fill", "Change UI in seconds",
                        "Reorder a feed, swap a paywall, restyle checkout — live, for everyone."),
                ),
            ),
            CapabilityStory(
                label = "One contract", ringIcon = "square.on.square",
                tint = listOf(c(0.00f, 0.72f, 0.62f), c(0.00f, 0.45f, 0.55f)),
                segments = listOf(
                    StorySegment("square.on.square", "iOS + Android, one JSON",
                        "The same payload renders with SwiftUI here and Jetpack Compose there."),
                    StorySegment("checkmark.seal.fill", "Validated before it ships",
                        "A zero-dependency validator catches bad payloads before they reach a screen."),
                ),
            ),
            CapabilityStory(
                label = "Live theming", ringIcon = "paintpalette.fill",
                tint = listOf(c(0.98f, 0.55f, 0.19f), c(0.85f, 0.30f, 0.30f)),
                segments = listOf(
                    StorySegment("paintpalette.fill", "Design tokens over the wire",
                        "Colors, type scale and spacing ship as data. Re-theme the whole app instantly."),
                    StorySegment("circle.lefthalf.filled", "A/B test the look",
                        "Run ten palettes in production and measure which one users prefer."),
                ),
            ),
            CapabilityStory(
                label = "Rich components", ringIcon = "square.grid.2x2.fill",
                tint = listOf(c(0.79f, 0.24f, 0.86f), c(0.55f, 0.18f, 0.72f)),
                segments = listOf(
                    StorySegment("square.grid.2x2.fill", "Charts, forms, calendars",
                        "Dozens of native components — plus a clips feed and a stories player like this one."),
                    StorySegment("hand.tap.fill", "Gestures & motion built in",
                        "Swipe, double-tap, spring and haptics — all declared in the contract."),
                ),
            ),
        )
    }
}

private const val SEGMENT_MS = 4_000

/**
 * A full-screen Instagram/iOS-style stories player — the Android twin of the iOS
 * `StoriesPlayer` (HomeStories.swift). Segmented auto-advancing progress bars, tap-left/
 * right to move between segments, press-and-hold to pause, a cube transition between
 * users, and drag-down to dismiss. Built on stable Compose primitives (Animatable +
 * HorizontalPager + pointerInput), minSdk-friendly, no third-party dependency.
 * See docs/blueprint/18-stories-player.md.
 */
@Composable
fun StoriesPlayer(stories: List<CapabilityStory>, start: Int, onClose: () -> Unit) {
    if (stories.isEmpty()) { onClose(); return }
    val pagerState = rememberPagerState(initialPage = start.coerceIn(0, stories.lastIndex)) { stories.size }
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    val density = LocalDensity.current

    val page = pagerState.currentPage
    val story = stories[page]

    var segmentIndex by remember { mutableIntStateOf(0) }
    var paused by remember { mutableStateOf(false) }
    var restartToken by remember { mutableIntStateOf(0) }
    val progress = remember { Animatable(0f) }
    var dragY by remember { mutableFloatStateOf(0f) }

    // Settling on a new user resets to their first segment (only the foreground ticks).
    LaunchedEffect(page) { segmentIndex = 0 }

    // Segment timer. One run per (page, segment, restart): reset to 0, then fill to 1 and
    // auto-advance. `collectLatest` on `paused` cancels the fill when paused (freezing the
    // bar) and resumes from the frozen value — the Compose analogue of iOS's Timer pause.
    LaunchedEffect(page, segmentIndex, restartToken) {
        progress.snapTo(0f)
        snapshotFlow { paused }.collectLatest { isPaused ->
            if (isPaused) return@collectLatest
            val remaining = ((1f - progress.value) * SEGMENT_MS).toInt().coerceAtLeast(1)
            progress.animateTo(1f, tween(durationMillis = remaining, easing = LinearEasing))
            // Reached the end (not cancelled by pause/next) → advance.
            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            when {
                segmentIndex < story.segments.lastIndex -> segmentIndex++
                page < stories.lastIndex -> pagerState.animateScrollToPage(page + 1)
                else -> onClose()
            }
        }
    }

    fun goForward() {
        when {
            segmentIndex < story.segments.lastIndex -> segmentIndex++
            page < stories.lastIndex -> scope.launch { pagerState.animateScrollToPage(page + 1) }
            else -> onClose()
        }
    }
    fun goBack() {
        when {
            progress.value > 0.15f -> restartToken++            // restart the current segment
            segmentIndex > 0 -> segmentIndex--
            page > 0 -> scope.launch { pagerState.animateScrollToPage(page - 1) }
            else -> restartToken++
        }
    }

    val scrimAlpha = (1f - dragY / 700f).coerceIn(0f, 1f)

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .offset { IntOffset(0, dragY.roundToInt()) }
            .graphicsLayer {
                val s = (1f - dragY / 1400f).coerceIn(0.85f, 1f)
                scaleX = s; scaleY = s
                clip = true
                shape = RoundedCornerShape((dragY / 40f).coerceIn(0f, 28f).dp)
            }
            .pointerInput(Unit) {
                detectVerticalDragGestures(
                    onVerticalDrag = { _, dy -> if (dy > 0 || dragY > 0) dragY = (dragY + dy).coerceAtLeast(0f) },
                    onDragEnd = { if (dragY > 140f) onClose() else dragY = 0f },
                    onDragCancel = { dragY = 0f },
                )
            },
    ) {
        HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { p ->
            val offsetFraction = (pagerState.currentPage - p) + pagerState.currentPageOffsetFraction
            StoryFace(
                story = stories[p],
                segmentIndex = if (p == page) segmentIndex else 0,
                progress = if (p == page) progress.value else 0f,
                onTapZone = { x, w -> if (x < w * 0.33f) goBack() else goForward() },
                onPressHold = { held -> paused = held },
                modifier = Modifier.graphicsLayer {
                    rotationY = offsetFraction * 90f
                    cameraDistance = 12f * density.density
                    transformOrigin = TransformOrigin(if (offsetFraction > 0f) 0f else 1f, 0.5f)
                    alpha = 1f - abs(offsetFraction) * 0.15f
                },
            )
        }

        // Foreground chrome (progress + header + action bar) fades with the drag.
        Column(Modifier.fillMaxSize().statusBarsPadding().alpha(scrimAlpha)) {
            SegmentBars(count = story.segments.size, active = segmentIndex, fill = progress.value)
            StoryHeader(story = story, onClose = onClose)
            Spacer(Modifier.weight(1f))
            StoryActionBar()
        }
    }
}

// ── Sub-views ─────────────────────────────────────────────────────────────────────────

@Composable
private fun StoryFace(
    story: CapabilityStory,
    segmentIndex: Int,
    progress: Float,
    onTapZone: (x: Float, width: Float) -> Unit,
    onPressHold: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val seg = story.segments[segmentIndex.coerceIn(0, story.segments.lastIndex)]
    Box(
        modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(story.tint))
            .pointerInput(story) {
                detectTapGestures(
                    onPress = {
                        onPressHold(true)
                        tryAwaitRelease()
                        onPressHold(false)
                    },
                    onTap = { offset: Offset -> onTapZone(offset.x, size.width.toFloat()) },
                )
            },
    ) {
        Column(
            Modifier.fillMaxSize().padding(horizontal = 28.dp),
            verticalArrangement = Arrangement.Center,
        ) {
            Box(
                Modifier.size(72.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(materialIcon(seg.icon), contentDescription = null, tint = Color.White, modifier = Modifier.size(34.dp))
            }
            Spacer(Modifier.height(24.dp))
            Text(seg.title, color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Bold, lineHeight = 36.sp)
            Spacer(Modifier.height(12.dp))
            Text(seg.body, color = Color.White.copy(alpha = 0.9f), fontSize = 17.sp, lineHeight = 24.sp)
        }
    }
}

@Composable
private fun SegmentBars(count: Int, active: Int, fill: Float) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        for (i in 0 until count) {
            val f = when {
                i < active -> 1f
                i > active -> 0f
                else -> fill
            }
            Box(
                Modifier.weight(1f).height(3.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.3f)),
            ) {
                Box(Modifier.fillMaxHeight().fillMaxWidth(f).clip(CircleShape).background(Color.White))
            }
        }
    }
}

@Composable
private fun StoryHeader(story: CapabilityStory, onClose: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(34.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.22f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(materialIcon(story.ringIcon), contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.size(10.dp))
        Text(story.label, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.weight(1f))
        Icon(
            Icons.Filled.Close, contentDescription = "Close", tint = Color.White,
            modifier = Modifier.size(26.dp).clip(CircleShape).clickableNoRipple(onClose),
        )
    }
}

@Composable
private fun StoryActionBar() {
    var liked by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 20.dp, vertical = 18.dp),
        horizontalArrangement = Arrangement.spacedBy(20.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Spacer(Modifier.weight(1f))
        Icon(
            if (liked) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
            contentDescription = "Like",
            tint = if (liked) Color(0xFFFF375F) else Color.White,
            modifier = Modifier.size(28.dp).clickableNoRipple { liked = !liked },
        )
        Icon(Icons.Filled.Send, contentDescription = "Share", tint = Color.White, modifier = Modifier.size(26.dp))
    }
}

// A tap target without the Material ripple (the player draws its own chrome over media).
private fun Modifier.clickableNoRipple(onClick: () -> Unit): Modifier =
    this.pointerInput(Unit) { detectTapGestures(onTap = { onClick() }) }

private fun Modifier.alpha(value: Float): Modifier = this.graphicsLayer { alpha = value }

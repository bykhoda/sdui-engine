package dev.sdui.render

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Reply
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.sdui.core.Action
import dev.sdui.core.BindingEngine
import dev.sdui.core.Component
import dev.sdui.core.JsonValue

/**
 * A full-screen vertical snap-pager — an Instagram Reels / TikTok feed driven from
 * JSON, the Compose port of the iOS `ClipsView` (ios/Sources/SDUIRender/ClipsView.swift).
 * Swipe up/down to page, double-tap to like. Each page carries its own media
 * (a gradient stand-in for a video/photo URL), a caption block and a right-side
 * action rail. Pages buffer with a shimmering skeleton before their media reveals.
 *
 * The same `pages` contract maps 1:1 across platforms: SwiftUI's hand-rolled snap
 * offset here becomes Compose's native `VerticalPager` (identical snap physics).
 */
@Composable
internal fun ClipsView(component: Component, ctx: RenderContext) {
    val pages = component.prop("pages")?.arrayValue ?: emptyList()
    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    val pagerState = rememberPagerState(pageCount = { pages.size })

    // Fallback like-state for pages that carry no `onLike` action (unwired demos). Wired
    // pages instead read `liked`/`likes` from the contract's bound state, so a like flows
    // through setState/increment/request exactly like the iOS ClipsView. See doc 19 §3a.
    val localLiked = remember { mutableStateListOf<Int>() }
    val loaded = remember { mutableStateListOf<Int>() }
    var burst by remember { mutableStateOf<Int?>(null) }

    // Buffer the current page (and clear a stale burst) whenever the feed settles.
    LaunchedEffect(pagerState.currentPage) {
        val page = pagerState.currentPage
        if (page !in loaded) {
            kotlinx.coroutines.delay(750)
            if (page !in loaded) loaded.add(page)
        }
    }
    LaunchedEffect(burst) {
        if (burst != null) {
            kotlinx.coroutines.delay(650)
            burst = null
        }
    }

    // A continuously spinning audio disc, shared by every page's rail.
    val discTransition = rememberInfiniteTransition(label = "clips-disc")
    val discAngle by discTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(6000, easing = LinearEasing), RepeatMode.Restart),
        label = "clips-disc-angle",
    )

    Primitive(component, ctx) { modifier ->
        Box(
            modifier = modifier
                .fillMaxWidth()
                .height(screenHeight)
                .background(Color.Black),
        ) {
            VerticalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
                val data = pages[page]
                val onLike = data["onLike"]?.decode<Action>()
                // Wired page → the heart reflects bound `liked`; unwired → local toggle.
                val isLiked = if (onLike != null) resolvedBool(data["liked"], ctx) else page in localLiked
                val fireLike = {
                    if (onLike != null) {
                        // The contract's onLike sets liked=true + increments; only fire while
                        // not already liked so a second tap can't double-count.
                        if (!isLiked) ctx.dispatch(onLike, ctx.binding)
                    } else {
                        toggleLike(localLiked, page)
                    }
                }
                ClipPage(
                    data = data,
                    index = page,
                    ctx = ctx,
                    isLiked = isLiked,
                    isLoaded = page in loaded,
                    burstActive = burst == page,
                    discAngle = discAngle,
                    onLike = fireLike,
                    onDoubleTap = {
                        fireLike()          // double-tap always likes (Instagram)
                        burst = page
                    },
                )
            }
            ClipsTopBar()
        }
    }
}

private fun toggleLike(liked: MutableList<Int>, page: Int) {
    if (page in liked) liked.remove(page) else liked.add(page)
}

/** Resolves a possibly-bound boolean field (e.g. `"$state.liked_c1"`) to a Bool. */
private fun resolvedBool(v: JsonValue?, ctx: RenderContext): Boolean {
    val raw = (v as? JsonValue.Str)?.value ?: return v?.boolValue ?: false
    return BindingEngine.resolve(raw, ctx.binding).boolValue ?: false
}

/** Dispatches an optional action field (onComment/onShare/onMore) if the page declares it. */
private fun dispatchField(field: String, data: JsonValue, ctx: RenderContext) {
    data[field]?.decode<Action>()?.let { ctx.dispatch(it, ctx.binding) }
}

/** Resolves a count field — a `$state` binding to a number, or a literal like `"1.2K"` —
 *  and renders it compactly (12401 → "12.4K"), matching how iOS formats the rail counts. */
private fun formatCount(v: JsonValue?, ctx: RenderContext): String {
    v ?: return "0"
    val resolved = if (v is JsonValue.Str && v.value.startsWith("$")) BindingEngine.resolve(v.value, ctx.binding) else v
    return when (resolved) {
        is JsonValue.Num -> shortNumber(resolved.value)
        is JsonValue.Str -> resolved.value
        else -> "0"
    }
}

private fun shortNumber(n: Double): String {
    val x = n.toLong()
    return when {
        x >= 1_000_000 -> trimTrailingZero(x / 1_000_000.0) + "M"
        x >= 1_000 -> trimTrailingZero(x / 1_000.0) + "K"
        else -> x.toString()
    }
}

private fun trimTrailingZero(d: Double): String {
    val s = "%.1f".format(d)
    return if (s.endsWith(".0")) s.dropLast(2) else s
}

@Composable
private fun ClipPage(
    data: JsonValue,
    index: Int,
    ctx: RenderContext,
    isLiked: Boolean,
    isLoaded: Boolean,
    burstActive: Boolean,
    discAngle: Float,
    onLike: () -> Unit,
    onDoubleTap: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(clipGradient(data, ctx))
            .pointerInput(index) { detectTapGestures(onDoubleTap = { onDoubleTap() }) },
    ) {
        // Legibility scrim: darken the top and bottom so white text and the rail
        // stay readable over any media.
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(
                    0f to Color.Black.copy(alpha = 0.15f),
                    0.5f to Color.Transparent,
                    1f to Color.Black.copy(alpha = 0.55f),
                ),
            ),
        )

        // Bottom overlay: caption block + action rail.
        Row(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .padding(horizontal = 18.dp)
                .padding(bottom = 54.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            ClipCaption(data, Modifier.weight(1f))
            Spacer(Modifier.width(12.dp))
            ClipActionRail(data, ctx, isLiked, discAngle, onLike)
        }

        // Double-tap heart burst.
        AnimatedVisibility(
            visible = burstActive,
            modifier = Modifier.align(Alignment.Center),
            enter = fadeIn() + scaleIn(initialScale = 0.4f),
            exit = fadeOut(),
        ) {
            Icon(
                imageVector = Icons.Filled.Favorite,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(120.dp),
            )
        }

        // Buffering skeleton until the media "loads".
        if (!isLoaded) {
            ClipSkeleton()
        }
    }
}

@Composable
private fun ClipCaption(data: JsonValue, modifier: Modifier) {
    val author = data["author"]?.stringValue ?: "@creator"
    Column(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            ClipAvatar(author)
            Text(author, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
            Box(
                Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .border(1.dp, Color.White, RoundedCornerShape(8.dp))
                    .padding(horizontal = 12.dp, vertical = 5.dp),
            ) {
                Text("Follow", color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
            }
        }
        data["caption"]?.stringValue?.let { caption ->
            Text(
                text = caption,
                color = Color.White.copy(alpha = 0.96f),
                fontSize = 15.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            Icon(Icons.Filled.MusicNote, contentDescription = null, tint = Color.White.copy(alpha = 0.95f), modifier = Modifier.size(14.dp))
            Text(
                text = data["audio"]?.stringValue ?: "Original audio",
                color = Color.White.copy(alpha = 0.95f),
                fontSize = 13.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** A gradient-ring avatar with the creator's initial (Instagram-style). */
@Composable
private fun ClipAvatar(handle: String) {
    val letter = handle.dropWhile { it == '@' }.firstOrNull()?.uppercase() ?: "-"
    Box(
        modifier = Modifier
            .size(38.dp)
            .clip(CircleShape)
            .background(
                Brush.sweepGradient(
                    listOf(
                        Color(0xFFFA4A5C), Color(0xFFFA8C30), Color(0xFFCA3DDB), Color(0xFFFA4A5C),
                    ),
                ),
            ),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.size(33.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.82f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(letter, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
        }
    }
}

@Composable
private fun ClipActionRail(data: JsonValue, ctx: RenderContext, isLiked: Boolean, discAngle: Float, onLike: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(24.dp)) {
        ClipRailButton(
            icon = if (isLiked) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
            label = formatCount(data["likes"], ctx),
            tint = if (isLiked) Color(0xFFFF3D5E) else Color.White,
            onClick = onLike,
        )
        ClipRailButton(Icons.Filled.ChatBubble, formatCount(data["comments"], ctx), onClick = { dispatchField("onComment", data, ctx) })
        ClipRailButton(Icons.Filled.Reply, formatCount(data["shares"], ctx), onClick = { dispatchField("onShare", data, ctx) })
        ClipRailButton(Icons.Filled.MoreHoriz, "", onClick = { dispatchField("onMore", data, ctx) })
        // Spinning audio disc.
        Box(
            modifier = Modifier
                .size(42.dp)
                .graphicsLayer { rotationZ = discAngle }
                .clip(CircleShape)
                .background(Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.9f), Color.Gray))),
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(14.dp).clip(CircleShape).background(Color.Black), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.MusicNote, contentDescription = null, tint = Color.White, modifier = Modifier.size(9.dp))
            }
        }
    }
}

@Composable
private fun ClipRailButton(icon: ImageVector, label: String, tint: Color = Color.White, onClick: (() -> Unit)? = null) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp),
        modifier = if (onClick != null) Modifier.pointerInput(Unit) { detectTapGestures { onClick() } } else Modifier,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(30.dp))
        if (label.isNotEmpty()) {
            Text(label, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
        }
    }
}

@Composable
private fun ClipsTopBar() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .padding(top = 56.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(22.dp),
    ) {
        Text("Following", color = Color.White.copy(alpha = 0.7f), fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("For You", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 15.sp)
            Spacer(Modifier.height(4.dp))
            Box(Modifier.width(20.dp).height(2.dp).clip(CircleShape).background(Color.White))
        }
        Spacer(Modifier.weight(1f))
        Icon(Icons.Filled.PhotoCamera, contentDescription = null, tint = Color.White, modifier = Modifier.size(24.dp))
    }
}

/** A shimmering placeholder feed loader — Instagram loads reels as pure skeletons. */
@Composable
private fun ClipSkeleton() {
    val transition = rememberInfiniteTransition(label = "clips-skeleton")
    val phase by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1100, easing = LinearEasing), RepeatMode.Restart),
        label = "clips-skeleton-phase",
    )
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f))) {
        Row(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .padding(horizontal = 18.dp)
                .padding(bottom = 54.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                ClipSkeletonBar(150.dp, 16.dp, phase)
                ClipSkeletonBar(240.dp, 12.dp, phase)
                ClipSkeletonBar(120.dp, 12.dp, phase)
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(22.dp)) {
                repeat(4) {
                    Box(Modifier.size(34.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.16f)))
                }
            }
        }
    }
}

@Composable
private fun ClipSkeletonBar(width: androidx.compose.ui.unit.Dp, height: androidx.compose.ui.unit.Dp, phase: Float) {
    Box(
        modifier = Modifier
            .width(width)
            .height(height)
            .clip(RoundedCornerShape(height / 2))
            .background(Color.White.copy(alpha = 0.16f)),
    ) {
        Box(
            Modifier.fillMaxSize().background(
                Brush.horizontalGradient(
                    colors = listOf(Color.Transparent, Color.White.copy(alpha = 0.22f), Color.Transparent),
                    startX = -200f + phase * 600f,
                    endX = phase * 600f,
                ),
            ),
        )
    }
}

/** Builds the page's backdrop gradient from its `colors`, falling back to purple→black. */
private fun clipGradient(data: JsonValue, ctx: RenderContext): Brush {
    val resolved = (data["colors"]?.arrayValue ?: emptyList())
        .mapNotNull { it.stringValue?.let { hex -> Theme.color(hex, ctx.binding) } }
    val colors = if (resolved.size >= 2) resolved else listOf(Color(0xFF7B2FF7), Color.Black)
    return Brush.linearGradient(colors = colors, start = Offset.Zero, end = Offset.Infinite)
}

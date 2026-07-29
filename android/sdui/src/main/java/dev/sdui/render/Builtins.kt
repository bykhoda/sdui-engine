package dev.sdui.render

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.padding
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Image
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.SubcomposeAsyncImage
import dev.sdui.core.Action
import dev.sdui.core.BindingEngine
import dev.sdui.core.Component
import dev.sdui.core.Condition
import dev.sdui.core.Dimension
import dev.sdui.core.JsonValue
import dev.sdui.core.evaluate

/**
 * Registers the built-in primitive components. Each maps one contract `type` to a
 * Composable. Keeping them in the registry (rather than a `when`) means a host app
 * can override any primitive or add new ones uniformly — the same extensibility
 * the iOS `Builtins.registerAll` provides.
 */
object Builtins {
    fun registerAll(registry: ComponentRegistry) {
        registry.register("vstack") { c, ctx -> StackView(c, ctx, vertical = true) }
        registry.register("hstack") { c, ctx -> StackView(c, ctx, vertical = false) }
        registry.register("zstack") { c, ctx -> ZStackView(c, ctx) }
        registry.register("scroll") { c, ctx -> ScrollView(c, ctx) }
        registry.register("list") { c, ctx -> ListView(c, ctx) }
        registry.register("spacer") { c, ctx -> SpacerView(c, ctx) }
        registry.register("divider") { c, ctx -> DividerView(c, ctx) }
        registry.register("text") { c, ctx -> TextView(c, ctx) }
        registry.register("image") { c, ctx -> ImageView(c, ctx) }
        registry.register("button") { c, ctx -> ButtonView(c, ctx) }
        registry.register("icon") { c, ctx -> IconView(c, ctx) }
        registry.register("gradient") { c, ctx -> GradientView(c, ctx) }
        registry.register("rings") { c, ctx -> RingsView(c, ctx) }
        registry.register("chart") { c, ctx -> ChartView(c, ctx) }
        registry.register("spinner") { c, ctx -> SpinnerView(c, ctx) }
        registry.register("async") { c, ctx -> AsyncView(c, ctx) }
        registry.register("progress") { c, ctx -> ProgressBarView(c, ctx) }
        registry.register("slider") { c, ctx -> SliderView(c, ctx) }
        registry.register("toggle") { c, ctx -> ToggleView(c, ctx) }
        registry.register("textfield") { c, ctx -> TextFieldView(c, ctx) }
        registry.register("grid") { c, ctx -> GridView(c, ctx) }
        registry.register("disclosure") { c, ctx -> DisclosureView(c, ctx) }
        registry.register("ticker") { c, ctx -> TickerView(c, ctx) }
        registry.register("pager") { c, ctx -> PagerView(c, ctx) }
        registry.register("picker") { c, ctx -> PickerView(c, ctx) }
        registry.register("datepicker") { c, ctx -> DatePickerView(c, ctx) }
        registry.register("calendar") { c, ctx -> CalendarGridView(c, ctx) }
        registry.register("roadmap") { c, ctx -> RoadmapView(c, ctx) }
        registry.register("filecell") { c, ctx -> FileCellView(c, ctx) }
        registry.register("clips") { c, ctx -> ClipsView(c, ctx) }
    }
}

/**
 * The shared wrapper every primitive uses: it applies the long-press context menu
 * host and the `Modifiers` chain around [content]. Centralising it guarantees all
 * built-ins honour modifiers identically, mirroring how the iOS registry appends
 * `.sduiModifiers` after every builder.
 */
@Composable
internal fun Primitive(
    component: Component,
    ctx: RenderContext,
    content: @Composable (Modifier) -> Unit,
) {
    val swipe = component.modifiers?.swipe
    contextMenuHost(component.modifiers, ctx) {
        if (swipe != null && (!swipe.leading.isNullOrEmpty() || !swipe.trailing.isNullOrEmpty())) {
            SwipeReveal(swipe, ctx) { content(Modifier.sduiModifiers(component.modifiers, ctx)) }
        } else {
            content(Modifier.sduiModifiers(component.modifiers, ctx))
        }
    }
}

// MARK: - Form controls (two-way bound to $state)

/** The bare state key behind a `bind`, tolerating both `"email"` and `"$state.email"`. */
private fun bindKey(component: Component): String =
    (component.prop("bind")?.stringValue ?: "").removePrefix("\$state.")

@Composable
private fun ToggleView(component: Component, ctx: RenderContext) {
    val key = bindKey(component)
    val title = BindingEngine.resolveString(component.prop("title")?.stringValue ?: "", ctx.binding)
    val checked = BindingEngine.resolve("\$state.$key", ctx.binding).boolValue ?: false
    Primitive(component, ctx) { modifier ->
        Row(
            modifier = modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(title, style = androidx.compose.material3.LocalTextStyle.current)
            androidx.compose.material3.Switch(
                checked = checked,
                onCheckedChange = { ctx.setState?.invoke(key, JsonValue.Bool(it)) },
            )
        }
    }
}

@Composable
private fun TextFieldView(component: Component, ctx: RenderContext) {
    val key = bindKey(component)
    val current = BindingEngine.resolve("\$state.$key", ctx.binding).stringValue ?: ""
    val label = BindingEngine.resolveString(component.prop("label")?.stringValue ?: "", ctx.binding)
    val placeholder = BindingEngine.resolveString(component.prop("placeholder")?.stringValue ?: "", ctx.binding)
    val secure = component.prop("secure")?.boolValue ?: false
    Primitive(component, ctx) { modifier ->
        androidx.compose.material3.OutlinedTextField(
            value = current,
            onValueChange = { ctx.setState?.invoke(key, JsonValue.Str(it)) },
            modifier = modifier.fillMaxWidth(),
            label = if (label.isNotEmpty()) ({ Text(label) }) else null,
            placeholder = if (placeholder.isNotEmpty()) ({ Text(placeholder) }) else null,
            singleLine = true,
            visualTransformation =
                if (secure) androidx.compose.ui.text.input.PasswordVisualTransformation()
                else androidx.compose.ui.text.input.VisualTransformation.None,
        )
    }
}

// MARK: - Grid + Disclosure

@Composable
private fun GridView(component: Component, ctx: RenderContext) {
    val cols = (component.prop("columns")?.doubleValue?.toInt() ?: 2).coerceAtLeast(1)
    val gap = component.prop("spacing")?.decode<Dimension>()?.let { Theme.dp(it, ctx.binding) } ?: 0.dp
    val itemsRef = component.prop("items")?.stringValue
    val template = component.prop("template")?.decode<Component>()
    Primitive(component, ctx) { modifier ->
        // A non-lazy chunked grid — safe inside the screen's outer scroll (a
        // LazyVerticalGrid would be measured with unbounded height and crash).
        val cells: List<@Composable () -> Unit> =
            if (itemsRef != null && template != null) {
                val items = BindingEngine.resolve(itemsRef, ctx.binding).arrayValue ?: emptyList()
                items.map { item -> { ctx.registry.Render(template, ctx.withItem(item)) } }
            } else {
                component.children.map { child -> { ctx.registry.Render(child, ctx) } }
            }
        Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(gap)) {
            cells.chunked(cols).forEach { rowCells ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(gap)) {
                    rowCells.forEach { cell -> Box(Modifier.weight(1f)) { cell() } }
                    repeat(cols - rowCells.size) { Box(Modifier.weight(1f)) {} }
                }
            }
        }
    }
}

@Composable
private fun DisclosureView(component: Component, ctx: RenderContext) {
    val title = BindingEngine.resolveString(component.prop("title")?.stringValue ?: "", ctx.binding)
    val subtitle = BindingEngine.resolveString(component.prop("subtitle")?.stringValue ?: "", ctx.binding)
    var expanded by remember(component.id) { mutableStateOf(component.prop("expanded")?.boolValue ?: false) }
    Primitive(component, ctx) { modifier ->
        Column(modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier.fillMaxWidth().clickable { expanded = !expanded }.padding(vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column {
                    Text(title, style = androidx.compose.material3.LocalTextStyle.current)
                    if (subtitle.isNotEmpty()) {
                        Text(subtitle, style = androidx.compose.material3.MaterialTheme.typography.bodySmall)
                    }
                }
                Text(if (expanded) "▾" else "▸")
            }
            AnimatedVisibility(visible = expanded) {
                Column { component.children.forEach { ctx.registry.Render(it, ctx) } }
            }
        }
    }
}

// MARK: - Ticker (invisible clock advancing a numeric $state on an interval)

@Composable
private fun TickerView(component: Component, ctx: RenderContext) {
    val key = bindKey(component)
    if (key.isEmpty()) return
    val interval = component.prop("interval")?.doubleValue ?: 1.0
    val step = component.prop("step")?.doubleValue ?: 0.01
    val max = component.prop("max")?.doubleValue ?: 1.0
    val loop = component.prop("loop")?.boolValue ?: false
    val whileKey = component.prop("while")?.stringValue?.removePrefix("\$state.")
    val active = whileKey == null ||
        (BindingEngine.resolve("\$state.$whileKey", ctx.binding).boolValue ?: false)

    LaunchedEffect(key, interval, step, max, loop, active) {
        if (!active) return@LaunchedEffect
        // Seed from state once, then accumulate locally so we never read a stale
        // captured binding on each tick.
        var v = BindingEngine.resolve("\$state.$key", ctx.binding).doubleValue ?: 0.0
        while (true) {
            kotlinx.coroutines.delay((interval * 1000).toLong().coerceAtLeast(1))
            v += step
            if (v >= max) v = if (loop) 0.0 else max
            ctx.setState?.invoke(key, JsonValue.Num(v))
            if (v >= max && !loop) break
        }
    }
    // Renders no UI — mirrors the iOS ticker.
}

// MARK: - Pager (auto-advancing carousel with page dots)

@Composable
private fun PagerView(component: Component, ctx: RenderContext) {
    val pages = component.children
    val height = component.prop("height")?.doubleValue ?: 200.0
    val autoMs = (component.prop("autoAdvanceMs")?.doubleValue ?: 0.0).toLong()
    val showDots = (component.prop("indicator")?.stringValue ?: "dots") != "none"
    val accent = Theme.color("\$token.color.primary", ctx.binding) ?: Color(0xFF5B5BF0)
    val state = rememberPagerState(pageCount = { pages.size })

    if (autoMs > 0 && pages.size > 1) {
        LaunchedEffect(state, autoMs) {
            while (true) {
                kotlinx.coroutines.delay(autoMs)
                state.animateScrollToPage((state.currentPage + 1) % pages.size)
            }
        }
    }

    Primitive(component, ctx) { modifier ->
        Column(modifier.fillMaxWidth()) {
            HorizontalPager(state = state, modifier = Modifier.fillMaxWidth().height(height.toFloat().dp)) { page ->
                ctx.registry.Render(pages[page], ctx)
            }
            if (showDots && pages.size > 1) {
                Row(
                    Modifier.fillMaxWidth().padding(top = 8.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    repeat(pages.size) { i ->
                        Box(
                            Modifier
                                .padding(horizontal = 3.dp)
                                .size(width = if (i == state.currentPage) 18.dp else 6.dp, height = 6.dp)
                                .clip(RoundedCornerShape(3.dp))
                                .background(if (i == state.currentPage) accent else Color.Gray.copy(alpha = 0.3f)),
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Layout primitives

@Composable
private fun StackView(component: Component, ctx: RenderContext, vertical: Boolean) {
    val spacing = component.prop("spacing")?.decode<Dimension>()
    val gap = spacing?.let { Theme.dp(it, ctx.binding) } ?: 0.dp
    val alignment = component.prop("alignment")?.stringValue
    Primitive(component, ctx) { modifier ->
        if (vertical) {
            Column(
                modifier = modifier,
                verticalArrangement = Arrangement.spacedBy(gap),
                horizontalAlignment = horizontalAlignment(alignment),
            ) {
                component.children.forEach { ctx.registry.Render(it, ctx) }
            }
        } else {
            Row(
                modifier = modifier,
                horizontalArrangement = Arrangement.spacedBy(gap),
                verticalAlignment = verticalAlignment(alignment),
            ) {
                component.children.forEach { ctx.registry.Render(it, ctx) }
            }
        }
    }
}

@Composable
private fun ZStackView(component: Component, ctx: RenderContext) {
    Primitive(component, ctx) { modifier ->
        Box(modifier = modifier, contentAlignment = boxAlignment(component.prop("alignment")?.stringValue)) {
            component.children.forEach { ctx.registry.Render(it, ctx) }
        }
    }
}

@Composable
private fun ScrollView(component: Component, ctx: RenderContext) {
    val horizontal = component.prop("axis")?.stringValue == "horizontal"
    val child = component.prop("child")?.decode<Component>()
    Primitive(component, ctx) { modifier ->
        val scrollModifier = if (horizontal) {
            modifier.horizontalScroll(rememberScrollState())
        } else {
            modifier.verticalScroll(rememberScrollState())
        }
        // A scroll container is a single-child box; the axis modifier makes it scroll.
        Box(modifier = scrollModifier) {
            child?.let { ctx.registry.Render(it, ctx) }
        }
    }
}

@Composable
private fun ListView(component: Component, ctx: RenderContext) {
    val spacing = component.prop("spacing")?.decode<Dimension>()
    val gap = spacing?.let { Theme.dp(it, ctx.binding) } ?: 0.dp
    val itemsRef = component.prop("items")?.stringValue
    val template = component.prop("template")?.decode<Component>()

    Primitive(component, ctx) { modifier ->
        LazyColumn(
            modifier = modifier,
            verticalArrangement = Arrangement.spacedBy(gap),
        ) {
            if (itemsRef != null && template != null) {
                // Data-bound list: resolve the array and render the template once
                // per element with `$item` scoped in.
                val items = BindingEngine.resolve(itemsRef, ctx.binding).arrayValue ?: emptyList()
                itemsIndexed(items) { _, item ->
                    ctx.registry.Render(template, ctx.withItem(item))
                }
            } else {
                // Static list: render the declared children.
                val children = component.children
                itemsIndexed(children) { _, child ->
                    ctx.registry.Render(child, ctx)
                }
            }
        }
    }
}

@Composable
private fun SpacerView(component: Component, ctx: RenderContext) {
    val min = component.prop("minLength")?.decode<Dimension>()?.let { Theme.dp(it, ctx.binding) } ?: 0.dp
    // A flexible gap. Compose's Spacer has no intrinsic "flex" like SwiftUI's
    // Spacer(), so we honour minLength as a fixed size; parents drive extra flex.
    Spacer(modifier = Modifier.width(min).height(min))
}

@Composable
private fun DividerView(component: Component, ctx: RenderContext) {
    val color = Theme.color(component.prop("color")?.stringValue, ctx.binding)
    Primitive(component, ctx) { modifier ->
        if (color != null) {
            HorizontalDivider(modifier = modifier, color = color)
        } else {
            HorizontalDivider(modifier = modifier)
        }
    }
}

// MARK: - Content primitives

/** Optional value formatting (mirrors iOS `formatted`): `elapsed`/`remaining` turn a 0…1
 *  progress into a clock string, `total` = length in seconds — so a ticking `$state`
 *  reads out as `1:14` / `-2:49` instead of a raw `0.356…`. No format → the string as-is. */
private fun sduiFormat(raw: String, format: String?, total: Double): String {
    if (format == null) return raw
    val progress = raw.toDoubleOrNull() ?: 0.0
    fun clock(seconds: Double): String {
        val s = maxOf(0, Math.round(seconds).toInt())
        return "%d:%02d".format(s / 60, s % 60)
    }
    return when (format) {
        "elapsed" -> clock(progress * total)
        "remaining" -> "-" + clock(maxOf(0.0, total - progress * total))
        else -> raw
    }
}

@Composable
private fun TextView(component: Component, ctx: RenderContext) {
    val value = component.prop("value")?.stringValue ?: ""
    val text = sduiFormat(
        BindingEngine.resolveString(value, ctx.binding),
        component.prop("format")?.stringValue,
        component.prop("total")?.doubleValue ?: 0.0,
    )
    val style = Theme.textStyle(component.prop("style")?.stringValue, ctx.binding)
    val color = Theme.color(component.prop("color")?.stringValue, ctx.binding)
    val lineLimit = component.prop("lineLimit")?.doubleValue?.toInt()

    Primitive(component, ctx) { modifier ->
        Text(
            text = text,
            modifier = modifier,
            color = color ?: Color.Unspecified,
            style = style ?: androidx.compose.material3.LocalTextStyle.current,
            maxLines = lineLimit ?: Int.MAX_VALUE,
            overflow = if (lineLimit != null) TextOverflow.Ellipsis else TextOverflow.Clip,
            textAlign = textAlign(component.prop("alignment")?.stringValue),
        )
    }
}

@Composable
private fun ImageView(component: Component, ctx: RenderContext) {
    val source = BindingEngine.resolveString(component.prop("source")?.stringValue ?: "", ctx.binding)
    val loader = component.prop("loader")
    val aspectRatio = loader?.get("aspectRatio")?.doubleValue
    // `contentMode`: fill → crop to fill the frame, fit → letterbox inside it.
    val fill = (loader?.get("contentMode")?.stringValue ?: "fill") == "fill"
    val placeholder = loader?.get("placeholder")?.stringValue ?: "skeleton"
    // Round the image itself: a bare `cornerRadius` modifier does not clip on
    // Android unless a background is set, so honour it here as iOS does.
    val radius = component.modifiers?.cornerRadius?.let { Theme.dp(it, ctx.binding) } ?: 0.dp
    val shape = RoundedCornerShape(radius)

    Primitive(component, ctx) { modifier ->
        var box = modifier
        if (aspectRatio != null && aspectRatio > 0) {
            box = box.fillMaxWidth().aspectRatio(aspectRatio.toFloat())
        }
        box = box.clip(shape)
        Box(modifier = box) {
            if (source.isNotEmpty()) {
                // Coil's SubcomposeAsyncImage caches (memory + disk) so scrolling a
                // list never re-fetches or flickers — the iOS `RemoteImage` analogue.
                SubcomposeAsyncImage(
                    model = source,
                    contentDescription = null,
                    contentScale = if (fill) ContentScale.Crop else ContentScale.Fit,
                    modifier = Modifier.fillMaxSize(),
                    loading = { ImagePlaceholder(placeholder) },
                    error = { ImageFailure() },
                )
            } else {
                ImagePlaceholder(placeholder)
            }
        }
    }
}

/** The loading state for an image: shimmer skeleton, spinner or nothing. */
@Composable
private fun ImagePlaceholder(kind: String) {
    when (kind) {
        "spinner" -> Box(
            modifier = Modifier.fillMaxSize().background(Color(0f, 0f, 0f, 0.06f)),
            contentAlignment = Alignment.Center,
        ) {
            CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
        }
        "none" -> Unit
        else -> SkeletonBox()
    }
}

/** A shimmering grey skeleton — a soft highlight sweeping across a greybox. */
@Composable
private fun SkeletonBox() {
    val transition = rememberInfiniteTransition(label = "sdui-image-skeleton")
    val progress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1200, easing = LinearEasing), RepeatMode.Restart),
        label = "sdui-image-skeleton-progress",
    )
    val base = Color(0f, 0f, 0f, 0.06f)
    Box(
        modifier = Modifier.fillMaxSize().drawBehind {
            drawRect(base)
            val sweep = size.width * 0.5f
            val startX = -sweep + progress * (size.width + sweep)
            drawRect(
                brush = Brush.horizontalGradient(
                    colors = listOf(Color.Transparent, Color(1f, 1f, 1f, 0.30f), Color.Transparent),
                    startX = startX,
                    endX = startX + sweep,
                ),
            )
        },
    )
}

/** Shown when an image fails to load — a subtle greybox with a photo glyph. */
@Composable
private fun ImageFailure() {
    Box(
        modifier = Modifier.fillMaxSize().background(Color(0f, 0f, 0f, 0.08f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = Icons.Filled.Image,
            contentDescription = null,
            tint = Color(0f, 0f, 0f, 0.30f),
            modifier = Modifier.size(28.dp),
        )
    }
}

@Composable
private fun ButtonView(component: Component, ctx: RenderContext) {
    val title = BindingEngine.resolveString(component.prop("title")?.stringValue ?: "", ctx.binding)
    val styleRef = component.prop("style")?.stringValue
    val styleNode = styleRef?.let { BindingEngine.resolve(it, ctx.binding) }
    val enabled = component.prop("enabledWhen")?.decode<Condition>()?.evaluate(ctx.binding) ?: true
    val onTap = component.prop("onTap")?.decode<Action>()

    val background = Theme.color(styleNode?.get("background")?.stringValue, ctx.binding) ?: Color(0xFF0A84FF)
    val foreground = Theme.color(styleNode?.get("foreground")?.stringValue, ctx.binding) ?: Color.White
    val radius = styleNode?.get("radius")?.decode<Dimension>()?.let { Theme.dp(it, ctx.binding) } ?: 12.dp
    val paddingV = styleNode?.get("paddingV")?.decode<Dimension>()?.let { Theme.dp(it, ctx.binding) } ?: 12.dp
    val paddingH = styleNode?.get("paddingH")?.decode<Dimension>()?.let { Theme.dp(it, ctx.binding) } ?: 16.dp

    Primitive(component, ctx) { modifier ->
        androidx.compose.material3.Button(
            onClick = { onTap?.let { ctx.dispatch(it, ctx.binding) } },
            modifier = modifier,
            enabled = enabled,
            shape = RoundedCornerShape(radius),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(
                horizontal = paddingH,
                vertical = paddingV,
            ),
            colors = androidx.compose.material3.ButtonDefaults.buttonColors(
                containerColor = background,
                contentColor = foreground,
            ),
        ) {
            component.prop("icon")?.stringValue?.let { icon ->
                // The shared contract uses SF Symbol / icon names the host maps to
                // resources. Without an icon registry we surface the name as text
                // so authoring intent is visible.
                // TODO: map icon names to painterResource via a host icon registry.
                Text(BindingEngine.resolveString(icon, ctx.binding))
                Spacer(modifier = Modifier.width(6.dp))
            }
            Text(title)
        }
    }
}

// MARK: - Alignment helpers

private fun horizontalAlignment(s: String?): Alignment.Horizontal = when (s) {
    "leading" -> Alignment.Start
    "trailing" -> Alignment.End
    else -> Alignment.CenterHorizontally
}

private fun verticalAlignment(s: String?): Alignment.Vertical = when (s) {
    "top" -> Alignment.Top
    "bottom" -> Alignment.Bottom
    else -> Alignment.CenterVertically
}

private fun boxAlignment(s: String?): Alignment = when (s) {
    "topLeading" -> Alignment.TopStart
    "top" -> Alignment.TopCenter
    "topTrailing" -> Alignment.TopEnd
    "leading" -> Alignment.CenterStart
    "trailing" -> Alignment.CenterEnd
    "bottomLeading" -> Alignment.BottomStart
    "bottom" -> Alignment.BottomCenter
    "bottomTrailing" -> Alignment.BottomEnd
    else -> Alignment.Center
}

private fun textAlign(s: String?): TextAlign = when (s) {
    "center" -> TextAlign.Center
    "trailing" -> TextAlign.End
    else -> TextAlign.Start
}

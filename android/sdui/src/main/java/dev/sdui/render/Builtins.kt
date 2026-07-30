package dev.sdui.render

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
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
import androidx.compose.foundation.lazy.rememberLazyListState
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
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.zIndex
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

/** True within a `scroll` subtree, so a nested `list` renders eagerly (a Column) instead
 *  of a LazyColumn — a lazy list inside a verticalScroll crashes with an infinite-height
 *  measure. Mirrors iOS flattening a matching-axis child into the scroll. */
internal val LocalInScroll = androidx.compose.runtime.staticCompositionLocalOf { false }

/** True when the current subtree is a direct child of an `hstack`, so a `divider` renders
 *  vertically (SwiftUI's `Divider()` is axis-adaptive; parity #19). */
internal val LocalInHStack = androidx.compose.runtime.staticCompositionLocalOf { false }

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
    val helper = BindingEngine.resolveString(component.prop("helper")?.stringValue ?: "", ctx.binding)
    val secure = component.prop("secure")?.boolValue ?: false
    // status: error | success | disabled — drives isError / enabled / border colour, matching
    // the iOS TextFieldView (parity #27). keyboardType maps to the native soft keyboard.
    val status = component.prop("status")?.stringValue
    val iconName = component.prop("icon")?.stringValue
    val keyboard = when (component.prop("keyboardType")?.stringValue) {
        "email", "emailAddress" -> KeyboardType.Email
        "number", "numberPad" -> KeyboardType.Number
        "decimal", "decimalPad" -> KeyboardType.Decimal
        "phone", "phonePad" -> KeyboardType.Phone
        "url", "URL" -> KeyboardType.Uri
        else -> KeyboardType.Text
    }
    val success = Color(0xFF34C759)
    Primitive(component, ctx) { modifier ->
        androidx.compose.material3.OutlinedTextField(
            value = current,
            onValueChange = { ctx.setState?.invoke(key, JsonValue.Str(it)) },
            modifier = modifier.fillMaxWidth(),
            enabled = status != "disabled",
            isError = status == "error",
            label = if (label.isNotEmpty()) ({ Text(label) }) else null,
            placeholder = if (placeholder.isNotEmpty()) ({ Text(placeholder) }) else null,
            leadingIcon = iconName?.let { { Icon(materialIcon(it), contentDescription = null) } },
            supportingText = if (helper.isNotEmpty()) ({ Text(helper) }) else null,
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = keyboard),
            colors = if (status == "success") {
                androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = success,
                    unfocusedBorderColor = success,
                    focusedLabelColor = success,
                )
            } else {
                androidx.compose.material3.OutlinedTextFieldDefaults.colors()
            },
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
    val icon = component.prop("icon")?.stringValue
    val accent = Theme.color(component.prop("accent")?.stringValue, ctx.binding) ?: Theme.accent(ctx.binding)
    var expanded by remember(component.id) { mutableStateOf(component.prop("expanded")?.boolValue ?: false) }
    val haptic = LocalHapticFeedback.current
    val colors = androidx.compose.material3.MaterialTheme.colorScheme
    val surface = Theme.color("\$token.color.surfaceElevated", ctx.binding) ?: colors.surface
    val hairline = colors.onSurface.copy(alpha = 0.06f)
    val chevron by animateFloatAsState(if (expanded) 180f else 0f, label = "disclosure-chevron")

    // A rounded card with a hairline border, a leading accent-tinted icon tile, a rotating
    // chevron, and a header/content divider — the Android twin of the iOS DisclosureView
    // (was bare rows with a "▾/▸" glyph; parity #30).
    Primitive(component, ctx) { modifier ->
        Column(
            modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(surface)
                .border(0.5.dp, hairline, RoundedCornerShape(16.dp)),
        ) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .clickable {
                        expanded = !expanded
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    }
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (!icon.isNullOrEmpty()) {
                    Box(
                        Modifier.size(32.dp).clip(RoundedCornerShape(9.dp)).background(accent.copy(alpha = 0.14f)),
                        contentAlignment = Alignment.Center,
                    ) { Icon(materialIcon(icon), null, tint = accent, modifier = Modifier.size(17.dp)) }
                    Spacer(Modifier.width(12.dp))
                }
                Column(Modifier.weight(1f)) {
                    Text(title, fontWeight = FontWeight.SemiBold)
                    if (subtitle.isNotEmpty()) {
                        Text(subtitle, style = androidx.compose.material3.MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
                    }
                }
                Icon(
                    Icons.Filled.KeyboardArrowDown,
                    contentDescription = null,
                    tint = colors.onSurfaceVariant,
                    modifier = Modifier.graphicsLayer { rotationZ = chevron },
                )
            }
            AnimatedVisibility(visible = expanded) {
                Column {
                    HorizontalDivider(color = hairline)
                    Column(Modifier.padding(16.dp)) {
                        component.children.forEach { ctx.registry.Render(it, ctx) }
                    }
                }
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
    val accent = Theme.color("\$token.color.primary", ctx.binding) ?: Theme.accent(ctx.binding)
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

/**
 * The main-axis weight a stack child should claim, or null for an intrinsically-sized child.
 * A `spacer` is greedy (weight 1, like a SwiftUI `Spacer`); a child whose `size.<mainAxis>.mode`
 * is `"weight"` claims its `value` (default 1, e.g. two boxes at weight 1 / 2 split the row 1:2).
 * The parent applies it because Compose's `Modifier.weight` is a Row/Column-scope modifier the
 * child's own `sizeModifier` cannot reach — matching how iOS distributes `.frame` weight.
 */
private fun mainAxisWeight(child: Component, vertical: Boolean): Float? {
    if (child.type == "spacer") return 1f
    val axis = if (vertical) child.modifiers?.size?.height else child.modifiers?.size?.width
    return if (axis?.mode == "weight") (axis.value ?: 1.0).toFloat().coerceAtLeast(0.0001f) else null
}

@Composable
private fun StackView(component: Component, ctx: RenderContext, vertical: Boolean) {
    val spacing = component.prop("spacing")?.decode<Dimension>()
    // Default to 8dp — SwiftUI's implicit VStack/HStack spacing, which iOS StackView
    // inherits by passing `spacing: nil`. Android's old 0dp default made every
    // un-spaced stack render tighter than iOS across the corpus (doc 21 parity #2).
    val gap = spacing?.let { Theme.dp(it, ctx.binding) } ?: 8.dp
    val alignment = component.prop("alignment")?.stringValue
    Primitive(component, ctx) { modifier ->
        // Publish the stack axis so a nested `divider` can render across it (parity #19).
        androidx.compose.runtime.CompositionLocalProvider(LocalInHStack provides !vertical) {
            if (vertical) {
                Column(
                    modifier = modifier,
                    verticalArrangement = Arrangement.spacedBy(gap),
                    horizontalAlignment = horizontalAlignment(alignment),
                ) {
                    component.children.forEach { child ->
                        val w = mainAxisWeight(child, vertical = true)
                        if (w != null) Box(Modifier.weight(w)) { ctx.registry.Render(child, ctx) }
                        else ctx.registry.Render(child, ctx)
                    }
                }
            } else {
                Row(
                    modifier = modifier,
                    horizontalArrangement = Arrangement.spacedBy(gap),
                    verticalAlignment = verticalAlignment(alignment),
                ) {
                    component.children.forEach { child ->
                        val w = mainAxisWeight(child, vertical = false)
                        if (w != null) Box(Modifier.weight(w)) { ctx.registry.Render(child, ctx) }
                        else ctx.registry.Render(child, ctx)
                    }
                }
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
    // Apple-Weather-style collapsing hero (vertical only) — the Android twin of the iOS
    // ScrollView `collapsingHeader` path. See docs/blueprint/06-collapsing-scroll.
    val header = if (!horizontal) component.prop("collapsingHeader") else null
    if (header != null) {
        Primitive(component, ctx) { modifier -> CollapsingScrollView(header, child, ctx, modifier) }
        return
    }
    Primitive(component, ctx) { modifier ->
        val scrollModifier = if (horizontal) {
            modifier.horizontalScroll(rememberScrollState())
        } else {
            modifier.verticalScroll(rememberScrollState())
        }
        // A scroll container is a single-child box; the axis modifier makes it scroll.
        // Mark the subtree as "inside a scroll" so a nested `list` renders NON-lazily —
        // a LazyColumn inside a verticalScroll crashes ("infinite max height"). This is
        // the Compose equivalent of iOS's LazyScrollContent flattening.
        Box(modifier = scrollModifier) {
            androidx.compose.runtime.CompositionLocalProvider(LocalInScroll provides true) {
                child?.let { ctx.registry.Render(it, ctx) }
            }
        }
    }
}

/**
 * A collapsing-hero scroll — the Android counterpart of the iOS `collapsingHeader`.
 * The `expanded` hero scrolls under a pinned `compact` bar: as the first `range` points
 * scroll away it fades + shrinks slightly + parallaxes at half speed, while the compact
 * bar cross-fades in on a material surface. All collapse maths run **inside
 * `graphicsLayer`** (a deferred read of the scroll offset), so scrolling animates without
 * recomposing the tree — the perf discipline from docs/blueprint/22-mobile-techniques.
 */
@Composable
private fun CollapsingScrollView(header: JsonValue, child: Component?, ctx: RenderContext, modifier: Modifier) {
    val scroll = rememberScrollState()
    val rangePx = with(LocalDensity.current) { ((header["range"]?.doubleValue ?: 150.0).toFloat()).dp.toPx() }
    val expanded = header["expanded"]?.decode<Component>()
    val compact = header["compact"]?.decode<Component>()
    val surface = Theme.color("\$token.color.surface", ctx.binding) ?: Color.White

    Box(modifier) {
        androidx.compose.runtime.CompositionLocalProvider(LocalInScroll provides true) {
            Column(Modifier.fillMaxWidth().verticalScroll(scroll)) {
                expanded?.let {
                    Box(
                        Modifier.graphicsLayer {
                            val p = (scroll.value / rangePx).coerceIn(0f, 1f)
                            translationY = scroll.value * 0.5f   // half-speed parallax
                            alpha = 1f - p
                            val s = 1f - p * 0.12f
                            scaleX = s; scaleY = s
                        },
                    ) { ctx.registry.Render(it, ctx) }
                }
                child?.let { ctx.registry.Render(it, ctx) }
            }
        }
        // Pinned compact bar, its material surface + content cross-fading in on collapse.
        compact?.let {
            Box(
                Modifier
                    .fillMaxWidth()
                    .align(Alignment.TopStart)
                    .graphicsLayer { alpha = (scroll.value / rangePx).coerceIn(0f, 1f) }
                    .background(surface),
            ) { ctx.registry.Render(it, ctx) }
        }
    }
}

/** A stable list key — an item's `id` when present, else its index. Keeps row identity
 *  across data changes so Compose reuses rows instead of recomposing (doc 22 anti-jank). */
private fun itemKey(item: JsonValue, index: Int): Any =
    ((item as? JsonValue.Obj)?.value?.get("id") as? JsonValue.Str)?.value ?: index

/** The list's data pipeline — filter → sort → limit — mirroring the iOS ListView so a
 *  bound query/chips/amount/limit narrow the same table identically (parity #8). */
private fun listItems(component: Component, ctx: RenderContext, itemsRef: String): List<JsonValue> {
    val raw = BindingEngine.resolve(itemsRef, ctx.binding).arrayValue ?: emptyList()
    return applyListLimit(applyListSort(applyListFilter(raw, component, ctx), component, ctx), component, ctx)
}

private fun applyListFilter(items: List<JsonValue>, component: Component, ctx: RenderContext): List<JsonValue> {
    val filter = component.prop("filter") ?: return items
    var result = items
    val query = BindingEngine.resolveString(filter["query"]?.stringValue ?: "", ctx.binding).trim().lowercase()
    if (query.isNotEmpty()) {
        val fields = filter["fields"]?.arrayValue?.mapNotNull { it.stringValue } ?: emptyList()
        result = result.filter { item -> fields.any { (item[it]?.stringValue ?: "").lowercase().contains(query) } }
    }
    filter["equals"]?.let { eq ->
        val field = eq["field"]?.stringValue
        val value = BindingEngine.resolveString(eq["value"]?.stringValue ?: "", ctx.binding)
        if (field != null && value.isNotEmpty() && value.lowercase() != "all") {
            result = result.filter { (it[field]?.stringValue ?: "") == value }
        }
    }
    filter["min"]?.let { mn ->
        val field = mn["field"]?.stringValue
        val v = BindingEngine.resolveString(mn["value"]?.stringValue ?: "", ctx.binding).toDoubleOrNull()
        if (field != null && v != null && v > 0) result = result.filter { (it[field]?.doubleValue ?: 0.0) >= v }
    }
    filter["max"]?.let { mx ->
        val field = mx["field"]?.stringValue
        val v = BindingEngine.resolveString(mx["value"]?.stringValue ?: "", ctx.binding).toDoubleOrNull()
        if (field != null && v != null && v > 0) result = result.filter { (it[field]?.doubleValue ?: 0.0) <= v }
    }
    return result
}

private fun applyListSort(items: List<JsonValue>, component: Component, ctx: RenderContext): List<JsonValue> {
    val sort = component.prop("sort") ?: return items
    val by = BindingEngine.resolveString(sort["by"]?.stringValue ?: "", ctx.binding)
    if (by.isEmpty()) return items
    val desc = BindingEngine.resolveString(sort["order"]?.stringValue ?: "asc", ctx.binding) == "desc"
    // Numeric when both sides parse, else lexicographic — matching the iOS comparator.
    val cmp = Comparator<JsonValue> { a, b ->
        val ad = a[by]?.doubleValue; val bd = b[by]?.doubleValue
        if (ad != null && bd != null) ad.compareTo(bd)
        else (a[by]?.stringValue ?: "").compareTo(b[by]?.stringValue ?: "")
    }
    return if (desc) items.sortedWith(cmp.reversed()) else items.sortedWith(cmp)
}

private fun applyListLimit(items: List<JsonValue>, component: Component, ctx: RenderContext): List<JsonValue> {
    val limitProp = component.prop("limit") ?: return items
    val limit = limitProp.stringValue?.let { BindingEngine.resolveString(it, ctx.binding).toIntOrNull() }
        ?: limitProp.doubleValue?.toInt() ?: return items
    return if (limit > 0) items.take(limit) else items
}

@Composable
private fun ListView(component: Component, ctx: RenderContext) {
    val spacing = component.prop("spacing")?.decode<Dimension>()
    val gap = spacing?.let { Theme.dp(it, ctx.binding) } ?: 0.dp
    val itemsRef = component.prop("items")?.stringValue
    val template = component.prop("template")?.decode<Component>()
    val reorder = component.prop("reorder")?.boolValue == true

    // Drag-to-reorder: only when `reorder` is set AND items bind to a `$state.<key>` array
    // (the new order is written straight back to state, so it must be host-mutable) — the
    // exact contract the iOS `.onMove` path honours. See reorder.json.
    val stateKey = itemsRef?.takeIf { reorder && it.startsWith("\$state.") }?.removePrefix("\$state.")
    if (stateKey != null && template != null && !LocalInScroll.current) {
        Primitive(component, ctx) { modifier -> ReorderableList(stateKey, itemsRef, template, gap, ctx, modifier) }
        return
    }

    // An `empty` component shown when the (filtered) data list has no rows (parity #8).
    val emptyComp = component.prop("empty")?.decode<Component>()
    // Pagination: fire `onReachEnd` (or bump a `limit` binding) as the user nears the end.
    val onReachEnd = component.prop("onReachEnd")?.decode<Action>()
    val limitKey = component.prop("limit")?.stringValue?.takeIf { it.startsWith("\$state.") }?.removePrefix("\$state.")
    val paginates = (onReachEnd != null || limitKey != null) &&
        (component.prop("paginateOnScroll")?.boolValue ?: (onReachEnd != null))

    Primitive(component, ctx) { modifier ->
        if (LocalInScroll.current) {
            // Inside a scroll: render eagerly in a Column (the outer scroll handles
            // scrolling). A nested LazyColumn here would crash with infinite height.
            Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(gap)) {
                if (itemsRef != null && template != null) {
                    val items = listItems(component, ctx, itemsRef)
                    if (items.isEmpty() && emptyComp != null) ctx.registry.Render(emptyComp, ctx)
                    else items.forEach { item -> ctx.registry.Render(template, ctx.withItem(item)) }
                } else {
                    component.children.forEach { child -> ctx.registry.Render(child, ctx) }
                }
            }
        } else {
            val listState = rememberLazyListState()
            val dataItems = if (itemsRef != null && template != null) listItems(component, ctx, itemsRef) else null

            // Fire onReachEnd (or bump the limit) once per data size as the last rows appear.
            if (paginates && dataItems != null) {
                val count = dataItems.size
                LaunchedEffect(listState, count) {
                    snapshotFlow { (listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0) >= count - 3 }
                        .distinctUntilChanged()
                        .collect { nearEnd ->
                            if (nearEnd && count > 0) {
                                if (onReachEnd != null) {
                                    ctx.dispatch(onReachEnd, ctx.binding)
                                } else if (limitKey != null) {
                                    val cur = BindingEngine.resolve("\$state.$limitKey", ctx.binding).doubleValue ?: 0.0
                                    ctx.setState?.invoke(limitKey, JsonValue.Num(cur + 6))
                                }
                            }
                        }
                }
            }

            LazyColumn(
                state = listState,
                modifier = modifier,
                verticalArrangement = Arrangement.spacedBy(gap),
            ) {
                if (dataItems != null) {
                    if (dataItems.isEmpty() && emptyComp != null) {
                        item { ctx.registry.Render(emptyComp, ctx) }
                    } else {
                        // Stable keys keep row identity across data changes, so Compose reuses
                        // rows instead of recomposing the whole list (doc 22 anti-jank #1).
                        itemsIndexed(dataItems, key = { i, item -> itemKey(item, i) }) { _, item ->
                            ctx.registry.Render(template!!, ctx.withItem(item))
                        }
                    }
                } else {
                    itemsIndexed(component.children, key = { i, child -> child.id ?: i }) { _, child ->
                        ctx.registry.Render(child, ctx)
                    }
                }
            }
        }
    }
}

/**
 * A long-press-and-drag reorderable list — the Android twin of the iOS `.onMove` reorder path.
 * Rows are dragged by long-press; as the dragged row's centre crosses a neighbour the working
 * copy swaps live (so the list animates under the finger), and on release the new order is
 * written back to `$state.<stateKey>` via [RenderContext.setState] — identical semantics and
 * identical state mutation to iOS. Built on the stable `detectDragGesturesAfterLongPress` +
 * `LazyListState.layoutInfo` primitives, no third-party dependency (min-version friendly).
 */
@Composable
private fun ReorderableList(
    stateKey: String,
    itemsRef: String,
    template: Component,
    gap: androidx.compose.ui.unit.Dp,
    ctx: RenderContext,
    modifier: Modifier,
) {
    val bound = BindingEngine.resolve(itemsRef, ctx.binding).arrayValue ?: emptyList()
    // Working copy, re-synced whenever the bound array's *content* changes (e.g. Reset order).
    // JsonValue is a data class, so `remember(bound)` compares structurally and survives the
    // recompositions triggered during a drag (state itself is untouched until release).
    val work = remember(bound) { mutableStateListOf<JsonValue>().apply { addAll(bound) } }
    val listState = rememberLazyListState()
    var dragIndex by remember { mutableStateOf<Int?>(null) }
    var dragDelta by remember { mutableFloatStateOf(0f) }

    LazyColumn(
        state = listState,
        verticalArrangement = Arrangement.spacedBy(gap),
        modifier = modifier.pointerInput(Unit) {
            detectDragGesturesAfterLongPress(
                onDragStart = { off ->
                    dragDelta = 0f
                    dragIndex = listState.layoutInfo.visibleItemsInfo
                        .firstOrNull { off.y.toInt() in it.offset..(it.offset + it.size) }?.index
                },
                onDragEnd = {
                    dragIndex = null; dragDelta = 0f
                    ctx.setState?.invoke(stateKey, JsonValue.Arr(work.toList()))
                },
                onDragCancel = { dragIndex = null; dragDelta = 0f },
                onDrag = { change, amount ->
                    change.consume()
                    dragDelta += amount.y
                    val cur = dragIndex ?: return@detectDragGesturesAfterLongPress
                    val info = listState.layoutInfo.visibleItemsInfo
                    val curInfo = info.firstOrNull { it.index == cur } ?: return@detectDragGesturesAfterLongPress
                    val centre = curInfo.offset + curInfo.size / 2f + dragDelta
                    val target = info.firstOrNull {
                        it.index != cur && it.index in work.indices &&
                            centre.toInt() in it.offset..(it.offset + it.size)
                    } ?: return@detectDragGesturesAfterLongPress
                    // Live swap; keep the row under the finger by re-basing the delta onto the
                    // slot it just moved into (so it doesn't visually jump on the swap).
                    work.add(target.index, work.removeAt(cur))
                    dragDelta += curInfo.offset - target.offset
                    dragIndex = target.index
                },
            )
        },
    ) {
        itemsIndexed(work) { index, item ->
            val dragging = index == dragIndex
            Box(
                Modifier
                    .zIndex(if (dragging) 1f else 0f)
                    .graphicsLayer {
                        translationY = if (dragging) dragDelta else 0f
                        if (dragging) { scaleX = 1.03f; scaleY = 1.03f; shadowElevation = 12f }
                    },
            ) { ctx.registry.Render(template, ctx.withItem(item)) }
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
    val vertical = LocalInHStack.current
    Primitive(component, ctx) { modifier ->
        when {
            vertical && color != null -> VerticalDivider(modifier = modifier, color = color)
            vertical -> VerticalDivider(modifier = modifier)
            color != null -> HorizontalDivider(modifier = modifier, color = color)
            else -> HorizontalDivider(modifier = modifier)
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
                    model = coil.request.ImageRequest.Builder(androidx.compose.ui.platform.LocalContext.current)
                        .data(source).crossfade(true).build(),
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

    val background = Theme.color(styleNode?.get("background")?.stringValue, ctx.binding) ?: Theme.accent(ctx.binding)
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
                // Map the SF-Symbol-style name to a real Material glyph (same table as
                // IconView) — showing the raw name as text read as broken.
                Icon(
                    materialIcon(BindingEngine.resolveString(icon, ctx.binding)),
                    contentDescription = null,
                    tint = foreground,
                    modifier = Modifier.size(18.dp),
                )
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

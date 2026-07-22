package dev.sdui.render

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.background
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.sdui.core.Action
import dev.sdui.core.BindingEngine
import dev.sdui.core.Component
import dev.sdui.core.Condition
import dev.sdui.core.Dimension
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
    contextMenuHost(component.modifiers, ctx) {
        content(Modifier.sduiModifiers(component.modifiers, ctx))
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

@Composable
private fun TextView(component: Component, ctx: RenderContext) {
    val value = component.prop("value")?.stringValue ?: ""
    val text = BindingEngine.resolveString(value, ctx.binding)
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

    // No third-party image loader is bundled. We reserve the declared aspect ratio
    // with a neutral placeholder Box so lists do not jump while loading.
    // TODO: plug in an image loader (e.g. Coil) to fetch `source` when non-empty.
    Primitive(component, ctx) { modifier ->
        var box = modifier
            .clip(RoundedCornerShape(0.dp))
            .background(Color(0f, 0f, 0f, 0.06f))
        if (aspectRatio != null && aspectRatio > 0) {
            box = box.fillMaxWidth().aspectRatio(aspectRatio.toFloat())
        }
        Box(modifier = box)
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

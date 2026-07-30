package dev.sdui.render

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.sdui.core.BindingEngine
import dev.sdui.core.Component

/**
 * A vertical numbered roadmap / timeline whose steps sit on a connecting rail —
 * the "how it works" idiom. Each step is a numbered node; steps with a `detail`
 * show it beneath the title. `done: true` marks a node complete (a check on a
 * filled node). Self-contained — no `$state`. The faithful Compose port of the
 * iOS `RoadmapView` (ios/Sources/SDUIRender/Roadmap.swift).
 */
@Composable
internal fun RoadmapView(component: Component, ctx: RenderContext) {
    val accent = Theme.color(component.prop("accent")?.stringValue, ctx.binding)
        ?: Theme.accent(ctx.binding)
    val rail = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.10f)
    val steps = parseRoadmapSteps(component, ctx)

    Primitive(component, ctx) { modifier ->
        Column(modifier.fillMaxWidth()) {
            steps.forEachIndexed { i, step ->
                RoadmapRow(
                    index = i,
                    step = step,
                    isLast = i == steps.lastIndex,
                    accent = accent,
                    rail = rail,
                )
            }
        }
    }
}

private data class RoadmapStep(val title: String, val detail: String, val done: Boolean)

private fun parseRoadmapSteps(component: Component, ctx: RenderContext): List<RoadmapStep> =
    (component.prop("steps")?.arrayValue ?: emptyList()).map { item ->
        RoadmapStep(
            title = BindingEngine.resolveString(item["title"]?.stringValue ?: "", ctx.binding),
            detail = BindingEngine.resolveString(item["detail"]?.stringValue ?: "", ctx.binding),
            done = item["done"]?.boolValue ?: false,
        )
    }

@Composable
private fun RoadmapRow(
    index: Int,
    step: RoadmapStep,
    isLast: Boolean,
    accent: Color,
    rail: Color,
) {
    val hasDetail = step.detail.isNotEmpty()
    // IntrinsicSize.Min lets the connecting rail fill the row's height so it always
    // reaches the next node whatever the text length — the Compose analogue of the
    // iOS `.frame(maxHeight: .infinity)` rail inside a top-aligned HStack.
    Row(
        modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min),
        verticalAlignment = Alignment.Top,
    ) {
        Column(
            modifier = Modifier.width(30.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                modifier = Modifier
                    .size(30.dp)
                    .clip(CircleShape)
                    .background(if (step.done) accent else accent.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center,
            ) {
                if (step.done) {
                    Icon(
                        imageVector = Icons.Filled.Check,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(16.dp),
                    )
                } else {
                    Text(
                        text = "${index + 1}",
                        color = accent,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
            if (!isLast) {
                Box(
                    modifier = Modifier
                        .width(2.dp)
                        .weight(1f)
                        .background(rail),
                )
            }
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = 14.dp, top = 5.dp, bottom = if (isLast) 0.dp else 20.dp),
        ) {
            Text(
                text = step.title,
                color = MaterialTheme.colorScheme.onSurface,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
            )
            if (hasDetail) {
                Text(
                    text = step.detail,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(top = 3.dp),
                )
            }
        }
    }
}

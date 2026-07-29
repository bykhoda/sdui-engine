package dev.sdui.render

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.sdui.core.BindingEngine
import dev.sdui.core.Component
import dev.sdui.core.JsonValue

/**
 * A single-select control two-way bound to `$state.<bind>` holding the chosen
 * option's `value`. The faithful Compose port of the iOS `PickerView`
 * (ios/Sources/SDUIRender/Builtins.swift:1864): the same `{style, title, options,
 * bind}` contract renders a native menu, a segmented control, or an inline list.
 *
 * `wheel` (a UIKit idiom) falls back to the menu style on Android, exactly as the
 * iOS picker falls back to `.menu` off iOS.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PickerView(component: Component, ctx: RenderContext) {
    val key = (component.prop("bind")?.stringValue ?: "").removePrefix("\$state.")
    val title = BindingEngine.resolveString(component.prop("title")?.stringValue ?: "", ctx.binding)
    val style = component.prop("style")?.stringValue ?: "menu"

    val options = (component.prop("options")?.arrayValue ?: emptyList()).map { opt ->
        PickerOption(
            label = BindingEngine.resolveString(opt["label"]?.stringValue ?: "", ctx.binding),
            value = opt["value"]?.stringValue ?: "",
        )
    }
    val selected = BindingEngine.resolve("\$state.$key", ctx.binding).stringValue ?: ""

    fun write(value: String) {
        ctx.setState?.invoke(key, JsonValue.Str(value))
    }

    Primitive(component, ctx) { modifier ->
        when (style) {
            "segmented" -> SegmentedPicker(modifier, options, selected, ::write)
            "inline" -> InlinePicker(modifier, title, options, selected, ::write)
            else -> MenuPicker(modifier, title, options, selected, ::write) // menu + wheel
        }
    }
}

private data class PickerOption(val label: String, val value: String)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MenuPicker(
    modifier: Modifier,
    title: String,
    options: List<PickerOption>,
    selected: String,
    onSelect: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val current = options.firstOrNull { it.value == selected }?.label ?: title

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = modifier.fillMaxWidth(),
    ) {
        OutlinedTextField(
            value = current,
            onValueChange = {},
            readOnly = true,
            label = if (title.isNotEmpty()) ({ Text(title) }) else null,
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(),
        )
        androidx.compose.material3.DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            options.forEach { opt ->
                androidx.compose.material3.DropdownMenuItem(
                    text = { Text(opt.label) },
                    onClick = {
                        onSelect(opt.value)
                        expanded = false
                    },
                    trailingIcon = if (opt.value == selected) ({
                        Icon(Icons.Filled.Check, contentDescription = null)
                    }) else null,
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SegmentedPicker(
    modifier: Modifier,
    options: List<PickerOption>,
    selected: String,
    onSelect: (String) -> Unit,
) {
    if (options.isEmpty()) return
    SingleChoiceSegmentedButtonRow(modifier = modifier.fillMaxWidth()) {
        options.forEachIndexed { i, opt ->
            SegmentedButton(
                selected = opt.value == selected,
                onClick = { onSelect(opt.value) },
                shape = SegmentedButtonDefaults.itemShape(index = i, count = options.size),
            ) {
                Text(opt.label)
            }
        }
    }
}

@Composable
private fun InlinePicker(
    modifier: Modifier,
    title: String,
    options: List<PickerOption>,
    selected: String,
    onSelect: (String) -> Unit,
) {
    Column(modifier.fillMaxWidth()) {
        if (title.isNotEmpty()) {
            Text(
                text = title,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(vertical = 6.dp),
            )
        }
        options.forEach { opt ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onSelect(opt.value) }
                    .padding(vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(opt.label, color = MaterialTheme.colorScheme.onSurface)
                if (opt.value == selected) {
                    Icon(
                        imageVector = Icons.Filled.Check,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
        }
    }
}

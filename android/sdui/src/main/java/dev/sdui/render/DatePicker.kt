package dev.sdui.render

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import dev.sdui.core.BindingEngine
import dev.sdui.core.Component
import dev.sdui.core.JsonValue
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * A native date picker driven from JSON, two-way bound to a `$state` key holding
 * an ISO `yyyy-MM-dd` string — the Compose counterpart of the iOS `DatePickerView`
 * (ios/Sources/SDUIRender/Calendar.swift). `style: "graphical"` shows the inline
 * Material month calendar; `style: "compact"` shows a field that opens the picker
 * in a dialog. Each platform renders its own native picker from the same contract.
 *
 * Approximation vs iOS: the picker seeds from `$state` once (SwiftUI's `Binding`
 * is continuously live). User selections write straight back to `$state`, so the
 * common one-way-in / two-way-out flow is identical; only an external rewrite of
 * the same key mid-session is not re-reflected into the open picker.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DatePickerView(component: Component, ctx: RenderContext) {
    val key = (component.prop("bind")?.stringValue ?: "").removePrefix("\$state.")
    val tint = Theme.color(component.prop("color")?.stringValue, ctx.binding) ?: Color(0xFF0A84FF)
    val graphical = (component.prop("style")?.stringValue ?: "graphical") == "graphical"
    val current = BindingEngine.resolve("\$state.$key", ctx.binding).stringValue ?: ""

    val state = rememberDatePickerState(
        initialSelectedDateMillis = isoToMillis(current),
    )

    // Mirror the picker's selection back into $state, but never write the initial
    // seed (guarded by comparing against the value we seeded from) so appearing on
    // screen does not mutate state.
    LaunchedEffect(state.selectedDateMillis) {
        val millis = state.selectedDateMillis ?: return@LaunchedEffect
        val iso = millisToIso(millis)
        if (iso != current) ctx.setState?.invoke(key, JsonValue.Str(iso))
    }

    val colors = DatePickerDefaults.colors(
        selectedDayContainerColor = tint,
        todayDateBorderColor = tint,
        selectedYearContainerColor = tint,
    )

    Primitive(component, ctx) { modifier ->
        if (graphical) {
            DatePicker(
                state = state,
                modifier = modifier.fillMaxWidth(),
                title = null,
                headline = null,
                showModeToggle = false,
                colors = colors,
            )
        } else {
            CompactDatePicker(modifier, state, current, colors)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CompactDatePicker(
    modifier: Modifier,
    state: androidx.compose.material3.DatePickerState,
    current: String,
    colors: androidx.compose.material3.DatePickerColors,
) {
    var showDialog by remember { mutableStateOf(false) }
    OutlinedButton(onClick = { showDialog = true }, modifier = modifier) {
        Icon(
            imageVector = Icons.Filled.CalendarToday,
            contentDescription = null,
            modifier = Modifier.size(18.dp),
        )
        Text(
            text = if (current.isEmpty()) "Select a date" else prettyIso(current),
            modifier = Modifier.padding(start = 8.dp),
        )
    }
    if (showDialog) {
        DatePickerDialog(
            onDismissRequest = { showDialog = false },
            confirmButton = {
                TextButton(onClick = { showDialog = false }) { Text("Done") }
            },
            dismissButton = {
                TextButton(onClick = { showDialog = false }) { Text("Cancel") }
            },
        ) {
            DatePicker(state = state, showModeToggle = false, colors = colors)
        }
    }
}

// MARK: - ISO <-> UTC-millis helpers (Material's selectedDateMillis is UTC midnight).

private val isoFormatter: SimpleDateFormat
    get() = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

private val prettyFormatter: SimpleDateFormat
    get() = SimpleDateFormat("EEE, MMM d", Locale.getDefault()).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

private fun isoToMillis(iso: String): Long? {
    if (iso.isEmpty()) return null
    return runCatching { isoFormatter.parse(iso)?.time }.getOrNull()
}

private fun millisToIso(millis: Long): String = isoFormatter.format(java.util.Date(millis))

private fun prettyIso(iso: String): String {
    val date = runCatching { isoFormatter.parse(iso) }.getOrNull() ?: return iso
    return prettyFormatter.format(date)
}

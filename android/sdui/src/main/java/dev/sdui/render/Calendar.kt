package dev.sdui.render

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.sdui.core.BindingEngine
import dev.sdui.core.Component
import dev.sdui.core.JsonValue
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * A custom month-grid calendar driven entirely from JSON — the faithful Compose
 * port of the iOS `CalendarGridView` (ios/Sources/SDUIRender/SDUICalendar.swift).
 * The same node renders a single-day picker, a contiguous date **range**, or a
 * **multi**-day selection, chosen by the bindable `mode` prop, so a row of chips
 * can flip the calendar live.
 *
 * State contract (all ISO `yyyy-MM-dd` strings in `$state`):
 *  - single: `bind`                → the chosen day
 *  - range : `startBind`,`endBind` → range ends (either may be empty)
 *  - multi : `multiBind` (or `bind`) → comma-separated days
 *
 * All date maths runs in UTC so a day never shifts across a DST boundary and the
 * ISO strings round-trip exactly, matching the iOS gregorian/POSIX formatter.
 */
@Composable
internal fun CalendarGridView(component: Component, ctx: RenderContext) {
    val weekStartMonday = BindingEngine.resolveString(
        component.prop("weekStart")?.stringValue ?: "sunday", ctx.binding,
    ) == "monday"
    val tint = Theme.color(component.prop("color")?.stringValue, ctx.binding)
        ?: Color(0xFF5B5BF0)
    val mode = BindingEngine.resolveString(
        component.prop("mode")?.stringValue ?: "single", ctx.binding,
    )

    val singleKey = (component.prop("bind")?.stringValue ?: "").removePrefix("\$state.")
    val startKey = (component.prop("startBind")?.stringValue ?: "").removePrefix("\$state.")
    val endKey = (component.prop("endBind")?.stringValue ?: "").removePrefix("\$state.")
    val multiKey = (component.prop("multiBind")?.stringValue ?: "")
        .removePrefix("\$state.").ifEmpty { singleKey }

    fun read(key: String): String =
        if (key.isEmpty()) "" else BindingEngine.resolve("\$state.$key", ctx.binding).stringValue ?: ""
    fun write(key: String, value: String) {
        if (key.isNotEmpty()) ctx.setState?.invoke(key, JsonValue.Str(value))
    }
    fun multiDates(): List<Long> = read(multiKey).split(",").mapNotNull { isoToUtcMillis(it.trim()) }

    var visibleMonth by remember { mutableLongStateOf(utcStartOfMonth(nowUtcMidnight())) }

    // On first appear, jump to the month of the current selection (start / single /
    // first multi day), matching iOS `syncVisibleMonthToSelection`.
    LaunchedEffect(Unit) {
        val anchor = isoToUtcMillis(read(startKey))
            ?: isoToUtcMillis(read(singleKey))
            ?: multiDates().firstOrNull()
        if (anchor != null) visibleMonth = utcStartOfMonth(anchor)
    }

    val today = nowUtcMidnight()
    val monthStart = utcStartOfMonth(visibleMonth)
    val grid = buildMonthGrid(monthStart, weekStartMonday)

    fun selectionKind(dayMillis: Long): CalKind = when (mode) {
        "range" -> {
            val s = isoToUtcMillis(read(startKey))
            val e = isoToUtcMillis(read(endKey))
            when {
                s != null && e != null -> when {
                    s == e -> if (dayMillis == s) CalKind.Single else CalKind.None
                    dayMillis == s -> CalKind.RangeStart
                    dayMillis == e -> CalKind.RangeEnd
                    dayMillis in (s + 1) until e -> CalKind.RangeMiddle
                    else -> CalKind.None
                }
                s != null && dayMillis == s -> CalKind.Single
                else -> CalKind.None
            }
        }
        "multi" -> if (multiDates().any { it == dayMillis }) CalKind.Single else CalKind.None
        else -> if (isoToUtcMillis(read(singleKey)) == dayMillis) CalKind.Single else CalKind.None
    }

    fun select(dayMillis: Long) {
        val iso = utcMillisToIso(dayMillis)
        when (mode) {
            "range" -> {
                val s = read(startKey)
                val e = read(endKey)
                val startMillis = isoToUtcMillis(s)
                if (s.isEmpty() || e.isNotEmpty()) {
                    write(startKey, iso); write(endKey, "")            // begin a new range
                } else if (startMillis != null) {
                    if (dayMillis < startMillis) write(startKey, iso)  // moved before start → new start
                    else write(endKey, iso)                            // complete the range
                }
            }
            "multi" -> {
                val days = multiDates().toMutableList()
                val idx = days.indexOfFirst { it == dayMillis }
                if (idx >= 0) days.removeAt(idx) else days.add(dayMillis)
                write(multiKey, days.sorted().joinToString(",") { utcMillisToIso(it) })
            }
            else -> write(singleKey, iso)
        }
    }

    Primitive(component, ctx) { modifier ->
        Column(
            modifier = modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            CalendarSummary(mode, tint, ::read, singleKey, startKey, endKey) { multiDates().size }
            CalendarHeader(
                monthStart = monthStart,
                tint = tint,
                onPrev = { visibleMonth = addUtcMonths(visibleMonth, -1) },
                onNext = { visibleMonth = addUtcMonths(visibleMonth, 1) },
            )
            CalendarWeekdayRow(weekStartMonday)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                grid.chunked(7).forEach { week ->
                    Row(Modifier.fillMaxWidth()) {
                        week.forEach { dayMillis ->
                            Box(Modifier.weight(1f)) {
                                if (dayMillis == null) {
                                    Box(Modifier.height(44.dp))
                                } else {
                                    CalendarDayCell(
                                        dayMillis = dayMillis,
                                        isToday = dayMillis == today,
                                        kind = selectionKind(dayMillis),
                                        tint = tint,
                                        onTap = { select(dayMillis) },
                                    )
                                }
                            }
                        }
                        // Pad the final short week so cells keep an even width.
                        repeat(7 - week.size) { Box(Modifier.weight(1f)) {} }
                    }
                }
            }
        }
    }
}

private enum class CalKind { None, Single, RangeStart, RangeEnd, RangeMiddle }

@Composable
private fun CalendarSummary(
    mode: String,
    tint: Color,
    read: (String) -> String,
    singleKey: String,
    startKey: String,
    endKey: String,
    multiCount: () -> Int,
) {
    val caption: String
    val label: String
    var trailing = ""
    when (mode) {
        "range" -> {
            caption = "SELECTED RANGE"
            val s = read(startKey)
            val e = read(endKey)
            label = when {
                s.isEmpty() -> "Select dates"
                e.isEmpty() -> "${prettyShort(s)} — select end"
                else -> {
                    trailing = nightsBetween(s, e)
                    "${prettyShort(s)} – ${prettyShort(e)}"
                }
            }
        }
        "multi" -> {
            caption = "SELECTED DAYS"
            val n = multiCount()
            label = if (n == 0) "Pick any days" else "$n selected"
        }
        else -> {
            caption = "SELECTED DATE"
            val v = read(singleKey)
            label = if (v.isEmpty()) "Select a date" else prettyFull(v)
        }
    }
    Column(Modifier.fillMaxWidth()) {
        Text(
            text = caption,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 3.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = tint,
            )
            if (trailing.isNotEmpty()) {
                Text(
                    text = trailing,
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun CalendarHeader(monthStart: Long, tint: Color, onPrev: () -> Unit, onNext: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = monthTitleFormatter.format(Date(monthStart)),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            CalendarChevron(Icons.Filled.ChevronLeft, tint, onPrev)
            CalendarChevron(Icons.Filled.ChevronRight, tint, onNext)
        }
    }
}

@Composable
private fun CalendarChevron(icon: androidx.compose.ui.graphics.vector.ImageVector, tint: Color, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(34.dp)
            .clip(CircleShape)
            .background(tint.copy(alpha = 0.10f))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(imageVector = icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun CalendarWeekdayRow(weekStartMonday: Boolean) {
    val base = listOf("S", "M", "T", "W", "T", "F", "S")
    val symbols = if (weekStartMonday) base.drop(1) + base.take(1) else base
    Row(Modifier.fillMaxWidth()) {
        symbols.forEach { s ->
            Text(
                text = s,
                modifier = Modifier.weight(1f),
                textAlign = TextAlign.Center,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun CalendarDayCell(
    dayMillis: Long,
    isToday: Boolean,
    kind: CalKind,
    tint: Color,
    onTap: () -> Unit,
) {
    val onFill = kind == CalKind.Single || kind == CalKind.RangeStart || kind == CalKind.RangeEnd
    val band = tint.copy(alpha = 0.15f)
    val leftBand = if (kind == CalKind.RangeEnd || kind == CalKind.RangeMiddle) band else Color.Transparent
    val rightBand = if (kind == CalKind.RangeStart || kind == CalKind.RangeMiddle) band else Color.Transparent

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(44.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onTap,
            ),
        contentAlignment = Alignment.Center,
    ) {
        // Continuous range band: endpoints fill only their inner half, middles fill
        // full width, so with zero column spacing the halves join into one pill.
        Row(Modifier.fillMaxWidth().height(40.dp)) {
            Box(Modifier.weight(1f).fillMaxSize().background(leftBand))
            Box(Modifier.weight(1f).fillMaxSize().background(rightBand))
        }
        when {
            onFill -> Box(Modifier.size(38.dp).clip(CircleShape).background(tint))
            kind == CalKind.None && isToday ->
                Box(Modifier.size(38.dp).clip(CircleShape).border(1.5.dp, tint.copy(alpha = 0.45f), CircleShape))
        }
        Text(
            text = utcDayOfMonth(dayMillis).toString(),
            fontSize = 15.sp,
            fontWeight = if (kind == CalKind.None) FontWeight.Normal else FontWeight.SemiBold,
            color = when {
                onFill -> Color.White
                isToday && kind == CalKind.None -> tint
                else -> MaterialTheme.colorScheme.onSurface
            },
        )
    }
}

// MARK: - UTC date maths (kept off java.time so it runs on minSdk 24 without desugaring)

private const val DAY_MS = 86_400_000L

private fun utcCalendar(): Calendar =
    Calendar.getInstance(TimeZone.getTimeZone("UTC"), Locale.US)

private fun nowUtcMidnight(): Long = utcStartOfDay(System.currentTimeMillis())

private fun utcStartOfDay(millis: Long): Long {
    val c = utcCalendar()
    c.timeInMillis = millis
    c.set(Calendar.HOUR_OF_DAY, 0)
    c.set(Calendar.MINUTE, 0)
    c.set(Calendar.SECOND, 0)
    c.set(Calendar.MILLISECOND, 0)
    return c.timeInMillis
}

private fun utcStartOfMonth(millis: Long): Long {
    val c = utcCalendar()
    c.timeInMillis = utcStartOfDay(millis)
    c.set(Calendar.DAY_OF_MONTH, 1)
    return c.timeInMillis
}

private fun addUtcMonths(millis: Long, delta: Int): Long {
    val c = utcCalendar()
    c.timeInMillis = utcStartOfMonth(millis)
    c.add(Calendar.MONTH, delta)
    return c.timeInMillis
}

private fun utcDayOfMonth(millis: Long): Int {
    val c = utcCalendar()
    c.timeInMillis = millis
    return c.get(Calendar.DAY_OF_MONTH)
}

/** Leading nulls for the month's first-weekday offset, then one UTC-midnight day. */
private fun buildMonthGrid(monthStart: Long, weekStartMonday: Boolean): List<Long?> {
    val c = utcCalendar()
    c.firstDayOfWeek = if (weekStartMonday) Calendar.MONDAY else Calendar.SUNDAY
    c.timeInMillis = monthStart
    val daysInMonth = c.getActualMaximum(Calendar.DAY_OF_MONTH)
    val firstWeekdayIndex = ((c.get(Calendar.DAY_OF_WEEK) - c.firstDayOfWeek) + 7) % 7
    val leading: List<Long?> = List(firstWeekdayIndex) { null }
    val days: List<Long?> = (0 until daysInMonth).map { monthStart + it * DAY_MS }
    return leading + days
}

private val utcIsoFormatter: SimpleDateFormat
    get() = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }

private val monthTitleFormatter: SimpleDateFormat
    get() = SimpleDateFormat("LLLL yyyy", Locale.getDefault()).apply { timeZone = TimeZone.getTimeZone("UTC") }

private val shortDateFormatter: SimpleDateFormat
    get() = SimpleDateFormat("MMM d", Locale.getDefault()).apply { timeZone = TimeZone.getTimeZone("UTC") }

private val fullDateFormatter: SimpleDateFormat
    get() = SimpleDateFormat("EEE, MMM d", Locale.getDefault()).apply { timeZone = TimeZone.getTimeZone("UTC") }

private fun isoToUtcMillis(iso: String): Long? {
    if (iso.isEmpty()) return null
    return runCatching { utcIsoFormatter.parse(iso)?.time }.getOrNull()
}

private fun utcMillisToIso(millis: Long): String = utcIsoFormatter.format(Date(millis))

private fun prettyShort(iso: String): String {
    val ms = isoToUtcMillis(iso) ?: return iso
    return shortDateFormatter.format(Date(ms))
}

private fun prettyFull(iso: String): String {
    val ms = isoToUtcMillis(iso) ?: return iso
    return fullDateFormatter.format(Date(ms))
}

private fun nightsBetween(startIso: String, endIso: String): String {
    val a = isoToUtcMillis(startIso) ?: return ""
    val b = isoToUtcMillis(endIso) ?: return ""
    val n = ((b - a) / DAY_MS).toInt()
    return "$n night${if (n == 1) "" else "s"}"
}

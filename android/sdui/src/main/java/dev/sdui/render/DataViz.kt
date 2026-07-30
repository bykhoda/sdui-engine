package dev.sdui.render

import androidx.compose.animation.core.animateFloat
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.FilterNone
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.ShowChart
import androidx.compose.material.icons.filled.SmartButton
import androidx.compose.material.icons.filled.SmartDisplay
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.Widgets
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.sdui.core.BindingEngine
import dev.sdui.core.Component
import dev.sdui.core.DataSource
import dev.sdui.core.JsonValue

/**
 * Immersive + data-visualisation primitives — the Compose counterparts of the iOS
 * `GradientView`, `RingsView` and `SDUIChartView`. They render natively (Canvas /
 * Brush) from the exact same contract fields, so one JSON payload drives both
 * platforms identically. Registered by [Builtins.registerAll].
 */

// MARK: - Gradient

/** A linear-gradient fill, typically used as an immersive `zstack` background. */
@Composable
internal fun GradientView(component: Component, ctx: RenderContext) {
    val colors = (component.prop("colors")?.arrayValue ?: emptyList())
        .mapNotNull { Theme.color(it.stringValue, ctx.binding) }
    val direction = component.prop("direction")?.stringValue ?: "vertical"
    val stops = if (colors.size >= 2) colors else listOf(Color(0xFF2A6FC9), Color(0xFF7FB8E8))
    val brush: Brush = when (direction) {
        "horizontal" -> Brush.horizontalGradient(stops)
        "diagonal" -> Brush.linearGradient(stops) // 0,0 → ∞,∞ = top-left to bottom-right
        else -> Brush.verticalGradient(stops)
    }
    Primitive(component, ctx) { modifier ->
        Box(modifier = modifier.background(brush))
    }
}

// MARK: - Activity rings

/**
 * Concentric progress rings (Apple Fitness idiom). Each value in `values` (0…1)
 * draws one ring, outermost first, over a faint track of the same hue.
 */
@Composable
internal fun RingsView(component: Component, ctx: RenderContext) {
    val values = (component.prop("values")?.arrayValue ?: emptyList()).mapNotNull { it.doubleValue }
    val colors = (component.prop("colors")?.arrayValue ?: emptyList())
        .mapNotNull { Theme.color(it.stringValue, ctx.binding) }
    val lineWidth = (component.prop("lineWidth")?.doubleValue ?: 16.0).toFloat()
    val gap = (component.prop("gap")?.doubleValue ?: 6.0).toFloat()

    Primitive(component, ctx) { modifier ->
        Canvas(modifier = modifier) {
            val lw = lineWidth.dp.toPx()
            val g = gap.dp.toPx()
            val side = minOf(size.width, size.height)
            values.forEachIndexed { index, value ->
                val color = colors.getOrElse(index) { Color(0xFF0A84FF) }
                val inset = index * (lw + g) + lw / 2f
                val diameter = side - inset * 2f
                if (diameter <= 0f) return@forEachIndexed
                val topLeft = Offset((size.width - diameter) / 2f, (size.height - diameter) / 2f)
                val arcSize = Size(diameter, diameter)
                // Faint full-circle track.
                drawArc(
                    color = color.copy(alpha = 0.18f),
                    startAngle = 0f, sweepAngle = 360f, useCenter = false,
                    topLeft = topLeft, size = arcSize,
                    style = Stroke(width = lw, cap = StrokeCap.Round),
                )
                // Progress arc, clockwise from 12 o'clock.
                drawArc(
                    color = color,
                    startAngle = -90f,
                    sweepAngle = (value.coerceIn(0.0, 1.0) * 360.0).toFloat(),
                    useCenter = false,
                    topLeft = topLeft, size = arcSize,
                    style = Stroke(width = lw, cap = StrokeCap.Round),
                )
            }
        }
    }
}

// MARK: - Chart

/**
 * A line / area / bar chart drawn natively. Accepts `values` (Y plotted against
 * index) or explicit `{x,y}` `points`. Mirrors the iOS Swift-Charts renderer;
 * lines are straight here (iOS applies Catmull-Rom smoothing).
 */
@Composable
internal fun ChartView(component: Component, ctx: RenderContext) {
    val style = component.prop("style")?.stringValue ?: "line"
    val color = Theme.color(component.prop("color")?.stringValue, ctx.binding) ?: Color(0xFF0A84FF)

    val points = (component.prop("points")?.arrayValue ?: emptyList()).mapNotNull { p ->
        val x = p["x"]?.doubleValue; val y = p["y"]?.doubleValue
        if (x != null && y != null) x to y else null
    }
    val values = (component.prop("values")?.arrayValue ?: emptyList()).mapNotNull { it.doubleValue }
    val xs = if (points.isNotEmpty()) points.map { it.first } else values.indices.map { it.toDouble() }
    val ys = if (points.isNotEmpty()) points.map { it.second } else values

    Primitive(component, ctx) { modifier ->
        Canvas(modifier = modifier) {
            if (ys.isEmpty() || xs.isEmpty()) return@Canvas
            val minY = ys.minOrNull()!!; val maxY = ys.maxOrNull()!!
            val yRange = (maxY - minY).let { if (it == 0.0) 1.0 else it }
            val minX = xs.minOrNull()!!; val maxX = xs.maxOrNull()!!
            val xRange = (maxX - minX).let { if (it == 0.0) 1.0 else it }
            val pad = 4f
            fun px(x: Double) = pad + ((x - minX) / xRange).toFloat() * (size.width - pad * 2)
            fun py(y: Double) = pad + (1f - ((y - minY) / yRange).toFloat()) * (size.height - pad * 2)

            if (style == "bar") {
                val n = ys.size
                val slot = size.width / n
                val barW = slot * 0.5f
                ys.forEachIndexed { i, y ->
                    val cx = (i + 0.5f) * slot
                    val top = py(y)
                    drawRoundRect(
                        color = color,
                        topLeft = Offset(cx - barW / 2f, top),
                        size = Size(barW, size.height - top),
                        cornerRadius = CornerRadius(barW / 2f, barW / 2f),
                    )
                }
                return@Canvas
            }

            // Smooth the line with a Catmull-Rom spline expressed as cubic béziers
            // (the technique behind MPAndroidChart/Vico's cubic mode) so the curve
            // flows through every point instead of the old jagged straight segments.
            val pts = xs.mapIndexed { i, x -> Offset(px(x), py(ys[i])) }
            val line = Path()
            if (pts.isNotEmpty()) {
                line.moveTo(pts[0].x, pts[0].y)
                if (pts.size < 3) {
                    for (i in 1 until pts.size) line.lineTo(pts[i].x, pts[i].y)
                } else {
                    for (i in 0 until pts.size - 1) {
                        val p0 = pts[if (i == 0) 0 else i - 1]
                        val p1 = pts[i]
                        val p2 = pts[i + 1]
                        val p3 = pts[if (i + 2 <= pts.size - 1) i + 2 else pts.size - 1]
                        val c1 = Offset(p1.x + (p2.x - p0.x) / 6f, p1.y + (p2.y - p0.y) / 6f)
                        val c2 = Offset(p2.x - (p3.x - p1.x) / 6f, p2.y - (p3.y - p1.y) / 6f)
                        line.cubicTo(c1.x, c1.y, c2.x, c2.y, p2.x, p2.y)
                    }
                }
            }
            if (style == "area") {
                val fill = Path().apply {
                    addPath(line)
                    lineTo(px(xs.last()), size.height)
                    lineTo(px(xs.first()), size.height)
                    close()
                }
                drawPath(fill, Brush.verticalGradient(listOf(color.copy(alpha = 0.35f), color.copy(alpha = 0f))))
            }
            drawPath(line, color, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
        }
    }
}

// MARK: - Icon

/**
 * Renders a named symbol. The contract uses SF Symbol names; on Android the host
 * maps them to resources via an icon registry. Absent that, we surface the name
 * as text so authoring intent stays visible — the same fallback [ButtonView] uses.
 */
// Maps an SF-Symbol-style contract icon name to a Material icon, so the same
// JSON that draws SF Symbols on iOS draws real glyphs on Android (not the name
// as text). A host `iconResolver` still wins when provided.
// Maps Apple SF Symbol names (the contract's icon vocabulary, authored against the iOS
// reference) to the closest Material icon. Covers everything the shipped content uses;
// the family-strip (".fill" etc.) folds to one Material glyph. Unknown names fall back to
// a neutral dot — never the old four-square "widgets" glyph that read as broken.
internal fun materialIcon(sf: String): ImageVector = when (sf) {
    // playback / media
    "play.fill", "play.circle.fill", "play.rectangle.fill" -> Icons.Filled.PlayArrow
    "pause.fill", "pause.circle.fill" -> Icons.Filled.Pause
    "backward.fill", "backward.end.fill" -> Icons.Filled.SkipPrevious
    "forward.fill", "forward.end.fill" -> Icons.Filled.SkipNext
    "shuffle" -> Icons.Filled.Shuffle
    "repeat", "repeat.1" -> Icons.Filled.Repeat
    "speaker.fill", "speaker.wave.1.fill", "speaker.wave.2.fill", "speaker.wave.3.fill" -> Icons.Filled.VolumeUp
    "speaker.slash.fill" -> Icons.Filled.VolumeOff
    "music.note", "music.note.list" -> Icons.Filled.MusicNote
    "film.fill" -> Icons.Filled.Movie
    // hearts / stars / ratings
    "heart" -> Icons.Filled.FavoriteBorder
    "heart.fill" -> Icons.Filled.Favorite
    "star" -> Icons.Filled.StarBorder
    "star.fill" -> Icons.Filled.Star
    "star.leadinghalf.filled" -> Icons.Filled.StarHalf
    // checks / marks / close
    "checkmark", "checkmark.seal", "checkmark.seal.fill" -> Icons.Filled.Check
    "checkmark.circle.fill" -> Icons.Filled.CheckCircle
    "xmark" -> Icons.Filled.Close
    "xmark.circle.fill" -> Icons.Filled.Cancel
    "plus" -> Icons.Filled.Add
    "plus.circle.fill" -> Icons.Filled.AddCircle
    "minus.circle.fill" -> Icons.Filled.RemoveCircle
    // people / comms
    "person", "person.fill", "person.crop.circle" -> Icons.Filled.Person
    "person.2.fill" -> Icons.Filled.Group
    "person.crop.circle.badge.plus" -> Icons.Filled.PersonAdd
    "person.crop.circle.badge.questionmark" -> Icons.Filled.PersonSearch
    "phone", "phone.fill" -> Icons.Filled.Call
    "message", "message.fill" -> Icons.Filled.ChatBubble
    "bubble.left.and.bubble.right.fill", "exclamationmark.bubble.fill" -> Icons.Filled.Forum
    "envelope" -> Icons.Filled.Email
    "envelope.open.fill" -> Icons.Filled.Drafts
    "paperplane.fill", "paperplane" -> Icons.Filled.Send
    "bell.fill" -> Icons.Filled.Notifications
    "bell.badge.fill" -> Icons.Filled.NotificationsActive
    "bell.slash.fill" -> Icons.Filled.NotificationsOff
    "hand.thumbsup.fill" -> Icons.Filled.ThumbUp
    "hand.raised.slash.fill" -> Icons.Filled.PanToolAlt
    // nav / chevrons / arrows
    "chevron.right" -> Icons.Filled.ChevronRight
    "chevron.left" -> Icons.Filled.ChevronLeft
    "ellipsis" -> Icons.Filled.MoreHoriz
    "line.3.horizontal" -> Icons.Filled.Menu
    "magnifyingglass" -> Icons.Filled.Search
    "arrow.up" -> Icons.Filled.ArrowUpward
    "arrow.down" -> Icons.Filled.ArrowDownward
    "arrow.up.arrow.down" -> Icons.Filled.SwapVert
    "arrow.left.arrow.right" -> Icons.Filled.SwapHoriz
    "arrow.counterclockwise", "arrow.triangle.2.circlepath" -> Icons.Filled.Autorenew
    "arrow.up.left.and.arrow.down.right" -> Icons.Filled.OpenInFull
    "arrow.down.right.and.arrow.up.left" -> Icons.Filled.CloseFullscreen
    "arrow.up.circle.fill" -> Icons.Filled.ArrowCircleUp
    "arrow.down.circle.fill" -> Icons.Filled.ArrowCircleDown
    "arrow.up.doc.fill", "square.and.arrow.up" -> Icons.Filled.UploadFile
    "square.and.arrow.down" -> Icons.Filled.Download
    "arrowshape.turn.up.left" -> Icons.Filled.Reply
    "arrow.triangle.branch" -> Icons.Filled.CallSplit
    // status / system
    "wifi" -> Icons.Filled.Wifi
    "wifi.slash" -> Icons.Filled.WifiOff
    "lock", "lock.fill" -> Icons.Filled.Lock
    "lock.open.fill" -> Icons.Filled.LockOpen
    "bolt.fill" -> Icons.Filled.Bolt
    "bolt.shield.fill" -> Icons.Filled.Security
    "flame.fill" -> Icons.Filled.LocalFireDepartment
    "leaf.fill" -> Icons.Filled.Eco
    "drop.fill" -> Icons.Filled.WaterDrop
    "gift.fill" -> Icons.Filled.CardGiftcard
    "crown.fill" -> Icons.Filled.WorkspacePremium
    "flag.fill" -> Icons.Filled.Flag
    "pin.fill" -> Icons.Filled.PushPin
    "bookmark.fill" -> Icons.Filled.Bookmark
    "tag.fill" -> Icons.Filled.Sell
    "bag.fill" -> Icons.Filled.ShoppingBag
    "cart.fill" -> Icons.Filled.ShoppingCart
    "archivebox.fill" -> Icons.Filled.Archive
    "tray.fill" -> Icons.Filled.Inbox
    "trash", "trash.fill" -> Icons.Filled.Delete
    "map" -> Icons.Filled.Map
    "safari" -> Icons.Filled.Public
    "link" -> Icons.Filled.Link
    "qrcode" -> Icons.Filled.QrCode2
    "apple.logo" -> Icons.Filled.PhoneIphone
    "dollarsign.circle" -> Icons.Filled.MonetizationOn
    // docs / files / photos
    "doc.fill", "doc.text.fill", "doc.richtext.fill" -> Icons.Filled.Description
    "doc.on.doc" -> Icons.Filled.FileCopy
    "photo.fill" -> Icons.Filled.Photo
    "photo.on.rectangle.angled" -> Icons.Filled.PhotoLibrary
    "square.on.square" -> Icons.Filled.FilterNone
    "square.stack.fill", "rectangle.stack.fill" -> Icons.Filled.Layers
    "tablecells.fill" -> Icons.Filled.TableChart
    "calendar" -> Icons.Filled.CalendarMonth
    // tools / editing
    "pencil" -> Icons.Filled.Edit
    "pencil.and.ruler.fill" -> Icons.Filled.DesignServices
    "hammer.fill" -> Icons.Filled.Build
    "slider.horizontal.3", "switch.2" -> Icons.Filled.Tune
    "textformat", "character.cursor.ibeam" -> Icons.Filled.TextFields
    "capsule.fill" -> Icons.Filled.SmartButton
    "cursorarrow.rays", "hand.draw.fill", "hand.tap.fill" -> Icons.Filled.TouchApp
    "wand.and.stars", "wand.and.rays", "sparkles" -> Icons.Filled.AutoAwesome
    "paintpalette", "paintpalette.fill" -> Icons.Filled.Palette
    "gearshape.fill" -> Icons.Filled.Settings
    "door.left.hand.closed", "rectangle.portrait.and.arrow.right" -> Icons.Filled.Logout
    "rectangle.portrait.bottomhalf.inset.filled" -> Icons.Filled.Wallpaper
    // numbered / misc from earlier
    "1.circle.fill" -> Icons.Filled.LooksOne
    "2.circle.fill" -> Icons.Filled.LooksTwo
    "3.circle.fill" -> Icons.Filled.Looks3
    "square.grid.2x2.fill", "square.grid.3x3.fill" -> Icons.Filled.GridView
    "figure.run" -> Icons.Filled.DirectionsRun
    "chart.line.uptrend.xyaxis" -> Icons.Filled.ShowChart
    "cloud.sun.fill" -> Icons.Filled.WbSunny
    "checklist", "list.bullet" -> Icons.Filled.Checklist
    "shippingbox.fill" -> Icons.Filled.Inventory2
    "dumbbell.fill" -> Icons.Filled.FitnessCenter
    else -> Icons.Filled.Circle
}

@Composable
internal fun IconView(component: Component, ctx: RenderContext) {
    val name = BindingEngine.resolveString(component.prop("name")?.stringValue ?: "", ctx.binding)
    val color = Theme.color(component.prop("color")?.stringValue, ctx.binding)
    val size = component.prop("size")?.doubleValue
    Primitive(component, ctx) { modifier ->
        val sized = if (size != null) modifier.size(size.dp) else modifier
        val painter = ctx.iconResolver?.invoke(name)
        if (painter != null) {
            androidx.compose.foundation.Image(painter = painter, contentDescription = name, modifier = sized)
        } else {
            Icon(
                imageVector = materialIcon(name),
                contentDescription = name,
                tint = color ?: LocalContentColor.current,
                modifier = sized,
            )
        }
    }
}

// MARK: - Spinner

/** A native circular activity indicator; use it in an `async` loading slot. */
@Composable
internal fun SpinnerView(component: Component, ctx: RenderContext) {
    val tint = Theme.color(component.prop("color")?.stringValue, ctx.binding)
    val scale = (component.prop("scale")?.doubleValue ?: 1.0).toFloat()
    Primitive(component, ctx) { modifier ->
        val m = if (scale != 1f) modifier.scale(scale) else modifier
        if (tint != null) CircularProgressIndicator(modifier = m, color = tint)
        else CircularProgressIndicator(modifier = m)
    }
}

// MARK: - Async (fetch-then-render)

/**
 * Fetch-then-render container — the declarative "loading component" and the
 * Compose counterpart of the iOS `AsyncView`. Declares one data `source`; shows
 * the `loading` slot (a spinner by default) while the request is in flight, then
 * renders `content` with the response bound as `$data.<source.id>` — or the
 * `error` slot on failure.
 */
@Composable
internal fun AsyncView(component: Component, ctx: RenderContext) {
    val source = remember(component) { component.prop("source")?.decode<DataSource>() }
    // 0 = loading, 1 = loaded, 2 = failed.
    var phase by remember(source) { mutableStateOf(0) }
    var value by remember(source) { mutableStateOf<JsonValue?>(null) }

    LaunchedEffect(source) {
        val load = ctx.loadSource
        if (source == null || load == null) { phase = 2; return@LaunchedEffect }
        phase = 0
        val fetched = load(source)
        if (fetched != null) { value = fetched; phase = 1 } else { phase = 2 }
    }

    Primitive(component, ctx) { modifier ->
        Box(modifier = modifier) {
            when (phase) {
                1 -> {
                    val content = component.prop("content")?.decode<Component>()
                    val v = value
                    if (content != null && source != null && v != null) {
                        ctx.registry.Render(content, ctx.copy(binding = ctx.binding.withData(source.id, v)))
                    }
                }
                2 -> {
                    val err = component.prop("error")?.decode<Component>()
                    if (err != null) ctx.registry.Render(err, ctx) else DefaultAsyncError()
                }
                else -> {
                    val loading = component.prop("loading")?.decode<Component>()
                    if (loading != null) ctx.registry.Render(loading, ctx) else DefaultAsyncSpinner()
                }
            }
        }
    }
}

@Composable
private fun DefaultAsyncSpinner() {
    Column(
        modifier = Modifier.fillMaxWidth().height(120.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) { CircularProgressIndicator() }
}

@Composable
private fun DefaultAsyncError() {
    Column(
        modifier = Modifier.fillMaxWidth().height(120.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) { Text("Couldn't load content") }
}

// MARK: - Progress bar

/**
 * A slim rounded progress bar — the Compose counterpart of the iOS
 * `ProgressBarView`. Determinate (`value` 0…1) fills; indeterminate (no `value`)
 * runs a light sweep. Drawn on Canvas so it is version-agnostic and matches iOS.
 */
@Composable
internal fun ProgressBarView(component: Component, ctx: RenderContext) {
    val tint = Theme.color(component.prop("color")?.stringValue, ctx.binding) ?: Color(0xFF0A84FF)
    val height = (component.prop("height")?.doubleValue ?: 6.0)
    val value = component.prop("value")?.let { raw ->
        val s = raw.stringValue
        if (s != null && s.startsWith("$")) BindingEngine.resolve(s, ctx.binding).doubleValue else raw.doubleValue
    }
    val transition = androidx.compose.animation.core.rememberInfiniteTransition(label = "progress")
    val phase by transition.animateFloat(
        initialValue = 0f, targetValue = 1f,
        animationSpec = androidx.compose.animation.core.infiniteRepeatable(
            animation = androidx.compose.animation.core.tween(1100),
            repeatMode = androidx.compose.animation.core.RepeatMode.Restart,
        ),
        label = "phase",
    )
    Primitive(component, ctx) { modifier ->
        Canvas(modifier = modifier.fillMaxWidth().height(height.dp)) {
            val r = size.height / 2f
            drawRoundRect(tint.copy(alpha = 0.16f), cornerRadius = CornerRadius(r, r))
            if (value != null) {
                drawRoundRect(
                    color = tint,
                    size = Size((value.coerceIn(0.0, 1.0)).toFloat() * size.width, size.height),
                    cornerRadius = CornerRadius(r, r),
                )
            } else {
                val bw = size.width * 0.4f
                val x = -bw + phase * (size.width + bw)
                drawRoundRect(
                    color = tint,
                    topLeft = Offset(x, 0f),
                    size = Size(bw, size.height),
                    cornerRadius = CornerRadius(r, r),
                )
            }
        }
    }
}

// MARK: - Slider

/**
 * A draggable continuous control (0…1), two-way bound to `$state.<bind>` — the
 * Compose counterpart of the iOS `SliderView`. Thin track + fill + optional thumb;
 * dragging writes the new value back into state via [RenderContext.setState].
 */
@Composable
internal fun SliderView(component: Component, ctx: RenderContext) {
    val key = component.prop("bind")?.stringValue ?: ""
    val tint = Theme.color(component.prop("color")?.stringValue, ctx.binding) ?: Color(0xFF0A84FF)
    val trackH = (component.prop("height")?.doubleValue ?: 6.0)
    val thumb = component.prop("thumb")?.boolValue ?: true
    val value = (BindingEngine.resolve("\$state.$key", ctx.binding).doubleValue ?: 0.0).coerceIn(0.0, 1.0)
    val rowH = trackH + if (thumb) 8.0 else 0.0

    fun write(fraction: Float) {
        ctx.setState?.invoke(key, JsonValue.Num(fraction.coerceIn(0f, 1f).toDouble()))
    }

    Primitive(component, ctx) { modifier ->
        Canvas(
            modifier = modifier
                .fillMaxWidth()
                .height(rowH.dp)
                .pointerInput(key) {
                    detectHorizontalDragGestures { change, _ ->
                        write((change.position.x / size.width))
                    }
                }
                .pointerInput(key) {
                    detectTapGestures { pos -> write(pos.x / size.width) }
                },
        ) {
            val h = trackH.dp.toPx()
            val cy = size.height / 2f
            val r = h / 2f
            drawRoundRect(
                color = tint.copy(alpha = 0.22f),
                topLeft = Offset(0f, cy - r), size = Size(size.width, h),
                cornerRadius = CornerRadius(r, r),
            )
            drawRoundRect(
                color = tint,
                topLeft = Offset(0f, cy - r), size = Size((value.toFloat()) * size.width, h),
                cornerRadius = CornerRadius(r, r),
            )
            if (thumb) {
                val td = h + 8f
                val cx = (value.toFloat() * size.width).coerceIn(td / 2f, size.width - td / 2f)
                drawCircle(color = Color.White, radius = td / 2f, center = Offset(cx, cy))
            }
        }
    }
}

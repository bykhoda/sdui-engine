package dev.sdui.render

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.text.format.Formatter
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.FolderZip
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.sdui.core.BindingEngine
import dev.sdui.core.Component

/**
 * A rich document/upload cell with the full uploader state set — the Compose port
 * of the iOS `FileCellView` (ios/Sources/SDUIRender/FileCell.swift): empty →
 * loading → success / too-large / failed. Tapping an empty cell opens the system
 * document picker; a picked file shows its icon, name and size with a "View"
 * action and a trash button.
 *
 * The contract can also pin a **fixed** `state` (`success` / `loading` /
 * `warning` / `error` / `empty`) with `title` + `size`, so a screen can lay out the
 * whole state catalogue without touching the picker — matching the iOS showcase.
 */
private enum class FilePhase { Empty, Loading, Success, Warning, Error }

private data class PickedFile(val name: String, val ext: String, val bytes: Long, val uri: Uri?)

@Composable
internal fun FileCellView(component: Component, ctx: RenderContext) {
    val context = LocalContext.current
    val tint = Theme.color(component.prop("color")?.stringValue, ctx.binding) ?: Theme.accent(ctx.binding)
    val maxKB = component.prop("maxSizeKB")?.doubleValue

    // A pinned showcase state, if the contract fixes one (otherwise interactive).
    val fixedPhase = when (component.prop("state")?.stringValue) {
        "loading" -> FilePhase.Loading
        "success" -> FilePhase.Success
        "warning", "tooLarge" -> FilePhase.Warning
        "error", "failed" -> FilePhase.Error
        "empty" -> FilePhase.Empty
        else -> null
    }
    val isShowcase = fixedPhase != null

    var picked by remember(component.id) { mutableStateOf<PickedFile?>(null) }
    var phase by remember(component.id) { mutableStateOf(FilePhase.Empty) }
    var message by remember(component.id) { mutableStateOf<String?>(null) }
    var loadingToken by remember(component.id) { mutableStateOf(0) }

    // A brief "uploading" phase after a valid pick, so the loading state is real.
    LaunchedEffect(loadingToken) {
        if (loadingToken == 0) return@LaunchedEffect
        kotlinx.coroutines.delay(1_100)
        if (phase == FilePhase.Loading) phase = FilePhase.Success
    }

    val currentPhase = fixedPhase ?: phase

    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val (name, bytes) = queryNameAndSize(context, uri)
        val ext = name.substringAfterLast('.', "").uppercase()
        if (maxKB != null && bytes > maxKB * 1024) {
            picked = PickedFile(name, ext, bytes, null)
            message = "Attach a file no larger than ${(maxKB / 1024).toInt()} MB"
            phase = FilePhase.Warning
            return@rememberLauncherForActivityResult
        }
        picked = PickedFile(name, ext, bytes, uri)
        message = null
        phase = FilePhase.Loading
        loadingToken += 1
    }

    // Derived display values (a picked file wins over the contract's fixed labels).
    val fileName = picked?.name ?: component.prop("title")?.stringValue ?: "File.pdf"
    val fileSize = picked?.let { formatBytes(context, it.bytes) }
        ?: component.prop("size")?.stringValue ?: ""
    val fileExt = picked?.ext
        ?: component.prop("title")?.stringValue?.substringAfterLast('.', "")?.uppercase() ?: ""
    val viewLabel = component.prop("viewLabel")?.stringValue ?: "View"
    val warningText = message
        ?: component.prop("limitText")?.stringValue
        ?: maxKB?.let { "Attach a file no larger than ${(it / 1024).toInt()} MB" }
        ?: "File is too large"
    val errorText = message ?: component.prop("errorText")?.stringValue ?: "Upload failed"

    fun remove() {
        if (isShowcase) return
        picked = null; message = null; phase = FilePhase.Empty
    }

    fun openPreview() {
        val uri = picked?.uri ?: return
        runCatching {
            val view = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, context.contentResolver.getType(uri) ?: "*/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(view)
        }
    }

    Primitive(component, ctx) { modifier ->
        Box(modifier.fillMaxWidth()) {
            when (currentPhase) {
                FilePhase.Empty -> EmptyFileCell(
                    tint = tint,
                    title = component.prop("title")?.stringValue ?: "Choose a file",
                    subtitle = maxKB?.let { "Max ${(it / 1024).toInt()} MB" } ?: "From Files or Drive",
                    onClick = { if (!isShowcase) launcher.launch("*/*") },
                )
                FilePhase.Loading -> LoadingFileCell()
                FilePhase.Success -> FileRow(
                    leadingIcon = iconFor(fileExt),
                    leadingTint = MaterialTheme.colorScheme.onSurfaceVariant,
                    name = fileName,
                    size = fileSize,
                    onRemove = ::remove,
                ) {
                    Text(
                        text = viewLabel,
                        color = tint,
                        fontWeight = FontWeight.SemiBold,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier
                            .padding(top = 2.dp)
                            .clickable { openPreview() },
                    )
                }
                FilePhase.Warning -> FileRow(
                    leadingIcon = Icons.Filled.Warning,
                    leadingTint = WARNING_TONE,
                    name = fileName,
                    size = fileSize,
                    onRemove = ::remove,
                ) {
                    Text(warningText, color = WARNING_TONE, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 2.dp))
                }
                FilePhase.Error -> FileRow(
                    leadingIcon = Icons.Filled.Cancel,
                    leadingTint = ERROR_TONE,
                    name = fileName,
                    size = fileSize,
                    onRemove = ::remove,
                ) {
                    Text(errorText, color = ERROR_TONE, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 2.dp))
                }
            }
        }
    }
}

private val WARNING_TONE = Color(0xFFF08C00)
private val ERROR_TONE = Color(0xFFE5484D)

@Composable
private fun EmptyFileCell(tint: Color, title: String, subtitle: String, onClick: () -> Unit) {
    val stroke = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.14f)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .dashedRoundedBorder(stroke, 16.dp)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(28.dp), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.UploadFile, contentDescription = null, tint = tint, modifier = Modifier.size(22.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
        }
        Icon(Icons.Filled.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun LoadingFileCell() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(cardColor(), RoundedCornerShape(16.dp))
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(9.dp)) {
            ShimmerBar(width = 190.dp)
            ShimmerBar(width = 120.dp)
        }
    }
}

@Composable
private fun FileRow(
    leadingIcon: ImageVector,
    leadingTint: Color,
    name: String,
    size: String,
    onRemove: () -> Unit,
    status: @Composable () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(cardColor(), RoundedCornerShape(16.dp))
            .padding(16.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(Modifier.size(28.dp), contentAlignment = Alignment.Center) {
            Icon(leadingIcon, contentDescription = null, tint = leadingTint, modifier = Modifier.size(24.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(
                text = name,
                color = MaterialTheme.colorScheme.onSurface,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (size.isNotEmpty()) {
                Text(size, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
            }
            status()
        }
        Icon(
            imageVector = Icons.Filled.Delete,
            contentDescription = "Remove",
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .size(24.dp)
                .clickable(onClick = onRemove),
        )
    }
}

@Composable
private fun ShimmerBar(width: androidx.compose.ui.unit.Dp) {
    val transition = rememberInfiniteTransition(label = "sdui-file-shimmer")
    val progress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1200, easing = LinearEasing), RepeatMode.Restart),
        label = "sdui-file-shimmer-progress",
    )
    val base = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)
    Box(
        modifier = Modifier
            .width(width)
            .height(12.dp)
            .drawBehind {
                drawRoundRect(color = base, cornerRadius = CornerRadius(6f, 6f))
                val sweep = size.width * 0.5f
                val startX = -sweep + progress * (size.width + sweep)
                drawRoundRect(
                    brush = androidx.compose.ui.graphics.Brush.horizontalGradient(
                        colors = listOf(Color.Transparent, Color(1f, 1f, 1f, 0.25f), Color.Transparent),
                        startX = startX,
                        endX = startX + sweep,
                    ),
                    cornerRadius = CornerRadius(6f, 6f),
                )
            },
    )
}

@Composable
private fun cardColor(): Color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f)

/** A dashed rounded stroke — the drop-zone affordance of the empty state. */
private fun Modifier.dashedRoundedBorder(color: Color, radius: androidx.compose.ui.unit.Dp): Modifier =
    drawBehind {
        val r = radius.toPx()
        drawRoundRect(
            color = color,
            size = Size(size.width, size.height),
            cornerRadius = CornerRadius(r, r),
            style = Stroke(
                width = 1.5.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 4.dp.toPx()), 0f),
            ),
        )
    }

private fun iconFor(ext: String): ImageVector = when (ext.lowercase()) {
    "pdf" -> Icons.Filled.PictureAsPdf
    "png", "jpg", "jpeg", "heic", "gif", "webp" -> Icons.Filled.Image
    "mp4", "mov", "m4v" -> Icons.Filled.Movie
    "zip", "rar", "7z" -> Icons.Filled.FolderZip
    "json", "txt", "md", "csv" -> Icons.Filled.Description
    else -> Icons.AutoMirrored.Filled.InsertDriveFile
}

/** Reads the display name and byte size of a content Uri via the resolver. */
private fun queryNameAndSize(context: android.content.Context, uri: Uri): Pair<String, Long> {
    var name = uri.lastPathSegment ?: "file"
    var size = 0L
    runCatching {
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (cursor.moveToFirst()) {
                if (nameIdx >= 0) cursor.getString(nameIdx)?.let { name = it }
                if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) size = cursor.getLong(sizeIdx)
            }
        }
    }
    return name to size
}

private fun formatBytes(context: android.content.Context, bytes: Long): String =
    if (bytes <= 0) "" else Formatter.formatShortFileSize(context, bytes)

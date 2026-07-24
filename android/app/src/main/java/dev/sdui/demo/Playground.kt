package dev.sdui.demo

import android.content.res.AssetManager
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.sdui.core.JsonValue
import dev.sdui.core.SduiDocument
import dev.sdui.core.SduiParser
import dev.sdui.render.SduiHostDelegate
import dev.sdui.render.SduiScreen

// ── Catalog model (parsed from the shared content/catalog.json) ─────────────

private data class CatalogEntry(val id: String, val subtitle: String)
private data class Category(val name: String, val colors: List<String>, val screens: List<CatalogEntry>)

/** Everything the playground needs, loaded once from the bundled assets. */
private class Playground(
    val categories: List<Category>,
    val screensById: Map<String, SduiDocument>,
    val tokens: JsonValue,
)

/**
 * Loads the SAME catalog + screens + tokens the iOS demo bundles, from the assets
 * synced by the `syncPlaygroundContent` Gradle task. Anything that fails to parse
 * is skipped, never fatal — the catalog degrades gracefully.
 */
private fun loadPlayground(assets: AssetManager): Playground {
    fun read(path: String): String? =
        runCatching { assets.open(path).bufferedReader().use { it.readText() } }.getOrNull()
    fun parseValue(json: String): JsonValue? =
        runCatching { JsonValue.CODEC.decodeFromString(JsonValue.serializer(), json) }.getOrNull()

    val tokens = read("content/tokens.json")?.let { parseValue(it) } ?: JsonValue.Obj(emptyMap())

    val screensById = LinkedHashMap<String, SduiDocument>()
    for (dir in listOf("content/screens", "content/nav")) {
        val files = runCatching { assets.list(dir)?.toList() }.getOrNull() ?: emptyList()
        for (name in files.filter { it.endsWith(".json") }) {
            val doc = read("$dir/$name")?.let { SduiParser.decodeOrNull(it) } ?: continue
            screensById[doc.screen.id] = doc
        }
    }

    val catalog = read("content/catalog.json")?.let { parseValue(it) }
    return Playground(parseCategories(catalog), screensById, tokens)
}

private fun parseCategories(catalog: JsonValue?): List<Category> {
    val cats = catalog?.get("categories")?.arrayValue ?: return emptyList()
    return cats.mapNotNull { c ->
        val name = c["name"]?.stringValue ?: return@mapNotNull null
        val colors = c["colors"]?.arrayValue?.mapNotNull { it.stringValue } ?: emptyList()
        val entries = c["screens"]?.arrayValue?.mapNotNull { s ->
            val id = s["id"]?.stringValue ?: return@mapNotNull null
            CatalogEntry(id, s["subtitle"]?.stringValue ?: "")
        } ?: emptyList()
        Category(name, colors, entries)
    }
}

// ── Navigation host: `navigate` between bundled screens by id ────────────────

private class PlaygroundHost(
    private val known: Set<String>,
    private val push: (String) -> Unit,
) : SduiHostDelegate {
    override fun navigate(screen: String, params: Map<String, JsonValue>, transition: String) {
        if (screen in known) push(screen)
    }
}

// ── UI ───────────────────────────────────────────────────────────────────────

@Composable
fun PlaygroundApp() {
    val context = LocalContext.current
    val playground = remember { loadPlayground(context.assets) }
    val dark = isSystemInDarkTheme()
    val env = remember(dark) {
        mapOf(
            "locale" to JsonValue.Str("en"),
            "theme" to JsonValue.Str(if (dark) "dark" else "light"),
            "platform" to JsonValue.Str("android"),
        )
    }

    // A minimal push/pop stack: empty = root catalog, otherwise the top is the
    // currently-shown screen id. Mirrors the iOS catalog's two-level navigation.
    // The chrome is itself a server-driven screen: root at `home` (generated from
    // catalog.json), rendered by the SAME engine as every other screen — so the
    // whole app looks identical to iOS/Aurora. `navigate` pushes onto the stack.
    val stack = remember { mutableStateListOf("home") }
    val host = remember(playground) { PlaygroundHost(playground.screensById.keys) { stack.add(it) } }

    MaterialTheme(colorScheme = if (dark) darkColorScheme() else lightColorScheme()) {
        Surface(Modifier.fillMaxSize()) {
            val currentId = stack.lastOrNull() ?: "home"
            val doc = playground.screensById[currentId]
            Column(Modifier.fillMaxSize()) {
                // A back affordance only once we've navigated past the home root.
                if (stack.size > 1) {
                    NavBar(
                        title = doc?.screen?.title ?: currentId,
                        onBack = { stack.removeAt(stack.lastIndex) },
                    )
                }
                Box(Modifier.fillMaxWidth().weight(1f)) {
                    if (doc != null) {
                        SduiScreen(document = doc, tokens = playground.tokens, env = env, delegate = host)
                    } else {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            Text("Screen \"$currentId\" is not bundled")
                        }
                    }
                }
            }
            BackHandler(enabled = stack.size > 1) { stack.removeAt(stack.lastIndex) }
        }
    }
}

@Composable
private fun NavBar(title: String, onBack: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .padding(horizontal = 12.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "‹  Back",
            color = MaterialTheme.colorScheme.primary,
            fontSize = 16.sp,
            modifier = Modifier.clickable(onClick = onBack).padding(end = 12.dp),
        )
        Text(title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
    }
}

@Composable
private fun CatalogList(categories: List<Category>, onOpen: (String) -> Unit) {
    LazyColumn(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        item {
            Text(
                "SDUI Playground",
                fontWeight = FontWeight.Bold,
                fontSize = 30.sp,
                modifier = Modifier.padding(top = 24.dp, bottom = 4.dp),
            )
        }
        for (category in categories) {
            item(key = "cat-${category.name}") {
                Text(
                    category.name.uppercase(),
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(top = 22.dp, bottom = 8.dp),
                )
            }
            for (entry in category.screens) {
                item(key = "screen-${entry.id}") {
                    CatalogRow(entry, category.colors) { onOpen(entry.id) }
                }
            }
        }
        item { Box(Modifier.size(24.dp)) }
    }
}

@Composable
private fun CatalogRow(entry: CatalogEntry, colors: List<String>, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 5.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
            .clickable(onClick = onClick)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(44.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(gradientOf(colors)),
        )
        Column(Modifier.padding(start = 14.dp)) {
            Text(entry.id, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            if (entry.subtitle.isNotEmpty()) {
                Text(
                    entry.subtitle,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 14.sp,
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
        }
    }
}

private fun gradientOf(colors: List<String>): Brush {
    val parsed = colors.mapNotNull(::hexColor)
    val stops = when {
        parsed.isEmpty() -> listOf(Color(0xFF5AC8FA), Color(0xFF0A84FF))
        parsed.size == 1 -> listOf(parsed[0], parsed[0])
        else -> parsed
    }
    return Brush.linearGradient(stops)
}

/** Parses `#RRGGBB` / `#RRGGBBAA` (the catalog's tile colours). */
private fun hexColor(s: String): Color? {
    val hex = s.removePrefix("#")
    return runCatching {
        when (hex.length) {
            6 -> Color(("FF$hex").toLong(16))
            8 -> {
                // input is RRGGBBAA; Compose Color(Long) wants AARRGGBB.
                val rgb = hex.substring(0, 6)
                val alpha = hex.substring(6, 8)
                Color(("$alpha$rgb").toLong(16))
            }
            else -> null
        }
    }.getOrNull()
}

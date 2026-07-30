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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.sdui.core.JsonValue
import dev.sdui.core.SduiDocument
import dev.sdui.core.SduiParser
import dev.sdui.core.BindingContext
import dev.sdui.core.DataConfig
import dev.sdui.render.DataLoader
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
    fun parseValue(json: String): JsonValue? = SduiParser.decodeValue(json)

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
    private val present: (String) -> Unit,
    private val onDismiss: () -> Unit,
    private val openStory: (Int) -> Unit,
) : SduiHostDelegate {
    override fun navigate(screen: String, params: Map<String, JsonValue>, transition: String) {
        if (screen !in known) return
        // `sheet` presents modally over the current screen — the Android twin of iOS's
        // `.sheet(item:)` (Navigation.swift). Everything else pushes onto the tab's stack.
        // `dismiss` closes the sheet if one is up, else pops the stack.
        when (transition) {
            "sheet" -> present(screen)
            else -> push(screen)
        }
    }

    override fun dismiss() = onDismiss()
    override fun dismissRoot() = onDismiss()

    // The home story rings fire `custom {name:"story", payload:{index}}` — open the
    // full-screen stories player, the Android twin of the iOS `fullScreenCover` path.
    override fun custom(name: String, payload: JsonValue?) {
        if (name == "story") {
            val index = (payload as? JsonValue.Obj)?.value?.get("index")?.let {
                (it as? JsonValue.Num)?.value?.toInt()
            } ?: 0
            openStory(index)
        }
    }
}

/**
 * A stand-in data loader for the showcase, which has no live backend. Every source
 * resolves to an empty success object, so a `request` (e.g. the optimistic-like POST on a
 * clip) *succeeds* and its `onSuccess`/no-op path runs instead of rolling back — the like
 * sticks, as it would against a real server. Screens that need visible rows seed them in
 * `state` and bind to `$state.*`. A production host swaps this for a real HTTP client.
 */
private class DemoLoader : DataLoader {
    override suspend fun load(config: DataConfig, ctx: BindingContext): Map<String, JsonValue> =
        config.sources.associate { it.id to JsonValue.Obj(emptyMap()) }
}

// ── UI ───────────────────────────────────────────────────────────────────────

/** Bottom-nav tabs — the Android twin of the iOS TabView (Home / Browse / Design / Settings).
 *  Each is its own navigation stack rooted at a bundled screen (or the native catalog). */
private enum class Tab(val label: String, val root: String, val icon: ImageVector) {
    HOME("Home", "home", Icons.Filled.Home),
    BROWSE("Browse", CATALOG, Icons.Filled.Search),
    DESIGN("Design", "figma", Icons.Filled.Favorite),
    SETTINGS("Settings", "settings", Icons.Filled.Settings),
}

private const val CATALOG = "__catalog"

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
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

    // One push/pop stack PER TAB, so switching tabs preserves where you were — the
    // standard bottom-navigation pattern. The top of the selected tab's stack is the
    // screen shown; `navigate` pushes onto it. Each screen is rendered by the SAME engine
    // as iOS/Aurora, so the whole app looks identical.
    var selected by remember { mutableStateOf(Tab.HOME) }
    val stacks = remember { Tab.entries.associateWith { mutableStateListOf(it.root) } }
    val stack = stacks.getValue(selected)
    // A single modal sheet presented over the whole app (comments, filters, repost…),
    // driven by `navigate transition:"sheet"`; null when nothing is presented.
    var sheetScreen by remember { mutableStateOf<String?>(null) }
    // The index of the currently open full-screen stories player, or null when closed.
    var openStoryIndex by remember { mutableStateOf<Int?>(null) }
    val loader = remember { DemoLoader() }
    val host = remember(playground, selected) {
        PlaygroundHost(
            known = playground.screensById.keys + CATALOG,
            push = { stack.add(it) },
            present = { sheetScreen = it },
            onDismiss = { if (sheetScreen != null) sheetScreen = null else if (stack.size > 1) stack.removeAt(stack.lastIndex) },
            openStory = { openStoryIndex = it },
        )
    }

    MaterialTheme(colorScheme = if (dark) darkColorScheme() else lightColorScheme()) {
        Scaffold(
            bottomBar = {
                NavigationBar {
                    for (tab in Tab.entries) {
                        NavigationBarItem(
                            selected = tab == selected,
                            onClick = { selected = tab },
                            icon = { Icon(tab.icon, contentDescription = tab.label) },
                            label = { Text(tab.label) },
                        )
                    }
                }
            },
        ) { insets ->
            val currentId = stack.lastOrNull() ?: selected.root
            Column(Modifier.fillMaxSize().padding(insets)) {
                if (stack.size > 1) {
                    val doc = playground.screensById[currentId]
                    NavBar(
                        title = doc?.screen?.title ?: currentId,
                        onBack = { stack.removeAt(stack.lastIndex) },
                    )
                }
                Box(Modifier.fillMaxWidth().weight(1f)) {
                    when {
                        currentId == CATALOG ->
                            CatalogList(playground.categories) { stack.add(it) }
                        else -> {
                            val doc = playground.screensById[currentId]
                            if (doc != null) {
                                SduiScreen(document = doc, tokens = playground.tokens, env = env, loader = loader, delegate = host)
                            } else {
                                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                    Text("Screen \"$currentId\" is not bundled")
                                }
                            }
                        }
                    }
                }
            }
            BackHandler(enabled = stack.size > 1) { stack.removeAt(stack.lastIndex) }
        }

        // Modal presentation for `navigate transition:"sheet"`. Material3 `ModalBottomSheet`
        // is the Android counterpart of SwiftUI's `.sheet` — a rounded, dismissible sheet with
        // a drag handle and scrim. The presented screen is rendered by the SAME engine, so a
        // comments/filters/repost modal is just an ordinary SDUI screen. See doc 19.
        val presented = sheetScreen
        if (presented != null) {
            val doc = playground.screensById[presented]
            ModalBottomSheet(onDismissRequest = { sheetScreen = null }) {
                if (doc != null) {
                    SduiScreen(document = doc, tokens = playground.tokens, env = env, loader = loader, delegate = host)
                } else {
                    Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                        Text("Screen \"$presented\" is not bundled")
                    }
                }
            }
        }

        // Full-screen stories player, presented above the whole app (tab bar included) —
        // the Android twin of the iOS `fullScreenCover` opened from the home story rings.
        openStoryIndex?.let { start ->
            StoriesPlayer(stories = CapabilityStory.all, start = start, onClose = { openStoryIndex = null })
            BackHandler { openStoryIndex = null }
        }
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun NavBar(title: String, onBack: () -> Unit) {
    // iOS-style: a centered title with an icon-only chevron back button (not a left-aligned
    // spelled-out "‹ Back title", not Material's ArrowBack).
    androidx.compose.material3.CenterAlignedTopAppBar(
        title = { Text(title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp) },
        navigationIcon = {
            androidx.compose.material3.IconButton(onClick = onBack) {
                Icon(
                    Icons.Filled.KeyboardArrowLeft,
                    contentDescription = "Back",
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
        },
    )
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

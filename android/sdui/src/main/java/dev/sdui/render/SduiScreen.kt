package dev.sdui.render

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import dev.sdui.core.AnalyticsTag
import dev.sdui.core.BindingContext
import dev.sdui.core.DataConfig
import dev.sdui.core.DataSource
import dev.sdui.core.JsonValue
import dev.sdui.core.Screen
import dev.sdui.core.SduiDocument
import dev.sdui.runtime.ActionHost
import dev.sdui.runtime.ActionInterpreter
import kotlinx.coroutines.launch

/**
 * Loads the data sources a screen declares. Intentionally an interface, not an
 * implementation: this SDK ships no networking client (mirroring how the iOS
 * `SDUIRender` module leaves `DataLoader` to `SDUINetwork`). A host provides a
 * concrete loader that maps `service` names to base URLs and performs the fetch.
 */
interface DataLoader {
    /**
     * Fetches every source in [config], honouring `parallel`/`sequential` mode and
     * `dependsOn` ordering, and returns the results keyed by source id — ready to
     * merge into [BindingContext.data].
     */
    suspend fun load(config: DataConfig, ctx: BindingContext): Map<String, JsonValue>
}

/**
 * App-level concerns the runtime hands back to the host: navigation, deep links,
 * sharing, analytics, haptics and any `custom` actions. Data loading, state and
 * refresh are handled inside the runtime, so a host only implements what genuinely
 * belongs to it — the same division as the iOS `SDUIHostDelegate`.
 *
 * Every method has a no-op default so a host overrides only what it needs.
 */
interface SduiHostDelegate {
    /** Navigate to a screen id / route with resolved params and a transition. */
    fun navigate(screen: String, params: Map<String, JsonValue>, transition: String) {}

    /** Dismiss the current screen. */
    fun dismiss() {}

    /** Dismiss the whole navigation stack. */
    fun dismissRoot() {}

    /** Open an external URL or deep link. */
    fun openUrl(url: String) {}

    /** Present the system share sheet. */
    fun share(text: String?, url: String?) {}

    /** Show a transient message. */
    fun showToast(message: String, style: String?) {}

    /** Emit haptic feedback. */
    fun haptic(style: String?) {}

    /** Emit an analytics event. */
    fun track(tag: AnalyticsTag) {}

    /** Handle a host-defined `custom` action. */
    fun custom(name: String, payload: JsonValue?) {}

    /** Present a minimum-version update alert (soft/hard); confirm opens the store. */
    fun requireVersion(
        minVersion: String,
        storeUrl: String,
        title: String,
        message: String,
        confirmTitle: String,
        dismissible: Boolean,
    ) {}

    /** Run the runtime-permission flow and return the outcome (`granted`/`denied`). */
    suspend fun requestPermission(permission: String, priming: JsonValue?): String = "denied"
}

/**
 * Owns the live state of one rendered screen: loaded data, mutable client state,
 * and the binding context assembled from tokens + env + data + state. It conforms
 * to [ActionHost] so the interpreter can drive it — the Compose analogue of the
 * iOS `SDUIScreenModel`.
 *
 * State is exposed through a Compose [androidx.compose.runtime.MutableState] so
 * mutations recompose the tree. It is created and remembered by [SduiScreen].
 */
class SduiScreenModel(
    private val screen: Screen,
    tokens: JsonValue,
    env: Map<String, JsonValue>,
    private val loader: DataLoader?,
    private val delegate: SduiHostDelegate?,
) : ActionHost {

    private val bindingState = mutableStateOf(
        BindingContext(
            tokens = tokens,
            env = env,
            state = screen.state ?: emptyMap(),
        ),
    )

    /** The current binding context; reading it in composition subscribes to updates. */
    val binding: BindingContext
        get() = bindingState.value

    private val loadingState = mutableStateOf(false)

    /** True while a data reload is in flight. */
    val isLoading: Boolean
        get() = loadingState.value

    // MARK: Lifecycle

    /** Runs the initial data load and the screen's `onAppear` action, in order. */
    suspend fun onAppear(interpreter: ActionInterpreter) {
        reload(sources = emptyList())
        screen.onAppear?.let { interpreter.run(it, binding) }
    }

    /** Reloads the named sources (empty = all), merging results into the context. */
    suspend fun reload(sources: List<String>) {
        val loader = loader ?: return
        val config = screen.data ?: return
        loadingState.value = true
        val filtered = if (sources.isEmpty()) {
            config
        } else {
            config.copy(sources = config.sources.filter { it.id in sources })
        }
        val result = loader.load(filtered, binding)
        var next = binding
        for ((id, value) in result) next = next.withData(id, value)
        bindingState.value = next
        loadingState.value = false
    }

    /**
     * Loads one ad-hoc source (used by the `async` component). Returns the value,
     * or `null` when there's no loader or the response was empty/failed.
     */
    suspend fun loadOne(source: DataSource): JsonValue? {
        val loader = loader ?: return null
        val result = loader.load(DataConfig(sources = listOf(source)), binding)
        val value = result[source.id]
        return if (value != null && value != JsonValue.Null) value else null
    }

    // MARK: ActionHost

    override suspend fun navigate(screen: String, params: Map<String, JsonValue>, transition: String) {
        delegate?.navigate(screen, params, transition)
    }

    override suspend fun dismiss() {
        delegate?.dismiss()
    }

    override suspend fun dismissRoot() {
        delegate?.dismissRoot()
    }

    override suspend fun openUrl(url: String) {
        // URL opening needs an Android Context/Intent, which belongs to the host.
        delegate?.openUrl(url)
    }

    override suspend fun setState(key: String, value: JsonValue) {
        bindingState.value = binding.withState(key, value)
    }

    /** `request` action: load one source and, on success, expose it as $data.<id> (which
     *  republishes the binding → re-render) so onSuccess and any bound view see it. */
    override suspend fun request(source: DataSource): Boolean {
        val value = loadOne(source) ?: return false
        bindingState.value = binding.withData(source.id, value)
        return true
    }

    override suspend fun refresh(sources: List<String>) {
        reload(sources)
    }

    /** Latest scrollTo request: id to generation, so repeats re-fire. */
    val scrollTargetState = mutableStateOf<Pair<String, Int>?>(null)

    override suspend fun scrollTo(id: String) {
        scrollTargetState.value = id to ((scrollTargetState.value?.second ?: 0) + 1)
    }

    override suspend fun showToast(message: String, style: String?) {
        delegate?.showToast(message, style)
    }

    override suspend fun haptic(style: String?) {
        delegate?.haptic(style)
    }

    override suspend fun share(text: String?, url: String?) {
        delegate?.share(text, url)
    }

    override suspend fun log(message: String) {
        android.util.Log.d("SDUI", message)
    }

    override suspend fun track(tag: AnalyticsTag) {
        delegate?.track(tag)
    }

    override suspend fun custom(name: String, payload: JsonValue?) {
        delegate?.custom(name, payload)
    }

    override suspend fun requireVersion(
        minVersion: String,
        storeUrl: String,
        title: String,
        message: String,
        confirmTitle: String,
        dismissible: Boolean,
    ) {
        delegate?.requireVersion(minVersion, storeUrl, title, message, confirmTitle, dismissible)
    }

    override suspend fun requestPermission(permission: String, priming: JsonValue?): String =
        delegate?.requestPermission(permission, priming) ?: "denied"
}

/**
 * The Composable a host embeds to render a server-driven screen.
 *
 * It wires together the model, the interpreter, the registry and the binding
 * scope, then renders the screen's single root component — the direct counterpart
 * of the iOS `SDUIScreenView`. Actions are dispatched fire-and-forget onto a
 * remembered coroutine scope so a tap never blocks the UI thread.
 *
 * @param document the parsed screen payload.
 * @param tokens the shared design-token table (parsed `tokens.json`).
 * @param env runtime environment values (locale, theme, platform...).
 * @param loader optional data loader; when null, `$data.*` bindings resolve empty.
 * @param registry the component registry; defaults to built-ins only.
 * @param delegate optional host delegate for navigation, analytics, etc.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun SduiScreen(
    document: SduiDocument,
    tokens: JsonValue,
    env: Map<String, JsonValue> = emptyMap(),
    loader: DataLoader? = null,
    registry: ComponentRegistry = remember { ComponentRegistry() },
    delegate: SduiHostDelegate? = null,
) {
    val screen = document.screen
    val model = remember(screen.id) {
        SduiScreenModel(screen, tokens, env, loader, delegate)
    }
    val interpreter = remember(model) { ActionInterpreter(model) }
    val scope = rememberCoroutineScope()

    val ctx = RenderContext(
        binding = model.binding,
        registry = registry,
        dispatch = { action, bindingCtx ->
            // Fire-and-forget: run the action on the screen's coroutine scope.
            scope.launch { interpreter.run(action, bindingCtx) }
        },
        loadSource = { source -> model.loadOne(source) },
        setState = { key, value -> scope.launch { model.setState(key, value) } },
    )

    // Run the initial load + onAppear exactly once when the screen id appears.
    LaunchedEffect(screen.id) {
        model.onAppear(interpreter)
    }

    // Pull-to-refresh — the Android twin of iOS's `.refreshable` (SDUIScreenView). When the
    // screen declares `refresh`, a pull reloads its data sources; the spinner tracks the
    // model's loading state.
    if (screen.refresh != null) {
        androidx.compose.material3.pulltorefresh.PullToRefreshBox(
            isRefreshing = model.isLoading,
            onRefresh = { scope.launch { model.reload(screen.refresh?.sources ?: emptyList()) } },
        ) {
            registry.Render(screen.content, ctx)
        }
    } else {
        registry.Render(screen.content, ctx)
    }
}

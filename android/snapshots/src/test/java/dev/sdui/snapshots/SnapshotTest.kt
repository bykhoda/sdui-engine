package dev.sdui.snapshots

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.test.swipeRight
import com.github.takahirom.roborazzi.captureRoboImage
import dev.sdui.core.JsonValue
import dev.sdui.core.SduiParser
import dev.sdui.render.SduiScreen
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/**
 * The Android leg of the visual snapshot harness. One parameterised case per
 * fixture × colour-scheme, driven entirely off spec/snapshots/manifest.json — no bespoke
 * test screens, no hand-capture. Each case renders the REAL renderer, captures the resting
 * state, then drives every mechanic the contract declared (`{id}@{state}`). PNGs land in
 * spec/snapshots/__out__ for stitch.mjs / sheet.mjs to glue against iOS + Aurora.
 *
 * Run: `<gradle> :snapshots:recordRoborazziDebug` (see build.gradle.kts).
 */
@RunWith(ParameterizedRobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w390dp-h844dp-xxhdpi")
class SnapshotTest(private val case: Case) {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun capture() {
        // Colour scheme is driven by the renderer's `isSystemInDarkTheme()`, which
        // Robolectric toggles via the `night` qualifier.
        RuntimeEnvironment.setQualifiers(if (case.scheme == "dark") "+night" else "+notnight")

        val doc = SduiParser.decode(case.json)
        compose.setContent {
            androidx.compose.foundation.layout.Box(Modifier.fillMaxSize()) {
                SduiScreen(document = doc, tokens = TOKENS)
            }
        }
        compose.waitForIdle()
        shoot("default")

        // Mechanic end-states — best-effort. A gesture is applied at the screen level (the
        // fixtures are single-purpose), so the pager advances, the chart scrubs, the row
        // reveals. Each is isolated: a mechanic that can't apply never fails the leg.
        // TODO(parity): per-node targeting via `Modifier.testTag(id)` for pinpoint gestures.
        for (m in case.mechanics) {
            runCatching {
                compose.onRoot().performTouchInput {
                    when (m.gesture) {
                        "swipeLeft" -> swipeLeft()
                        "longPress" -> longClick()
                        "dragAlongX" -> swipeRight()
                        "tap" -> click()
                    }
                }
                compose.waitForIdle()
                shoot(m.id)
            }
        }
    }

    private fun shoot(state: String) {
        val stem = if (state == "default") case.id else "${case.id}@$state"
        val dest = File(OUT, "$stem.android.${case.scheme}.png")
        compose.onRoot().captureRoboImage(dest.path)
    }

    /** One parameterised fixture render: the fixture id, its content JSON, mechanics, scheme. */
    data class Case(
        val id: String,
        val json: String,
        val mechanics: List<Mechanic>,
        val scheme: String,
    ) {
        override fun toString() = "$id-$scheme" // names the generated PNG folder per case
    }

    data class Mechanic(val id: String, val gesture: String, val target: String?)

    companion object {
        private val REPO = repoRoot()
        private val OUT = File(REPO, "spec/snapshots/__out__").apply { mkdirs() }
        private val TOKENS: JsonValue =
            SduiParser.decodeValue(File(REPO, "ios/Sources/SDUIPlayground/Content/tokens.json").readText())
                ?: JsonValue.Obj(emptyMap())

        /** Ascend from the test working dir until the manifest is found — robust to cwd. */
        private fun repoRoot(): File {
            var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
            while (dir != null) {
                if (File(dir, "spec/snapshots/manifest.json").exists()) return dir
                dir = dir.parentFile
            }
            error("could not locate repo root (spec/snapshots/manifest.json) from ${System.getProperty("user.dir")}")
        }

        // The screen `source` is repo-relative in the iOS-authored form; map both flavours.
        private fun resolveSource(source: String): File = when {
            source.startsWith("content/screens/") ->
                File(REPO, "ios/Sources/SDUIPlayground/Content/screens/${source.removePrefix("content/screens/")}")
            source.startsWith("snapshots/components/") ->
                File(REPO, "spec/snapshots/${source.removePrefix("snapshots/")}")
            else -> File(REPO, source)
        }

        private fun schemes(): List<String> =
            (System.getProperty("sdui.snapshot.schemes") ?: "light,dark").split(",").map { it.trim() }.filter { it.isNotEmpty() }

        @JvmStatic
        @ParameterizedRobolectricTestRunner.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> {
            val manifest = SduiParser.decodeValue(File(REPO, "spec/snapshots/manifest.json").readText())
                ?: error("unreadable manifest.json")
            val fixtures = (manifest["screens"]?.arrayValue.orEmpty()) + (manifest["components"]?.arrayValue.orEmpty())
            val out = ArrayList<Array<Any>>()
            for (scheme in schemes()) {
                for (fx in fixtures) {
                    val id = fx["id"]?.stringValue ?: continue
                    val src = fx["source"]?.stringValue ?: continue
                    val file = resolveSource(src)
                    if (!file.exists()) continue
                    val mechanics = fx["mechanics"]?.arrayValue.orEmpty().mapNotNull { m ->
                        val mid = m["id"]?.stringValue ?: return@mapNotNull null
                        Mechanic(mid, m["gesture"]?.stringValue ?: "tap", m["target"]?.stringValue)
                    }
                    out.add(arrayOf(Case(id, file.readText(), mechanics, scheme)))
                }
            }
            return out
        }
    }
}

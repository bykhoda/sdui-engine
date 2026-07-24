package dev.sdui.demo

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent

/**
 * The single Activity host. Everything above it is Compose — the Android sibling
 * of the iOS demo's `DemoApp` entry point. It just hands control to [PlaygroundApp].
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { PlaygroundApp() }
    }
}

// Root build script.
//
// Plugins are declared here with `apply false` so their versions are pinned in
// one place and applied per-module. This mirrors how the iOS side pins tool and
// dependency versions in `Package.swift`.
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("com.android.library") version "8.5.2" apply false
    kotlin("android") version "2.0.20" apply false
    kotlin("plugin.serialization") version "2.0.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.20" apply false
    // Roborazzi drives the JVM visual-snapshot leg (:snapshots) — test-only, never in an app.
    id("io.github.takahirom.roborazzi") version "1.26.0" apply false
}

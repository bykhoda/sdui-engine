// Root Gradle settings for the Android (Jetpack Compose) SDUI renderer.
//
// This module is a sibling of the iOS Swift package: both consume the SAME
// platform-neutral JSON contract in `spec/`. Dependency resolution is centralised
// here so every module (currently just `:sdui`) pulls plugins and libraries from
// the same repositories and version catalog.

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    // Fail if a module tries to declare its own repositories — keeps resolution
    // reproducible and centralised.
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "sdui-android"

include(":sdui")
// The demo/playground application — the Android sibling of ios/Examples/DemoApp.
// Renders the SAME bundled catalog + screens through the Compose renderer.
include(":app")
// The visual-snapshot leg — a TEST-ONLY module (no shipped code, nothing in any APK). It
// renders every fixture from spec/snapshots/manifest.json through the real `:sdui` renderer
// via Roborazzi on the JVM (no emulator) and writes PNGs for the cross-platform gallery.
include(":snapshots")

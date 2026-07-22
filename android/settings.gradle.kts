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

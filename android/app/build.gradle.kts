// The demo/playground application — the Android sibling of `ios/Examples/DemoApp`.
//
// It ships no UI of its own beyond a catalog browser: every screen is the SAME
// server-driven JSON the iOS demo renders, drawn by the `:sdui` Compose renderer.
// This module is what proves the core promise — one contract, two native apps.
plugins {
    id("com.android.application")
    kotlin("android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "dev.sdui.demo"
    compileSdk = 34

    defaultConfig {
        applicationId = "dev.sdui.demo"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "0.1"
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    sourceSets["main"].java.srcDir("src/main/java")

    // The playground content (catalog + screens + tokens) is authored ONCE. To
    // render byte-identical JSON on both platforms without committing a second
    // copy, we sync it into a generated assets dir at build time (see
    // `syncPlaygroundContent` below). The build/ output is git-ignored, so there
    // is exactly one source of truth on disk.
    // TODO(best-practice): relocate the shared content to a neutral top-level
    // `content/` dir and point both iOS resources and this task at it.
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/playgroundAssets"))
}

// Copy the iOS demo's bundled Content/ (catalog.json, screens/*.json, nav/*.json,
// tokens.json) into this app's generated assets under `content/`.
val syncPlaygroundContent by tasks.registering(Copy::class) {
    from(rootProject.file("../ios/Sources/SDUIPlayground/Content"))
    into(layout.buildDirectory.dir("generated/playgroundAssets/content"))
}
tasks.named("preBuild") { dependsOn(syncPlaygroundContent) }

dependencies {
    implementation(project(":sdui"))

    val composeBom = platform("androidx.compose:compose-bom:2024.09.02")
    implementation(composeBom)

    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.runtime:runtime")

    debugImplementation("androidx.compose.ui:ui-tooling")
}

// The `:snapshots` module — the Android leg of the cross-platform visual snapshot harness.
//
// It ships NOTHING: no `src/main` code, no manifest entries, nothing in any APK. It exists
// only to run JVM tests that render every fixture in spec/snapshots/manifest.json through
// the real `:sdui` renderer with Roborazzi (Robolectric-backed, no emulator) and write a
// PNG per fixture/mechanic/scheme into spec/snapshots/__out__. See
// docs/blueprint/20-visual-snapshot-harness.md.
//
//   ~/.gradle/.../gradle :snapshots:recordRoborazziDebug     # capture / refresh PNGs
//   ~/.gradle/.../gradle :snapshots:verifyRoborazziDebug     # fail on a pixel diff (CI)
plugins {
    id("com.android.library")
    kotlin("android")
    kotlin("plugin.serialization")
    id("org.jetbrains.kotlin.plugin.compose")
    id("io.github.takahirom.roborazzi")
}

android {
    namespace = "dev.sdui.snapshots"
    compileSdk = 34

    defaultConfig { minSdk = 24 }

    buildFeatures { compose = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    sourceSets["test"].java.srcDir("src/test/java")

    // Robolectric needs the merged Android resources to render real Compose.
    testOptions { unitTests { isIncludeAndroidResources = true } }
}

dependencies {
    // The renderer under test + the Compose graph it draws with (one aligned BOM).
    implementation(project(":sdui"))
    val composeBom = platform("androidx.compose:compose-bom:2024.09.02")
    implementation(composeBom)
    testImplementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // Roborazzi + Robolectric + the Compose test rule = JVM screenshots with gesture input.
    testImplementation("io.github.takahirom.roborazzi:roborazzi:1.26.0")
    testImplementation("io.github.takahirom.roborazzi:roborazzi-compose:1.26.0")
    testImplementation("io.github.takahirom.roborazzi:roborazzi-junit-rule:1.26.0")
    testImplementation("org.robolectric:robolectric:4.13")
    testImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
    testImplementation("junit:junit:4.13.2")
}

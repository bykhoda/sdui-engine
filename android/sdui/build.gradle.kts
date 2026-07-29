// The `:sdui` library module — the Compose renderer for the SDUI contract.
//
// Its only third-party dependencies are Kotlin, Jetpack Compose,
// kotlinx.serialization and Coil (the de-facto Compose image loader, used for the
// `image` primitive — the counterpart of the iOS `AsyncImage`/`RemoteImage`).
// Networking is still left as a `DataLoader` interface the host implements, so the
// module stays free of a concrete network stack, exactly like iOS `SDUIRender`.
plugins {
    id("com.android.library")
    kotlin("android")
    kotlin("plugin.serialization")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "dev.sdui"
    compileSdk = 34

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
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

    // Keep java sources under the conventional `src/main/java` path even though
    // they are Kotlin, matching the layout requested for this repo. The unit-test
    // set uses the same convention so `src/test/java/**/*.kt` is compiled.
    sourceSets["main"].java.srcDir("src/main/java")
    sourceSets["test"].java.srcDir("src/test/java")

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    // Compose is pulled via the BOM so all Compose artifacts share one aligned
    // set of versions — the Compose analogue to a resolved Swift package graph.
    val composeBom = platform("androidx.compose:compose-bom:2024.09.02")
    implementation(composeBom)

    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    // SF-Symbol-named icons in the contract map to Material icons on Android.
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.runtime:runtime")
    // Activity Result APIs (rememberLauncherForActivityResult) back the `filecell`
    // system file picker — the Compose analogue of the iOS `.fileImporter`.
    implementation("androidx.activity:activity-compose:1.9.2")

    // JSON contract decoding.
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // Image loading for the `image` primitive: memory + disk cached async images,
    // the Compose-native analogue of the iOS `RemoteImage`. Backdrop-blur is host
    // territory; this only fetches/decodes/caches, keeping the SDK network-agnostic.
    implementation("io.coil-kt:coil-compose:2.7.0")

    // Coroutines back the async action interpreter and data-loading interface.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    debugImplementation("androidx.compose.ui:ui-tooling")

    // JVM unit tests for the pure-Kotlin core (binding engine, parser), run via
    // `testDebugUnitTest` — no device needed, mirroring the iOS SDUICoreTests.
    testImplementation(kotlin("test-junit"))
    testImplementation("junit:junit:4.13.2")
}

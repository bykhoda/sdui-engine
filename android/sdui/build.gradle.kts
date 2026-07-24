// The `:sdui` library module — the Compose renderer for the SDUI contract.
//
// It intentionally depends on nothing beyond Kotlin, Jetpack Compose and
// kotlinx.serialization: no image loader, no networking client. Async images use
// a placeholder Box and networking is left as a `DataLoader` interface the host
// implements, exactly mirroring how the iOS `SDUIRender` module stays free of a
// concrete network stack.
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

    // JSON contract decoding. This is the ONLY third-party dependency in the SDK.
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // Coroutines back the async action interpreter and data-loading interface.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    debugImplementation("androidx.compose.ui:ui-tooling")

    // JVM unit tests for the pure-Kotlin core (binding engine, parser), run via
    // `testDebugUnitTest` — no device needed, mirroring the iOS SDUICoreTests.
    testImplementation(kotlin("test-junit"))
    testImplementation("junit:junit:4.13.2")
}

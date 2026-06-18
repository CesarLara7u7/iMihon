import org.jetbrains.kotlin.gradle.ExperimentalKotlinGradlePluginApi

plugins {
    kotlin("multiplatform")
    id("app.cash.sqldelight")
}

kotlin {
    @OptIn(ExperimentalKotlinGradlePluginApi::class)
    applyDefaultHierarchyTemplate()

    // Solo iOS por ahora (sin Android: no hay SDK de Android en esta máquina).
    listOf(
        iosX64(),
        iosArm64(),
        iosSimulatorArm64(),
    ).forEach { target ->
        target.binaries.framework {
            baseName = "Shared"
            isStatic = true
        }
    }

    sourceSets {
        commonMain.dependencies {
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.11.0")
            implementation("app.cash.sqldelight:runtime:2.3.2")
            implementation("app.cash.sqldelight:coroutines-extensions:2.3.2")
            // Red (equivalente multiplataforma de OkHttp/NetworkHelper en Mihon)
            implementation("io.ktor:ktor-client-core:3.0.3")
            implementation("io.ktor:ktor-client-logging:3.0.3")
            // JSON para hablar GraphQL con Suwayomi (solo runtime; sin plugin)
            implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
        }
        iosMain.dependencies {
            implementation("app.cash.sqldelight:native-driver:2.3.2")
            // Motor HTTP nativo de iOS (usa NSURLSession por debajo)
            implementation("io.ktor:ktor-client-darwin:3.0.3")
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}

sqldelight {
    databases {
        create("MihonDatabase") {
            packageName.set("mihon.shared.database")
            // Mismo dialecto que Mihon (SQLite 3.38).
            dialect("app.cash.sqldelight:sqlite-3-38-dialect:2.3.2")
        }
    }
}

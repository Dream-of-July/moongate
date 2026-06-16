plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "com.moongate.mobile.worker"
    compileSdk = 35

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(project(":core:data"))
    implementation(project(":core:domain"))
    implementation(libs.androidx.core)
    implementation(libs.androidx.work.runtime.ktx)

    testImplementation(kotlin("test-junit"))
}

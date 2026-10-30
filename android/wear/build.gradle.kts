plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.wesc9.athlth.wear"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.wesc9.athlth.wear"
        minSdk = 30
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation("androidx.health:health-services-client:1.1.0")
    implementation("androidx.core:core-ktx:1.16.0")
}

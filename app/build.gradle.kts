plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "com.monprojet.ia"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.monprojet.ia"
        minSdk = 28          // Android 9 (Pie)
        targetSdk = 34
        versionCode = 2
        versionName = "0.2.0"

        // Les bibliotheques x86 et x86_64 ne servent qu'aux emulateurs sur PC : 30,8 Mo
        // de poids mort sur un telephone.
        ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a") }
    }

    buildFeatures {
        // Genere BuildConfig, desactive par defaut depuis AGP 8 : MainActivity s'en sert
        // pour n'activer l'inspection de la WebView qu'en debogage.
        buildConfig = true
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    packaging {
        resources.excludes += setOf("META-INF/{AL2.0,LGPL2.1}")
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.activity)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.kotlinx.coroutines.android)

    // Moteur d'inference local. Google lui a succede LiteRT-LM, qui exige Android 12 :
    // MediaPipe reste le seul runtime officiel compatible Android 9.
    implementation(libs.mediapipe.tasks.genai)
}

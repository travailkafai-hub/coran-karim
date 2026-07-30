plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.corankarim.coran_karim"
    // whisper_ggml -> ffmpeg_kit_flutter_new_min exige compileSdk >= 35
    compileSdk = 36
    // whisper_ggml exige NDK 29.0.13113456
    ndkVersion = "29.0.13113456"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Requis par flutter_local_notifications (adhan programme, 2026-07-24).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.corankarim.coran_karim"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Crash natif ONNX (2026-07-23) : R8 renommait ai.onnxruntime.**,
            // que le code natif cherche par nom via FindClass -> java_class ==
            // null -> SIGABRT des la 1re inference. On coupe R8 (garanti) ET on
            // garde une regle keep dediee (proguard-rules.pro) si R8 est
            // reactive plus tard pour optimiser la taille de l'APK.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Inference du modele FastConformer CTC (Quran ASR) en parallele de whisper.cpp
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.20.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20180813")
    // Core library desugaring (flutter_local_notifications, adhan programme).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

// Sorties des bancs (println) visibles dans la console : sans ca, un banc qui
// tourne 20 s ne rend aucun chiffre et il faut passer par les fichiers XML.
tasks.withType<Test> {
    testLogging { showStandardStreams = true }
    // Les workers de test ne HERITENT PAS des -D de la ligne de commande : sans
    // ce relais, un balayage de parametres rend trois fois le meme chiffre et
    // on croit que le parametre n'a aucun effet. Piege paye le 2026-07-30.
    for (k in listOf("pauseMin", "maxBloc", "fusion")) {
        System.getProperty(k)?.let { systemProperty(k, it) }
    }
}

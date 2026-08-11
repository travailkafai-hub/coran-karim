import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── SIGNATURE DE PUBLICATION (2026-08-10) ────────────────────────────────────
//
// Les identifiants du keystore vivent dans `android/key.properties`, un fichier
// DELIBEREMENT ABSENT DU DEPOT (deja couvert par android/.gitignore, avec
// *.jks et *.keystore). Aucun mot de passe ne doit apparaitre dans un fichier
// suivi par git.
//
// Le fichier n'existe pas encore : c'est a l'editeur de le creer, parce que
// generer le keystore ailleurs ferait transiter son mot de passe hors de ses
// mains. Modele attendu :
//
//     storeFile=/chemin/absolu/coran-karim-release.jks
//     storePassword=...
//     keyAlias=coran-karim
//     keyPassword=...
//
// Et la commande qui produit le keystore :
//
//     keytool -genkey -v -keystore ~/coran-karim-release.jks \
//       -keyalg RSA -keysize 2048 -validity 10000 -alias coran-karim
//
// ATTENTION : perdre ce keystore rend TOUTE mise a jour de l'application
// impossible, definitivement. En faire une sauvegarde hors machine avant meme
// le premier televersement, et activer Play App Signing cote console.
val fichierCles = rootProject.file("key.properties")
val cles = Properties().apply {
    if (fichierCles.exists()) FileInputStream(fichierCles).use { load(it) }
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

    signingConfigs {
        create("release") {
            // Renseigne uniquement si key.properties existe. Sinon la config
            // reste vide et n'est pas utilisee (cf. buildTypes ci-dessous).
            if (fichierCles.exists()) {
                storeFile = file(cles["storeFile"] as String)
                storePassword = cles["storePassword"] as String
                keyAlias = cles["keyAlias"] as String
                keyPassword = cles["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            //
            // FAIT le 2026-08-10 (le TODO ci-dessus est conserve pour l'histoire) :
            // la config `release` est utilisee des que `android/key.properties`
            // existe. Tant qu'il est absent, on RETOMBE sur la cle de debug pour
            // que `flutter build --release` continue de fonctionner sur une
            // machine qui n'a pas le keystore.
            //
            // ⚠️ Ce repli est un piege s'il passe inapercu : un binaire signe en
            // debug est REFUSE par Play, y compris en test interne. D'ou le
            // message ci-dessous, qui s'affiche a chaque build concerne.
            signingConfig = if (fichierCles.exists()) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("ATTENTION : android/key.properties absent -> build " +
                    "release signe avec la cle de DEBUG. Non publiable sur Play.")
                signingConfigs.getByName("debug")
            }
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
    for (k in listOf("pauseMin", "maxBloc", "fusion", "seuilRms", "fautesTous", "typeFaute", "adaptatif",
        // 2026-08-06 : `apercu`/`largeurApercu` MANQUAIENT a cette liste. Le
        // banc affichait donc 3,0/9,0 (les defauts) quels que soient les -D
        // passes -- exactement le piege que le commentaire ci-dessus decrit,
        // reintroduit par omission quand le curseur glissant a ete ajoute.
        "apercu", "largeurApercu",
        // "k" : nombre de preuves concordantes exigees pour figer (cf.
        // Decideur.k). Meme piege que ci-dessus -- sans le relais, tout le
        // balayage k=1/k=2 rendrait le meme chiffre.
        "k", "apercu2", "largeurApercu2", "maxFusion")) {
        System.getProperty(k)?.let { systemProperty(k, it) }
    }
}

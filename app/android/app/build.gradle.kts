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

    // `resValue` est refuse tant que cette option est fermee (« Build Type
    // debug contains custom resource values, but the feature is disabled ») --
    // elle l'est par defaut depuis AGP 8. On l'ouvre pour que chaque variante
    // porte son propre nom d'application (cf. `debug` plus bas).
    buildFeatures {
        resValues = true
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
            // ── SEC-11 (audit securite 2026-09-06, ferme le 2026-09-09) ─────
            //
            // Le repli reste le DEFAUT : rien ne change pour un build local
            // (`flutter build apk --release` sur une machine sans keystore
            // continue de marcher, cf. le commentaire d'origine ci-dessus).
            //
            // Ce que l'audit demandait -- « echouer explicitement pour toute
            // commande de PUBLICATION sans configuration de signature valide,
            // garder le confort de developpement dans une variante dediee » --
            // est desormais possible sans toucher au chemin par defaut : la
            // propriete Gradle `requireReleaseSigning` (absente/false par
            // defaut) fait ECHOUER le build au lieu de replier sur debug.
            // Un script de publication l'active explicitement :
            //     ./gradlew bundleRelease -PrequireReleaseSigning=true
            val publicationExigee =
                project.hasProperty("requireReleaseSigning") &&
                    project.property("requireReleaseSigning") == "true"
            signingConfig = if (fichierCles.exists()) {
                signingConfigs.getByName("release")
            } else if (publicationExigee) {
                throw GradleException(
                    "android/key.properties absent et requireReleaseSigning=true : " +
                    "build refuse plutot que signe avec la cle de DEBUG (non " +
                    "publiable sur Play).")
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
            // Le manifeste porte `@string/app_name` (2026-09-04) pour que la
            // variante DEV puisse s'appeler autrement. La ressource doit donc
            // exister dans CHAQUE variante, celle-ci comprise.
            resValue("string", "app_name", "Coran Karim")
        }

        // ── LA VERSION DE DEV COEXISTE AVEC CELLE DU PLAY STORE (2026-09-04)
        //
        // Demande utilisateur : « quand tu veux installer, installe en version
        // DEV, comme ca je peux telecharger l'app du Play Store ».
        //
        // DEUX PROBLEMES D'UN COUP. (1) Un APK debug et un APK release signes
        // par des cles differentes ne peuvent pas s'installer l'un sur l'autre
        // -- adb rend INSTALL_FAILED_UPDATE_INCOMPATIBLE, et la seule issue
        // etait de DESINSTALLER, donc de perdre les preferences, le journal et
        // les captures WAV de la session en cours. (2) Meme signature, la
        // version testee ECRASAIT celle du Store : impossible d'avoir les deux.
        //
        // Un applicationId distinct fait deux applications aux yeux d'Android :
        // icones separees, donnees separees, aucune ne remplace l'autre.
        //
        // ⚠️ CONSEQUENCE POUR LE DIAGNOSTIC : les chemins de donnees changent.
        // Le journal et les captures de la version DEV vivent sous
        //   /sdcard/Android/data/com.corankarim.coran_karim.dev/files/
        // et non plus sous `com.corankarim.coran_karim`. Toute commande adb
        // (pull du journal, RECUPWAV, run-as) doit viser le bon paquet, sans
        // quoi elle lira le journal de l'AUTRE application -- et une analyse
        // faite sur le mauvais journal ne se voit pas.
        debug {
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            // Nom sous l'icone : sans ca, deux « Coran Karim » identiques sur
            // l'ecran d'accueil, et on ne sait plus laquelle on lance.
            resValue("string", "app_name", "Coran Karim DEV")
        }

        // ── LA VARIANTE DE MESURE (ajoutee 2026-09-13) ──────────────────────
        //
        // `profile` est creee par le plugin Gradle de Flutter, pas par nous :
        // elle n'existait donc dans AUCUN des deux blocs ci-dessus, et
        // n'heritait pas de leur `resValue`. Depuis que le manifeste porte
        // `@string/app_name` (2026-09-04), tout `flutter build apk --profile`
        // echouait donc net :
        //
        //   ERROR: AndroidManifest.xml:137: AAPT: error: resource
        //          string/app_name (aka com.corankarim.coran_karim:string/app_name)
        //          not found.
        //
        // ⚠️ CE QUE CA COUTAIT, et pourquoi ca ne se voyait pas : `profile` est
        // LA variante de mesure de performance de Flutter -- compilee en AOT
        // comme une release, mais sans keystore et avec le traceur branche.
        // Tant qu'elle ne compile pas, la seule chose qu'on peut lancer sur un
        // telephone est un build `debug` : Dart en JIT, couche de validation
        // Vulkan chargee, aucune optimisation AOT. Toute plainte de lenteur
        // devient alors indecidable -- on ne peut pas distinguer « l'app est
        // lente » de « le mode debug est lent », faute de point de comparaison.
        // C'est exactement le mur rencontre lors de l'audit du 2026-09-13.
        //
        // Meme suffixe `.dev` que `debug` : les chemins de diagnostic
        // (/sdcard/Android/data/com.corankarim.coran_karim.dev/files/) restent
        // identiques, donc toutes les commandes adb et scripts de banc
        // existants continuent de marcher sans modification. Consequence
        // assumee : un build profile REMPLACE le build debug installe (meme
        // applicationId, meme cle de debug) -- c'est voulu, on compare deux
        // regimes du meme binaire, pas deux applications.
        //
        // `versionNameSuffix` distinct pour qu'un releve ne puisse jamais etre
        // attribue a la mauvaise variante (piege projet deja paye : « v8 mesure
        // sous l'etiquette v23 pendant des heures »).
        // `getByName` et non `profile { }` : le DSL Kotlin ne genere d'accesseur
        // que pour `debug` et `release`. `profile` est cree a la main par le
        // plugin Gradle de Flutter (`initWith debug`, au moment ou le plugin est
        // applique, donc AVANT ce bloc) -- il existe deja, on le recupere.
        getByName("profile") {
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-profile"
            resValue("string", "app_name", "Coran Karim DEV")
        }
    }

    // ── CE QUI RALENTIT UN BUILD DEBUG, ET CE QU'ON EN RETIRE (2026-09-13) ───
    //
    // Contexte : les builds de ce projet sont en DEBUG par defaut (decision
    // utilisateur -- en release le journal Dart est muet et les WAV de
    // diagnostic inaccessibles). Donc « c'est lent parce que c'est du debug »
    // n'est PAS une reponse acceptable ici : le debug est le regime de tous
    // les jours, il doit etre utilisable sur un telephone milieu de gamme.
    //
    // Mesure A/B faite ce jour sur Redmi Note 9 Pro, `am start -W`, meme
    // session, meme telephone :
    //     debug   : 3828 / 3434 / 3450 ms   (mediane ~3450)
    //     profile : 1984 / 1996 / 1947 / 1897 ms  (mediane ~1970, -43 %)
    // Le profile est compile en AOT et ne contient NI `kernel_blob.bin`
    // (33,6 Mo de code Dart non compile, JIT au lancement) NI la couche de
    // validation Vulkan -- verifie en listant le contenu des deux APK.
    //
    // Des deux, une seule peut etre retiree d'un build debug sans perdre le
    // debug lui-meme : la couche de validation.
    //
    //   `libVkLayer_khronos_validation.so` -- 15,2 Mo dans l'APK debug, et le
    //   chargeur Vulkan d'Android la charge REELLEMENT (ligne logcat
    //   « added global layer 'VK_LAYER_KHRONOS_validation' » au demarrage).
    //   Son travail est d'intercepter et de valider CHAQUE appel Vulkan emis
    //   par le moteur de rendu Impeller. C'est un outil pour qui developpe le
    //   MOTEUR Flutter, pas pour qui developpe une application : elle ne
    //   diagnostique rien de ce code-ci, et son cout est paye a chaque frame.
    //
    // Ce qu'on NE perd PAS en la retirant : le JIT, le hot reload, le
    // `DiagnosticLog`, les WAV de capture, `run-as`, le VM service, les
    // assertions Dart, `flutter analyze`, le banc a deux telephones. Tout le
    // diagnostic du projet est intact -- seule disparait une validation des
    // appels graphiques que personne ici ne lit.
    //
    // Reversible en une commande, sans toucher a ce fichier :
    //     flutter build apk --debug -PgarderValidationVulkan=true
    // (a utiliser le jour ou l'on soupconne un bug de rendu natif et ou l'on
    // veut relire les avertissements de la couche).
    packaging {
        jniLibs {
            if (!project.hasProperty("garderValidationVulkan")) {
                excludes += "**/libVkLayer_khronos_validation.so"
            }
            // ── 72 Mo d'emulateur dans chaque APK de developpement ──────────
            //
            // L'APK debug mesure 303 Mo, dont 204 Mo de bibliotheques natives
            // reparties en TROIS jeux d'instructions :
            //     lib/arm64-v8a     80,4 Mo   <- le seul utilise par un
            //                                    telephone recent
            //     lib/x86_64        72,2 Mo   <- emulateur uniquement
            //     lib/armeabi-v7a   51,6 Mo   <- telephones 32 bits anciens
            //
            // ⚠️ HONNETETE SUR CE QUE CA CORRIGE : un jeu d'instructions
            // inutilise n'est jamais charge en memoire (les .so sont mappes a
            // la demande), donc retirer x86_64 ne change RIEN au temps de
            // demarrage ni a la fluidite. Ce n'est pas un correctif de
            // performance de l'application -- c'est un correctif de la BOUCLE
            // de developpement : 72 Mo de moins a transferer et a installer a
            // chaque `adb install`, et 72 Mo rendus sur le telephone. Ne pas
            // le presenter autrement dans une mesure.
            //
            // `armeabi-v7a` est CONSERVE : la regle projet « fonctionnel sur
            // n'importe quel telephone » couvre aussi les appareils 32 bits,
            // et rien ne prouve qu'aucun des telephones de recette ne l'est.
            // Seul x86/x86_64 part, car il ne sert qu'a un emulateur -- et le
            // banc de ce projet tourne sur deux telephones REELS
            // (benchmark/recette_2tel.sh), jamais sur emulateur.
            //
            // Le jour ou un emulateur devient necessaire :
            //     flutter build apk --debug -PgarderAbiEmulateur=true
            if (!project.hasProperty("garderAbiEmulateur")) {
                excludes += "lib/x86/**"
                excludes += "lib/x86_64/**"
            }
        }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    // Rattache le pack Play Asset Delivery portant le modele ASR (2026-08-11)
    // -- cf. app/android/model_pack/build.gradle.kts pour le pourquoi (limite
    // de 200 Mo du module de base, PUBLICATION_PLAY.md §2.2). Syntaxe
    // verifiee sur la documentation officielle Android le 2026-08-11.
    assetPacks += listOf(":model_pack")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Inference du modele FastConformer CTC (Quran ASR) en parallele de whisper.cpp
    //
    // 1.20.0 -> 1.26.0 le 2026-08-21, pour une raison PRECISE et mesuree.
    // Le modele 4 tetes INT8 est quantifie avec des poids INT8, ce qui produit
    // des noeuds ConvInteger a poids signes. Le noyau CPU de ConvInteger
    // n etait enregistre qu en UINT8 jusqu a une version posterieure a 1.20 :
    //     ORT_NOT_IMPLEMENTED - Could not find an implementation for
    //     ConvInteger(10) node with name node_conv2d_quant
    // Constate a l ecran, modele pourtant trouve et lu. Verifie en local :
    // le MEME fichier tourne sans erreur sous onnxruntime 1.26.0 et rend ses
    // quatre sorties finies. Les 205 MatMulInteger passaient deja en 1.20 --
    // seuls les 61 Conv bloquaient.
    //
    // L autre voie etait de reecrire les poids INT8 en UINT8 (exact : ajouter
    // 128 au poids ET a son point zero laisse (w - w_zp) inchange). Ecartee :
    // 61 tenseurs a retoucher pour eviter une montee de version qui apporte
    // aussi les correctifs des six versions intermediaires.
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.26.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20180813")
    // Banc JVM sur les vrais WAV : meme version ORT que l'app, bibliotheques
    // natives Windows/Linux uniquement dans le runtime des tests, jamais l'APK.
    testRuntimeOnly("com.microsoft.onnxruntime:onnxruntime:1.26.0")
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
    // Replay explicite : le C2 de MS JDK 21.0.10 plante en compilant
    // Localisateur.localiser (hs_err_pid29428, 15/09). Contournement du banc
    // PC seulement, aucune option ni modification du runtime Android.
    if (System.getProperty("asrBanc") == "true") {
        jvmArgs("-XX:CompileCommand=exclude,com.corankarim.coran_karim.recitation2.Localisateur::localiser")
        // 2026-09-15, second crash du MEME C2 sur une AUTRE methode
        // (hs_err_pid30276 : `CollectionsKt___CollectionsKt::maxOrThrow`),
        // apparu en etendant le banc de 5 a 8 cas -- plus de code sollicite,
        // donc plus d'occasions de tomber sur ce bug du JDK. Exclure methode
        // par methode ne tient pas a l'echelle : on coupe C2 pour le banc.
        // C1 seul suffit ici (le banc mesure des VERDICTS, pas des temps), et
        // rien de tout ceci ne concerne le runtime Android.
        jvmArgs("-XX:TieredStopAtLevel=1")
    }
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
        "k", "apercu2", "largeurApercu2", "maxFusion", "asrBanc", "avanceeDebut", "teteT3", "corpusBanc", "seuilTete3", "margeGauche")) {
        System.getProperty(k)?.let { systemProperty(k, it) }
    }
}

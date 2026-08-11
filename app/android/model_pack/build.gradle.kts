// ── MODULE ASSET PACK -- livraison du modele ASR (2026-08-11) ────────────────
//
// POURQUOI un module a part : le modele de reconnaissance vocale
// (model.onnx, 458,8 Mo + vocab.json/word_tokens.json/tete3.json/rules.json,
// ~3,9 Mo) depasse largement les 200 Mo autorises pour le module de base
// d'un AAB (cf. PUBLICATION_PLAY.md §2.2 -- ce n'est pas un choix, c'est une
// limite de la plateforme). Play Asset Delivery resout ca via un module
// Gradle separe, livre par le Store en plus du module de base.
//
// DELIVERY `install-time` (decision utilisateur, PAD retenu contre
// l'alternative INT8) : ce pack est installe EN MEME TEMPS que l'app, pas en
// telechargement differe -- l'utilisateur n'a rien a attendre, le modele est
// deja la au premier lancement, et l'app reste hors ligne ensuite. C'est la
// promesse affichee dans l'ecran « A propos ».
//
// PLUGIN `com.android.asset-pack` (pas `dynamic-feature`) : c'est le plugin
// DEDIE aux packs qui ne contiennent QUE des assets, sans code (le nom de
// module suffit a Gradle pour generer lui-meme l'AndroidManifest.xml du pack
// -- aucun manifeste n'est ecrit a la main ici, contrairement a l'ancienne
// approche `dynamic-feature` + `<dist:module dist:type="asset-pack">` d'AGP
// < 4.2). Verifie sur la documentation officielle Android (developer.android
// .com/guide/playcore/asset-delivery) le 2026-08-11.
plugins {
    id("com.android.asset-pack")
}

assetPack {
    // Doit correspondre au nom du module Gradle (":model_pack", cf.
    // settings.gradle.kts) -- c'est aussi l'identifiant que Play utilise pour
    // suivre l'etat du pack cote AssetPackManager (fast-follow/on-demand
    // uniquement ; en install-time, cf. FastConformerCtcPlugin.kt, on ne
    // passe meme pas par cette API, seul AssetManager sert).
    packName.set("model_pack")
    dynamicDelivery {
        // install-time : livre AVEC l'installation de l'app (pas de
        // telechargement differe, pas d'attente au premier lancement).
        // Cf. le commentaire de fastconformer_verifier.dart::ensureLoaded()
        // pour le piege qui en decoule (pas de chemin de fichier direct,
        // uniquement un flux AssetManager -> copie unique necessaire).
        deliveryType.set("install-time")
    }
}

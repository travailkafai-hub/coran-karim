package com.corankarim.coran_karim

import com.corankarim.coran_karim.fastconformer.FastConformerCtcPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Point d'entree de RECETTE (2026-07-28) — le banc a deux telephones se pilote
 * par intent, pas par des `input tap`.
 *
 *     adb shell am start -n com.corankarim.coran_karim/.MainActivity \
 *         --es recette ecoute --ei sourate 105
 *
 * Les coordonnees d'un tap dependent de l'ecran, de la langue et de l'etat de
 * navigation ; un tap qui rate ne se voit pas dans le log, et on analyse alors
 * une session qui n'a jamais demarre. L'intent porte le mode explicitement, et
 * Dart le journalise : la session dit elle-meme ce qu'elle teste.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(FastConformerCtcPlugin())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL)
            .setMethodCallHandler { call, result ->
                if (call.method == "lire") {
                    // Consomme une seule fois : un retour au premier plan ne
                    // doit pas relancer la recette a l'insu de l'operateur.
                    val m = intent?.getStringExtra("recette")
                    val s = intent?.getIntExtra("sourate", 2) ?: 2
                    intent?.removeExtra("recette")
                    val n = intent?.getIntExtra("versets", 20) ?: 20
                    val w = intent?.getStringExtra("wav")
                    intent?.removeExtra("wav")
                    result.success(
                        if (m == null) null
                        else mapOf("mode" to m, "sourate" to s, "versets" to n,
                                   "wav" to w))
                } else result.notImplemented()
            }
    }

    companion object { private const val CANAL = "coran_karim/recette" }
}

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
 * `--ei depart N` demarre au verset N au lieu du premier (defaut 1).
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
                    // Premier verset charge (1 = debut de sourate). Cf. le
                    // commentaire de RecetteScreen.depart : c'est la seule
                    // variable jamais bougee des mesures du 2026-07-29, et
                    // celle qui separe « la cause est la duree ecoulee » de
                    // « la cause est le texte de ce passage ».
                    val d = intent?.getIntExtra("depart", 1) ?: 1
                    val w = intent?.getStringExtra("wav")
                    intent?.removeExtra("wav")
                    // `--ez normal true` (2026-08-05) : la recette impose
                    // TOUJOURS le mode reference (cf. RecetteScreen). Ce drapeau
                    // permet EXCEPTIONNELLEMENT de forcer le mode normal pour
                    // une seule mesure de diagnostic -- verifier qu'un audio
                    // deterministe qui se juge bien en reference se comporte
                    // pareil sous SAUT REFUSE/decrochage (actifs uniquement en
                    // normal). Defaut false : n'importe quel appel existant du
                    // banc continue de forcer la reference comme avant.
                    val normal = intent?.getBooleanExtra("normal", false) ?: false
                    intent?.removeExtra("normal")
                    // `--ez fusion false` : coupe le BLOC DE FUSION pour la
                    // mesure (cf. FastConformerCtcPlugin.v2Fusion). Defaut
                    // true = comportement en place, aucun appel existant du
                    // banc n'est affecte.
                    val fusion = intent?.getBooleanExtra("fusion", true) ?: true
                    intent?.removeExtra("fusion")
                    // `--ei preuves 1` : Decideur.k, cf. FastConformerCtcPlugin.
                    val preuves = intent?.getIntExtra("preuves", 2) ?: 2
                    intent?.removeExtra("preuves")
                    result.success(
                        if (m == null) null
                        else mapOf("mode" to m, "sourate" to s, "versets" to n,
                                   "depart" to d, "wav" to w, "normal" to normal,
                                   "fusion" to fusion,
                                   "preuves" to preuves))
                } else result.notImplemented()
            }
    }

    companion object { private const val CANAL = "coran_karim/recette" }
}

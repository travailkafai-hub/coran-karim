package com.corankarim.coran_karim

import com.corankarim.coran_karim.adhan.AdhanSchedulerPlugin
import com.corankarim.coran_karim.fastconformer.FastConformerCtcPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.view.WindowManager
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
        flutterEngine.plugins.add(AdhanSchedulerPlugin())
        // ── GARDER L'ECRAN ALLUME PENDANT LA RECITATION (2026-08-13) ──────
        // Constat utilisateur : « lors de la recitation l'ecran peut
        // s'eteindre, du coup ca coupe le suivi ».
        //
        // FLAG_KEEP_SCREEN_ON plutot qu'un wakelock : il est porte par la
        // FENETRE, donc le systeme le retire tout seul des que l'app passe en
        // arriere-plan ou se ferme, meme sur un crash. Un wakelock, lui, se
        // relache a la main -- et un chemin d'erreur qui oublie de le faire
        // vide la batterie en silence.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_ECRAN)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "garderAllume" -> {
                        val actif = call.argument<Boolean>("actif") ?: false
                        runOnUiThread {
                            if (actif) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL)
            .setMethodCallHandler { call, result ->
                if (call.method == "lire") {
                    // ── VERROU DE PRODUCTION (2026-08-09, decision
                    // utilisateur) ────────────────────────────────────────
                    // MainActivity est `exported=true` (c'est le lanceur) :
                    // N'IMPORTE QUELLE application installee peut donc lancer
                    // cette activite avec ces extras, dont un chemin `wav`
                    // arbitraire, et detourner l'app vers l'ecran de RECETTE.
                    // Aucun degat direct (l'app ne lit qu'un fichier qu'elle a
                    // deja le droit de lire), mais c'est une porte de
                    // developpement laissee ouverte dans un binaire publie.
                    //
                    // Le banc a deux telephones n'est pas affecte : il installe
                    // un APK DEBUGGABLE, parce que `run-as` -- donc la
                    // recuperation des WAV de session -- ne marche pas
                    // autrement (cf. benchmark/recette_2tel.sh, ~l.73). Le test
                    // porte sur ce meme drapeau, pas sur BuildConfig.DEBUG :
                    // `buildConfig` n'est pas active dans le module et le
                    // drapeau debuggable est justement le critere dont depend
                    // deja le banc.
                    //
                    // Pas de retour anticipe ici : on neutralise `m`, et le
                    // chemin `if (m == null) null` tout en bas -- qui existe
                    // deja et renvoie l'accueil normal -- fait le reste. Un
                    // seul chemin de sortie, rien a reindenter.
                    val debogable = (applicationInfo.flags and
                        android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
                    // Consomme une seule fois : un retour au premier plan ne
                    // doit pas relancer la recette a l'insu de l'operateur.
                    val m = if (debogable) intent?.getStringExtra("recette") else null
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
                    // `--es pas 4.0 --es largeur 4.0` : recouvrement de la
                    // ligne d'apercus (largeur - pas). Chaines et non flottants
                    // : `am start` n'a pas d'extra double portable.
                    val pas = intent?.getStringExtra("pas")?.toDoubleOrNull() ?: 4.0
                    val largeur = intent?.getStringExtra("largeur")?.toDoubleOrNull() ?: 4.0
                    val maxBloc = intent?.getStringExtra("maxbloc")?.toDoubleOrNull() ?: 10.0
                    intent?.removeExtra("pas"); intent?.removeExtra("largeur")
                    val maxFusion = intent?.getStringExtra("maxfusion")?.toDoubleOrNull() ?: 18.0
                    intent?.removeExtra("maxbloc"); intent?.removeExtra("maxfusion")
                    result.success(
                        if (m == null) null
                        else mapOf("mode" to m, "sourate" to s, "versets" to n,
                                   "depart" to d, "wav" to w, "normal" to normal,
                                   "fusion" to fusion,
                                   "preuves" to preuves,
                                   "pas" to pas, "largeur" to largeur,
                                   "maxbloc" to maxBloc, "maxfusion" to maxFusion))
                } else result.notImplemented()
            }
    }

    companion object {
        private const val CANAL = "coran_karim/recette"
        private const val CANAL_ECRAN = "coran_karim/ecran"
    }
}

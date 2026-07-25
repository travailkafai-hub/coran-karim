package com.corankarim.coran_karim.fastconformer

import android.util.Log
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Pendant Kotlin de lib/services/diagnostic_log.dart -- ECRIT DANS LE MEME
 * FICHIER (chemin transmis par Dart via "setLogFile", cf.
 * FastConformerCtcPlugin) pour que tout le pipeline de recitation (Dart ET
 * natif : BufferedTranscriber, alignement force, segments) atterrisse dans
 * UNE SEULE chronologie lisible, persistante sur le telephone, independante
 * de toute connexion adb (demande utilisateur 2026-07-11).
 */
object DiagnosticLog {
    private const val TAG = "DiagnosticLog"
    private var file: File? = null
    private val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)

    // Interrupteur global, pilote par Dart (methode plugin "setLogEnabled",
    // reglage utilisateur 2026-07-25). Meme motif que le pendant Dart : chaque
    // ligne ouvre/ecrit/ferme un FileWriter, et le BufferedTranscriber en emet
    // depuis le thread d'inference. L'utilisateur doit pouvoir couper toute
    // l'instrumentation pour verifier que le retard de validation ne vient pas
    // de l'instrumentation elle-meme.
    @Volatile var enabled = true

    @Synchronized
    fun setFile(path: String) {
        file = File(path)
        log("DiagnosticLog", "=== fichier natif relie : $path ===")
    }

    @Synchronized
    fun log(tag: String, message: String) {
        // Sortie AVANT tout formatage (interpolation + SimpleDateFormat) :
        // c'est le cout dominant quand le log est verbeux.
        if (!enabled) return
        val line = "${fmt.format(Date())} [$tag] $message"
        Log.i(TAG, line) // garde aussi la visibilite logcat habituelle
        val f = file ?: return
        try {
            FileWriter(f, true).use { it.write("$line\n") }
        } catch (e: Exception) {
            // Le fichier n'est pas critique au fonctionnement -- ne jamais
            // faire planter la recitation pour un souci d'ecriture disque.
            Log.w(TAG, "echec ecriture fichier: ${e.message}")
        }
    }
}

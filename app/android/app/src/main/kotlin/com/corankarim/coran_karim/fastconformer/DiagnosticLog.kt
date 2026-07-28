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

    // ── TRACE FINE (2026-07-27) : accumulee EN MEMOIRE, ecrite a la fin ─────
    // Pourquoi ce chemin separe de log() : log() ouvre/ecrit/FERME un
    // FileWriter A CHAQUE ligne, et il est appele depuis le chemin audio
    // (feed()) comme depuis le thread d'inference. Mesure deja au dossier
    // (2026-07-25) : l'instrumentation seule representait 22 a 32 ecritures
    // fichier synchrones par seconde -- c'est la raison d'etre de
    // l'interrupteur `enabled`. Tracer FINEMENT une latence avec ce mecanisme
    // reviendrait a mesurer l'instrumentation elle-meme : un diagnostic qui
    // modifie ce qu'il mesure n'est pas un diagnostic.
    //
    // Ici : un simple ajout dans une liste (aucune I/O, aucun logcat, aucun
    // formatage de date -- on stocke le nanoTime brut), puis UNE SEULE
    // ouverture de fichier au moment du vidage, apres la recitation.
    private val traceBuf = ArrayList<String>(64_000)
    private var traceT0 = 0L

    /** Borne dure : ~200k lignes (~10 Mo). Au-dela on cesse d'ajouter plutot
     *  que de risquer un OOM en pleine recitation -- la trace est un outil de
     *  diagnostic, jamais une raison de faire tomber l'app. */
    private const val TRACE_MAX = 200_000

    @Synchronized
    fun traceReset() {
        traceBuf.clear()
        traceT0 = System.nanoTime()
    }

    /** Ajout O(1) sans I/O. [t] = etiquette courte d'etape, [msg] = donnees. */
    @Synchronized
    fun trace(t: String, msg: String) {
        if (!enabled || traceBuf.size >= TRACE_MAX) return
        if (traceT0 == 0L) traceT0 = System.nanoTime()
        // Millisecondes depuis le debut de la trace, a 0,1 ms pres : c'est un
        // ECART qu'on veut lire, pas une heure absolue.
        val ms = (System.nanoTime() - traceT0) / 100_000L
        traceBuf.add("${ms / 10}.${ms % 10}\t$t\t$msg")
    }

    /** Ecrit toute la trace accumulee en UNE ouverture de fichier, puis vide le
     *  tampon. A appeler UNIQUEMENT hors recitation (fin de session). */
    @Synchronized
    fun flushTrace(): Int {
        val n = traceBuf.size
        if (n == 0) return 0
        val f = file
        if (f == null) { traceBuf.clear(); return 0 }
        try {
            FileWriter(f, true).use { w ->
                w.write("--- TRACE ($n lignes) : ms\tetape\tdonnees ---\n")
                for (line in traceBuf) w.write("T\t$line\n")
                w.write("--- FIN TRACE ---\n")
            }
        } catch (e: Exception) {
            Log.w(TAG, "echec ecriture trace: ${e.message}")
        }
        traceBuf.clear()
        return n
    }

    // ── CONTEXTE D'EMISSION (2026-07-27) ────────────────────────────────────
    // Le secours rejoue le VRAI aligneur (`align(isFinal = true)`) sur une
    // fenetre d'un seul mot. Il emet donc les memes lignes que le chemin
    // principal -- `ZERO FRAME`, `AVANCE SANS JUGER`, `ETRANGLE PAR LA
    // REFERENCE` -- sans rien qui permette de les distinguer.
    //
    // Ce que ca a coute (session du 21:19) : 24 lignes `AVANCE SANS JUGER`,
    // dont **zero** venait du chemin principal. Compare aux 1 de la session
    // precedente, ca ressemblait a une regression d'un facteur 24 sur l'ancre.
    // Il n'y en avait aucune : c'etait le secours qui parlait.
    //
    // Marquer ICI plutot que dans ForcedAligner : un seul point de passage, et
    // ca couvre toute ligne emise pendant le secours, d'ou qu'elle vienne.
    // Serialise par `busy` (le secours ne tourne jamais en parallele d'une
    // passe), donc un simple champ suffit -- pas de pile, pas de thread-local.
    @Volatile private var contexte: String = ""

    fun contexteDebut(c: String) { contexte = c }
    fun contexteFin() { contexte = "" }

    @Synchronized
    fun log(tag: String, message: String) {
        // Sortie AVANT tout formatage (interpolation + SimpleDateFormat) :
        // c'est le cout dominant quand le log est verbeux.
        if (!enabled) return
        val c = contexte
        val line = "${fmt.format(Date())} [${if (c.isEmpty()) tag else "$c:$tag"}] $message"
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

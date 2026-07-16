package com.corankarim.coran_karim.fastconformer

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.sqrt

/**
 * "Streaming bufferise" : re-transcrit le buffer audio du SEGMENT COURANT avec
 * le modele OFFLINE (FastConformerCtc) toutes les ~1,5s de nouvel audio.
 * Latence percue ~1,5-3s, mais continu et sans arret manuel.
 *
 * Pourquoi pas le vrai streaming cache-aware : verdict du 2026-07-04 — notre
 * checkpoint est entraine en mode offline avec des convolutions NON-causales
 * (subsampling + convs depthwise regardent ~4 frames dans le futur). Le masque
 * d'attention chunked_limited fonctionne en zero-shot sur un enonce complet,
 * mais le decoupage chunk-par-chunk avec cache corrompt chaque frontiere (le
 * cache ne transporte que le contexte gauche des convs) -> decode 100% blank ;
 * meme le chemin officiel NeMo conformer_stream_step crashe (rel_shift sur
 * tenseur vide au 1er chunk). Le vrai streaming exige un fine-tune dedie avec
 * convolutions causales (config fastconformer_hybrid_..._streaming.yaml) —
 * planifie apres la fin du training offline en cours.
 *
 * v2 (2026-07-04) — instabilite constatee sur device : la re-transcription
 * peut s'effondrer (quasi-vide) une seconde apres avoir parfaitement reconnu
 * le meme debut d'enonce. Cause probable : la normalisation "per_feature" du
 * modele (mean/std recalcules sur TOUT le buffer a chaque appel) est perturbee
 * par les silences entre versets qui s'accumulent au fil de la session.
 * Mitigation tentee : plafonner le silence CONSERVE dans le buffer (~300ms max
 * par pause).
 *
 * v3 (2026-07-05) — la mitigation v2 attenue mais n'elimine PAS la derive :
 * confirme par test reel (Al-Fatiha), une snapshot couvrant les versets 4-6
 * quasi-parfaite a ete suivie de re-transcriptions DEGRADEES du meme contenu
 * (melange de versets, mots perdus) alors que l'utilisateur recitait
 * correctement. La vraie cause : le buffer entier (potentiellement plusieurs
 * dizaines de secondes sur une sourate) reste bien au-dela de la duree d'un
 * clip d'entrainement -> la normalisation "per_feature" (recalculee sur tout
 * le buffer a chaque appel) derive structurellement, meme avec le silence
 * plafonne. Fix reel : sur une pause franche (~700ms de silence continu,
 * typiquement fin de verset/groupe de mots), on FIGE (commit) la
 * transcription du segment courant — elle n'est PLUS JAMAIS reconsideree,
 * eliminant la corruption retroactive — et on repart sur un buffer neuf pour
 * la suite. Chaque segment reste ainsi proche d'un clip d'entrainement, avec
 * des statistiques de normalisation stables sur toute sa duree de vie. Le
 * texte retourne = segments figes (stables) + apercu du segment courant
 * (encore susceptible d'evoluer jusqu'a sa propre pause de fin).
 *
 * Durcissement (2026-07-05, suite a relecture independante) : le seul
 * declenchement par pause laissait un trou -- une recitation continue sans
 * pause franche (le cas d'usage principal !) laisse le buffer regonfler sans
 * borne et reintroduit la derive silencieusement. Ajoute : MAX_SEGMENT_SECONDS
 * force un gel meme sans silence detecte (risque residuel accepte : coupure
 * en plein mot dans ce cas limite, rare) ; MIN_COMMIT_SECONDS evite de figer
 * un segment trop court sur des statistiques de normalisation peu fiables.
 * Piste non retenue faute de temps de validation : remplacer la normalisation
 * "per_feature" par des statistiques FIXES (precalculees sur le corpus
 * d'entrainement, cf. option NeMo fixed_mean/fixed_std) -- eliminerait la
 * derive quelle que soit la taille du segment, mais demande de valider que le
 * checkpoint tolere ce changement (jamais vu ces stats a l'entrainement).
 */
class BufferedTranscriber(private val engine: FastConformerCtc) {

    companion object {
        private const val TAG = "BufferedTranscriber"
        private const val SAMPLE_RATE = 16000
        private const val MAX_SECONDS = 180          // garde-fou memoire/latence par segment
        private const val MIN_NEW_SECONDS = 1.5f     // cadence de re-transcription du segment courant
        private const val SILENCE_RMS_THRESHOLD = 0.02f      // approx -34dBFS
        private const val MAX_SILENCE_SAMPLES = (SAMPLE_RATE * 0.3f).toInt() // 300ms max garde par pause (dans un segment)
        // 450ms par defaut (et non 700ms) : test reel 2026-07-05 — une recitation
        // fluide ne marque jamais 700ms entre versets, le gel sur pause ne tirait
        // donc jamais et seule la borne dure (12s, deja trop long pour le modele)
        // agissait. Ajustable par profil personnel via setCommitSilenceMs().
        private const val DEFAULT_COMMIT_SILENCE_MS = 450
        private const val MIN_COMMIT_SECONDS = 2.5f   // pas de gel sur un segment trop court (stats de normalisation peu fiables)
        // 12s (et non 20s) : test reel du 2026-07-05 — la derive de normalisation
        // est deja nette a ~10s de buffer, un gel force a 20s fige du texte degrade.
        private const val MAX_SEGMENT_SECONDS = 12f   // borne dure : force le gel meme sans pause
        private const val MIN_TRACKED_PAUSE_MS = 150  // pauses plus courtes = micro-respirations, ignorees du profil
    }

    private val lock = Any()
    private var samples = FloatArray(0)
    @Volatile private var latestText = ""      // apercu du segment courant (encore revisable)
    @Volatile private var committedText = ""   // segments precedents, definitivement figes

    // ── Alignement force GOP (cf. ForcedAligner.kt, refonte 2026-07-11) ──────
    // Le texte attendu (tokenise par mot, indices absolus) est fourni par Dart
    // via le plugin ; chaque passe de re-transcription calcule EN PLUS du texte
    // un alignement force des mots restants (depuis l'ancre) sur les logprobs
    // de la MEME inference — zero cout ONNX supplementaire. L'ancre avance
    // nativement a chaque gel de segment (l'audio de ces mots ne sera plus
    // jamais reanalyse) ; Dart peut la forcer (correction/recul) via
    // setAlignmentAnchor.
    @Volatile private var alignTokens: List<IntArray>? = null
    @Volatile private var alignAnchor = 0
    @Volatile private var alignSeq = 0
    @Volatile private var lastAlign: Map<String, Any>? = null
    // Garde-fou "2 chances max" (2026-07-14, cf. ForcedAligner.MIN_FRAMES_FOR_JUDGMENT) :
    // index du mot differe par le dernier appel FINAL (segment trop court
    // apres lui pour juger equitablement), ou -1 si aucun. Repasse en
    // forceJudgeIndex au prochain appel FINAL -- si le MEME mot se retrouve
    // encore a la frontiere avec trop peu d'opportunite, on le juge quand
    // meme cette fois (jamais differe indefiniment, cf. discussion
    // utilisateur : un vrai mot rate/saute doit finir par passer au rouge).
    @Volatile private var deferredOnceIndex = -1
    private val aligner: ForcedAligner by lazy {
        ForcedAligner(engine.vocabPieces, engine.blank)
    }

    /** Nombre max de mots alignes par passe — borne le cout de la DP (T x 2N+1). */
    private val maxAlignWords = 80

    fun setAlignmentTarget(tokens: List<IntArray>, anchor: Int) {
        alignTokens = tokens
        alignAnchor = anchor.coerceIn(0, tokens.size)
        lastAlign = null
        deferredOnceIndex = -1
        DiagnosticLog.log(TAG, "cible d'alignement : ${tokens.size} mots, ancre=$alignAnchor")
    }

    fun setAlignmentAnchor(anchor: Int) {
        val tokens = alignTokens ?: return
        alignAnchor = anchor.coerceIn(0, tokens.size)
        lastAlign = null // les resultats en vol reference l'ancienne ancre
        deferredOnceIndex = -1
        DiagnosticLog.log(TAG, "ancre d'alignement deplacee : $alignAnchor")
    }

    /** Etend la cible d'alignement avec des mots supplementaires, a la SUITE de
     *  la cible actuelle — SANS toucher l'ancre (contrairement a
     *  setAlignmentTarget, qui remplace tout). Enchainement sur la sourate
     *  suivante sans interrompre la session en cours (demande utilisateur
     *  2026-07-11). */
    fun extendAlignmentTarget(newTokens: List<IntArray>) {
        val current = alignTokens
        alignTokens = if (current != null) current + newTokens else newTokens
        DiagnosticLog.log(TAG, "cible d'alignement etendue : +${newTokens.size} mots, " +
                "total=${alignTokens?.size}, ancre inchangee=$alignAnchor")
    }

    /** Dernier resultat d'alignement (ou null) — joint au payload feedBufferedAudio. */
    fun alignmentPayload(): Map<String, Any>? = lastAlign

    /** Calcule l'alignement force des mots restants sur les logprobs de la passe
     *  courante. [isFinal] : segment fige (l'audio ne sera plus reanalyse) —
     *  les jugements de cette passe sont definitifs et l'ancre native avance. */
    private fun runAlignment(logprobs: Array<FloatArray>, isFinal: Boolean, clipPath: String? = null) {
        val tokens = alignTokens ?: return
        val anchor = alignAnchor
        if (anchor >= tokens.size) return
        try {
            val slice = tokens.subList(anchor, minOf(tokens.size, anchor + maxAlignWords))
            // forceJudgeIndex seulement sur un appel FINAL : un apercu ne
            // verrouille jamais rien, differer un mot sur un apercu ne compte
            // pas comme une "tentative" reelle.
            val forceIdx = if (isFinal) deferredOnceIndex else -1
            val res = aligner.align(logprobs, slice, anchor, forceIdx, isFinal) ?: return
            val words = res.words.map {
                mapOf(
                    "i" to it.index,
                    "gop" to it.gop,
                    "forced" to it.forced,
                    "covered" to it.covered,
                    "actual" to it.actual,
                )
            }
            alignSeq++
            lastAlign = mapOf(
                "seq" to alignSeq,
                "anchor" to anchor,
                "frontier" to res.frontier,
                "final" to isFinal,
                "words" to words,
            ) + (if (clipPath != null) mapOf("clipPath" to clipPath) else emptyMap())
            // IMPORTANT (bug corrige 2026-07-11) : sur un segment FIGE, Dart juge
            // (et verrouille) TOUS les mots de `res.words` -- y compris le mot a
            // la frontiere lui-meme s'il a recu ne serait-ce que quelques frames
            // (couvert ou non, cf. `!r.covered && !p.isFinal` cote Dart : le
            // garde-fou "pas encore couvert" ne s'applique QUE hors segment
            // final). Faire avancer l'ancre native seulement jusqu'a `frontier`
            // (au lieu de anchor+words.size) desynchronise donc l'ancre native de
            // ce que Dart a reellement verrouille : l'appel suivant redemande a
            // la DP de forcer l'alignement sur un mot DEJA verrouille, qui
            // n'existe plus dans le nouvel audio -- corrompt l'attribution de
            // frames et fait retomber le mot SUIVANT (le vrai premier mot du
            // nouveau segment) avec un score catastrophique malgre une bonne
            // prononciation (constate : "مَـٰلِكِ" verrouille error, gop=-7.36,
            // "entendu"="كِ" alors que le decodage libre du meme segment montre
            // "مَالِكِ..." parfaitement correct).
            if (isFinal) {
                alignAnchor = anchor + res.words.size
                // cf. deferredOnceIndex : ce FINAL a soit juge le mot qu'on
                // forcait (forceIdx, alors deja inclus dans res.words -> on
                // efface le garde-fou), soit differe un NOUVEAU mot (a
                // repasser en force au prochain FINAL), soit n'a rien differe
                // du tout (deferredIndex=null -> RAZ).
                deferredOnceIndex = res.deferredIndex ?: -1
            }
            DiagnosticLog.log(TAG, "alignement seq=$alignSeq ancre=$anchor frontiere=${res.frontier} " +
                    "final=$isFinal mots=${words.size} nouvelle_ancre=$alignAnchor differe=$deferredOnceIndex")
        } catch (e: Exception) {
            DiagnosticLog.log(TAG, "echec alignement force: ${e.message}")
        }
    }

    // Exposes separement pour que le scoring Dart puisse s'ANCRER sur la partie
    // figee (append-only, jamais revisee) et ne re-aligner que l'apercu -- le
    // re-alignement complet depuis le mot 0 calait des que le debut du texte
    // etait perdu par une re-transcription (curseur bloque, test 2026-07-05).
    val committed: String get() = committedText
    val preview: String get() = latestText
    private val busy = AtomicBoolean(false)
    @Volatile private var lastRunSize = 0
    // Deux compteurs distincts (bug corrige 2026-07-05) : retainedSilence sert au
    // plafond de silence CONSERVE dans le buffer (300ms) ; pauseSamples mesure la
    // duree REELLE de la pause en cours et continue de compter meme quand les
    // blocs sont jetes — sinon il plafonne a ~300ms et le gel sur pause (700ms)
    // ne se declenche jamais (seule la borne dure tombait, trop tard).
    private var retainedSilenceSamples = 0
    private var pauseSamples = 0
    @Volatile private var pendingCommit = false
    @Volatile private var pendingForceCommit = false
    // Taille du buffer couverte par le dernier apercu (latestText) — permet au
    // gel force de figer l'apercu sans re-transcrire (cf. borne dure ci-dessous).
    @Volatile private var lastPreviewSize = 0
    // Seuil de gel sur pause, personnalisable par le profil utilisateur (Dart).
    @Volatile private var commitSilenceSamples =
        SAMPLE_RATE * DEFAULT_COMMIT_SILENCE_MS / 1000
    // Duree (ms) de chaque pause terminee de la session — sert a apprendre le
    // profil de pauses de l'utilisateur (idee "personnalisation" 2026-07-05 :
    // la 1ere recitation complete revele ou et combien la personne s'arrete).
    private val sessionPausesMs = mutableListOf<Int>()

    // Capture de clips VERIFIES CORRECTS pour le futur mini-LoRA de
    // personnalisation vocale (FONCTIONNALITES_FUTURES.md, "Personnalisation
    // voix -- niveau 3", implemente 2026-07-12). null = capture desactivee
    // (comportement par defaut, aucun cout). Active par Dart UNIQUEMENT
    // pendant une session de reference (cf. KaraokeRecitationScreen) --
    // Dart decide ensuite, a la fin de la session, si les clips sont
    // definitivement conserves (bon score) ou jetes.
    @Volatile private var captureDir: String? = null

    fun setClipCapture(dir: String?) {
        captureDir = dir
        DiagnosticLog.log(TAG, "capture de clips ${if (dir != null) "activee -> $dir" else "desactivee"}")
    }

    /** Ajuste le seuil de gel sur pause (profil personnel). Borne 300-1500ms. */
    fun setCommitSilenceMs(ms: Int) {
        val clamped = ms.coerceIn(300, 1500)
        commitSilenceSamples = SAMPLE_RATE * clamped / 1000
        DiagnosticLog.log(TAG, "seuil de gel personnalise : ${clamped}ms")
    }

    /** Durees (ms) des pauses >= ${MIN_TRACKED_PAUSE_MS}ms observees depuis reset(). */
    fun getSessionPausesMs(): List<Int> = synchronized(sessionPausesMs) { sessionPausesMs.toList() }

    fun reset() {
        synchronized(lock) { samples = FloatArray(0) }
        latestText = ""
        committedText = ""
        lastRunSize = 0
        retainedSilenceSamples = 0
        pauseSamples = 0
        pendingCommit = false
        pendingForceCommit = false
        lastPreviewSize = 0
        // L'ancre d'alignement n'est PAS touchee ici : reset() est appele
        // pendant la correction (resetBuffer Dart) qui repositionne l'ancre
        // elle-meme via setAlignmentAnchor -- seul le resultat en vol (calcule
        // sur l'audio qu'on vient de jeter) doit etre oublie.
        lastAlign = null
        synchronized(sessionPausesMs) { sessionPausesMs.clear() }
    }

    /**
     * Ajoute du PCM et declenche une re-transcription en arriere-plan si assez
     * de nouvel audio s'est accumule (ou qu'une pause franche impose de figer
     * le segment courant) et qu'aucune inference n'est en cours. Retourne
     * immediatement le texte complet connu (segments figes + apercu courant).
     */
    fun feed(newSamples: FloatArray, scope: CoroutineScope): String {
        var sumSq = 0.0
        for (v in newSamples) sumSq += v.toDouble() * v
        val rms = sqrt(sumSq / newSamples.size)
        val isSilence = rms < SILENCE_RMS_THRESHOLD

        val toAppend: FloatArray? = if (!isSilence) {
            // Fin d'une pause : consigner sa duree reelle dans le profil de session.
            if (pauseSamples >= SAMPLE_RATE * MIN_TRACKED_PAUSE_MS / 1000) {
                val ms = pauseSamples * 1000 / SAMPLE_RATE
                synchronized(sessionPausesMs) { sessionPausesMs.add(ms) }
            }
            retainedSilenceSamples = 0
            pauseSamples = 0
            newSamples
        } else {
            pauseSamples += newSamples.size // duree reelle de la pause, sans plafond
            if (retainedSilenceSamples >= MAX_SILENCE_SAMPLES) {
                null // deja assez de silence conserve pour cette pause -> on jette ce bloc
            } else {
                retainedSilenceSamples += newSamples.size
                newSamples
            }
        }

        var size: Int
        synchronized(lock) {
            if (toAppend != null && samples.size < SAMPLE_RATE * MAX_SECONDS) {
                val old = samples
                samples = old.copyOf(old.size + toAppend.size)
                System.arraycopy(toAppend, 0, samples, old.size, toAppend.size)
            }
            size = samples.size
        }

        val sizeSeconds = size.toFloat() / SAMPLE_RATE
        // Le gel exige un segment assez long — verifie ICI (au moment de armer
        // le flag) ET au lancement (le flag peut survivre a un gel precedent :
        // course observee en test reel, micro-segment d'1s fige corrompu).
        if (isSilence && pauseSamples >= commitSilenceSamples &&
            sizeSeconds >= MIN_COMMIT_SECONDS
        ) {
            pendingCommit = true // pause franche sur un segment assez long -> fin de verset/groupe probable
        }
        if (sizeSeconds >= MAX_SEGMENT_SECONDS) {
            // Borne dure : recitation continue sans pause detectee. On ne
            // RE-transcrit PAS (test reel 2026-07-05 : a 12s la re-transcription
            // de gel etait degradee alors que le dernier apercu etait parfait) —
            // on fige le dernier apercu tel quel et on ne retire du buffer que
            // l'audio qu'il couvrait.
            pendingForceCommit = true
        }
        if (pendingCommit && sizeSeconds < MIN_COMMIT_SECONDS) {
            pendingCommit = false // flag herite d'un gel precedent, segment courant trop court
        }

        if (pendingForceCommit && !busy.get()) {
            pendingForceCommit = false
            val previewText = latestText
            val covered = lastPreviewSize
            if (previewText.isNotEmpty() && covered > 0) {
                synchronized(lock) {
                    samples = if (samples.size > covered) {
                        samples.copyOfRange(covered, samples.size)
                    } else {
                        FloatArray(0)
                    }
                    lastRunSize = 0
                }
                val sep = if (committedText.isEmpty()) "" else " "
                committedText = committedText + sep + previewText
                latestText = ""
                lastPreviewSize = 0
                // L'apercu reutilise devient definitif sans re-transcription :
                // promouvoir de meme le dernier alignement (calcule sur ce meme
                // apercu) en resultat FINAL et avancer l'ancre native.
                val la = lastAlign
                if (la != null && la["final"] == false) {
                    alignSeq++
                    lastAlign = HashMap(la).apply {
                        put("final", true)
                        put("seq", alignSeq)
                    }
                    // Meme regle que runAlignment() : Dart verrouille TOUS les
                    // mots de la liste des lors que final=true (le garde-fou
                    // "pas encore couvert" ne s'applique qu'aux apercus) --
                    // l'ancre native doit donc avancer de anchor + words.size,
                    // pas juste jusqu'a frontier (cf. commentaire runAlignment).
                    @Suppress("UNCHECKED_CAST")
                    val wordsList = la["words"] as? List<Map<String, Any>>
                    val laAnchor = la["anchor"] as Int
                    alignAnchor = laAnchor + (wordsList?.size ?: 0)
                }
                DiagnosticLog.log(TAG, "segment FIGE (borne ${MAX_SEGMENT_SECONDS}s, apercu reutilise, ${covered / SAMPLE_RATE}s couverts) : \"${previewText.take(80)}\"")
            } else {
                // Pas d'apercu utilisable -> gel classique avec re-transcription.
                pendingCommit = true
            }
        }

        val newSinceLast = size - lastRunSize
        val shouldRun =
            size > 0 && (newSinceLast >= (SAMPLE_RATE * MIN_NEW_SECONDS).toInt() || pendingCommit)
        if (shouldRun && busy.compareAndSet(false, true)) {
            lastRunSize = size
            val committing = pendingCommit
            pendingCommit = false
            val snapshot: FloatArray
            synchronized(lock) { snapshot = samples.copyOf() }
            scope.launch(Dispatchers.Default) {
                try {
                    val t0 = System.nanoTime()
                    // Une seule inference ONNX : les logprobs servent au texte
                    // (greedy) ET a l'alignement force GOP (cf. runAlignment).
                    val logprobs = engine.computeLogProbs(snapshot)
                    val text = engine.greedyDecode(logprobs)
                    val ms = (System.nanoTime() - t0) / 1_000_000
                    if (committing) {
                        // Segment fige : plus jamais reconsidere. On ne retire du
                        // buffer QUE la portion transcrite ici -- de l'audio a pu
                        // arriver pendant l'inference (feed() n'est pas bloquant).
                        synchronized(lock) {
                            samples = if (samples.size > snapshot.size) {
                                samples.copyOfRange(snapshot.size, samples.size)
                            } else {
                                FloatArray(0)
                            }
                            lastRunSize = samples.size
                        }
                        val sep = if (committedText.isEmpty()) "" else " "
                        committedText = committedText + sep + text
                        latestText = ""
                        lastPreviewSize = 0
                        // Capture du clip (session de reference uniquement, cf.
                        // setClipCapture) -- best-effort, un echec d'ecriture ne
                        // doit jamais interrompre la recitation en cours.
                        var clipPath: String? = null
                        val dir = captureDir
                        if (dir != null) {
                            try {
                                clipPath = "$dir/clip_${System.currentTimeMillis()}.wav"
                                WavWriter.writeMono16k(clipPath, snapshot)
                            } catch (e: Exception) {
                                DiagnosticLog.log(TAG, "echec capture clip: ${e.message}")
                                clipPath = null
                            }
                        }
                        DiagnosticLog.log(TAG, "segment FIGE ${snapshot.size / SAMPLE_RATE}s -> ${ms}ms : \"${text.take(80)}\"")
                        runAlignment(logprobs, isFinal = true, clipPath = clipPath)
                    } else {
                        latestText = text
                        lastPreviewSize = snapshot.size
                        DiagnosticLog.log(TAG, "retranscription ${snapshot.size / SAMPLE_RATE}s -> ${ms}ms : \"${text.take(80)}\"")
                        runAlignment(logprobs, isFinal = false)
                    }
                } catch (e: Exception) {
                    DiagnosticLog.log(TAG, "echec retranscription: ${e.message}")
                } finally {
                    busy.set(false)
                }
            }
        }
        val committed = committedText
        val preview = latestText
        val sep = if (committed.isEmpty() || preview.isEmpty()) "" else " "
        return committed + sep + preview
    }
}

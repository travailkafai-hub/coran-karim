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
        //
        // 12s -> 6s essaye le 2026-07-23 puis REMIS a 12s le meme jour : teste
        // EN MEME TEMPS que le recouvrement, impossible de savoir lequel des
        // deux causait quoi -- et la mesure a montre une degradation nette
        // (segments de 2-5s, transcriptions fragmentaires, ancre qui patine).
        // A retenter SEUL, apres validation du recouvrement. Raisonnement
        // d'origine, qui reste valable :
        // borne avait ete ECARTE plus tot dans la meme session : elle double
        // les gels, donc les coupures a une position arbitraire, donc les mots
        // TRANCHES -- defaut mesure (entendu="عَلَيْ" pour عَلَيْهِمْ, "كَفَ"
        // pour كَفَرُوا۟ ; 6 des 7 "erreurs de lettre" d'une session).
        // OVERLAP_SECONDS annule cette objection : un mot coupe a la borne se
        // retrouve ENTIEREMENT dans les 2s conservees, donc traite normalement
        // au segment suivant. Les deux changements ne valent QUE pris ensemble.
        //
        // Gains attendus, tous deux mesures comme problematiques avant :
        //  - la derive de normalisation (nette des ~9-10s, cf. instrument
        //    DERIVE) ne peut plus s'installer : le buffer reste sous 6s ;
        //  - l'ancre avance toutes les ~4s d'audio neuf (6s - 2s de
        //    recouvrement) au lieu de 12s : le vert arrive bien plus vite,
        //    ce qui etait la plainte initiale sur une recitation fluide (3
        //    gels sur 4 passaient par la borne dure faute de pause de 450ms).
        // Cout : les 2s de recouvrement sont re-transcrites, soit ~33% de
        // calcul redondant -- sans effet perceptible, l'inference tourne a
        // 12x le temps reel (10s d'audio en 0,8s, mesure device).
        private const val MAX_SEGMENT_SECONDS = 12f   // borne dure : force le gel meme sans pause
        // RECOUVREMENT de segment (2026-07-23, idee utilisateur : « flashback
        // pour recuperer ce qui etait dit », duree fixee a 2s par lui — « 0,5
        // c'est rien » : en recitation coranique un mot avec madd dure
        // facilement 1 a 2s, 0,5s ne couvre meme pas un mot entier).
        // Jusqu'ici le buffer etait VIDE au gel : le segment suivant demarrait
        // avec ZERO contexte acoustique, ce qui penalise son premier mot et
        // casse les regles de JONCTION a la frontiere (idgham/iqlab/ikhafa
        // entre le dernier mot d'un segment et le premier du suivant).
        //
        // ⚠️ Le recouvrement audio ne se suffit PAS a lui-meme : si l'ancre
        // avancait quand meme au mot suivant, la DP tenterait de placer CE mot
        // sur de l'audio DEJA recite -> desynchronisation (exactement le bug
        // constate le 2026-07-23 en ne reculant que l'un des deux). L'ancre
        // recule donc du nombre de mots contenus dans ces 2s ; ces mots sont
        // deja VERROUILLES cote Dart, les rejuger est sans effet
        // (`if (words[i].locked) return`), mais la DP retrouve la bonne
        // correspondance audio<->texte.
        private const val OVERLAP_SECONDS = 2f
        private const val MIN_TRACKED_PAUSE_MS = 150  // pauses plus courtes = micro-respirations, ignorees du profil
    }

    /** Concatene `next` a `base` en supprimant le RECOUVREMENT : la plus
     *  longue fin de `base` qui est aussi un debut de `next` (au niveau des
     *  MOTS) n'est ecrite qu'une fois. Necessaire depuis OVERLAP_SECONDS : les
     *  dernieres secondes d'un segment sont volontairement re-transcrites dans
     *  le suivant (pour lui donner du contexte acoustique), leurs mots
     *  apparaitraient donc en double dans le texte fige. */
    private fun appendMergingOverlap(base: String, next: String): String {
        if (base.isEmpty()) return next
        if (next.isEmpty()) return base
        val b = base.split(" ").filter { it.isNotEmpty() }
        val n = next.split(" ").filter { it.isNotEmpty() }
        val max = minOf(b.size, n.size, 12) // au-dela, ce n'est plus un recouvrement
        for (k in max downTo 1) {
            if (b.subList(b.size - k, b.size) == n.subList(0, k)) {
                val rest = n.drop(k)
                return if (rest.isEmpty()) base else base + " " + rest.joinToString(" ")
            }
        }
        return base + " " + next
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
    // Variantes confusables par mot, PARALLELE a alignTokens (rescoring NLL,
    // cf. ForcedAligner.WordResult.rescoreMargin / ConfusableVariants). Null ou
    // liste vide pour un mot -> pas de rescoring sur ce mot (comportement
    // identique a avant ce champ).
    @Volatile private var alignVariants: List<List<Pair<String, IntArray>>>? = null
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

    fun setAlignmentTarget(
        tokens: List<IntArray>,
        anchor: Int,
        variants: List<List<Pair<String, IntArray>>>? = null,
    ) {
        alignTokens = tokens
        alignVariants = variants
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
    fun extendAlignmentTarget(
        newTokens: List<IntArray>,
        newVariants: List<List<Pair<String, IntArray>>>? = null,
    ) {
        val current = alignTokens
        alignTokens = if (current != null) current + newTokens else newTokens
        if (newVariants != null) {
            val currentV = alignVariants ?: List(current?.size ?: 0) { emptyList() }
            alignVariants = currentV + newVariants
        }
        DiagnosticLog.log(TAG, "cible d'alignement etendue : +${newTokens.size} mots, " +
                "total=${alignTokens?.size}, ancre inchangee=$alignAnchor")
    }

    /** Dernier resultat d'alignement (ou null) — joint au payload feedBufferedAudio. */
    fun alignmentPayload(): Map<String, Any>? = lastAlign

    /** Calcule l'alignement force des mots restants sur les logprobs de la passe
     *  courante. [isFinal] : segment fige (l'audio ne sera plus reanalyse) —
     *  les jugements de cette passe sont definitifs et l'ancre native avance. */
    private fun runAlignment(logprobs: Array<FloatArray>, isFinal: Boolean, clipPath: String? = null,
                             segmentRules: List<DetectedRule> = emptyList(),
                             // Logprobs bruts de la tete 2 -> GOP tajwid gradue
                             // (cf. ForcedAligner.WordResult.tajwidGop).
                             tajwidLogprobs: Array<FloatArray>? = null,
                             // Nombre d'echantillons sur lesquels `logprobs` a
                             // ete calcule -> conversion frame->echantillon
                             // pour le gel sur frontiere de mot.
                             sourceSamples: Int = 0) {
        val tokens = alignTokens ?: return
        val anchor = alignAnchor
        if (anchor >= tokens.size) return
        try {
            val end = minOf(tokens.size, anchor + maxAlignWords)
            val slice = tokens.subList(anchor, end)
            // forceJudgeIndex seulement sur un appel FINAL : un apercu ne
            // verrouille jamais rien, differer un mot sur un apercu ne compte
            // pas comme une "tentative" reelle.
            val forceIdx = if (isFinal) deferredOnceIndex else -1
            val variantsSlice = alignVariants?.let {
                if (anchor < it.size) it.subList(anchor, minOf(it.size, end)) else null
            }
            var res = aligner.align(logprobs, slice, anchor, forceIdx, isFinal, variantsSlice,
                                    segmentRules, tajwidLogprobs) ?: return
            // ── Garde-fou : le GEL ne doit pas DEGRADER un bon apercu ───────
            // Mesure device 2026-07-23 (recitation hesitante) :
            //   18:02:20  apercu 5s -> "أَيَحْسَبُ أَندٌ"   (mot correct)
            //   18:02:21  GEL    5s -> "أَيَحْسَ أَندٌ"     (tronque)
            //   -> alignement du gel : 0 mot, ancre BLOQUEE a 27, le vert
            //      s'arrete alors que le mot avait ete parfaitement entendu.
            // Le chemin MAX_SEGMENT_SECONDS evite deja ce piege depuis le
            // 2026-07-05 (« a 12s la re-transcription de gel etait degradee
            // alors que le dernier apercu etait parfait -> on fige le dernier
            // apercu tel quel »), mais le gel sur PAUSE, lui, re-transcrivait
            // sans filet -- or c'est celui qui se declenche quand on hesite.
            // Ici : si le gel n'aligne AUCUN mot alors que le dernier apercu
            // a la MEME ancre en alignait, on retient l'apercu. On ne fige
            // jamais un resultat vide qui bloquerait la progression.
            // Contexte (frames, echantillons) auquel se rapportent les
            // endFrame de `res` : celui du gel, ou celui de l'APERCU si on lui
            // a substitue le resultat ci-dessous. Indispensable au calcul du
            // recouvrement, qui convertit des frames en echantillons.
            var resFrames = logprobs.size
            var resSamples = sourceSamples
            var usedPreview = false
            if (isFinal && res.words.isEmpty()) {
                val prev = lastGoodPreview
                if (prev != null && lastGoodPreviewAnchor == anchor && prev.words.isNotEmpty()) {
                    DiagnosticLog.log(TAG,
                        "GEL DEGRADE ignore : la re-transcription du gel n'aligne " +
                        "aucun mot, on retient l'apercu precedent " +
                        "(${prev.words.size} mot(s), ancre=$anchor)")
                    res = prev
                    resFrames = lastGoodPreviewFrames
                    resSamples = lastGoodPreviewSamples
                    usedPreview = true
                }
            }
            if (!isFinal && res.words.isNotEmpty()) {
                lastGoodPreview = res
                lastGoodPreviewAnchor = anchor
                lastGoodPreviewFrames = logprobs.size
                lastGoodPreviewSamples = sourceSamples
            }
            // Frontiere de gel = fin du dernier mot ENTIEREMENT prononce,
            // convertie en echantillons via le rapport REEL du segment
            // (aucun facteur de sous-echantillonnage code en dur : il depend
            // du modele charge). Sert au gel sur borne dure, pour couper
            // apres un mot complet au lieu d'une position arbitraire du
            // buffer -- cf. ForcedAligner.Result.lastCoveredFrame.
            if (res.lastCoveredFrame >= 0 && logprobs.isNotEmpty() && sourceSamples > 0) {
                val perFrame = sourceSamples.toFloat() / logprobs.size
                val cut = ((res.lastCoveredFrame + 1) * perFrame).toInt()
                lastWordBoundarySamples = cut.coerceIn(0, sourceSamples)
            }
            val words = res.words.map {
                mapOf(
                    "i" to it.index,
                    "gop" to it.gop,
                    "forced" to it.forced,
                    "covered" to it.covered,
                    "actual" to it.actual,
                ) + (it.rescoreMargin?.let { m -> mapOf("rescoreMargin" to m) } ?: emptyMap()) +
                    (it.rescoreHeard?.let { h -> mapOf("rescoreHeard" to h) } ?: emptyMap()) +
                    // Regles REELLEMENT detectees sur les frames de ce mot
                    // (tete 2). Cle absente si aucune -> le Dart distingue
                    // "modele sans tete tajwid" de "regle non realisee".
                    (if (it.detectedRules.isEmpty()) emptyMap() else mapOf(
                        "rules" to it.detectedRules.map { r ->
                            mapOf("id" to r.ruleId, "prob" to r.prob.toDouble())
                        })) +
                    // GOP tajwid gradue par classe (cf. tajwidGop) : permet a
                    // Dart de juger une regle sur un SEUIL au lieu du binaire
                    // "presente dans rules". Cle absente sur un modele a une
                    // seule tete.
                    (if (it.tajwidGop.isEmpty()) emptyMap() else mapOf(
                        "tajwidGop" to it.tajwidGop.map { g -> g.toDouble() }))
            }
            // ── Instrument DESYNC ──────────────────────────────────────────
            // Un segment qui contient de la parole mais dont l'alignement ne
            // place AUCUN mot (ou n'avance pas la frontiere) signale que
            // l'ancre ne pointe plus sur ce qui est recite : la DP ne
            // retrouve pas le texte attendu dans l'audio. C'est ce qui
            // precede systematiquement les cascades d'erreurs (mesure device
            // 2026-07-23 : ancre=0 alors que l'audio disait deja le verset 1,
            // puis "لَآ" juge rouge avec entendu="وَمَآِينَ").
            if (isFinal && res.words.isEmpty() && sourceSamples > SAMPLE_RATE) {
                DiagnosticLog.log(TAG,
                    "DESYNC ancre=$anchor : segment FINAL de " +
                    "${sourceSamples / SAMPLE_RATE}s, AUCUN mot aligne " +
                    "(la DP ne retrouve pas le texte attendu dans l'audio)")
            }
            alignSeq++
            lastAlign = mapOf(
                "seq" to alignSeq,
                "anchor" to anchor,
                "frontier" to res.frontier,
                "final" to isFinal,
                "words" to words,
                // deferredIndex conserve ici (meme sur un apercu) pour que le
                // chemin MAX_SEGMENT_SECONDS (pendingForceCommit plus bas)
                // puisse le recuperer s'il promeut CET apercu en final sans
                // rappeler align() -- cf. Finding #7, revue de code 2026-07-16.
            ) + (if (res.deferredIndex != null) mapOf("deferredIndex" to res.deferredIndex) else emptyMap()) +
                (if (clipPath != null) mapOf("clipPath" to clipPath) else emptyMap())
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
                // Mots dont l'audio tombe dans la zone de recouvrement : ils
                // resteront dans le buffer du prochain segment, l'ancre doit
                // donc reculer d'autant (cf. OVERLAP_SECONDS).
                // Recouvrement sur des MOTS ENTIERS (correctif 2026-07-23).
                // Version precedente : on gardait 2s pile et on reculait
                // l'ancre des mots dont la FIN tombait dedans -- or un mot peut
                // finir dans ces 2s tout en ayant COMMENCE avant : on ne
                // gardait alors que sa queue, l'alignement suivant cherchait le
                // mot entier, ne le trouvait pas, et se bloquait (mesure
                // device : ancre figee a 10 sur وَوَالِدٍ, DESYNC, 0 mot aligne).
                // Ici la coupe audio ET le recul d'ancre derivent du MEME
                // debut de mot : les deux parlent forcement de la meme chose.
                var keepSamples = 0
                overlapWordCount = if (resSamples > 0 && resFrames > 0 && !usedPreview) {
                    val perFrame = resSamples.toFloat() / resFrames
                    val overlapStartFrame =
                        resFrames - (SAMPLE_RATE * OVERLAP_SECONDS / perFrame).toInt()
                    // Mots ENTIEREMENT contenus dans la zone (debut ET fin).
                    val whole = res.words.filter {
                        it.startFrame >= 0 && it.startFrame >= overlapStartFrame
                    }
                    // Jamais reculer de TOUT le segment : au moins un mot doit
                    // rester acquis, sinon l'ancre n'avance jamais.
                    val n = whole.size.coerceAtMost(maxOf(0, res.words.size - 1))
                    if (n > 0) {
                        val first = res.words[res.words.size - n]
                        val cut = (first.startFrame * perFrame).toInt()
                        keepSamples = (resSamples - cut).coerceIn(0, resSamples)
                    }
                    n
                } else 0
                overlapKeepSamples = keepSamples
                alignAnchor = anchor + res.words.size - overlapWordCount
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
    // Position (en echantillons) de la fin du dernier mot ENTIEREMENT
    // prononce du segment courant, d'apres le dernier alignement. Point de
    // coupe privilegie du gel sur borne dure : couper la ne tranche aucun
    // mot. 0 = inconnu (pas encore d'alignement exploitable).
    @Volatile private var lastWordBoundarySamples = 0
    // Instrumentation DERIVE (2026-07-23) : texte de l'apercu precedent, pour
    // detecter qu'une re-transcription du MEME buffer (juste allonge) a PERDU
    // du contenu deja transcrit -- signature de la derive de normalisation
    // per_feature decrite dans l'en-tete. Constat device : a 7s le buffer
    // donnait "بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ", a 9s le MEME buffer
    // donnait "لَآ أُقْسِمُ بِهَـٰذَا ٱلْبَلَدِ" -- la Basmala avait disparu, et
    // l'ancre s'est desynchronisee de 4 mots. Mesure indispensable pour
    // trancher sur PLUSIEURS tests au lieu d'un seul.
    // Nombre de mots du dernier alignement FINAL dont l'audio tombe dans la
    // zone de recouvrement -> de combien reculer l'ancre au gel.
    @Volatile private var overlapWordCount = 0
    // Echantillons du buffer courant qui proviennent du RECOUVREMENT du
    // segment precedent (deja transcrits) -- exclus des seuils de gel.
    @Volatile private var overlapCarriedSamples = 0
    // Echantillons a CONSERVER au prochain gel : calcule sur un debut de mot
    // (cf. overlapWordCount), pour que l'audio garde et le recul d'ancre
    // portent exactement sur les memes mots entiers. 0 = pas de recouvrement.
    @Volatile private var overlapKeepSamples = 0
    // Dernier APERCU ayant reellement aligne des mots, conserve tel quel
    // (objet, pas la map serialisee) avec le contexte necessaire au calcul du
    // recouvrement. Sert de repli quand la re-transcription du GEL degrade un
    // apercu qui etait bon -- cf. le garde-fou dans runAlignment.
    @Volatile private var lastGoodPreview: ForcedAligner.Result? = null
    @Volatile private var lastGoodPreviewAnchor = -1
    @Volatile private var lastGoodPreviewFrames = 0
    @Volatile private var lastGoodPreviewSamples = 0
    @Volatile private var prevPreviewText = ""
    @Volatile private var prevPreviewSamples = 0
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
        overlapCarriedSamples = 0
        overlapWordCount = 0
        prevPreviewText = ""
        prevPreviewSamples = 0
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

        // Seuils de gel mesures sur l'audio NEUF, recouvrement EXCLU
        // (correctif 2026-07-23). Defaut constate a la mesure : le buffer
        // demarre deja a OVERLAP_SECONDS d'audio DEJA transcrit ; en comptant
        // le total, une pause 0,5s apres un gel declenchait un segment de
        // 2,5s compose a 80% de re-ecoute, sans contenu neuf -- d'ou des
        // segments de 2-3s, un modele sans contexte, des transcriptions
        // fragmentaires ("ـٰرُونَ") et une ancre qui n'avance plus. Un seuil
        // sur du contenu deja traite n'a aucun sens : seul l'audio neuf
        // justifie un gel.
        val sizeSeconds = (size - overlapCarriedSamples).toFloat() / SAMPLE_RATE
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
            // Point de coupe : fin du dernier mot ENTIEREMENT prononce si on
            // la connait, sinon repli sur l'ancien comportement (taille de
            // l'apercu). Correctif 2026-07-23 : couper a `lastPreviewSize`
            // tombait a une position ARBITRAIRE du buffer, donc regulierement
            // EN PLEIN MOT -- mesure device : "عَلَيْ" pour عَلَيْهِمْ, "كَفَ"
            // pour كَفَرُوا۟, "تَ" pour وَأَنتَ ; 6 des 7 "erreurs de lettre"
            // d'une session etaient ces troncatures. Couper apres un mot
            // complet supprime cette cause par construction, et c'est
            // d'autant plus important que ce chemin (borne dure) est celui
            // qui se declenche sur une recitation FLUIDE : mesure sur le log
            // du 2026-07-23, 3 gels sur 4 passaient par ici faute de pause
            // de 450ms. Le lecteur regulier etait donc le plus penalise.
            // ⚠️ NE PAS couper ici sur `lastWordBoundarySamples` : essaye le
            // 2026-07-23, ANNULE le jour meme apres constat device. Couper
            // l'audio sur une frontiere de mot SANS couper le TEXTE au meme
            // endroit desynchronise les deux : `previewText` couvre tout
            // l'apercu (~10s) alors qu'on ne retirait que l'audio du dernier
            // mot complet (~2s). Le texte etait donc fige EN AVANCE sur
            // l'audio, l'ancre sautait plusieurs mots, et les ~8s restantes
            // etaient realignees contre le mauvais mot -> "لَآ" juge rouge
            // avec entendu="وَمَآِينَ" puis "أَمْ" alors qu'il etait bien
            // recite (log 17:29:24-32).
            //
            // Couper sur une frontiere de mot reste la bonne idee (elle
            // supprime les mots tranches, cf. Result.lastCoveredFrame), mais
            // elle exige de ne figer QUE le texte des mots situes avant la
            // coupe -- le texte n'est pas encore decoupe par mot ici. A
            // reprendre avec cette correspondance texte/audio, pas avant.
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
                lastWordBoundarySamples = 0 // porte sur le segment qu'on vient de consommer
                overlapCarriedSamples = 0   // ce chemin ne conserve pas de recouvrement
                lastGoodPreview = null; lastGoodPreviewAnchor = -1
                prevPreviewText = ""; prevPreviewSamples = 0
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
                    // Bug corrige 2026-07-16 (revue de code, Finding #7) : ce
                    // chemin promeut l'apercu en cache directement en "final"
                    // SANS rappeler align()/runAlignment() -- deferredOnceIndex
                    // n'etait donc jamais mis a jour ici, silencieusement
                    // brisant la garantie "2 chances max" pour cette instance
                    // (un mot differe dans CET apercu restait sans memoire de
                    // son differe). Recupere le deferredIndex deja calcule et
                    // stocke sur l'apercu (cf. runAlignment) -- meme regle que
                    // la ligne 200 : efface (-1) si rien n'etait differe.
                    deferredOnceIndex = (la["deferredIndex"] as? Int) ?: -1
                }
                DiagnosticLog.log(TAG, "segment FIGE (borne ${MAX_SEGMENT_SECONDS}s, apercu reutilise, ${covered / SAMPLE_RATE}s couverts, coupe=taille apercu) : \"${previewText.take(80)}\"")
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
                    val outputs = engine.computeAll(snapshot)
                    val logprobs = outputs.letters
                    // Tete 2 : decodee UNE fois pour tout le segment, puis
                    // repartie par mot dans l'aligneur (recouvrement de frames).
                    val segmentRules = engine.decodeTajwid(outputs.tajwid)
                    val text = engine.greedyDecode(logprobs)
                    val ms = (System.nanoTime() - t0) / 1_000_000
                    if (committing) {
                        // ⚠️ ORDRE CRITIQUE (correctif 2026-07-23) : l'ALIGNEMENT
                        // d'abord, la coupe du buffer ENSUITE.
                        //
                        // C'est lui qui calcule, pour CE segment, combien de mots
                        // entiers tiennent dans la zone de recouvrement
                        // (overlapWordCount) et jusqu'ou couper l'audio
                        // (overlapKeepSamples). Couper AVANT utilisait la valeur
                        // du segment PRECEDENT -- l'ancre reculait alors des mots
                        // du segment courant pendant que l'audio conservait ceux
                        // de l'ancien. Mesure device 2026-07-23 : ancre reculee a
                        // 28 (مَالًا لُّبَدًا) alors que ces mots n'etaient pas dans
                        // l'audio garde -> DESYNC, 0 mot aligne, blocage sur le
                        // 2e أَيَحْسَبُ. Meme famille d'erreur que les deux
                        // precedentes : audio et ancre doivent TOUJOURS deriver du
                        // meme calcul, sur le meme segment.
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
                        runAlignment(logprobs, isFinal = true, clipPath = clipPath,
                                     segmentRules = segmentRules,
                                     tajwidLogprobs = outputs.tajwid,
                                     sourceSamples = snapshot.size)
                        // Coupe du buffer AVEC les valeurs qui viennent d'etre
                        // calculees sur CE segment : les dernieres
                        // OVERLAP_SECONDS (arrondies a des mots ENTIERS) restent
                        // pour donner du contexte au segment suivant, et l'ancre
                        // a recule exactement de ces mots-la.
                        val keep = minOf(overlapKeepSamples, snapshot.size)
                        val drop = snapshot.size - keep
                        overlapCarriedSamples = keep
                        lastGoodPreview = null; lastGoodPreviewAnchor = -1
                        synchronized(lock) {
                            samples = if (samples.size > drop) {
                                samples.copyOfRange(drop, samples.size)
                            } else {
                                FloatArray(0)
                            }
                            lastRunSize = samples.size
                        }
                        // Les mots du recouvrement seront re-transcrits dans le
                        // segment suivant -> fusion pour ne pas les ecrire deux
                        // fois dans le texte fige.
                        committedText = appendMergingOverlap(committedText, text)
                        latestText = ""
                        lastPreviewSize = 0
                    } else {
                        // ── Instrument DERIVE ──────────────────────────────
                        // Le buffer ne fait que GRANDIR entre deux apercus :
                        // le nouveau texte devrait donc CONTENIR l'ancien (a
                        // la revision des derniers mots pres). S'il perd les
                        // premiers mots, ce n'est pas la recitation qui a
                        // change -- c'est la transcription du meme audio qui
                        // s'effondre. On mesure la perte sur le DEBUT du texte
                        // (5 premiers mots), la partie deja stabilisee.
                        // Seuil : en dessous de ~4s le buffer ne contient
                        // souvent qu'un fragment de mot, et sa transcription
                        // varie normalement d'une passe a l'autre -- mesurer
                        // la "derive" la n'a aucun sens. Premiere version de
                        // cet instrument (2026-07-23) sans ce seuil : 19
                        // declenchements, TOUS sur des buffers de 0 a 5s, donc
                        // sur du bruit normal et non sur le phenomene vise.
                        val prevHead = prevPreviewText.split(" ").take(5)
                        if (prevHead.size >= 3 && prevPreviewText.isNotEmpty() &&
                            snapshot.size > prevPreviewSamples &&
                            prevPreviewSamples >= SAMPLE_RATE * 4) {
                            val kept = prevHead.count { text.contains(it) }
                            if (kept <= prevHead.size / 2) {
                                DiagnosticLog.log(TAG,
                                    "DERIVE buffer ${prevPreviewSamples / SAMPLE_RATE}s->" +
                                    "${snapshot.size / SAMPLE_RATE}s : $kept/${prevHead.size} " +
                                    "mots de tete conserves | avant=\"${prevPreviewText.take(60)}\" " +
                                    "| apres=\"${text.take(60)}\"")
                            }
                        }
                        prevPreviewText = text
                        prevPreviewSamples = snapshot.size
                        latestText = text
                        lastPreviewSize = snapshot.size
                        DiagnosticLog.log(TAG, "retranscription ${snapshot.size / SAMPLE_RATE}s -> ${ms}ms : \"${text.take(80)}\"")
                        runAlignment(logprobs, isFinal = false, segmentRules = segmentRules,
                                     tajwidLogprobs = outputs.tajwid,
                                     sourceSamples = snapshot.size)
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

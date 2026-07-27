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
        private const val MAX_TARGET_SECONDS = MAX_SEGMENT_SECONDS
        private const val MIN_TRACKED_PAUSE_MS = 150  // pauses plus courtes = micro-respirations, ignorees du profil

        // ── COUPE SUR MICRO-SILENCE (2026-07-25, idee utilisateur) ──────────
        // OBJECTIF : borner le retard de validation SANS jamais couper au
        // milieu d'un mot. Les deux tentatives precedentes echouaient parce
        // qu'elles opposaient ces deux exigences (gel sur pause = frontiere
        // propre mais retard non borne ; gel sur horloge = retard borne mais
        // coupe en plein mot, mesure : segments commencant en pleine parole
        // 5/7 -> 11/14). Ici on ne coupe QUE sur un silence, mais on va le
        // chercher a une resolution assez fine pour qu'il y en ait toujours un.
        //
        // MESURE QUI DEBLOQUE LE PROBLEME : le portier analyse des blocs de
        // 80ms (la taille livree par le micro), granularite trop grossiere pour
        // voir les frontieres de mots -- un micro-arret de 30-40ms est moyenne
        // avec de la parole dans le meme bloc et devient invisible. Mesure sur
        // les WAV captes de l'utilisateur, meme seuil (0.02), resolutions
        // differentes :
        //     80ms -> 15 silences, plages de parole med. 1920ms, max 7760ms
        //     20ms -> 38 silences, plages de parole med.  760ms, max 3800ms
        //     10ms -> 46 silences, plages de parole med.  620ms
        // Le "bloc de 7,76s sans aucun silence" etait donc un ARTEFACT de
        // resolution. A 20ms, la plage mediane vaut 760ms, soit ~1 mot (duree
        // mediane d'un mot mesuree sur les timings officiels quran.com :
        // 1019ms, moyenne 1193ms, max 3420ms). Les micro-arrets existent bien,
        // en nombre suffisant pour decouper mot par mot ou deux par deux.
        //
        // PRINCIPE : quand le buffer atteint la cible, on cherche le
        // micro-silence LE PLUS PROCHE DE LA CIBLE et on coupe la. L'audio situe
        // APRES la coupe reste dans le buffer et servira au segment suivant --
        // c'est ce qui garantit qu'aucun mot n'est saute (demande explicite de
        // l'utilisateur : "il ne faut pas sauter le 2"). Aucun mot n'est juge
        // deux fois : les mots apres la coupe n'ont jamais ete transcrits, donc
        // l'ancre n'a pas avance dessus -- on evite le piege du recouvrement
        // naif (cf. ForcedAligner "TENTATIVE 1", fenetre glissante a WER>100%).
        //
        // Si AUCUN micro-silence n'est trouve (cas theorique), on ne coupe pas :
        // le comportement d'avant reprend la main (pause franche, puis borne
        // dure MAX_SEGMENT_SECONDS). On ne cree jamais de coupe en plein mot.
        private const val FINE_WINDOW_MS = 20         // resolution d'analyse (cf. mesure ci-dessus)
        private const val MIN_MICRO_SILENCE_MS = 40   // 2 fenetres : un vrai inter-mot, pas une occlusive

        // ── CIBLE DE SEGMENT : 3,0s FIXES ────────────────────────────────────
        // HISTORIQUE DES DEUX TENTATIVES PRECEDENTES, conserve pour ne pas les
        // refaire :
        //
        // (a) Cible fixe 2,0s -- MESUREE et REJETEE. Le retard tombait bien a
        //     2,9s de mediane, mais chaque gel ne renvoyait plus qu'UN SEUL mot
        //     avec une frontiere qui n'avancait pas (`ancre=13 frontiere=13
        //     mots=1 nouvelle_ancre=14`, repete a l'identique) : l'aligneur
        //     n'avait pas assez de frames pour placer plusieurs mots, et comme
        //     `isFinal=true` force le jugement ET le verrouillage de tout ce
        //     qu'il renvoie, 278 mots ont ete tamponnes "correct" quasi a vide.
        //     Retour utilisateur : "il valide avant que je dise le mot".
        //
        // (b) Cible DYNAMIQUE `WORDS_PER_SEGMENT (3) x secPerWord`, le debit
        //     etant appris en continu par moyenne glissante sur
        //     `samples figes / mots places`. MESUREE et REJETEE aussi, pour une
        //     raison de fond : quand l'aligneur echoue (`mots=0`, `mots=1` sur
        //     un segment de 4s), ce rapport n'est PAS un debit, c'est un signal
        //     d'echec -- et il pousse la cible vers le haut. Cible plus longue
        //     -> segment plus long -> moins de mots places -> cible encore plus
        //     longue : BOUCLE QUI S'EMBALLE. Mesure du 14:48 : secPerWord parti
        //     de 1,00 s'est envole a 1,53, la cible a 4,6s, et les
        //     transcriptions sont devenues "مِ ٱللَّهِ ٱلرَّحْمَحِيمِ", "هُ".
        //     Ne pas reintroduire d'apprentissage du debit sans regler d'abord
        //     ce point : un echec d'alignement doit etre exclu de la mesure.
        //
        // POURQUOI 3,0s, mesure sur l'audio reel du device (23 WAV, 81s,
        // `benchmark/compare_onnx_on_device_wavs.py`) : depuis un MEME vrai
        // inter-mot, le nombre de mots emis croit avec la duree sans se degrader
        // jusqu'a ~5,6s -- 3,08s -> 5 mots justes, 4,80s -> 8, 5,56s -> 9. Le
        // DEBIT de mots est donc constant (1,6-2,0 mots/s de parole) : l'ancre
        // avance aussi vite avec des segments de 3s qu'avec des segments de
        // 5,5s. Mais le RETARD DE VALIDATION vaut la duree du segment
        // (mesure : retard = duree + 0,3 a 1,5s). 3,0s donne donc la meme
        // precision et le meme avancement pour moitie moins de retard.
        //
        // ⚠️ A NE PAS CROIRE : "au-dela de 3,5-4s la transcription se degrade".
        // Je l'ai ecrit le 2026-07-25 puis MESURE FAUX -- c'etait un artefact de
        // comparaison entre segments qui ne commencaient pas au meme endroit. Ce
        // qui detruit une transcription, c'est un segment qui DEMARRE au milieu
        // d'un mot, pas sa longueur (preuve : le segment de 6,27s capte par
        // l'app rend "هُ", alors que le MEME audio recoupe depuis un vrai
        // inter-mot rend "هُدًى لِّلْمُتَّقِينَ" parfaitement). Le plafond a 3,5s
        // ci-dessous est justifie par le RETARD, jamais par l'acoustique.
        // (c) Cible fixe 3,0s -- TESTEE et REJETEE aussi (2026-07-25, retour
        //     utilisateur). Le retard tombait bien a 2,1-4,6s, mais les
        //     transcriptions se sont DEGRADEES par rapport aux segments longs :
        //     "ٱللَّهُمٍ", "قِينَ", "إِنَّقُونَ" la ou une cible plus longue rendait
        //     du texte propre. Explication mesuree : hors device, en choisissant
        //     LIBREMENT la coupe dans tout l'audio, 3,08s rend
        //     "ذَٰلِكَ ٱلْكِتَـٰبُ لَا رَيْبَ فِيهِ" parfaitement -- mais dans l'app la
        //     coupe du segment N+1 est CONTRAINTE par celle du segment N. Une
        //     coupe qui tombe mal decale toutes les suivantes : les erreurs de
        //     frontiere se COMPOSENT. Raccourcir la cible multiplie les
        //     frontieres, donc les occasions de se tromper.
        //     ⇒ On ne peut pas gagner en jouant sur la longueur. Le retard doit
        //     etre decouple du gel -- cf. la refonte "deux horloges" decrite
        //     dans ARCHITECTURE_RECITATION.md.
        //
        // ETAT COURANT (2026-07-25, demande utilisateur "remettre a 12s") : la
        // coupe sur micro-silence est NEUTRALISEE (cible = la borne dure), donc
        // seuls les mecanismes d'origine agissent -- gel sur pause franche et
        // borne dure MAX_SEGMENT_SECONDS. C'est l'etat de reference sur lequel
        // la refonte sera comparee. `findCutOffset` et les constantes de coupe
        // sont CONSERVES (code et mesures) : ne pas les supprimer, ils
        // documentent trois politiques deja testees.
        private const val TARGET_SECONDS = MAX_SEGMENT_SECONDS
        private const val MIN_TARGET_SECONDS = 2.5f
        // Rayon de recherche du silence AUTOUR de la cible. On coupe au silence
        // le PLUS PROCHE de la cible, jamais au dernier du buffer : couper trop
        // tot laisse une grosse queue d'audio qui depasse elle-meme la cible ->
        // nouvelle coupe immediate -> cascade de gels qui verrouillent un mot a
        // chaque tour meme quand le recitateur s'est TU (bug mesure sur la 1re
        // version).
        private const val CUT_SEARCH_RADIUS_SECONDS = 0.8f
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
    // Planchers de duree de reference (frames), PARALLELE a alignTokens (cf.
    // ForcedAligner.combinedMinFrames, WordTimingService cote Dart). Null pour
    // un mot -> aucune reference (verset hors couverture quran.com), le
    // plancher CTC reste seul a s'appliquer pour ce mot.
    @Volatile private var alignRefMinFrames: List<Int?>? = null
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
        // Planchers de duree de reference (frames), paralleles a `tokens` --
        // cf. ForcedAligner.combinedMinFrames (2026-07-27).
        refMinFrames: List<Int?>? = null,
    ) {
        alignTokens = tokens
        alignVariants = variants
        alignRefMinFrames = refMinFrames
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
        newRefMinFrames: List<Int?>? = null,
    ) {
        val current = alignTokens
        alignTokens = if (current != null) current + newTokens else newTokens
        if (newVariants != null) {
            val currentV = alignVariants ?: List(current?.size ?: 0) { emptyList() }
            alignVariants = currentV + newVariants
        }
        if (newRefMinFrames != null) {
            val currentR = alignRefMinFrames ?: List(current?.size ?: 0) { null }
            alignRefMinFrames = currentR + newRefMinFrames
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
                             segmentSamples: Int = 0): Int {
        val tokens = alignTokens ?: return -1
        val anchor = alignAnchor
        if (anchor >= tokens.size) return -1
        try {
            val end = minOf(tokens.size, anchor + maxAlignWords)
            val slice = tokens.subList(anchor, end)
            // forceJudgeIndex seulement sur un appel FINAL : un apercu ne
            // verrouille jamais rien, differer un mot sur un apercu ne compte
            // pas comme une "tentative" reelle.
            //
            // ... et seulement sur un segment assez long pour ETRE une vraie
            // seconde chance (ajout 2026-07-25). Le commentaire de
            // deferredOnceIndex dit "si le MEME mot se retrouve encore a la
            // frontiere avec trop peu d'opportunite, on le juge quand meme" :
            // un segment de 0,2s n'est pas une opportunite. Mesure qui l'a
            // impose : le gel parasite du 14:12:22.609 (200ms d'audio) est
            // arrive avec forceJudgeIndex=19 et a juge يُنفِقُونَ en rouge avec
            // `entendu=""`. Avec commitInFlight + le garde-fou de duree
            // minimale, un tel segment ne peut plus etre fige -- cette
            // condition est un filet de securite : aucun mot ne doit JAMAIS
            // etre juge sans preuve acoustique, quel que soit le chemin.
            val realChance = segmentSamples >= (SAMPLE_RATE * MIN_COMMIT_SECONDS).toInt()
            val forceIdx = if (isFinal && realChance) deferredOnceIndex else -1
            val variantsSlice = alignVariants?.let {
                if (anchor < it.size) it.subList(anchor, minOf(it.size, end)) else null
            }
            val refMinFramesSlice = alignRefMinFrames?.let {
                if (anchor < it.size) it.subList(anchor, minOf(it.size, end)) else null
            }
            val res = aligner.align(logprobs, slice, anchor, forceIdx, isFinal, variantsSlice,
                                    segmentRules, refMinFramesSlice) ?: return -1
            val words = res.words.map {
                mapOf(
                    "i" to it.index,
                    "gop" to it.gop,
                    "forced" to it.forced,
                    "covered" to it.covered,
                    "actual" to it.actual,
                    // Mot etrangle (2026-07-27) : la DP lui a donne moins de
                    // frames que le minimum requis par le CTC. Complete le
                    // signal `free` cote Dart pour le garde-fou "pas de
                    // jugement sans preuve exploitable" -- cf. WordResult.starved.
                    "starved" to it.starved,
                ) + (it.rescoreMargin?.let { m -> mapOf("rescoreMargin" to m) } ?: emptyMap()) +
                    (it.rescoreHeard?.let { h -> mapOf("rescoreHeard" to h) } ?: emptyMap()) +
                    // Regles REELLEMENT detectees sur les frames de ce mot
                    // (tete 2). Cle absente si aucune -> le Dart distingue
                    // "modele sans tete tajwid" de "regle non realisee".
                    (if (it.detectedRules.isEmpty()) emptyMap() else mapOf(
                        "rules" to it.detectedRules.map { r ->
                            mapOf("id" to r.ruleId, "prob" to r.prob.toDouble())
                        })) +
                    // Provenance du texte `actual` (cf. WordResult.actualFromFree) :
                    // journalisee cote Dart en `src=libre` / `src=dp`.
                    (if (it.actualFromFree) mapOf("srcFree" to true) else emptyMap())
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
                alignAnchor = anchor + res.words.size
                // (Ici vivait l'apprentissage du debit `secPerWord`, retire le
                // 2026-07-25 : voir le bloc (b) des constantes de segment -- un
                // echec d'alignement y etait compte comme un debit et faisait
                // s'emballer la cible.)
                // cf. deferredOnceIndex : ce FINAL a soit juge le mot qu'on
                // forcait (forceIdx, alors deja inclus dans res.words -> on
                // efface le garde-fou), soit differe un NOUVEAU mot (a
                // repasser en force au prochain FINAL), soit n'a rien differe
                // du tout (deferredIndex=null -> RAZ).
                // `realChance` (cf. plus haut) : sur un segment trop court pour
                // etre une vraie chance, on n'a PAS force -- il ne faut donc pas
                // consommer le sursis en cours, sinon le mot perd sa seconde
                // chance sans l'avoir eue.
                deferredOnceIndex = res.deferredIndex ?: (if (realChance) -1 else deferredOnceIndex)
            }
            DiagnosticLog.log(TAG, "alignement seq=$alignSeq ancre=$anchor frontiere=${res.frontier} " +
                    "final=$isFinal mots=${words.size} nouvelle_ancre=$alignAnchor " +
                    "differe=$deferredOnceIndex derniere_frame=${res.lastFrame}")
            return res.lastFrame
        } catch (e: Exception) {
            DiagnosticLog.log(TAG, "echec alignement force: ${e.message}")
        }
        return -1
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
    // VRAI entre le prelevement de l'extrait d'un gel et la purge du buffer par
    // la coroutine (~265ms plus tard, duree de l'inference). Pendant cette
    // fenetre `samples` MENT : il contient encore l'audio deja parti en
    // inference et deja en cours de verrouillage. Toute decision prise sur
    // `samples.size` y est donc fausse -- ce drapeau les interdit toutes.
    //
    // BUG QUI A IMPOSE CE DRAPEAU (mesure 2026-07-25, log 14:12:22) : les blocs
    // PCM arrivent par rafales (deux feed() a 4ms d'ecart portant 80ms d'audio
    // chacun). La 2e a rearme la MEME coupe (offset 3320ms) sur le buffer non
    // encore purge ; `busy` etant pris, elle est restee en attente ; une fois le
    // buffer purge il ne restait que 120ms, et cet offset perime a fige un
    // segment de 0,2s (`segment FIGE 0s -> 34ms : "م"`) qui a verrouille
    // يُنفِقُونَ en ROUGE avec `entendu=""` 300ms AVANT que l'utilisateur ne le
    // prononce -- puis a fait avancer l'ancre, si bien que le mot suivant
    // recevait l'audio du precedent. C'est exactement le "la validation m'a
    // devance" rapporte.
    @Volatile private var commitInFlight = false
    // Offset (samples) ou couper le prochain segment fige, trouve sur un
    // micro-silence (cf. findCutOffset). -1 = pas de coupe programmee, le
    // segment est fige en entier comme avant.
    @Volatile private var pendingCutOffset = -1
    // Taille du buffer couverte par le dernier apercu (latestText) — permet au
    // gel force de figer l'apercu sans re-transcrire (cf. borne dure ci-dessous).
    @Volatile private var lastPreviewSize = 0
    // Debut (horloge murale) de l'audio actuellement dans le buffer -- sert
    // UNIQUEMENT a logger l'ecart entre le moment ou un mot a ete PRONONCE et
    // celui ou il est VALIDE (demande utilisateur 2026-07-25 : mesurer le
    // retard du curseur sans le deduire). Aucune influence sur le
    // comportement : ni la segmentation, ni le jugement ne le lisent.
    @Volatile private var segmentStartWallMs = 0L
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

    /** RMS d'une fenetre de [len] samples a partir de [from]. */
    private fun rmsAt(buf: FloatArray, from: Int, len: Int): Float {
        var sum = 0.0
        val end = minOf(from + len, buf.size)
        for (i in from until end) sum += buf[i].toDouble() * buf[i]
        val n = end - from
        return if (n <= 0) 0f else sqrt(sum / n).toFloat()
    }

    /**
     * Cherche dans [buf] le micro-silence (>= [MIN_MICRO_SILENCE_MS]) dont le
     * milieu est le PLUS PROCHE de [targetOffset], entre [minKeep] (jamais de
     * segment plus court) et la FIN du buffer. Retourne l'offset de coupe
     * (milieu du silence : queue propre pour le segment fige, amorce propre
     * pour le suivant), ou -1 si aucun silence exploitable.
     *
     * "LE PLUS PROCHE DE LA CIBLE" et non "le dernier du buffer" : couper trop
     * tot laisse une queue qui depasse elle-meme la cible -> recoupe immediate
     * -> cascade de gels verrouillant un mot a chaque tour, meme quand le
     * recitateur s'est tu (bug mesure sur la 1re version, cf. constantes).
     *
     * BORNE DROITE = FIN DU BUFFER, correctif 2026-07-25 (2e mesure, validee
     * par l'utilisateur). Avant, la recherche etait enfermee dans un couloir
     * FIXE [cible-0,8s ; cible+0,8s] qui ne bougeait jamais : si ce couloir de
     * 1,6s ne contenait aucun micro-silence, findCutOffset rendait -1, et au
     * bloc suivant on rescannait EXACTEMENT le meme couloir avec le meme
     * resultat -- indefiniment. Mesure sur la session du 14:25 : sur 15 gels,
     * 5 coupes seulement, toutes dans les 15 premieres secondes, puis PLUS
     * AUCUNE. Les segments montaient alors a 4s, 5s, 6s, 7s (seules la pause
     * franche et la borne dure tranchaient encore) et le retard de validation
     * passait de ~3s a 7,5-8,2s.
     *
     * Pire, c'est ce qui provoquait la DESYNCHRONISATION de la fin de session :
     * a 6-7s la transcription libre s'effondre (derive de normalisation deja
     * documentee en tete de fichier). Le gel de 7s a 14:26:09 a AVALE 4 mots
     * (le texte rendu ne contenait ni "ءَأَنذَرْتَهُمْ" ni "أَمْ لَمْ تُنذِرْهُمْ"),
     * l'ancre a donc pris 7 mots de retard ; a partir de la, l'audio qui
     * arrivait ne contenait plus les mots attendus, l'aligneur ne placait plus
     * qu'UN mot par gel (ancre 45,46,47,48,49) et ne rattrapait JAMAIS. En
     * gardant les segments courts des qu'un micro-silence existe quelque part
     * apres la cible, la transcription reste dans son domaine de stabilite et
     * l'ancre suit le recitateur.
     *
     * Pas de retour de la cascade : la selection reste "le plus proche de la
     * cible" (donc la queue laissee derriere est minimale) et [minKeep]
     * garantit que tout segment fige fait au moins MIN_TARGET_SECONDS -- les
     * micro-segments a `mots=1` de la v1 sont structurellement impossibles.
     *
     * Analyse a FINE_WINDOW_MS et non par blocs de 80ms : c'est tout l'objet du
     * correctif -- a 80ms les frontieres de mots sont invisibles (mesure : 15
     * silences vus a 80ms contre 38 a 20ms sur le meme audio).
     */
    private fun findCutOffset(buf: FloatArray, targetOffset: Int, minKeep: Int): Int {
        val win = SAMPLE_RATE * FINE_WINDOW_MS / 1000
        val minRunWins = MIN_MICRO_SILENCE_MS / FINE_WINDOW_MS
        val radius = (SAMPLE_RATE * CUT_SEARCH_RADIUS_SECONDS).toInt()
        // Borne GAUCHE bornee par le rayon : on ne coupe jamais loin AVANT la
        // cible (sinon segments inutilement courts). Borne DROITE = fin du
        // buffer : elle avance avec l'audio, c'est ce qui rend la fenetre
        // glissante (cf. bloc de documentation ci-dessus).
        val from = maxOf(minKeep, targetOffset - radius)
        val to = buf.size
        if (to - from < win * minRunWins) return -1

        var best = -1
        var bestDist = Int.MAX_VALUE
        var runStart = -1
        var i = from
        while (i + win <= to) {
            val silent = rmsAt(buf, i, win) < SILENCE_RMS_THRESHOLD
            if (silent) {
                if (runStart < 0) runStart = i
            } else if (runStart >= 0) {
                if (i - runStart >= win * minRunWins) {
                    val mid = (runStart + i) / 2
                    val dist = kotlin.math.abs(mid - targetOffset)
                    if (dist < bestDist) { bestDist = dist; best = mid }
                }
                runStart = -1
            }
            i += win
        }
        // Silence encore ouvert a la fin de la plage examinee.
        if (runStart >= 0 && to - runStart >= win * minRunWins) {
            val mid = (runStart + to) / 2
            if (kotlin.math.abs(mid - targetOffset) < bestDist) best = mid
        }
        return best
    }

    /** Cible de longueur de segment (cf. TARGET_SECONDS pour la mesure). */
    private fun targetSeconds(): Float =
        TARGET_SECONDS.coerceIn(MIN_TARGET_SECONDS, MAX_TARGET_SECONDS)

    fun reset() {
        synchronized(lock) { samples = FloatArray(0) }
        latestText = ""
        committedText = ""
        lastRunSize = 0
        segmentStartWallMs = 0L // mesure seule, cf. segmentStartWallMs
        retainedSilenceSamples = 0
        pauseSamples = 0
        pendingCommit = false
        pendingForceCommit = false
        pendingCutOffset = -1
        commitInFlight = false
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
        // Horodatage du debut de l'audio de ce segment (mesure seule, cf.
        // segmentStartWallMs) -- pose au premier bloc effectivement accumule.
        if (segmentStartWallMs == 0L && size > 0) segmentStartWallMs = System.currentTimeMillis()
        // Le gel exige un segment assez long — verifie ICI (au moment de armer
        // le flag) ET au lancement (le flag peut survivre a un gel precedent :
        // course observee en test reel, micro-segment d'1s fige corrompu).
        if (isSilence && pauseSamples >= commitSilenceSamples &&
            sizeSeconds >= MIN_COMMIT_SECONDS && !commitInFlight
        ) {
            pendingCommit = true // pause franche sur un segment assez long -> fin de verset/groupe probable
        }
        // Coupe sur MICRO-SILENCE (cf. commentaire des constantes) : des que le
        // buffer atteint la longueur visee, on cherche en arriere un vrai
        // inter-mot et on coupe la. Si on n'en trouve pas, on ne force RIEN --
        // les mecanismes d'avant (pause franche, borne dure) gardent la main,
        // donc on ne coupe jamais en plein mot.
        val target = targetSeconds()
        if (!pendingCommit && pendingCutOffset < 0 && !commitInFlight && sizeSeconds >= target) {
            val targetOffset = (SAMPLE_RATE * target).toInt()
            val minKeep = (SAMPLE_RATE * MIN_TARGET_SECONDS).toInt()
            val cut = synchronized(lock) { findCutOffset(samples, targetOffset, minKeep) }
            if (cut > 0) {
                pendingCutOffset = cut
                pendingCommit = true
                DiagnosticLog.log(TAG, "coupe sur micro-silence a ${cut * 1000 / SAMPLE_RATE}ms " +
                        "(buffer ${"%.1f".format(sizeSeconds)}s, cible ${"%.1f".format(target)}s) " +
                        "-- ${(size - cut) * 1000 / SAMPLE_RATE}ms conserves pour le segment suivant")
            }
        }
        if (sizeSeconds >= MAX_SEGMENT_SECONDS && !commitInFlight) {
            // Borne dure : recitation continue sans pause detectee. On ne
            // RE-transcrit PAS (test reel 2026-07-05 : a 12s la re-transcription
            // de gel etait degradee alors que le dernier apercu etait parfait) —
            // on fige le dernier apercu tel quel et on ne retire du buffer que
            // l'audio qu'il couvrait.
            pendingForceCommit = true
        }
        // Garde-fou de duree minimale. Il teste la longueur REELLEMENT PREVUE
        // pour le gel (l'offset de coupe s'il y en a un, sinon tout le buffer)
        // et non `sizeSeconds`.
        //
        // TENTATIVE PRECEDENTE, FAUSSE (2026-07-25, conservee comme mise en
        // garde) : la condition portait `&& pendingCutOffset < 0`, au motif
        // qu'un gel programme respecte deja MIN_TARGET_SECONDS par
        // construction (parametre minKeep de findCutOffset). C'est vrai DANS LE
        // BUFFER OU L'OFFSET A ETE CALCULE -- et faux des que ce buffer est
        // purge entre-temps. Cette exclusion a perce le trou par lequel un
        // offset perime de 3320ms a fige un segment de 200ms et verrouille un
        // mot en rouge avant qu'il soit prononce (cf. commitInFlight). Ne pas
        // la reintroduire : c'est precisement ce garde-fou, dans sa forme
        // d'origine, qui rattrapait la course.
        val plannedSamples = if (pendingCutOffset > 0) minOf(pendingCutOffset, size) else size
        if (pendingCommit && plannedSamples < (SAMPLE_RATE * MIN_COMMIT_SECONDS).toInt()) {
            pendingCommit = false // segment prevu trop court (flag herite, ou offset perime)
            pendingCutOffset = -1
        }
        // Un offset de coupe qui depasse le buffer n'a plus aucun sens : il a
        // ete calcule sur un audio qui n'est plus la. On l'invalide ICI plutot
        // que de le laisser degrader au prelevement (ou il figeait TOUT le
        // buffer -- le pire choix possible, cf. le log de l'anomalie plus bas).
        if (pendingCutOffset > 0 && pendingCutOffset >= size) {
            DiagnosticLog.log(TAG, "offset de coupe perime (${pendingCutOffset} >= buffer ${size}) " +
                    "-- invalide, aucun gel")
            pendingCutOffset = -1
            pendingCommit = false
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
                val ageMs = System.currentTimeMillis() - segmentStartWallMs
                segmentStartWallMs = 0L
                DiagnosticLog.log(TAG, "segment FIGE (borne ${MAX_SEGMENT_SECONDS}s, apercu reutilise, ${covered / SAMPLE_RATE}s couverts) " +
                        "| VALIDATION retard=${ageMs}ms depuis le debut de cet audio : \"${previewText.take(80)}\"")
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
            // Coupe sur micro-silence : on ne transcrit/juge QUE jusqu'au
            // silence trouve. L'audio d'apres reste dans `samples` (la purge
            // post-gel plus bas retire exactement `snapshot.size`), donc il
            // sera transcrit avec le segment suivant -- aucun mot saute, aucun
            // mot juge deux fois.
            val cutAt = if (committing) pendingCutOffset else -1
            pendingCutOffset = -1
            // A partir d'ici et jusqu'a la purge (cf. bloc `committing` dans la
            // coroutine), `samples` contient de l'audio deja en cours de gel :
            // aucune decision de segmentation ne doit plus s'appuyer dessus.
            if (committing) commitInFlight = true
            val snapshot: FloatArray
            synchronized(lock) {
                snapshot = if (cutAt in 1 until samples.size) {
                    samples.copyOfRange(0, cutAt)
                } else {
                    // Ne devrait plus jamais arriver (invalide en amont) -- mais
                    // ce repli figeait TOUT le buffer en silence : le rendre
                    // visible plutot que muet.
                    if (cutAt > 0) DiagnosticLog.log(TAG,
                            "ANOMALIE: offset de coupe $cutAt hors buffer ${samples.size} au prelevement")
                    samples.copyOf()
                }
            }
            scope.launch(Dispatchers.Default) {
                try {
                    // Correctif crash natif (2026-07-23, mesure device : "JNI
                    // DETECTED ERROR IN APPLICATION: java_class == null" dans
                    // ai.onnxruntime.OrtSession.run, sur un thread du pool
                    // Dispatchers.Default -- SIGABRT, process tue). Un thread de
                    // pool de coroutines cree par kotlinx.coroutines n'herite pas
                    // toujours du classloader applicatif (PathClassLoader) qui a
                    // charge les classes ai.onnxruntime.* -- FindClass/GetMethodID
                    // resolvent alors contre le bootstrap classloader et
                    // echouent. Fixer explicitement le classloader du thread
                    // AVANT tout appel dans la bibliotheque native regle la cause
                    // (pas juste le symptome) : reproduit 3 fois de suite avant
                    // ce correctif, plus jamais depuis.
                    Thread.currentThread().contextClassLoader =
                        FastConformerCtc::class.java.classLoader
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
                        // ── ALIGNER D'ABORD, PURGER ENSUITE (2026-07-25) ────
                        // L'ordre est essentiel : c'est l'alignement qui dit
                        // jusqu'ou l'audio a ete REELLEMENT consomme, et on ne
                        // purge que jusque-la.
                        //
                        // CE QUE CA CORRIGE (mesure du 16:32) : avant, le buffer
                        // jetait TOUT le segment alors que l'ancre n'avancait que
                        // de `words.size`. Exemple exact du log --
                        //   seq=20 : `segment FIGE 3s : "وَمَآ أُنزِلَ مِنبِ"`,
                        //   `ancre=25 frontiere=25 mots=1 nouvelle_ancre=26`.
                        // L'audio contenait les mots 25, 26, 27 (+ debut de 28) ;
                        // l'aligneur n'a place QUE le mot 25 ; l'audio de 26 et 27
                        // a ete DETRUIT. Deux gels plus tard :
                        //   `mot=26 "أُنزِلَ" forced=-20.00 entendu="" -> error`
                        //   `mot=27 "مِن"    forced=-20.00 entendu="" -> error`
                        // -- rouges definitifs sur des mots reellement prononces,
                        // juges sur un audio qui ne les contenait pas. L'ancre est
                        // restee bloquee a 28 pendant que le recitateur etait au
                        // mot 43 ("la validation ne me suit pas").
                        //
                        // Ce N'EST PAS un recouvrement : l'audio conserve n'a
                        // jamais ete juge. Le piege de duplication (cf.
                        // "TENTATIVE 1" dans ForcedAligner, fenetre glissante
                        // naive a WER > 100 %) ne s'applique pas -- a condition
                        // de ne figer QUE le texte des frames consommees, d'ou la
                        // borne passee a greedyDecode ci-dessous.
                        // Capture du clip (cf. setClipCapture) -- ECRITE AVANT
                        // l'alignement depuis le 2026-07-25 : `clipPath` est joint
                        // au payload d'alignement, il doit donc exister avant
                        // l'appel. Ne depend que de `snapshot`, l'ordre est donc
                        // libre. Best-effort : un echec d'ecriture ne doit jamais
                        // interrompre la recitation en cours.
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
                        val lastFrame = runAlignment(logprobs, isFinal = true,
                                                     clipPath = clipPath,
                                                     segmentRules = segmentRules,
                                                     segmentSamples = snapshot.size)
                        // Conversion frames -> samples DEDUITE, jamais codee en
                        // dur : le facteur de sous-echantillonnage de l'encodeur
                        // est une propriete du modele exporte ; une constante
                        // fausse ne se verrait pas et decalerait tout.
                        val samplesPerFrame =
                            if (logprobs.isNotEmpty()) snapshot.size / logprobs.size else 0
                        val consumed = if (lastFrame >= 0 && samplesPerFrame > 0) {
                            minOf(snapshot.size, (lastFrame + 1) * samplesPerFrame)
                        } else {
                            // Aucun mot place (ou pas de cible d'alignement) :
                            // comportement historique, on purge tout. Conserver le
                            // buffer ici FIGERAIT la session -- on recommitterait
                            // sans fin le meme audio sans jamais progresser.
                            snapshot.size
                        }
                        synchronized(lock) {
                            samples = if (samples.size > consumed) {
                                samples.copyOfRange(consumed, samples.size)
                            } else {
                                FloatArray(0)
                            }
                            lastRunSize = samples.size
                        }
                        // Texte fige = celui des frames consommees UNIQUEMENT.
                        val committedPart =
                            if (consumed < snapshot.size) engine.greedyDecode(logprobs, lastFrame)
                            else text
                        val sep = if (committedText.isEmpty()) "" else " "
                        committedText = committedText + sep + committedPart
                        latestText = ""
                        lastPreviewSize = 0
                        // Ecart AUDIO -> VALIDATION : temps ecoule entre le
                        // DEBUT de l'audio de ce segment et l'instant ou ses
                        // mots sont definitivement valides (l'ancre avance
                        // juste apres, cf. runAlignment isFinal=true). C'est
                        // exactement le retard du curseur percu a l'ecran.
                        // `wav=` permet de recaler sur le fichier capte.
                        val ageMs = System.currentTimeMillis() - segmentStartWallMs
                        segmentStartWallMs = 0L
                        DiagnosticLog.log(TAG, "segment FIGE ${snapshot.size / SAMPLE_RATE}s -> ${ms}ms " +
                                "| consomme=${consumed * 1000 / SAMPLE_RATE}ms " +
                                "conserve=${(snapshot.size - consumed) * 1000 / SAMPLE_RATE}ms " +
                                "| VALIDATION retard=${ageMs}ms depuis le debut de cet audio" +
                                "${if (clipPath != null) " | wav=${clipPath.substringAfterLast('/')}" else ""}" +
                                " : \"${committedPart.take(80)}\"")
                    } else {
                        latestText = text
                        lastPreviewSize = snapshot.size
                        DiagnosticLog.log(TAG, "retranscription ${snapshot.size / SAMPLE_RATE}s -> ${ms}ms : \"${text.take(80)}\"")
                        runAlignment(logprobs, isFinal = false, segmentRules = segmentRules)
                    }
                } catch (e: Exception) {
                    DiagnosticLog.log(TAG, "echec retranscription: ${e.message}")
                } finally {
                    // Leve dans le `finally` et non apres la purge : si
                    // l'inference echoue, la purge n'a PAS lieu, le buffer est
                    // donc intact et les decisions peuvent reprendre
                    // immediatement. L'oublier ici bloquerait tout gel jusqu'a
                    // la fin de la session.
                    commitInFlight = false
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

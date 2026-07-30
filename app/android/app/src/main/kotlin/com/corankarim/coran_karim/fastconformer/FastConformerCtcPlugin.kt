package com.corankarim.coran_karim.fastconformer

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Deuxieme verificateur ASR (FastConformer CTC), en parallele de whisper.cpp
 * (canal FFI existant de whisper_ggml, inchange). Un MethodChannel est utilise ici
 * plutot que du FFI car l'API ONNX Runtime Android est Kotlin/Java, pas une lib C
 * a lier directement -- pas de pattern FFI adapte pour ce modele.
 *
 * Cote Dart : voir lib/services/fastconformer_verifier.dart.
 */
class FastConformerCtcPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private companion object { const val TAG = "FastConformerCtcPlugin" }

    private lateinit var channel: MethodChannel
    private var engine: FastConformerCtc? = null
    private var streaming: FastConformerStreamingSession? = null
    private var causalAlignment: CausalAlignmentSession? = null
    private var buffered: BufferedTranscriber? = null
    // Seuil personnalise recu AVANT la creation (lazy) du BufferedTranscriber —
    // applique des sa construction, sinon un setCommitSilenceMs appele avant le
    // premier bloc audio serait perdu.
    @Volatile private var pendingCommitSilenceMs: Int? = null
    /** Retenu ici tant que `buffered` n'existe pas (le reglage arrive avant la
     *  premiere inference) -- meme motif que pendingCommitSilenceMs. */
    @Volatile private var pendingNeverBlockAnchor = false
    // Meme pattern : dossier de capture des clips de reference (mini-LoRA
    // personnalisation vocale, cf. setClipCapture), applique des la creation
    // du BufferedTranscriber si demande avant le premier bloc audio.
    @Volatile private var pendingClipCaptureDir: String? = null
    // Cible d'alignement force GOP (cf. ForcedAligner.kt) : mots attendus
    // tokenises + ancre. Stockee au niveau plugin (meme pattern que
    // pendingCommitSilenceMs : setAlignmentTarget peut arriver AVANT le premier
    // bloc audio qui cree le BufferedTranscriber) ET utilisee directement par
    // alignFile (mode coach, un seul WAV, pas de BufferedTranscriber).
    @Volatile private var alignTokens: List<IntArray>? = null
    @Volatile private var alignAnchor: Int = 0
    // Rescoring NLL par mot (cf. ForcedAligner.WordResult.rescoreMargin,
    // ConfusableVariants) : desactive par defaut -- diagnostic pas encore
    // valide sur device (offline seulement, cf. constrained_decoding_eval.py),
    // et calcule un forward CTC supplementaire par variante confusable sur
    // CHAQUE mot d'une passe finale. Active via setRescoringEnabled(true).
    @Volatile private var rescoringEnabled: Boolean = false
    @Volatile private var alignVariants: List<List<Pair<String, IntArray>>>? = null
    private var tokenizer: CtcTokenizer? = null
    // Dictionnaire mot->tokens precalcule (cf. loadModel) -- null si absent.
    @Volatile private var wordTokenLookup: Map<String, IntArray>? = null
    private var fingerprint: VoiceFingerprint? = null
    // ── CHAINE v2, BRANCHEE EN PARALLELE (2026-07-30) ────────────────────────
    // Elle tourne EN PLUS de la v1, sur le meme PCM, et rend ses verdicts a
    // part. C'est le motif que le projet utilise deja pour comparer deux
    // moteurs (`useGopScoring` : les deux calculent, un seul peint l'ecran) --
    // la v1 ne peut donc pas regresser du fait de son branchement.
    // Mesure de reference (banc, flux brut du 2026-07-30) : v1 10,10 % de mots
    // non verts, v2 2,03 %.
    @Volatile private var v2Actif = false
    private var v2Chaine: com.corankarim.coran_karim.recitation2.ChaineRecitation? = null
    @Volatile private var v2Mots: List<String> = emptyList()
    private val scope = CoroutineScope(Dispatchers.Default)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.corankarim/fastconformer_ctc")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        engine?.close()
        engine = null
        streaming?.close()
        streaming = null
        causalAlignment = null
        fingerprint?.close()
        fingerprint = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Relie le fichier de log persistant sur le telephone (cf.
            // lib/services/diagnostic_log.dart) -- BufferedTranscriber et
            // ForcedAligner y ecrivent via DiagnosticLog.kt pour que TOUT le
            // pipeline (Dart + natif) atterrisse dans la meme chronologie,
            // recuperable par `adb pull` a la demande (demande utilisateur
            // 2026-07-11), independamment de toute connexion adb continue.
            "setLogFile" -> {
                val path = call.argument<String>("path")
                if (path != null) DiagnosticLog.setFile(path)
                result.success(null)
            }
            "loadModel" -> scope.launch {
                try {
                    // Correctif crash natif (2026-07-23) : voir le meme
                    // correctif et son explication complete dans
                    // BufferedTranscriber.kt (juste avant engine.computeAll).
                    // Ici en plus car c'est la PREMIERE fois que le thread
                    // touche la bibliotheque native (creation de la session
                    // ONNX) -- fixer le classloader des ce premier contact
                    // laisse la lib natif mettre en cache les bonnes
                    // references de classe pour tous les appels suivants,
                    // depuis n'importe quel thread du pool.
                    Thread.currentThread().contextClassLoader =
                        FastConformerCtc::class.java.classLoader
                    // Idempotent : NE PAS fermer/recreer un moteur deja charge.
                    // `engine` est partage par tous les appelants Dart (la
                    // transcription mono-shot ET le flux continu bufferise du
                    // karaoke, cf. feedBufferedAudio) -- chaque nouvelle
                    // instance Dart de FastConformerVerifier() a son propre
                    // flag `_loaded` local et rappelle loadModel() sans savoir
                    // qu'un moteur tourne deja. Bug reel constate 2026-07-06 :
                    // ouvrir la boucle de correction manuelle ("reessayer ce
                    // mot") pendant une recitation karaoke fermait la session
                    // ONNX en cours d'utilisation par le flux continu ->
                    // IllegalStateException "Trying to score a closed
                    // OrtSession" en boucle, recitation cassee jusqu'a relance.
                    if (engine != null) {
                        withContext(Dispatchers.Main) { result.success(true) }
                        return@launch
                    }
                    // Une autre instance Dart peut appeler loadModel pendant
                    // une recitation causale. Ne jamais fermer son moteur
                    // global : le changement explicite passe d'abord par
                    // disposeStreaming(), sinon ce chargement est refuse.
                    if (streaming != null) {
                        withContext(Dispatchers.Main) { result.success(false) }
                        return@launch
                    }
                    val modelPath = call.argument<String>("modelPath")!!
                    val vocabPath = call.argument<String>("vocabPath")!!
                    // rules.json : noms des classes de la TETE 2 (modeles a deux
                    // tetes, cf. export_dual_head_checkpoint.py). Optionnel --
                    // absent sur les anciens modeles, la detection tajwid reste
                    // alors simplement inactive.
                    val rulesPath = call.argument<String>("rulesPath")
                    engine = FastConformerCtc(modelPath, vocabPath, rulesPath)
                    DiagnosticLog.log(TAG, "modele charge — tete tajwid : " +
                        if (engine!!.hasTajwid) "OUI (${engine!!.ruleNames.size} classes)"
                        else "non (modele a une seule tete)")
                    // Dictionnaire mot->tokens precalcule (optionnel, cf.
                    // build_word_token_lookup.py) -- source primaire du
                    // tokenizer de l'alignement force, null si absent
                    // (CtcTokenizer se rabat alors sur le greedy pour tout).
                    val wordTokensPath = call.argument<String>("wordTokensPath")
                    wordTokenLookup = wordTokensPath?.let { loadWordTokenLookup(it) }
                    tokenizer = null // reconstruit au prochain setAlignmentTarget avec le bon lookup
                    withContext(Dispatchers.Main) { result.success(true) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("LOAD_FAILED", e.message, null) }
                }
            }
            "transcribe" -> scope.launch {
                try {
                    val wavPath = call.argument<String>("wavPath")!!
                    val current = engine
                    if (current == null) {
                        withContext(Dispatchers.Main) { result.error("NOT_LOADED", "loadModel() n'a pas ete appele", null) }
                        return@launch
                    }
                    val pcm = WavReader.readMono16kFloat(wavPath)
                    val text = current.transcribe(pcm)
                    withContext(Dispatchers.Main) { result.success(text) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("TRANSCRIBE_FAILED", e.message, null) }
                }
            }
            "dispose" -> {
                buffered = null
                engine?.close()
                engine = null
                result.success(null)
            }
            // ── Streaming cache-aware (vrai flux continu, karaoke) ─────────────
            "loadStreamingModel" -> scope.launch {
                try {
                    if (streaming != null) {
                        withContext(Dispatchers.Main) { result.success(true) }
                        return@launch
                    }
                    // Symetrique de loadModel : une instance secondaire ne
                    // doit pas fermer le moteur stateless d'une session active.
                    // Le proprietaire appelle dispose() avant une bascule
                    // intentionnelle (FastConformerVerifier).
                    if (engine != null) {
                        withContext(Dispatchers.Main) { result.success(false) }
                        return@launch
                    }
                    val modelPath = call.argument<String>("modelPath")!!
                    val vocabPath = call.argument<String>("vocabPath")!!
                    val configPath = call.argument<String>("configPath")!!
                    val wordTokensPath = call.argument<String>("wordTokensPath")
                    // Contrainte device 6 Go : le modele causal et le modele
                    // stateless ne doivent jamais cohabiter. Le fallback est
                    // recharge seulement si ce chargement echoue cote Dart.
                    buffered = null
                    Thread.currentThread().contextClassLoader =
                        FastConformerStreamingSession::class.java.classLoader
                    val newStreaming = FastConformerStreamingSession(
                        modelPath,
                        vocabPath,
                        configPath,
                    )
                    streaming = newStreaming
                    causalAlignment = CausalAlignmentSession(
                        newStreaming.vocabPieces,
                        newStreaming.blank,
                    )
                    wordTokenLookup =
                        wordTokensPath?.let { loadWordTokenLookup(it) }
                    tokenizer = null
                    withContext(Dispatchers.Main) { result.success(true) }
                } catch (e: Exception) {
                    streaming?.close()
                    streaming = null
                    causalAlignment = null
                    withContext(Dispatchers.Main) { result.error("LOAD_STREAMING_FAILED", e.message, null) }
                }
            }
            "feedAudioChunk" -> scope.launch {
                try {
                    val pcm16 = call.argument<ByteArray>("pcm16")!!
                    val current = streaming
                    if (current == null) {
                        withContext(Dispatchers.Main) { result.error("NOT_LOADED", "loadStreamingModel() n'a pas ete appele", null) }
                        return@launch
                    }
                    val samples = pcm16ToFloat(pcm16)
                    val output = current.feedAudio(samples)
                    withContext(Dispatchers.Main) { result.success(output.text) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("FEED_CHUNK_FAILED", e.message, null) }
                }
            }
            "feedCausalAudio" -> scope.launch {
                try {
                    val pcm16 = call.argument<ByteArray>("pcm16")!!
                    val current = streaming
                    if (current == null) {
                        withContext(Dispatchers.Main) {
                            result.error(
                                "NOT_LOADED",
                                "loadStreamingModel() n'a pas ete appele",
                                null,
                            )
                        }
                        return@launch
                    }
                    val output = current.feedAudio(pcm16ToFloat(pcm16))
                    val alignment = causalAlignment?.feed(output.logProbs)
                    val payload = mapOf(
                        "committed" to output.text,
                        "preview" to "",
                        "align" to alignment,
                        "inferenceCount" to output.inferenceCount,
                        "cacheLength" to output.cacheLength,
                    )
                    withContext(Dispatchers.Main) { result.success(payload) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) {
                        result.error("FEED_CAUSAL_FAILED", e.message, null)
                    }
                }
            }
            "resetStreaming" -> {
                streaming?.reset()
                causalAlignment?.reset()
                result.success(null)
            }
            "disposeStreaming" -> {
                streaming?.close()
                streaming = null
                causalAlignment = null
                result.success(null)
            }
            // ── Streaming "bufferise" (fallback fiable, cf. BufferedTranscriber) ──
            // Reutilise le moteur OFFLINE (engine) deja charge via loadModel --
            // pas de session/modele separe a charger ici.
            "feedBufferedAudio" -> scope.launch {
                try {
                    val pcm16 = call.argument<ByteArray>("pcm16")!!
                    val current = engine
                    if (current == null) {
                        withContext(Dispatchers.Main) { result.error("NOT_LOADED", "loadModel() n'a pas ete appele", null) }
                        return@launch
                    }
                    // ── v1 COUPEE QUAND LA v2 PILOTE (2026-07-30) ──────────
                    // Les deux moteurs tournaient sur le meme audio : le
                    // telephone faisait le travail DEUX FOIS. Mesure : sur le
                    // Redmi, les seules passes v1 prenaient 1167 ms en mediane
                    // (2015 ms au pire), et l'affichage devenait lourd.
                    // La v1 reste entierement presente et redevient active des
                    // que `v2SetEnabled(false)` -- c'est toujours le filet de
                    // securite, il ne consomme simplement plus rien tant que la
                    // v2 fait mieux (2,03 % contre 10,10 %).
                    val v1Coupee = v2Actif && v2Mots.isNotEmpty()
                    if (buffered == null && !v1Coupee) {
                        buffered = BufferedTranscriber(current)
                        pendingCommitSilenceMs?.let { buffered!!.setCommitSilenceMs(it) }
                        buffered!!.setNeverBlockAnchor(pendingNeverBlockAnchor)
                        buffered!!.setClipCapture(pendingClipCaptureDir)
                        alignTokens?.let { buffered!!.setAlignmentTarget(it, alignAnchor, alignVariants) }
                    }
                    val samples = pcm16ToFloat(pcm16)
                    // ── REDECOUPAGE EN BLOCS DE 80 ms (2026-07-27) ──────────
                    // Dart groupe desormais plusieurs blocs par appel pour
                    // reduire les allers-retours MethodChannel (la file
                    // atteignait ~35 s, cf. le commentaire du listener PCM).
                    // Mais le portier RMS et la detection de pause de
                    // BufferedTranscriber decident PAR APPEL a feed() :
                    // transmettre un gros paquet d'un coup rendrait le portier
                    // plus grossier et changerait la segmentation.
                    // On regroupe donc le TRANSPORT sans toucher au TRAITEMENT :
                    // le natif redecoupe a la granularite d'origine, et le
                    // comportement reste bit pour bit celui d'avant.
                    val block = 1280 // 80 ms a 16 kHz, la taille livree par le micro
                    if (!v1Coupee) {
                        var off = 0
                        while (off < samples.size) {
                            val end = minOf(off + block, samples.size)
                            buffered!!.feed(samples.copyOfRange(off, end), scope)
                            off = end
                        }
                    }
                    // Parties figee/apercu separees : le scoring Dart s'ancre sur
                    // la partie figee (append-only) au lieu de re-aligner du mot 0.
                    // "align" : dernier resultat d'alignement force GOP (nullable,
                    // deduplique cote Dart par son champ "seq").
                    // La v2 recoit LE MEME audio, en parallele, et rend ses
                    // propres changements de statut. Aucun etat partage avec la
                    // v1 : si elle echoue, la v1 continue exactement comme
                    // avant (le catch est local).
                    val v2 = if (v2Actif) alimenterV2(current, samples) else null
                    val payload = mapOf(
                        "committed" to (buffered?.committed ?: ""),
                        "preview" to (buffered?.preview ?: ""),
                        "align" to buffered?.alignmentPayload(),
                    ) + (v2?.let { mapOf("v2" to it) } ?: emptyMap())
                    withContext(Dispatchers.Main) { result.success(payload) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("FEED_BUFFERED_FAILED", e.message, null) }
                }
            }
            "resetBuffered" -> {
                buffered?.reset()
                result.success(null)
            }
            // Vide la trace fine accumulee en memoire (cf. DiagnosticLog.trace)
            // -- A APPELER HORS RECITATION uniquement : c'est une ecriture
            // fichier unique mais volumineuse.
            "flushTrace" -> {
                result.success(DiagnosticLog.flushTrace())
            }
            "setNeverBlockAnchor" -> {
                val v = call.argument<Boolean>("value") ?: false
                pendingNeverBlockAnchor = v
                buffered?.setNeverBlockAnchor(v)
                result.success(null)
            }
            "traceReset" -> {
                DiagnosticLog.traceReset()
                result.success(null)
            }
            // ── Alignement force GOP (cf. ForcedAligner.kt) ────────────────────
            // Le texte attendu est CONNU d'avance : chaque passe de transcription
            // aligne de force les mots restants sur les logprobs et retourne un
            // score par mot (gop = forced - free) au lieu de laisser Dart faire
            // un diff textuel flou apres coup.
            "setAlignmentTarget" -> scope.launch {
                try {
                    val current = engine
                    val currentStreaming = streaming
                    val vocabPieces =
                        current?.vocabPieces ?: currentStreaming?.vocabPieces
                    if (vocabPieces == null) {
                        // Pas une erreur : le modele n'est juste pas encore deploye.
                        withContext(Dispatchers.Main) { result.success(false) }
                        return@launch
                    }
                    val words = call.argument<List<String>>("words")!!
                    val anchor = call.argument<Int>("anchor") ?: 0
                    if (tokenizer == null) {
                        tokenizer = CtcTokenizer(vocabPieces, wordTokenLookup)
                    }
                    val tokens = words.map { tokenizer!!.tokenizeWord(it) }
                    val empty = tokens.count { it.isEmpty() }
                    if (empty > 0) {
                        DiagnosticLog.log("FastConformerCtcPlugin",
                            "$empty mot(s) intokenisable(s) sur ${words.size} — alignement quand meme actif")
                    }
                    alignTokens = tokens
                    alignAnchor = anchor
                    val variants = if (rescoringEnabled) buildVariants(words) else null
                    alignVariants = variants
                    // Planchers de duree de reference (frames), envoyes par Dart
                    // (WordTimingService) en parallele de `words` -- null pour un
                    // mot hors couverture quran.com. Cf. ForcedAligner.combinedMinFrames.
                    val refMinFrames = call.argument<List<Int?>>("refMinFrames")
                    buffered?.setAlignmentTarget(tokens, anchor, variants, refMinFrames)
                    causalAlignment?.setTarget(tokens, anchor, variants, refMinFrames)
                    withContext(Dispatchers.Main) { result.success(true) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("SET_ALIGN_TARGET_FAILED", e.message, null) }
                }
            }
            "setAlignmentAnchor" -> {
                val anchor = call.argument<Int>("anchor")
                if (anchor != null) {
                    alignAnchor = anchor
                    buffered?.setAlignmentAnchor(anchor)
                    causalAlignment?.setAnchor(anchor)
                }
                result.success(null)
            }
            // Enchainement sur la sourate suivante (demande utilisateur
            // 2026-07-11) : ajoute des mots a la SUITE de la cible actuelle sans
            // toucher l'ancre -- la recitation continue exactement ou elle en
            // etait, juste avec plus de texte a reciter derriere.
            "extendAlignmentTarget" -> scope.launch {
                try {
                    val current = engine
                    val currentStreaming = streaming
                    val vocabPieces =
                        current?.vocabPieces ?: currentStreaming?.vocabPieces
                    if (vocabPieces == null) {
                        withContext(Dispatchers.Main) { result.success(false) }
                        return@launch
                    }
                    val words = call.argument<List<String>>("words")!!
                    if (tokenizer == null) {
                        tokenizer = CtcTokenizer(vocabPieces, wordTokenLookup)
                    }
                    val newTokens = words.map { tokenizer!!.tokenizeWord(it) }
                    alignTokens = (alignTokens ?: emptyList()) + newTokens
                    val newVariants = if (rescoringEnabled) buildVariants(words) else null
                    if (newVariants != null) {
                        val currentV = alignVariants ?: List((alignTokens?.size ?: newTokens.size) - newTokens.size) { emptyList() }
                        alignVariants = currentV + newVariants
                    }
                    val newRefMinFrames = call.argument<List<Int?>>("refMinFrames")
                    buffered?.extendAlignmentTarget(newTokens, newVariants, newRefMinFrames)
                    causalAlignment?.extendTarget(newTokens, newVariants, newRefMinFrames)
                    DiagnosticLog.log("FastConformerCtcPlugin",
                        "cible etendue : +${newTokens.size} mots, total=${alignTokens?.size}")
                    withContext(Dispatchers.Main) { result.success(true) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("EXTEND_ALIGN_TARGET_FAILED", e.message, null) }
                }
            }
            // Mode coach (segment WAV unique) : une inference + alignement force
            // one-shot sur la cible courante. Resultat toujours final (l'audio
            // est complet, il ne sera jamais reanalyse).
            "alignFile" -> scope.launch {
                try {
                    val current = engine
                    val tokens = alignTokens
                    if (current == null || tokens == null) {
                        withContext(Dispatchers.Main) { result.success(null) }
                        return@launch
                    }
                    val wavPath = call.argument<String>("wavPath")!!
                    val anchor = alignAnchor.coerceIn(0, tokens.size)
                    if (anchor >= tokens.size) {
                        withContext(Dispatchers.Main) { result.success(null) }
                        return@launch
                    }
                    val pcm = WavReader.readMono16kFloat(wavPath)
                    val outputs = current.computeAll(pcm)
                    val logprobs = outputs.letters
                    val segmentRules = current.decodeTajwid(outputs.tajwid)
                    val aligner = ForcedAligner(current.vocabPieces, current.blank)
                    val slice = tokens.subList(anchor, tokens.size)
                    val variantsSlice = alignVariants?.let {
                        if (anchor < it.size) it.subList(anchor, it.size) else null
                    }
                    var res = aligner.align(logprobs, slice, anchor, isFinal = true,
                                            wordVariants = variantsSlice, segmentRules = segmentRules)
                    if (res == null) {
                        withContext(Dispatchers.Main) { result.success(null) }
                        return@launch
                    }
                    // Bug corrige 2026-07-16 (revue de code, Finding #3) : ce
                    // mode one-shot ne rappelait jamais align() avec
                    // forceJudgeIndex -- un mot differe (res.deferredIndex)
                    // etait donc perdu DEFINITIVEMENT pour ce clip (pas de
                    // "prochain appel FINAL" possible ici, contrairement au
                    // mode continu ou BufferedTranscriber s'en charge via
                    // deferredOnceIndex). Comme tout l'audio du clip est deja
                    // disponible, le "prochain appel" peut se faire ICI MEME,
                    // dans le meme invocation : redemande l'alignement en
                    // forcant ce mot precis, garantissant le jugement promis
                    // par le contrat "2 chances max" meme en mode one-shot.
                    val deferred = res.deferredIndex
                    if (deferred != null) {
                        val retried = aligner.align(
                            logprobs, slice, anchor, forceJudgeIndex = deferred, isFinal = true,
                            wordVariants = variantsSlice, segmentRules = segmentRules)
                        if (retried != null) res = retried
                    }
                    val payload = mapOf(
                        "seq" to -1, // one-shot : pas de dedup necessaire cote Dart
                        "anchor" to anchor,
                        "frontier" to res!!.frontier,
                        "final" to true,
                        "words" to res!!.words.map {
                            mapOf(
                                "i" to it.index,
                                "gop" to it.gop,
                                "forced" to it.forced,
                                "covered" to it.covered,
                                "actual" to it.actual,
                                "starved" to it.starved,
                                "frames" to it.frames,
                                "noEvidence" to it.noEvidence,
                            ) + (it.rescoreMargin?.let { m -> mapOf("rescoreMargin" to m) } ?: emptyMap()) +
                                (it.rescoreHeard?.let { h -> mapOf("rescoreHeard" to h) } ?: emptyMap()) +
                                (if (it.detectedRules.isEmpty()) emptyMap() else mapOf(
                                    "rules" to it.detectedRules.map { r ->
                                        mapOf("id" to r.ruleId, "prob" to r.prob.toDouble())
                                    }))
                        },
                    )
                    withContext(Dispatchers.Main) { result.success(payload) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("ALIGN_FILE_FAILED", e.message, null) }
                }
            }
            // Rescoring NLL par mot (cf. ForcedAligner.WordResult.rescoreMargin) :
            // recalcule les variantes confusables de la cible d'alignement DEJA
            // fixee (si presente), pour ne pas exiger un nouvel appel
            // setAlignmentTarget cote Dart juste pour activer le diagnostic.
            "setRescoringEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                rescoringEnabled = enabled
                result.success(null)
            }
            // Profil de pauses personnel (par passage, cf. BufferedTranscriber) :
            // le seuil de gel s'adapte a la facon dont CET utilisateur recite CE
            // passage, appris de ses recitations validees precedentes.
            "setCommitSilenceMs" -> {
                val ms = call.argument<Int>("ms")
                if (ms != null) {
                    pendingCommitSilenceMs = ms
                    buffered?.setCommitSilenceMs(ms)
                }
                result.success(null)
            }
            "getSessionPauses" -> {
                result.success(buffered?.getSessionPausesMs() ?: emptyList<Int>())
            }
            // Capture de clips VERIFIES CORRECTS (mini-LoRA personnalisation
            // vocale, cf. FONCTIONNALITES_FUTURES.md "Personnalisation voix --
            // niveau 3", implemente 2026-07-12). [dir] = null desactive la
            // capture (defaut). C'est Dart qui decide, a la fin de la session,
            // si les clips ecrits sont conserves definitivement ou jetes.
            // Interrupteur du diagnostic natif (cf. DiagnosticLog.enabled).
            // Pilote par le meme reglage utilisateur que le cote Dart, pour que
            // "diagnostic desactive" veuille dire la MEME chose des deux cotes.
            // Active/desactive la chaine v2 en parallele de la v1. Tant que
            // c'est faux, RIEN de la v2 ne s'execute -- pas de cout, pas de
            // risque.
            "v2SetEnabled" -> {
                v2Actif = call.argument<Boolean>("enabled") ?: false
                if (!v2Actif) v2Chaine = null
                DiagnosticLog.log(TAG, "[v2] chaine parallele " +
                    if (v2Actif) "ACTIVE" else "desactivee")
                result.success(null)
            }
            // Texte attendu de la v2. Separe de setAlignmentTarget : la v2
            // travaille sur des MOTS, la v1 sur des tokens deja calcules.
            "v2SetTarget" -> {
                v2Mots = call.argument<List<String>>("mots") ?: emptyList()
                v2Chaine = null // recree au prochain bloc audio, avec la cible
                DiagnosticLog.log(TAG, "[v2] cible = ${v2Mots.size} mots")
                result.success(null)
            }
            // ── CHAINE v2 (package recitation2) — BANC SUR AUDIO REEL ────────
            // Rejoue un WAV complet dans la chaine v2, bloc de 80 ms par bloc de
            // 80 ms, avec le VRAI modele. C'est le banc 1/2/4 de
            // CONCEPTION_RECITATION_V2.md, et il n'existe qu'ici : reimplementer
            // la politique de fenetrage en Python a produit, deux jours de suite,
            // des predictions confiantes et fausses ("le banc mesurait mon
            // decoupage, pas l'app"). Ici le banc APPELLE le code de l'app.
            //
            // Ne touche a rien du chemin v1 : aucun etat partage, aucune
            // instance commune. Les deux chaines peuvent coexister le temps de
            // la comparaison a WAV identique.
            "v2AnalyserWav" -> scope.launch {
                try {
                    val moteur = engine
                    if (moteur == null) {
                        withContext(Dispatchers.Main) {
                            result.error("NOT_LOADED", "loadModel() n'a pas ete appele", null)
                        }
                        return@launch
                    }
                    val wavPath = call.argument<String>("wavPath")!!
                    val mots = call.argument<List<String>>("mots")!!
                    val fenetreS = call.argument<Double>("fenetreSecondes") ?: 6.0
                    val pasS = call.argument<Double>("pasSecondes") ?: 1.5

                    // Tokenizer LOCAL, jamais l'instance partagee `tokenizer` :
                    // la v2 ne doit ecrire aucun etat lu par la v1, sinon la
                    // comparaison a WAV identique (banc 4) mesurerait les deux
                    // chaines en interaction. Meme construction, meme
                    // dictionnaire precalcule -- seule la duree de vie change.
                    val tk = CtcTokenizer(moteur.vocabPieces, wordTokenLookup)
                    val journal = ArrayList<String>()
                    val chaine = com.corankarim.coran_karim.recitation2.ChaineRecitation(
                        front = com.corankarim.coran_karim.recitation2.FrontOnnx(moteur),
                        tokeniser = { mot -> tk.tokenizeWord(mot) },
                        constructeur = com.corankarim.coran_karim.recitation2
                            .ConstructeurDeFenetres(
                                pauseMinSecondes = fenetreS,
                                maxBlocSecondes = pasS,
                            ),
                        localisateur = com.corankarim.coran_karim.recitation2
                            .Localisateur(moteur.vocabPieces, moteur.blank),
                        aligneur = com.corankarim.coran_karim.recitation2
                            .AligneurForce(moteur.vocabPieces, moteur.blank),
                        journal = { l -> journal.add(l) },
                    )
                    chaine.definirTexte(mots)

                    val pcm = WavReader.readMono16kFloat(wavPath)
                    val bloc = com.corankarim.coran_karim.recitation2.Horloge.ECH_PAR_FRAME
                    val debut = System.currentTimeMillis()
                    var i = 0
                    while (i < pcm.size) {
                        val fin = minOf(i + bloc, pcm.size)
                        chaine.alimenter(pcm.copyOfRange(i, fin))
                        i = fin
                    }
                    chaine.terminer()
                    val duree = System.currentTimeMillis() - debut

                    val statuts = chaine.statuts
                    val motsSortie = mots.indices.map { idx ->
                        val obs = chaine.preuves.observations(idx)
                        mapOf(
                            "i" to idx,
                            "mot" to mots[idx],
                            "statut" to nomStatut(statuts[idx]),
                            "observations" to obs.size,
                            "interieures" to obs.count { it.interieur },
                            "gop" to (obs.lastOrNull { it.interieur }?.gop?.toDouble()),
                            "free" to (obs.lastOrNull { it.interieur }?.free?.toDouble()),
                            "forced" to (obs.lastOrNull { it.interieur }?.forced?.toDouble()),
                            "entendu" to (obs.lastOrNull { it.interieur }?.entendu ?: ""),
                            // TOUTES les observations, pas seulement la derniere.
                            // Sans ca on ne peut pas distinguer « la preuve
                            // n'existe pas » de « la preuve existe et la regle
                            // de decision l'a ratee » -- c'est exactement le
                            // trou qui a rendu la piste "prefixe stable"
                            // invalidable hors device le 2026-07-29.
                            "obs" to obs.map { o ->
                                mapOf(
                                    "f" to o.fenetreId,
                                    "gop" to o.gop.toDouble(),
                                    "free" to o.free.toDouble(),
                                    "int" to o.interieur,
                                    "sc" to o.sansCreneau,
                                    "fr" to o.frames,
                                    "e" to o.entendu,
                                )
                            },
                        )
                    }
                    val payload = mapOf(
                        "dureeAudioMs" to (pcm.size * 1000L / 16000),
                        "dureeCalculMs" to duree,
                        "indexMaxVotant" to chaine.preuves.indexMaxVotant(),
                        "observations" to chaine.preuves.total(),
                        "mots" to motsSortie,
                        "journal" to journal,
                    )
                    DiagnosticLog.log(TAG, "[v2] banc WAV : ${pcm.size / 16000}s audio, " +
                        "${duree}ms calcul, ancre max ${chaine.preuves.indexMaxVotant()}")
                    withContext(Dispatchers.Main) { result.success(payload) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) {
                        result.error("V2_WAV_FAILED", e.message, null)
                    }
                }
            }
            "setLogEnabled" -> {
                DiagnosticLog.enabled = call.argument<Boolean>("enabled") ?: true
                result.success(null)
            }
            "setClipCapture" -> {
                val dir = call.argument<String>("dir")
                pendingClipCaptureDir = dir
                buffered?.setClipCapture(dir)
                result.success(null)
            }
            // ── Empreinte vocale (niveau 1, comparaison audio-a-audio) ─────────
            // Voir VoiceFingerprint.kt + memoire voice-personalization-idea.
            "loadFingerprintModel" -> scope.launch {
                try {
                    // Meme principe d'idempotence que "loadModel" ci-dessus :
                    // deux instances de VoiceFingerprintService (coach_screen.dart
                    // en cree une par etat) partagent ce meme moteur natif.
                    if (fingerprint != null) {
                        withContext(Dispatchers.Main) { result.success(true) }
                        return@launch
                    }
                    val modelPath = call.argument<String>("modelPath")!!
                    fingerprint = VoiceFingerprint(modelPath)
                    withContext(Dispatchers.Main) { result.success(true) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("LOAD_FINGERPRINT_FAILED", e.message, null) }
                }
            }
            "saveFingerprint" -> scope.launch {
                try {
                    val wavPath = call.argument<String>("wavPath")!!
                    val outPath = call.argument<String>("outPath")!!
                    val fp = fingerprint
                    if (fp == null) {
                        withContext(Dispatchers.Main) { result.error("NOT_LOADED", "loadFingerprintModel() n'a pas ete appele", null) }
                        return@launch
                    }
                    val pcm = WavReader.readMono16kFloat(wavPath)
                    val embedding = fp.computeEmbedding(pcm)
                    VoiceFingerprint.save(outPath, embedding)
                    withContext(Dispatchers.Main) { result.success(true) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("SAVE_FINGERPRINT_FAILED", e.message, null) }
                }
            }
            "compareFingerprint" -> scope.launch {
                try {
                    val wavPath = call.argument<String>("wavPath")!!
                    val refPath = call.argument<String>("refPath")!!
                    val fp = fingerprint
                    if (fp == null) {
                        withContext(Dispatchers.Main) { result.error("NOT_LOADED", "loadFingerprintModel() n'a pas ete appele", null) }
                        return@launch
                    }
                    val pcm = WavReader.readMono16kFloat(wavPath)
                    val embedding = fp.computeEmbedding(pcm)
                    val reference = VoiceFingerprint.load(refPath)
                    val similarity = VoiceFingerprint.dtwSimilarity(embedding, reference)
                    withContext(Dispatchers.Main) { result.success(similarity) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("COMPARE_FINGERPRINT_FAILED", e.message, null) }
                }
            }
            "disposeFingerprint" -> {
                fingerprint?.close()
                fingerprint = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Variantes confusables tokenisees, PARALLELE a la liste [words] (cf.
     *  ConfusableVariants, ForcedAligner.WordResult.rescoreMargin). Tokenisation
     *  SILENCIEUSE (tokenizeVariantQuiet) : les variantes sont volontairement
     *  hors-Coran, presque aucune n'est dans le dictionnaire precalcule. */
    private fun buildVariants(words: List<String>): List<List<Pair<String, IntArray>>> {
        val tok = tokenizer ?: return words.map { emptyList() }
        return words.map { w ->
            ConfusableVariants.variantsOf(w).map { v -> v to tok.tokenizeVariantQuiet(v) }
        }
    }

    /**
     * Alimente la chaine v2 et rend les mots dont le STATUT A CHANGE.
     *
     * Tout est enferme dans un try/catch : la v2 est en observation, elle ne
     * doit sous aucun pretexte faire tomber la chaine qui peint l'ecran.
     */
    private fun alimenterV2(moteur: FastConformerCtc, samples: FloatArray):
        List<Map<String, Any?>>? {
        if (v2Mots.isEmpty()) return null
        return try {
            var chaine = v2Chaine
            if (chaine == null) {
                val tk = CtcTokenizer(moteur.vocabPieces, wordTokenLookup)
                chaine = com.corankarim.coran_karim.recitation2.ChaineRecitation(
                    front = com.corankarim.coran_karim.recitation2.FrontOnnx(moteur),
                    tokeniser = { mot -> tk.tokenizeWord(mot) },
                    localisateur = com.corankarim.coran_karim.recitation2
                        .Localisateur(moteur.vocabPieces, moteur.blank),
                    aligneur = com.corankarim.coran_karim.recitation2
                        .AligneurForce(moteur.vocabPieces, moteur.blank),
                    journal = { l -> DiagnosticLog.log(TAG, l) },
                )
                chaine.definirTexte(v2Mots)
                v2Chaine = chaine
            }
            chaine.alimenter(samples).map { c ->
                // Les SCORES accompagnent le statut. Sans eux, le log dit ce que
                // la chaine a DECIDE et jamais POURQUOI -- c'est exactement le
                // manque qui a rendu le bloc de 8 mots omis de Yusuf
                // indiagnosticable le 2026-07-30. On remonte la derniere
                // observation VOTANTE, et a defaut la derniere tout court (un
                // mot `omis` n'en a aucune qui vote : savoir ce qu'il avait
                // quand meme est precisement l'information utile).
                val obs = chaine.preuves.observationsVotantes(c.motIndex).lastOrNull()
                    ?: chaine.preuves.observations(c.motIndex).lastOrNull()
                mapOf(
                    "i" to c.motIndex,
                    "statut" to nomStatut(c.statut),
                    "gop" to obs?.gop?.toDouble(),
                    "forced" to obs?.forced?.toDouble(),
                    "free" to obs?.free?.toDouble(),
                    "frames" to (obs?.frames ?: 0),
                    "entendu" to (obs?.entendu ?: ""),
                    "interieur" to (obs?.interieur ?: false),
                    "sansCreneau" to (obs?.sansCreneau ?: false),
                    "nbObs" to chaine.preuves.observations(c.motIndex).size,
                )
            }
        } catch (e: Exception) {
            DiagnosticLog.log(TAG, "[v2] echec (la v1 continue) : ${e.message}")
            null
        }
    }

    /** Nom lisible d'un statut v2 pour le payload Dart. `null` = jamais observe
     *  — c'est une reponse legitime, pas une erreur (aucun verdict par defaut). */
    private fun nomStatut(s: com.corankarim.coran_karim.recitation2.Statut?): String = when (s) {
        null, is com.corankarim.coran_karim.recitation2.Statut.Inconnu -> "inconnu"
        is com.corankarim.coran_karim.recitation2.Statut.Provisoire ->
            "provisoire:${s.couleur.name.lowercase()}"
        is com.corankarim.coran_karim.recitation2.Statut.Definitif ->
            "definitif:${s.couleur.name.lowercase()}"
        is com.corankarim.coran_karim.recitation2.Statut.Omis -> "omis"
    }

    /** PCM16 little-endian (format `AudioEncoder.pcm16bits` du package `record`) -> float [-1,1]. */
    private fun pcm16ToFloat(bytes: ByteArray): FloatArray {
        val n = bytes.size / 2
        val out = FloatArray(n)
        for (i in 0 until n) {
            val lo = bytes[i * 2].toInt() and 0xFF
            val hi = bytes[i * 2 + 1].toInt()
            val sample = (hi shl 8) or lo
            out[i] = sample / 32768.0f
        }
        return out
    }
}

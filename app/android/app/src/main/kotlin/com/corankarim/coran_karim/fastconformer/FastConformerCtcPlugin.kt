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
                    if (buffered == null) {
                        buffered = BufferedTranscriber(current)
                        pendingCommitSilenceMs?.let { buffered!!.setCommitSilenceMs(it) }
                        buffered!!.setClipCapture(pendingClipCaptureDir)
                        alignTokens?.let { buffered!!.setAlignmentTarget(it, alignAnchor, alignVariants) }
                    }
                    val samples = pcm16ToFloat(pcm16)
                    buffered!!.feed(samples, scope)
                    // Parties figee/apercu separees : le scoring Dart s'ancre sur
                    // la partie figee (append-only) au lieu de re-aligner du mot 0.
                    // "align" : dernier resultat d'alignement force GOP (nullable,
                    // deduplique cote Dart par son champ "seq").
                    val payload = mapOf(
                        "committed" to buffered!!.committed,
                        "preview" to buffered!!.preview,
                        "align" to buffered!!.alignmentPayload(),
                    )
                    withContext(Dispatchers.Main) { result.success(payload) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("FEED_BUFFERED_FAILED", e.message, null) }
                }
            }
            "resetBuffered" -> {
                buffered?.reset()
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

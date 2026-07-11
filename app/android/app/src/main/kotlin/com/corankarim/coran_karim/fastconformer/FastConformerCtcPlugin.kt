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
    private lateinit var channel: MethodChannel
    private var engine: FastConformerCtc? = null
    private var streaming: FastConformerStreamingSession? = null
    private var buffered: BufferedTranscriber? = null
    // Seuil personnalise recu AVANT la creation (lazy) du BufferedTranscriber —
    // applique des sa construction, sinon un setCommitSilenceMs appele avant le
    // premier bloc audio serait perdu.
    @Volatile private var pendingCommitSilenceMs: Int? = null
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
        fingerprint?.close()
        fingerprint = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadModel" -> scope.launch {
                try {
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
                    val modelPath = call.argument<String>("modelPath")!!
                    val vocabPath = call.argument<String>("vocabPath")!!
                    engine = FastConformerCtc(modelPath, vocabPath)
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
                engine?.close()
                engine = null
                result.success(null)
            }
            // ── Streaming cache-aware (vrai flux continu, karaoke) ─────────────
            "loadStreamingModel" -> scope.launch {
                try {
                    val modelPath = call.argument<String>("modelPath")!!
                    val vocabPath = call.argument<String>("vocabPath")!!
                    streaming?.close()
                    streaming = FastConformerStreamingSession(modelPath, vocabPath)
                    withContext(Dispatchers.Main) { result.success(true) }
                } catch (e: Exception) {
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
                    val text = current.feedAudio(samples)
                    withContext(Dispatchers.Main) { result.success(text) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("FEED_CHUNK_FAILED", e.message, null) }
                }
            }
            "resetStreaming" -> {
                streaming?.reset()
                result.success(null)
            }
            "disposeStreaming" -> {
                streaming?.close()
                streaming = null
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
                    }
                    val samples = pcm16ToFloat(pcm16)
                    buffered!!.feed(samples, scope)
                    // Parties figee/apercu separees : le scoring Dart s'ancre sur
                    // la partie figee (append-only) au lieu de re-aligner du mot 0.
                    val payload = mapOf(
                        "committed" to buffered!!.committed,
                        "preview" to buffered!!.preview,
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

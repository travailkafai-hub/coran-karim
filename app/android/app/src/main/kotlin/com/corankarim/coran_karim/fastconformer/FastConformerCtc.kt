package com.corankarim.coran_karim.fastconformer

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import org.json.JSONArray
import java.io.File
import java.nio.FloatBuffer
import java.nio.LongBuffer

/**
 * Verificateur ASR "parallele" (FastConformer CTC, modele Quran fine-tune, cf.
 * benchmark/models/fastconformer-quran-pcd) -- tourne EN PLUS de whisper.cpp
 * (pas un remplacement), le temps de valider precision/latence en conditions
 * reelles. Pipeline : PCM brut -> MelSpectrogram.compute() -> ONNX (encodeur+CTC
 * precalcules cote Python, cf. benchmark/export_pcd_checkpoint.py) -> greedy CTC
 * -> detokenisation BPE (simple jointure, pas besoin de SentencePiece natif).
 *
 * Modele et vocab deployes a cote des autres modeles (pas embarques dans l'APK),
 * voir la meme convention que whisper-medium-ggml.
 */
class FastConformerCtc(modelPath: String, vocabPath: String) {

    private val env: OrtEnvironment = OrtEnvironment.getEnvironment()
    private val session: OrtSession = env.createSession(modelPath, OrtSession.SessionOptions())
    private val vocab: List<String> = loadVocab(vocabPath)
    private val blankId: Int = vocab.size // CTC blank = dernier index (vocab_size), verifie cote Python

    /** Pieces BPE du vocabulaire — pour le tokenizer/aligneur force (cf. ForcedAligner.kt). */
    val vocabPieces: List<String> get() = vocab

    /** Index du blank CTC — pour l'aligneur force. */
    val blank: Int get() = blankId

    private fun loadVocab(path: String): List<String> {
        val json = File(path).readText(Charsets.UTF_8)
        val arr = JSONArray(json)
        return (0 until arr.length()).map { arr.getString(it) }
    }

    /** @param pcm audio brut mono 16kHz, [-1,1]. @return texte decode (harakat incluses). */
    fun transcribe(pcm: FloatArray): String = greedyDecode(computeLogProbs(pcm))

    /**
     * Log-probabilites par frame (T, vocab+1) — la matiere premiere du decodage
     * glouton ET de l'alignement force GOP (ForcedAligner). Exposee separement
     * pour ne lancer l'inference ONNX qu'UNE fois quand les deux en ont besoin.
     */
    fun computeLogProbs(pcm: FloatArray): Array<FloatArray> {
        val feats = MelSpectrogram.compute(pcm) // (80, T)
        val nMels = feats.size
        val t = feats[0].size

        val audioBuf = FloatBuffer.allocate(nMels * t)
        for (m in 0 until nMels) for (i in 0 until t) audioBuf.put(feats[m][i])
        audioBuf.rewind()

        val lengthBuf = LongBuffer.allocate(1)
        lengthBuf.put(t.toLong())
        lengthBuf.rewind()

        OnnxTensor.createTensor(env, audioBuf, longArrayOf(1, nMels.toLong(), t.toLong())).use { audioTensor ->
            OnnxTensor.createTensor(env, lengthBuf, longArrayOf(1)).use { lengthTensor ->
                val inputs = mapOf("audio_signal" to audioTensor, "length" to lengthTensor)
                session.run(inputs).use { results ->
                    @Suppress("UNCHECKED_CAST")
                    val logprobs = results[0].value as Array<Array<FloatArray>> // (1, T, vocab+1)
                    return logprobs[0] // copie JVM materialisee par .value — survit au close()
                }
            }
        }
    }

    fun greedyDecode(logprobs: Array<FloatArray>): String {
        val ids = ArrayList<Int>(logprobs.size)
        var prev = -1
        for (frame in logprobs) {
            var best = 0
            var bestVal = frame[0]
            for (c in 1 until frame.size) {
                if (frame[c] > bestVal) { bestVal = frame[c]; best = c }
            }
            if (best != prev && best != blankId) ids.add(best)
            prev = best
        }
        // Detokenisation BPE : jointure directe des pieces + "▁" -> espace (verifie
        // identique a tokenizer.ids_to_text() de NeMo cote Python, pas besoin de SentencePiece).
        val sb = StringBuilder()
        for (id in ids) if (id < vocab.size) sb.append(vocab[id])
        return sb.toString().replace('▁', ' ').trim()
    }

    fun close() {
        session.close()
    }
}

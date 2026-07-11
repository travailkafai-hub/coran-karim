package com.corankarim.coran_karim.fastconformer

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.FloatBuffer
import java.nio.LongBuffer
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Comparaison audio-a-audio ("empreinte vocale"), niveau 1 de l'idee de
 * personnalisation proposee par l'utilisateur (memoire voice-personalization-idea,
 * 2026-06-27) : au lieu de decoder en texte (instable a 20% d'entrainement, cf.
 * SKILL.md), on compare directement les EMBEDDINGS phonetiques de l'encodeur
 * entre une recitation deja verifiee correcte et la nouvelle tentative, via DTW.
 *
 * Validé côté recherche (benchmark/test_embedding_dtw.py) : même verset récité
 * par des récitateurs DIFFÉRENTS -> similarité ~0.94 en moyenne ; versets
 * différents -> ~0.86. Écart net (contrairement à l'alignement forcé testé
 * avant, qui ne discriminait quasiment pas). Le cas d'usage réel (même
 * personne, verifie vs nouvelle tentative) devrait être encore plus net
 * qu'un test cross-reciteur.
 *
 * Modele : fastconformer_embed_pcd.onnx (export_embedding_model.py) -- meme
 * encodeur que le modele CTC standard, mais expose aussi la representation
 * brute (avant la tete CTC) comme sortie "embeddings" (T, 512).
 */
class VoiceFingerprint(modelPath: String) {

    private val env: OrtEnvironment = OrtEnvironment.getEnvironment()
    private val session: OrtSession = env.createSession(modelPath, OrtSession.SessionOptions())

    /** Calcule l'empreinte (embeddings bruts de l'encodeur) d'un audio PCM 16kHz mono. */
    fun computeEmbedding(pcm: FloatArray): Array<FloatArray> {
        val feats = MelSpectrogram.compute(pcm) // (80, T)
        val nMels = feats.size
        val t = feats[0].size

        val audioBuf = FloatBuffer.allocate(nMels * t)
        for (m in 0 until nMels) for (i in 0 until t) audioBuf.put(feats[m][i])
        audioBuf.rewind()
        val lengthBuf = LongBuffer.allocate(1).put(t.toLong()).apply { rewind() }

        OnnxTensor.createTensor(env, audioBuf, longArrayOf(1, nMels.toLong(), t.toLong())).use { audioTensor ->
            OnnxTensor.createTensor(env, lengthBuf, longArrayOf(1)).use { lengthTensor ->
                val inputs = mapOf("audio_signal" to audioTensor, "length" to lengthTensor)
                session.run(inputs).use { results ->
                    @Suppress("UNCHECKED_CAST")
                    val embeddings = results[0].value as Array<Array<FloatArray>> // (1, T, 512)
                    return embeddings[0]
                }
            }
        }
    }

    companion object {
        /** Sérialise (T, 512) en binaire simple : int32 T, int32 D, puis T*D float32. */
        fun save(path: String, embedding: Array<FloatArray>) {
            DataOutputStream(FileOutputStream(path)).use { out ->
                val t = embedding.size
                val d = if (t > 0) embedding[0].size else 0
                out.writeInt(t)
                out.writeInt(d)
                for (row in embedding) for (v in row) out.writeFloat(v)
            }
        }

        fun load(path: String): Array<FloatArray> {
            DataInputStream(FileInputStream(path)).use { inp ->
                val t = inp.readInt()
                val d = inp.readInt()
                return Array(t) { FloatArray(d) { inp.readFloat() } }
            }
        }

        /**
         * Similarité [0,1] entre deux séquences d'embeddings via DTW sur distance
         * cosinus, normalisée par la longueur du chemin. O(Ta*Tb) — acceptable
         * pour des séquences de quelques centaines de frames (verset/passage,
         * pas une sourate entière).
         */
        fun dtwSimilarity(a: Array<FloatArray>, b: Array<FloatArray>): Double {
            if (a.isEmpty() || b.isEmpty()) return 0.0
            val an = normalizeRows(a)
            val bn = normalizeRows(b)
            val ta = an.size
            val tb = bn.size

            // cost[i][j] = 1 - cos_sim(an[i], bn[j]) ∈ [0,2]
            val cost = Array(ta) { i -> DoubleArray(tb) { j -> 1.0 - dot(an[i], bn[j]) } }

            val d = Array(ta + 1) { DoubleArray(tb + 1) { Double.POSITIVE_INFINITY } }
            d[0][0] = 0.0
            for (i in 1..ta) {
                for (j in 1..tb) {
                    val c = cost[i - 1][j - 1]
                    d[i][j] = c + min(d[i - 1][j], min(d[i][j - 1], d[i - 1][j - 1]))
                }
            }
            val avgCost = d[ta][tb] / maxOf(ta, tb)
            return (1.0 - avgCost / 2.0).coerceIn(0.0, 1.0)
        }

        private fun normalizeRows(x: Array<FloatArray>): Array<FloatArray> = Array(x.size) { i ->
            val row = x[i]
            var normSq = 0.0
            for (v in row) normSq += v.toDouble() * v
            val norm = sqrt(normSq) + 1e-8
            FloatArray(row.size) { k -> (row[k] / norm).toFloat() }
        }

        private fun dot(a: FloatArray, b: FloatArray): Double {
            var s = 0.0
            for (k in a.indices) s += a[k].toDouble() * b[k]
            return s
        }
    }

    fun close() {
        session.close()
    }
}

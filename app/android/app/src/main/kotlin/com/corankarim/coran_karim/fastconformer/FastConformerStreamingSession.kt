package com.corankarim.coran_karim.fastconformer

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.util.Log
import org.json.JSONArray
import java.io.File
import java.nio.FloatBuffer
import java.nio.LongBuffer
import kotlin.math.sqrt

/**
 * Session de streaming CTC "cache-aware" (vrai flux continu, pas des segments
 * VAD transcrits en batch). Modele exporte via benchmark/export_streaming_onnx.py
 * (encodeur FastConformer bascule en attention chunked_limited [70,1] + tete CTC,
 * cache d'encodeur en entree/sortie -- validee fidele au PyTorch natif a 4e-5
 * pres, cf. benchmark/validate_streaming_onnx.py).
 *
 * v2 (2026-07-04) -- reecriture de la featurisation apres un premier test device
 * ou TOUT decodait blank. Deux causes racines corrigees :
 *  1. La normalisation "per_feature" etait appliquee sur un historique PCM de
 *     ~0,6s seulement (le modele est entraine avec des stats par enonce entier)
 *     -> features hors distribution -> CTC s'effondre sur blank.
 *     Fix : statistiques mean/std CUMULATIVES sur toute la session (approxime
 *     les stats par enonce), appliquees a la fenetre a chaque inference.
 *  2. Les frames mel les plus recentes etaient calculees avec du zero-padding
 *     de fin (le STFT centre "voit" 256 echantillons dans le futur) -> les
 *     frames porteuses du nouveau contenu etaient corrompues a chaque appel.
 *     Fix : calcul strictement causal -- une frame n'est emise que quand tous
 *     ses echantillons reels sont disponibles (retard fixe de 456 echantillons
 *     = ~28ms, negligeable).
 *
 * Grille temporelle (streaming_cfg du modele, att_context_size=[70,1]) :
 *   chunk_size=16 frames mel neuves par inference (~160ms), pre_cache=9 frames
 *   de contexte gauche -> fenetre de 25 frames par appel, avancant de 16.
 */
class FastConformerStreamingSession(modelPath: String, vocabPath: String) {

    companion object {
        private const val TAG = "FastConformerStream"
        private const val N_MELS = MelSpectrogram.N_MELS_PUBLIC
        private const val HOP = MelSpectrogram.HOP_PUBLIC
        private const val CHUNK_FRAMES = 16
        private const val PRE_CACHE_FRAMES = 9
        private const val WINDOW_FRAMES = CHUNK_FRAMES + PRE_CACHE_FRAMES // 25
        private const val NUM_LAYERS = 17
        private const val CACHE_LEN = 70
        private const val D_MODEL = 512
        private const val TIME_CACHE = 4
        private const val NORM_EPS = 1e-5
    }

    private val env: OrtEnvironment = OrtEnvironment.getEnvironment()
    private val session: OrtSession = env.createSession(modelPath, OrtSession.SessionOptions())
    private val vocab: List<String> = loadVocab(vocabPath)
    private val blankId: Int = vocab.size

    // ── Etat encodeur (persiste entre inferences — c'est le coeur du streaming)
    private var cacheLastChannel = FloatArray(NUM_LAYERS * CACHE_LEN * D_MODEL)
    private var cacheLastTime = FloatArray(NUM_LAYERS * D_MODEL * TIME_CACHE)
    private var cacheLastChannelLen: Long = 0L

    // ── Signal preemphasise + padde-centre, buffer roulant a indexation globale
    // paddedBuf[i] correspond a l'indice global (bufGlobalStart + i) du signal padde.
    private var paddedBuf = DoubleArray(0)
    private var bufGlobalStart = 0L
    private var paddedTotalLen = 0L
    private var prevRawSample = 0f

    // ── Frames mel (log, NON normalisees) + stats cumulatives de session
    private var framesComputed = 0L
    private var nextWindowEndFrame = CHUNK_FRAMES.toLong() // 1ere fenetre couvre frames [-9,16)
    private val melWindow = ArrayDeque<FloatArray>() // dernieres <=WINDOW_FRAMES frames
    private val statSum = DoubleArray(N_MELS)
    private val statSumSq = DoubleArray(N_MELS)
    private var statCount = 0L

    private val decodedIds = ArrayList<Int>()
    private var prevTokenForCollapse = -1
    private var inferenceCount = 0L

    init {
        seedCenterPad()
    }

    private fun seedCenterPad() {
        paddedBuf = DoubleArray(MelSpectrogram.CENTER_PAD) // 256 zeros (pad centre de debut)
        bufGlobalStart = 0L
        paddedTotalLen = MelSpectrogram.CENTER_PAD.toLong()
    }

    private fun loadVocab(path: String): List<String> {
        val arr = JSONArray(File(path).readText(Charsets.UTF_8))
        return (0 until arr.length()).map { arr.getString(it) }
    }

    /** Reinitialise tout l'etat (nouvelle session de recitation). */
    fun reset() {
        cacheLastChannel = FloatArray(NUM_LAYERS * CACHE_LEN * D_MODEL)
        cacheLastTime = FloatArray(NUM_LAYERS * D_MODEL * TIME_CACHE)
        cacheLastChannelLen = 0L
        seedCenterPad()
        prevRawSample = 0f
        framesComputed = 0L
        nextWindowEndFrame = CHUNK_FRAMES.toLong()
        melWindow.clear()
        java.util.Arrays.fill(statSum, 0.0)
        java.util.Arrays.fill(statSumSq, 0.0)
        statCount = 0L
        decodedIds.clear()
        prevTokenForCollapse = -1
        inferenceCount = 0L
    }

    /**
     * Alimente la session avec du PCM brut (mono 16kHz, [-1,1], taille libre).
     * Retourne le texte complet decode jusqu'ici.
     */
    fun feedAudio(newSamples: FloatArray): String {
        appendPreemphasized(newSamples)

        // Calcule toutes les frames devenues ENTIEREMENT calculables (causal strict)
        while (MelSpectrogram.paddedEndForFrame(framesComputed) <= paddedTotalLen) {
            val globalStart = framesComputed * HOP
            val localStart = (globalStart - bufGlobalStart).toInt()
            val lm = MelSpectrogram.frameLogMel(paddedBuf, localStart)

            melWindow.addLast(lm)
            if (melWindow.size > WINDOW_FRAMES) melWindow.removeFirst()
            for (m in 0 until N_MELS) {
                statSum[m] += lm[m].toDouble()
                statSumSq[m] += lm[m].toDouble() * lm[m]
            }
            statCount++
            framesComputed++

            if (framesComputed == nextWindowEndFrame) {
                runInference()
                nextWindowEndFrame += CHUNK_FRAMES
            }
        }

        compactBuffer()
        return detokenize(decodedIds)
    }

    private fun appendPreemphasized(samples: FloatArray) {
        val old = paddedBuf
        val oldLen = old.size
        paddedBuf = old.copyOf(oldLen + samples.size)
        var prev = prevRawSample
        for (i in samples.indices) {
            paddedBuf[oldLen + i] = (samples[i] - MelSpectrogram.PREEMPH_PUBLIC * prev).toDouble()
            prev = samples[i]
        }
        prevRawSample = prev
        paddedTotalLen += samples.size
    }

    private fun compactBuffer() {
        // On ne relira jamais avant le debut de la prochaine frame a calculer.
        val keepFromGlobal = framesComputed * HOP
        val drop = (keepFromGlobal - bufGlobalStart).toInt()
        if (drop > HOP * 64) { // compacter par paquets, pas a chaque appel
            paddedBuf = paddedBuf.copyOfRange(drop, paddedBuf.size)
            bufGlobalStart = keepFromGlobal
        }
    }

    private fun runInference() {
        val t0 = System.nanoTime()

        // mean/std cumulatifs de session (ddof=1 comme NeMo)
        val mean = DoubleArray(N_MELS)
        val std = DoubleArray(N_MELS)
        val n = statCount.toDouble()
        for (m in 0 until N_MELS) {
            mean[m] = statSum[m] / n
            val variance = if (statCount > 1) {
                ((statSumSq[m] - n * mean[m] * mean[m]) / (n - 1.0)).coerceAtLeast(0.0)
            } else 0.0
            std[m] = sqrt(variance) + NORM_EPS
        }

        // Fenetre de 25 frames : les dernieres melWindow.size frames, completees
        // a gauche par des zeros EN ESPACE NORMALISE (= valeur moyenne) pour la
        // toute premiere fenetre (frames "-9..-1" inexistantes) — meme convention
        // que la validation Python (F.pad sur les features normalisees).
        val missing = WINDOW_FRAMES - melWindow.size
        val audioBuf = FloatBuffer.allocate(N_MELS * WINDOW_FRAMES)
        val frames = melWindow.toList()
        for (m in 0 until N_MELS) {
            for (i in 0 until WINDOW_FRAMES) {
                val v = if (i < missing) 0f
                else ((frames[i - missing][m] - mean[m]) / std[m]).toFloat()
                audioBuf.put(v)
            }
        }
        audioBuf.rewind()

        val lengthBuf = LongBuffer.allocate(1).put(WINDOW_FRAMES.toLong()).apply { rewind() }
        val cacheChBuf = FloatBuffer.wrap(cacheLastChannel)
        val cacheTBuf = FloatBuffer.wrap(cacheLastTime)
        val cacheLenBuf = LongBuffer.allocate(1).put(cacheLastChannelLen).apply { rewind() }

        OnnxTensor.createTensor(env, audioBuf, longArrayOf(1, N_MELS.toLong(), WINDOW_FRAMES.toLong())).use { audioTensor ->
        OnnxTensor.createTensor(env, lengthBuf, longArrayOf(1)).use { lengthTensor ->
        OnnxTensor.createTensor(env, cacheChBuf, longArrayOf(1, NUM_LAYERS.toLong(), CACHE_LEN.toLong(), D_MODEL.toLong())).use { cacheChTensor ->
        OnnxTensor.createTensor(env, cacheTBuf, longArrayOf(1, NUM_LAYERS.toLong(), D_MODEL.toLong(), TIME_CACHE.toLong())).use { cacheTTensor ->
        OnnxTensor.createTensor(env, cacheLenBuf, longArrayOf(1)).use { cacheLenTensor ->
            val inputs = mapOf(
                "audio_signal" to audioTensor,
                "length" to lengthTensor,
                "cache_last_channel" to cacheChTensor,
                "cache_last_time" to cacheTTensor,
                "cache_last_channel_len" to cacheLenTensor,
            )
            session.run(inputs).use { results ->
                @Suppress("UNCHECKED_CAST")
                val logprobs = results[0].value as Array<Array<FloatArray>>
                @Suppress("UNCHECKED_CAST")
                val nextCacheCh = results[1].value as Array<Array<Array<FloatArray>>>
                @Suppress("UNCHECKED_CAST")
                val nextCacheT = results[2].value as Array<Array<Array<FloatArray>>>
                val nextCacheLen = (results[3].value as LongArray)[0]

                appendGreedyDecode(logprobs[0])

                cacheLastChannel = flatten4D(nextCacheCh, NUM_LAYERS, CACHE_LEN, D_MODEL)
                cacheLastTime = flatten4D(nextCacheT, NUM_LAYERS, D_MODEL, TIME_CACHE)
                cacheLastChannelLen = nextCacheLen
            }
        }}}}}

        inferenceCount++
        if (inferenceCount % 25 == 1L) {
            val ms = (System.nanoTime() - t0) / 1_000_000
            Log.i(TAG, "inference #$inferenceCount : ${ms}ms | frames=$framesComputed | ids=${decodedIds.size} | cacheLen=$cacheLastChannelLen")
        }
    }

    private fun flatten4D(arr: Array<Array<Array<FloatArray>>>, d1: Int, d2: Int, d3: Int): FloatArray {
        val out = FloatArray(d1 * d2 * d3)
        var idx = 0
        for (i in 0 until d1) for (j in 0 until d2) for (k in 0 until d3) out[idx++] = arr[0][i][j][k]
        return out
    }

    private fun appendGreedyDecode(frames: Array<FloatArray>) {
        for (frame in frames) {
            var best = 0
            var bestVal = frame[0]
            for (c in 1 until frame.size) {
                if (frame[c] > bestVal) { bestVal = frame[c]; best = c }
            }
            if (best != prevTokenForCollapse && best != blankId) decodedIds.add(best)
            prevTokenForCollapse = best
        }
    }

    private fun detokenize(ids: List<Int>): String {
        val sb = StringBuilder()
        for (id in ids) if (id < vocab.size) sb.append(vocab[id])
        return sb.toString().replace('▁', ' ').trim()
    }

    fun close() {
        session.close()
    }
}

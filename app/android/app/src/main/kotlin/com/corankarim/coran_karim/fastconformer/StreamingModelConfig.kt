package com.corankarim.coran_karim.fastconformer

import org.json.JSONArray
import org.json.JSONObject

/**
 * Versioned deployment contract written next to the cache-aware ONNX export.
 *
 * The first mobile deployment intentionally accepts only the causal checkpoint
 * validated by benchmark/export_streaming_onnx.py. Failing fast here prevents
 * the historical 25/16/time-cache=4 prototype from silently corrupting a
 * 121/112/time-cache=8 inference session.
 */
data class StreamingModelConfig(
    val schemaVersion: Int,
    val sourceNemo: String,
    val attentionContextSize: List<Int>,
    val inputFrames: Int,
    val shiftFrames: Int,
    val preEncodeCacheFrames: Int,
    val validOutputFrames: Int,
    val cacheLastChannelShape: List<Long>,
    val cacheLastTimeShape: List<Long>,
    val subsamplingFactor: Int,
    val windowStrideMs: Int,
    val lookaheadMs: Int,
    val hasTajwidHead: Boolean,
) {
    init {
        require(schemaVersion == SCHEMA_VERSION) {
            "schema streaming non supporte: $schemaVersion"
        }
        require(sourceNemo == EXPECTED_SOURCE_NEMO) {
            "checkpoint streaming inattendu: $sourceNemo"
        }
        require(attentionContextSize == EXPECTED_ATTENTION_CONTEXT) {
            "contexte causal inattendu: $attentionContextSize"
        }
        require(
            inputFrames == EXPECTED_INPUT_FRAMES &&
                shiftFrames == EXPECTED_SHIFT_FRAMES &&
                preEncodeCacheFrames == EXPECTED_PRE_ENCODE_CACHE_FRAMES &&
                inputFrames == shiftFrames + preEncodeCacheFrames
        ) {
            "fenetre streaming invalide: input=$inputFrames shift=$shiftFrames " +
                "preCache=$preEncodeCacheFrames"
        }
        require(validOutputFrames == EXPECTED_VALID_OUTPUT_FRAMES) {
            "nombre de sorties streaming inattendu: $validOutputFrames"
        }
        require(cacheLastChannelShape == EXPECTED_CHANNEL_CACHE_SHAPE) {
            "cache de canal inattendu: $cacheLastChannelShape"
        }
        require(cacheLastTimeShape == EXPECTED_TIME_CACHE_SHAPE) {
            "cache temporel inattendu: $cacheLastTimeShape"
        }
        require(
            subsamplingFactor == EXPECTED_SUBSAMPLING_FACTOR &&
                windowStrideMs == EXPECTED_WINDOW_STRIDE_MS &&
                lookaheadMs ==
                attentionContextSize[1] * subsamplingFactor * windowStrideMs
        ) {
            "grille temporelle streaming invalide"
        }
        require(!hasTajwidHead) {
            "ce deploiement causal doit rester sans tete tajweed"
        }
    }

    val numLayers: Int
        get() = cacheLastChannelShape[1].toInt()

    val channelCacheFrames: Int
        get() = cacheLastChannelShape[2].toInt()

    val modelDimension: Int
        get() = cacheLastChannelShape[3].toInt()

    val timeCacheFrames: Int
        get() = cacheLastTimeShape[3].toInt()

    companion object {
        private const val SCHEMA_VERSION = 1
        private const val EXPECTED_SOURCE_NEMO = "causal-final.nemo"
        private val EXPECTED_ATTENTION_CONTEXT = listOf(70, 13)
        private const val EXPECTED_INPUT_FRAMES = 121
        private const val EXPECTED_SHIFT_FRAMES = 112
        private const val EXPECTED_PRE_ENCODE_CACHE_FRAMES = 9
        private const val EXPECTED_VALID_OUTPUT_FRAMES = 14
        private val EXPECTED_CHANNEL_CACHE_SHAPE = listOf(1L, 17L, 70L, 512L)
        private val EXPECTED_TIME_CACHE_SHAPE = listOf(1L, 17L, 512L, 8L)
        private const val EXPECTED_SUBSAMPLING_FACTOR = 8
        private const val EXPECTED_WINDOW_STRIDE_MS = 10

        fun fromJson(json: String): StreamingModelConfig {
            try {
                val value = JSONObject(json)
                return StreamingModelConfig(
                    schemaVersion = value.getInt("schema_version"),
                    sourceNemo = value.getString("source_nemo"),
                    attentionContextSize =
                    value.getJSONArray("att_context_size").toIntList(),
                    inputFrames = value.getInt("input_frames"),
                    shiftFrames = value.getInt("shift_frames"),
                    preEncodeCacheFrames =
                    value.getInt("pre_encode_cache_frames"),
                    validOutputFrames = value.getInt("valid_output_frames"),
                    cacheLastChannelShape =
                    value.getJSONArray("cache_last_channel_shape").toLongList(),
                    cacheLastTimeShape =
                    value.getJSONArray("cache_last_time_shape").toLongList(),
                    subsamplingFactor = value.getInt("subsampling_factor"),
                    windowStrideMs = value.getInt("window_stride_ms"),
                    lookaheadMs = value.getInt("lookahead_ms"),
                    hasTajwidHead = value.getBoolean("has_tajwid_head"),
                )
            } catch (error: IllegalArgumentException) {
                throw error
            } catch (error: Exception) {
                throw IllegalArgumentException(
                    "metadonnees streaming invalides: ${error.message}",
                    error,
                )
            }
        }

        private fun JSONArray.toIntList(): List<Int> =
            List(length()) { index -> getInt(index) }

        private fun JSONArray.toLongList(): List<Long> =
            List(length()) { index -> getLong(index) }
    }
}

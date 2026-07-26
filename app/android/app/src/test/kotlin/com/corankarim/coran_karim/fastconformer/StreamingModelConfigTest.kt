package com.corankarim.coran_karim.fastconformer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test

class StreamingModelConfigTest {

    @Test
    fun parsesTheValidatedCausalExportContract() {
        val config = StreamingModelConfig.fromJson(VALID_CONFIG)

        assertEquals(121, config.inputFrames)
        assertEquals(112, config.shiftFrames)
        assertEquals(9, config.preEncodeCacheFrames)
        assertEquals(listOf(1L, 17L, 70L, 512L), config.cacheLastChannelShape)
        assertEquals(listOf(1L, 17L, 512L, 8L), config.cacheLastTimeShape)
        assertFalse(config.hasTajwidHead)
    }

    @Test
    fun rejectsDimensionsFromTheOldPrototype() {
        val invalid = VALID_CONFIG
            .replace("\"input_frames\": 121", "\"input_frames\": 25")
            .replace("\"shift_frames\": 112", "\"shift_frames\": 16")

        assertThrows(IllegalArgumentException::class.java) {
            StreamingModelConfig.fromJson(invalid)
        }
    }

    @Test
    fun rejectsADeploymentWithTajwidHead() {
        val invalid = VALID_CONFIG.replace(
            "\"has_tajwid_head\": false",
            "\"has_tajwid_head\": true",
        )

        assertThrows(IllegalArgumentException::class.java) {
            StreamingModelConfig.fromJson(invalid)
        }
    }

    private companion object {
        val VALID_CONFIG = """
            {
              "schema_version": 1,
              "source_nemo": "causal-final.nemo",
              "att_context_size": [70, 13],
              "input_frames": 121,
              "shift_frames": 112,
              "pre_encode_cache_frames": 9,
              "valid_output_frames": 14,
              "cache_last_channel_shape": [1, 17, 70, 512],
              "cache_last_time_shape": [1, 17, 512, 8],
              "subsampling_factor": 8,
              "window_stride_ms": 10,
              "lookahead_ms": 1040,
              "has_tajwid_head": false
            }
        """.trimIndent()
    }
}

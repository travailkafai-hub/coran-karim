package com.corankarim.coran_karim.fastconformer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CausalAlignmentSessionTest {

    @Test
    fun commitsCoveredWordsAndContinuesFromTheNextAnchor() {
        val session = CausalAlignmentSession(
            vocab = listOf("▁a", "▁b"),
            blankId = 2,
            log = {},
        )
        session.setTarget(
            tokens = listOf(intArrayOf(0), intArrayOf(1)),
            newAnchor = 0,
        )

        val first = session.feed(logProbs(0, 2, 2))
        assertNotNull(first)
        assertEquals(true, first!!["final"])
        assertEquals(0, first["anchor"])
        assertEquals(listOf(0), wordIndexes(first))

        val second = session.feed(logProbs(1, 2, 2))
        assertNotNull(second)
        assertEquals(true, second!!["final"])
        assertEquals(1, second["anchor"])
        assertEquals(listOf(1), wordIndexes(second))
    }

    @Test
    fun resetDropsPendingAudioButKeepsTheDeclaredTargetAndAnchor() {
        val session = CausalAlignmentSession(
            vocab = listOf("▁a"),
            blankId = 1,
            log = {},
        )
        session.setTarget(listOf(intArrayOf(0)), newAnchor = 0)
        session.reset()

        val payload = session.feed(logProbsForSingleToken(0, 1))

        assertNotNull(payload)
        assertTrue(wordIndexes(payload!!).contains(0))
    }

    private fun logProbs(vararg bestIds: Int): Array<FloatArray> =
        Array(bestIds.size) { frame ->
            FloatArray(3) { -8f }.also { it[bestIds[frame]] = -0.01f }
        }

    private fun logProbsForSingleToken(
        tokenId: Int,
        blankId: Int,
    ): Array<FloatArray> = arrayOf(
        floatArrayOf(-8f, -8f).also { it[tokenId] = -0.01f },
        floatArrayOf(-8f, -8f).also { it[blankId] = -0.01f },
    )

    @Suppress("UNCHECKED_CAST")
    private fun wordIndexes(payload: Map<String, Any>): List<Int> =
        (payload["words"] as List<Map<String, Any>>).map { it["i"] as Int }
}

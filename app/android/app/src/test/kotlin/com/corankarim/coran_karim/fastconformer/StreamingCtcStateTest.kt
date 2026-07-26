package com.corankarim.coran_karim.fastconformer

import org.junit.Assert.assertEquals
import org.junit.Test

class StreamingCtcStateTest {

    @Test
    fun repeatedTokenAcrossChunkBoundaryIsEmittedOnce() {
        val state = StreamingCtcState(blankId = 3)

        state.appendArgmax(intArrayOf(0, 1, 1))
        state.appendArgmax(intArrayOf(1, 1, 2))

        assertEquals(listOf(0, 1, 2), state.decodedIds)
    }

    @Test
    fun blankAcrossChunkBoundaryAllowsTokenToBeEmittedAgain() {
        val state = StreamingCtcState(blankId = 3)

        state.appendArgmax(intArrayOf(1, 3))
        state.appendArgmax(intArrayOf(1))

        assertEquals(listOf(1, 1), state.decodedIds)
    }

    @Test
    fun resetClearsTokensAndBoundaryState() {
        val state = StreamingCtcState(blankId = 3)
        state.appendArgmax(intArrayOf(1))

        state.reset()
        state.appendArgmax(intArrayOf(1))

        assertEquals(listOf(1), state.decodedIds)
    }
}

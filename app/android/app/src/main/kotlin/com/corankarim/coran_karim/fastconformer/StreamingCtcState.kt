package com.corankarim.coran_karim.fastconformer

/**
 * Maintains the CTC collapse boundary across successive causal model outputs.
 *
 * A token repeated at the beginning of a new chunk must not be emitted twice
 * unless a blank was observed between the two occurrences.
 */
class StreamingCtcState(
    private val blankId: Int,
) {
    private val emittedIds = ArrayList<Int>()
    private var previousTokenId: Int? = null

    val decodedIds: List<Int>
        get() = emittedIds

    fun appendArgmax(tokenIds: IntArray) {
        tokenIds.forEach(::appendToken)
    }

    fun appendLogProbs(logProbs: Array<FloatArray>) {
        for (frame in logProbs) {
            if (frame.isEmpty()) continue

            var bestId = 0
            var bestScore = frame[0]
            for (tokenId in 1 until frame.size) {
                if (frame[tokenId] > bestScore) {
                    bestId = tokenId
                    bestScore = frame[tokenId]
                }
            }
            appendToken(bestId)
        }
    }

    fun reset() {
        emittedIds.clear()
        previousTokenId = null
    }

    private fun appendToken(tokenId: Int) {
        if (tokenId != blankId && tokenId != previousTokenId) {
            emittedIds.add(tokenId)
        }
        previousTokenId = tokenId
    }
}

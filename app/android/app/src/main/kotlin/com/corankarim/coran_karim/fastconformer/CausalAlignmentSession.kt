package com.corankarim.coran_karim.fastconformer

/**
 * Incremental forced alignment over append-only CTC outputs.
 *
 * Model caches and CTC outputs are independent from the alignment window:
 * completed words are committed, their consumed frames are discarded, while
 * the encoder caches continue uninterrupted. This bounds the dynamic-program
 * cost without cutting PCM in the middle of a word.
 */
class CausalAlignmentSession(
    vocab: List<String>,
    blankId: Int,
    private val log: (String) -> Unit = { message ->
        DiagnosticLog.log(TAG, message)
    },
) {
    private companion object {
        private const val TAG = "CausalAlignment"
        private const val MAX_ALIGN_WORDS = 80
    }

    private val aligner = ForcedAligner(vocab, blankId)
    private val logProbBuffer = ArrayList<FloatArray>()

    private var targetTokens: List<IntArray>? = null
    private var targetVariants: List<List<Pair<String, IntArray>>>? = null
    private var anchor = 0
    private var sequence = 0
    private var lastPayload: Map<String, Any>? = null

    @Synchronized
    fun setTarget(
        tokens: List<IntArray>,
        newAnchor: Int,
        variants: List<List<Pair<String, IntArray>>>? = null,
    ) {
        targetTokens = tokens
        targetVariants = variants
        anchor = newAnchor.coerceIn(0, tokens.size)
        clearAudioState()
        log("cible causale : ${tokens.size} mots, ancre=$anchor")
    }

    @Synchronized
    fun extendTarget(
        newTokens: List<IntArray>,
        newVariants: List<List<Pair<String, IntArray>>>? = null,
    ) {
        val current = targetTokens
        targetTokens = if (current == null) newTokens else current + newTokens
        if (newVariants != null) {
            val currentVariants =
                targetVariants ?: List(current?.size ?: 0) { emptyList() }
            targetVariants = currentVariants + newVariants
        }
        log("cible causale etendue : +${newTokens.size}, total=${targetTokens?.size}")
    }

    @Synchronized
    fun setAnchor(newAnchor: Int) {
        val tokens = targetTokens ?: return
        anchor = newAnchor.coerceIn(0, tokens.size)
        clearAudioState()
        log("ancre causale deplacee : $anchor")
    }

    @Synchronized
    fun reset() {
        clearAudioState()
    }

    /**
     * Appends the model frames once and returns the latest payload.
     *
     * Only a contiguous prefix of fully covered words is final. The frontier
     * word remains a preview and its frames stay buffered for the next chunk.
     */
    @Synchronized
    fun feed(newLogProbs: Array<FloatArray>): Map<String, Any>? {
        if (newLogProbs.isEmpty()) return lastPayload
        val tokens = targetTokens ?: return null
        if (anchor >= tokens.size) return null

        logProbBuffer.addAll(newLogProbs)
        val end = minOf(tokens.size, anchor + MAX_ALIGN_WORDS)
        val slice = tokens.subList(anchor, end)
        val variantsSlice = targetVariants?.let {
            if (anchor < it.size) it.subList(anchor, minOf(it.size, end)) else null
        }
        val result = aligner.align(
            logprobs = logProbBuffer.toTypedArray(),
            wordTokens = slice,
            anchor = anchor,
            isFinal = true,
            wordVariants = variantsSlice,
            segmentRules = emptyList(),
        ) ?: return lastPayload

        val coveredWords = result.words.takeWhile { it.covered }
        sequence++
        if (coveredWords.isEmpty()) {
            lastPayload = payload(
                payloadAnchor = anchor,
                frontier = result.frontier,
                isFinal = false,
                words = result.words,
            )
            return lastPayload
        }

        val payloadAnchor = anchor
        val lastConsumedFrame = coveredWords.last().lastFrame
        require(lastConsumedFrame >= 0) {
            "mot couvert sans frame CTC consommee"
        }

        anchor += coveredWords.size
        logProbBuffer.subList(0, lastConsumedFrame + 1).clear()
        lastPayload = payload(
            payloadAnchor = payloadAnchor,
            frontier = anchor,
            isFinal = true,
            words = coveredWords,
        )
        log(
            "alignement causal seq=$sequence ancre=$payloadAnchor " +
                "mots=${coveredWords.size} nouvelle_ancre=$anchor " +
                "frames_restantes=${logProbBuffer.size}",
        )
        return lastPayload
    }

    private fun payload(
        payloadAnchor: Int,
        frontier: Int,
        isFinal: Boolean,
        words: List<ForcedAligner.WordResult>,
    ): Map<String, Any> = mapOf(
        "seq" to sequence,
        "anchor" to payloadAnchor,
        "frontier" to frontier,
        "final" to isFinal,
        "words" to words.map { word ->
            mapOf(
                "i" to word.index,
                "gop" to word.gop,
                "forced" to word.forced,
                "covered" to word.covered,
                "actual" to word.actual,
            ) + (word.rescoreMargin?.let { mapOf("rescoreMargin" to it) }
                ?: emptyMap()) +
                (word.rescoreHeard?.let { mapOf("rescoreHeard" to it) }
                    ?: emptyMap()) +
                (if (word.actualFromFree) mapOf("srcFree" to true) else emptyMap())
        },
    )

    private fun clearAudioState() {
        logProbBuffer.clear()
        lastPayload = null
    }
}

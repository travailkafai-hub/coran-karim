package com.corankarim.coran_karim.fastconformer

/**
 * Alignement force CTC + score GOP (Goodness of Pronunciation).
 *
 * Principe (refonte 2026-07-11, remplace le diff textuel flou cote Dart) : le
 * texte a reciter est CONNU d'avance -- au lieu de decoder librement puis
 * comparer les textes (chemin expose au biais du modele qui "corrige" vers le
 * texte canonique, et source des ~10 regles ad hoc accumulees dans
 * recitation_provider.dart), on aligne de force la sequence de tokens attendue
 * sur les log-probabilites du modele (programmation dynamique CTC classique,
 * type torchaudio.functional.forced_align), et on juge chaque mot par l'ECART
 * entre deux scores mesures sur les MEMES frames :
 *
 *   forced = logprob moyenne du chemin force (le mot attendu, harakat comprises)
 *   free   = logprob moyenne du meilleur token par frame (ce que le modele
 *            prefererait dire, sans contrainte)
 *   gop    = forced - free   (toujours <= 0 ; proche de 0 = l'audio soutient
 *            pleinement le mot attendu ; tres negatif = le modele est bien
 *            plus sur d'avoir entendu AUTRE CHOSE)
 *
 * Les harakat sont des tokens BPE distincts dans notre vocabulaire (modele
 * "pcd") : une fatha au lieu d'une kasra effondre la logprob du chemin force
 * precisement sur les frames de la voyelle fautive -- detection a la harakat
 * pres, la ou le diff textuel devait deviner apres coup si une difference de
 * mots decodes etait une voyelle ou du bruit ASR. Et le signal survit au biais
 * du modele : meme quand l'argmax "corrige" vers le mot canonique, l'hesitation
 * reste visible dans les probabilites sous-jacentes.
 *
 * Les scores ne sont mesures QUE sur les frames ou le chemin force est dans un
 * etat TOKEN (pas blank) : les frames blank sont partagees par les deux chemins
 * (gop ~= 0) et ne feraient que diluer le signal.
 */
class ForcedAligner(
    private val vocab: List<String>,
    private val blankId: Int,
) {

    companion object {
        private const val TAG = "ForcedAligner"
    }

    /** Resultat par mot. [index] est l'index ABSOLU dans le texte attendu complet. */
    data class WordResult(
        val index: Int,
        val gop: Double,
        val forced: Double,
        val covered: Boolean,
        val actual: String,
    )

    /**
     * [frontier] : index ABSOLU du premier mot que l'audio ne couvre PAS
     * completement (= le mot "en cours" cote UI). Les mots avant frontier sont
     * juges fiables ; le mot a frontier peut apparaitre dans [words] avec
     * covered=false (partiellement entendu, a ne pas juger sur un apercu).
     */
    data class Result(
        val frontier: Int,
        val words: List<WordResult>,
    )

    /**
     * Aligne les mots attendus (tokens par mot, a partir de l'ancre [anchor],
     * indices absolus) sur [logprobs] (T frames x vocab+1). L'alignement est
     * PARTIEL : le meilleur etat final peut etre au milieu de la sequence --
     * l'audio ne contient peut-etre que les premiers mots (c'est la frontiere).
     * Retourne null si rien d'alignable (pas de frames, pas de tokens).
     */
    fun align(
        logprobs: Array<FloatArray>,
        wordTokens: List<IntArray>,
        anchor: Int,
    ): Result? {
        val t = logprobs.size
        if (t == 0 || wordTokens.isEmpty()) return null

        // Sequence plate de tokens + mot proprietaire de chaque token.
        val flat = ArrayList<Int>()
        val owner = ArrayList<Int>()
        wordTokens.forEachIndexed { w, toks ->
            for (tok in toks) {
                flat.add(tok)
                owner.add(w)
            }
        }
        val n = flat.size
        if (n == 0) return null
        // Etats etendus CTC : [blank, tok0, blank, tok1, ..., tokN-1, blank]
        // etat 2i = blank AVANT le token i ; etat 2i+1 = token i.
        val s = 2 * n + 1

        val negInf = Double.NEGATIVE_INFINITY
        var prev = DoubleArray(s) { negInf }
        var cur = DoubleArray(s) { negInf }
        // Retro-pointeurs : 0 = rester, 1 = depuis s-1, 2 = depuis s-2 (saut de
        // blank entre deux tokens differents).
        val bp = Array(t) { ByteArray(s) }

        fun emit(ti: Int, si: Int): Double {
            val lp = logprobs[ti]
            return if (si % 2 == 0) lp[blankId].toDouble()
            else lp[flat[(si - 1) / 2]].toDouble()
        }

        prev[0] = emit(0, 0)
        if (s > 1) prev[1] = emit(0, 1)

        for (ti in 1 until t) {
            for (si in 0 until s) {
                var best = prev[si]
                var from: Byte = 0
                if (si >= 1 && prev[si - 1] > best) {
                    best = prev[si - 1]; from = 1
                }
                if (si >= 3 && si % 2 == 1 &&
                    flat[(si - 1) / 2] != flat[(si - 3) / 2] &&
                    prev[si - 2] > best
                ) {
                    best = prev[si - 2]; from = 2
                }
                cur[si] = if (best == negInf) negInf else best + emit(ti, si)
                bp[ti][si] = from
            }
            val tmp = prev; prev = cur; cur = tmp
            java.util.Arrays.fill(cur, negInf)
        }

        // Fin PARTIELLE : meilleur etat final sur TOUS les etats (pas seulement
        // le dernier) -- l'audio peut s'arreter au milieu du texte attendu. Le
        // chemin qui explique le mieux l'audio gagne naturellement : rester en
        // arriere pendant que de la parole existe force des blanks a logprob
        // faible sur ces frames.
        var bestEnd = 0
        var bestVal = prev[0]
        for (si in 1 until s) {
            if (prev[si] > bestVal) {
                bestVal = prev[si]; bestEnd = si
            }
        }
        if (bestVal == negInf) return null

        // Retro-parcours -> etat du chemin force a chaque frame.
        val path = IntArray(t)
        var siCur = bestEnd
        for (ti in t - 1 downTo 0) {
            path[ti] = siCur
            if (ti > 0) siCur -= bp[ti][siCur]
        }

        // Agregation par mot : frames de tokens uniquement (pas les blanks).
        val w = wordTokens.size
        val wordFirstFrame = IntArray(w) { -1 }
        val wordLastFrame = IntArray(w) { -1 }
        val wordForcedSum = DoubleArray(w)
        val wordFreeSum = DoubleArray(w)
        val wordFrames = IntArray(w)

        for (ti in 0 until t) {
            val si = path[ti]
            if (si % 2 == 0) continue
            val tokIdx = (si - 1) / 2
            val wIdx = owner[tokIdx]
            if (wordFirstFrame[wIdx] < 0) wordFirstFrame[wIdx] = ti
            wordLastFrame[wIdx] = ti
            val lp = logprobs[ti]
            wordForcedSum[wIdx] += lp[flat[tokIdx]].toDouble()
            var mx = lp[0]
            for (c in 1 until lp.size) if (lp[c] > mx) mx = lp[c]
            wordFreeSum[wIdx] += mx.toDouble()
            wordFrames[wIdx]++
        }

        // Frontiere : etat 2i (blank avant token i) => tokens 0..i-1 termines,
        // prochain a dire = i ; etat 2i+1 => token i en cours. Dans les deux
        // cas, l'index du token frontiere = bestEnd / 2 (division entiere).
        val frontierTok = bestEnd / 2
        val frontierWordRel = if (frontierTok >= n) w else owner[frontierTok]

        val results = ArrayList<WordResult>(w)
        for (wi in 0 until w) {
            if (wordFrames[wi] == 0) break // au-dela de la frontiere, plus de frames
            val covered = wi < frontierWordRel
            val forced = wordForcedSum[wi] / wordFrames[wi]
            val free = wordFreeSum[wi] / wordFrames[wi]
            val actual = greedyDecodeRange(logprobs, wordFirstFrame[wi], wordLastFrame[wi])
            results.add(WordResult(anchor + wi, forced - free, forced, covered, actual))
        }
        return Result(anchor + frontierWordRel, results)
    }

    /** Decodage glouton LIBRE restreint a une plage de frames [from..toIncl] --
     *  donne "ce que le modele a reellement entendu" sur la plage du mot. */
    private fun greedyDecodeRange(logprobs: Array<FloatArray>, from: Int, toIncl: Int): String {
        val ids = ArrayList<Int>()
        var prevBest = -1
        for (ti in from..toIncl) {
            val frame = logprobs[ti]
            var best = 0
            var bestVal = frame[0]
            for (c in 1 until frame.size) {
                if (frame[c] > bestVal) { bestVal = frame[c]; best = c }
            }
            if (best != prevBest && best != blankId) ids.add(best)
            prevBest = best
        }
        val sb = StringBuilder()
        for (id in ids) if (id < vocab.size) sb.append(vocab[id])
        return sb.toString().replace('▁', ' ').trim()
    }
}

/**
 * Tokenizer BPE pour l'alignement force. Source PRIMAIRE : dictionnaire
 * mot -> IDs precalcule avec le VRAI tokenizer NeMo (SentencePiece),
 * cf. benchmark/build_word_token_lookup.py -- couvre tout le vocabulaire
 * coranique (18k+ mots, verifie 2026-07-11), zero risque de divergence avec
 * ce que le modele a reellement appris a predire. Repli : correspondance
 * gloutonne la plus longue sur les pieces du vocabulaire, pour un mot absent
 * du dictionnaire (texte hors-Coran, ex. Arabic Speech Corpus si jamais
 * utilise ici, ou dictionnaire pas encore deploye/a jour) -- verifie
 * coincider avec le vrai tokenizer sur plusieurs mots testes, mais reste une
 * approximation, jamais la source de verite si le dictionnaire est present.
 * Le texte d'entree doit etre normalise comme le corpus d'entrainement
 * (ArabicNormalizer.normalizeTraining cote Dart -- PAS normalizeStrict, qui
 * fusionne des lettres que le modele distingue, cf. FONCTIONNALITES_FUTURES.md §5.3).
 */
class CtcTokenizer(vocab: List<String>, private val wordLookup: Map<String, IntArray>? = null) {
    companion object {
        private const val TAG = "CtcTokenizer"
    }

    private val pieceToId = HashMap<String, Int>(vocab.size * 2)
    private val maxPieceLen: Int
    private var lookupHits = 0
    private var lookupMisses = 0

    init {
        var maxLen = 1
        vocab.forEachIndexed { id, piece ->
            pieceToId[piece] = id
            if (piece.length > maxLen) maxLen = piece.length
        }
        maxPieceLen = maxLen
        if (wordLookup != null) {
            DiagnosticLog.log(TAG, "dictionnaire mot->tokens charge : ${wordLookup.size} mots")
        }
    }

    fun tokenizeWord(word: String): IntArray {
        wordLookup?.get(word)?.let {
            lookupHits++
            return it
        }
        if (wordLookup != null) {
            lookupMisses++
            DiagnosticLog.log(TAG, "mot absent du dictionnaire precalcule, repli greedy : \"$word\" " +
                    "(hits=$lookupHits misses=$lookupMisses)")
        }
        return tokenizeWordGreedy(word)
    }

    /** Repli : correspondance gloutonne la plus longue (prefixe "▁" = debut de
     *  mot SentencePiece). Caracteres hors vocabulaire ignores avec un log. */
    private fun tokenizeWordGreedy(word: String): IntArray {
        val target = "▁$word"
        val ids = ArrayList<Int>(target.length)
        var pos = 0
        while (pos < target.length) {
            var matched = false
            var len = minOf(maxPieceLen, target.length - pos)
            while (len >= 1) {
                val id = pieceToId[target.substring(pos, pos + len)]
                if (id != null) {
                    ids.add(id); pos += len; matched = true; break
                }
                len--
            }
            if (!matched) {
                DiagnosticLog.log(TAG, "caractere hors vocab ignore : '${target[pos]}' dans \"$word\"")
                pos++
            }
        }
        return ids.toIntArray()
    }
}

/** Charge le dictionnaire mot->IDs precalcule (JSON plat {mot: [ids...]}).
 *  Retourne null si absent/invalide -- CtcTokenizer se rabat alors entierement
 *  sur le greedy (comportement identique a avant l'introduction du lookup). */
fun loadWordTokenLookup(path: String): Map<String, IntArray>? {
    return try {
        val json = org.json.JSONObject(java.io.File(path).readText(Charsets.UTF_8))
        val map = HashMap<String, IntArray>(json.length() * 2)
        val keys = json.keys()
        while (keys.hasNext()) {
            val word = keys.next()
            val arr = json.getJSONArray(word)
            val ids = IntArray(arr.length()) { arr.getInt(it) }
            map[word] = ids
        }
        map
    } catch (e: Exception) {
        DiagnosticLog.log("CtcTokenizer", "echec chargement word_tokens.json ($path): ${e.message}")
        null
    }
}

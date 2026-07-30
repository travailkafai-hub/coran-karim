package com.corankarim.coran_karim.recitation2

/**
 * Banc synthetique — outillage commun aux tests de la chaine v2.
 *
 * POURQUOI UN FAUX FRONT ACOUSTIQUE, ET PAS UN VRAI MODELE : le contrat v2 dit
 * que les couches B, D, E, F, G sont PURES et n'ont aucune dependance au
 * modele. On peut donc les mesurer entierement sans ONNX, en JVM, en quelques
 * millisecondes — et surtout sans REIMPLEMENTER leur logique ailleurs.
 *
 * C'est la reponse directe au piege le plus couteux du graphe : "un banc qui ne
 * reproduit ni la PARTIALITE de l'entree ni les REFUS du composant reel peut
 * classer des hypotheses, jamais valider un correctif" (2026-07-29, apres deux
 * predictions hors device confiantes et fausses). Ici le banc n'imite rien : il
 * appelle le code de l'app. Seule la source des logprobs est remplacee.
 *
 * ENCODAGE : chaque frame de 80 ms (1280 echantillons) est remplie d'une valeur
 * constante qui code l'id de token que le modele "entend". [FauxFront] relit
 * cette valeur — il reste donc une fonction PURE de la fenetre, exactement
 * comme le vrai front.
 */
object Synthese {

    const val BASE = 0.1f
    const val PAS = 0.0005f

    fun valeurPourId(id: Int): Float = BASE + id * PAS

    fun idDepuisValeur(v: Float, blank: Int): Int =
        if (v < 0.05f) blank else Math.round((v - BASE) / PAS)

    /**
     * Vocabulaire jouet : le 1er caractere d'un mot devient la piece "▁x",
     * les suivants des pieces d'un caractere. Un mot de n lettres fait donc
     * n tokens — ce qui exerce reellement le treillis CTC.
     */
    fun vocabulaire(mots: List<String>): List<String> {
        val pieces = LinkedHashSet<String>()
        for (m in mots) {
            if (m.isEmpty()) continue
            pieces.add("▁" + m[0])
            for (i in 1 until m.length) pieces.add(m[i].toString())
        }
        return pieces.toList()
    }

    fun tokeniseur(pieces: List<String>): (String) -> IntArray {
        val index = pieces.withIndex().associate { (i, p) -> p to i }
        return { mot ->
            val ids = ArrayList<Int>(mot.length)
            if (mot.isNotEmpty()) {
                index["▁" + mot[0]]?.let { ids.add(it) }
                for (i in 1 until mot.length) index[mot[i].toString()]?.let { ids.add(it) }
            }
            ids.toIntArray()
        }
    }

    /**
     * PCM d'une recitation : chaque token occupe [framesParToken] frames, chaque
     * mot est suivi de [framesBlanc] frames de blanc (le modele CTC emet du
     * blanc entre les mots).
     */
    fun pcm(
        motsPrononces: List<String>,
        tokeniser: (String) -> IntArray,
        blank: Int,
        framesParToken: Int = 2,
        framesBlanc: Int = 2,
    ): FloatArray {
        val frames = ArrayList<Int>()
        for (m in motsPrononces) {
            for (tk in tokeniser(m)) repeat(framesParToken) { frames.add(tk) }
            repeat(framesBlanc) { frames.add(blank) }
        }
        val out = FloatArray(frames.size * Horloge.ECH_PAR_FRAME)
        frames.forEachIndexed { i, id ->
            val v = valeurPourId(id)
            java.util.Arrays.fill(
                out, i * Horloge.ECH_PAR_FRAME, (i + 1) * Horloge.ECH_PAR_FRAME, v
            )
        }
        return out
    }

    /** Silence reel (RMS nul) — pour exercer le portier et la table d'horloges. */
    fun silence(secondes: Double): FloatArray =
        FloatArray(Horloge.secondesVersEch(secondes))
}

/** Front acoustique de banc : fonction pure de la fenetre, comme le vrai. */
class FauxFront(override val pieces: List<String>) : FrontAcoustique {
    override val blank: Int = pieces.size

    override fun logprobs(echantillons: FloatArray): Array<FloatArray> {
        val t = echantillons.size / Horloge.ECH_PAR_FRAME
        val v = pieces.size + 1
        return Array(t) { f ->
            val id = Synthese.idDepuisValeur(echantillons[f * Horloge.ECH_PAR_FRAME], blank)
            FloatArray(v) { c -> if (c == id) -0.01f else -12f }
        }
    }
}

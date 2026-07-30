package com.corankarim.coran_karim.recitation2

/**
 * COUCHE D — LOCALISATION.
 *
 * Repond a UNE question : quelle tranche du texte attendu cette fenetre
 * couvre-t-elle ?
 *
 * CONTRAT :
 *  - entree : logprobs de la fenetre, texte attendu, dernier mot verrouille ;
 *  - AUCUN effet de bord. D ne deplace aucun etat global, ne verrouille rien,
 *    n'abandonne aucun mot, ne connait aucun seuil de couleur ;
 *  - peut repondre `null` ("je ne sais pas") — la fenetre ne produit alors
 *    aucun jugement. C'est un resultat legitime, pas un echec a compenser.
 *
 * TROIS DEFAUTS DE LA v1 QUE CE CONTRAT SUPPRIME :
 *
 * 1. [PIEGE] resync_avant_seulement — `findResyncOffset` ne cherchait QU'EN
 *    AVANT (`bestOff > anchor`). Un recitateur qui REPETE ne pouvait
 *    structurellement pas etre suivi, et le banc (audio lineaire) ne pouvait
 *    pas produire le cas. Ici la recherche est BORNEE DES DEUX COTES
 *    ([reculMax] / [avanceMax]).
 *
 * 2. La regression v22 (`305db63`, 8,16 % -> 13,40 %, annulee) venait du
 *    COUPLAGE "deplacer l'ancre" => "les mots derriere sont perdus". Ici les
 *    deux operations sont decorrelees : deplacer la bande n'abandonne rien.
 *    Les mots depasses restent dans le registre de preuves, eligibles a
 *    n'importe quelle fenetre ulterieure — et leur audio est toujours dans le
 *    flux brut. Il n'y a plus d'ancre mutable dont l'erreur se propage : la
 *    position est REESTIMEE a chaque fenetre depuis l'acoustique, jamais
 *    incrementee depuis l'historique.
 *
 * 3. La comparaison porte sur du TEXTE, pas sur des ids de tokens — piste
 *    mesuree `4606d64` (Maryam 15,46 % -> 9,18 %, rouges 10 -> 6), restee sans
 *    objet en v1 parce que `RESYNC_ACTIF` etait passe a false.
 */
class Localisateur(
    private val pieces: List<String>,
    private val blank: Int,
    private val reculMax: Int = 12,
    private val avanceMax: Int = 24,
    private val margeAval: Int = 3,
    private val minAppariements: Int = 2,
) {
    /**
     * @param i0 premier mot attendu couvert par la fenetre (inclus)
     * @param i1 dernier mot attendu couvert (inclus)
     * @param confiance appariements / mots entendus, dans [0,1]
     * @param recul vrai si la bande part EN ARRIERE du dernier mot verrouille
     *   (le recitateur repete) — journalise, jamais silencieux.
     * @param attestes index de mot attendu -> plage de frames ou le DECODAGE
     *   LIBRE l'a effectivement entendu. C'est la seule preuve positive qu'un
     *   mot a ete PRONONCE ; l'alignement force, lui, place toujours tous les
     *   mots qu'on lui donne, prononces ou non.
     */
    data class Bande(
        val i0: Int,
        val i1: Int,
        val confiance: Float,
        val recul: Boolean,
        val attestes: Map<Int, IntRange>,
    )

    fun localiser(
        logprobs: Array<FloatArray>,
        motsAttendus: List<String>,
        dernierVerrouille: Int,
    ): Bande? {
        if (motsAttendus.isEmpty() || logprobs.isEmpty()) return null
        val entendusAvecFrames = Decodage.motsAvecFrames(logprobs, pieces, blank)
            .map { it to NormalisationComparaison.normaliser(it.texte) }
            .filter { it.second.isNotEmpty() }
        if (entendusAvecFrames.isEmpty()) return null
        val entendus = entendusAvecFrames.map { it.second }

        val attendus = motsAttendus.map { NormalisationComparaison.normaliser(it) }
        val depart = (dernierVerrouille + 1).coerceIn(0, motsAttendus.size - 1)
        val min = (depart - reculMax).coerceAtLeast(0)
        val max = (depart + avanceMax).coerceAtMost(motsAttendus.size - 1)

        var meilleurDebut = -1
        var meilleurScore = 0
        var meilleurFin = -1
        var meilleureDistance = Int.MAX_VALUE
        var meilleursAttestes: Map<Int, IntRange> = emptyMap()

        for (s in min..max) {
            val (score, fin, attestes) = apparier(entendus, attendus, s, entendusAvecFrames)
            if (score < minAppariements) continue
            val distance = kotlin.math.abs(s - depart)
            // Depart le mieux apparie ; a egalite, le plus proche de la position
            // connue ; a egalite encore, l'AVANT (continuite de recitation).
            val meilleur = score > meilleurScore ||
                (score == meilleurScore && distance < meilleureDistance) ||
                (score == meilleurScore && distance == meilleureDistance && s > meilleurDebut)
            if (meilleur) {
                meilleurScore = score
                meilleurDebut = s
                meilleurFin = fin
                meilleureDistance = distance
                meilleursAttestes = attestes
            }
        }
        if (meilleurDebut < 0) return null

        val i1 = (meilleurFin + margeAval).coerceAtMost(motsAttendus.size - 1)
        return Bande(
            i0 = meilleurDebut,
            i1 = maxOf(i1, meilleurDebut),
            confiance = meilleurScore.toFloat() / entendus.size,
            recul = meilleurDebut < depart,
            attestes = meilleursAttestes,
        )
    }

    /**
     * Appariement glouton dans l'ordre : combien de mots entendus retrouve-t-on
     * dans `attendus` a partir de [depart], en autorisant des sauts des deux
     * cotes (le modele peut avaler un mot, le recitateur peut en ajouter un).
     *
     * @return (nombre d'appariements, index attendu du dernier apparie,
     *   index attendu -> plage de frames ou il a ete entendu)
     */
    private fun apparier(
        entendus: List<String>,
        attendus: List<String>,
        depart: Int,
        avecFrames: List<Pair<Decodage.MotEntendu, String>>,
    ): Triple<Int, Int, Map<Int, IntRange>> {
        var i = depart
        var score = 0
        var dernier = depart
        var sautsEntendus = 0
        val attestes = HashMap<Int, IntRange>()
        for ((rang, mot) in entendus.withIndex()) {
            var trouve = -1
            var j = i
            val limite = minOf(attendus.size - 1, i + 2) // un mot attendu saute au plus 2 fois
            while (j <= limite) {
                if (correspond(mot, attendus[j])) { trouve = j; break }
                j++
            }
            if (trouve >= 0) {
                score++
                dernier = trouve
                i = trouve + 1
                sautsEntendus = 0
                val f = avecFrames[rang].first
                attestes[trouve] = f.premiereFrame..f.derniereFrame
            } else {
                sautsEntendus++
                if (sautsEntendus > 3) break // le decodage a decroche du texte attendu
            }
        }
        return Triple(score, dernier, attestes)
    }

    /** Egalite exacte apres normalisation, ou prefixe long (>= 3 lettres) —
     *  un mot tronque par le decodage libre ne doit pas casser la LOCALISATION
     *  (il sera de toute facon juge par l'alignement force, pas ici). */
    private fun correspond(entendu: String, attendu: String): Boolean {
        if (entendu == attendu) return true
        val n = minOf(entendu.length, attendu.length)
        if (n < 3) return false
        return entendu.regionMatches(0, attendu, 0, n)
    }
}

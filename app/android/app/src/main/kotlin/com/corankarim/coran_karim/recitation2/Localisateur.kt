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
    /** Doit couvrir le PLUS LONG bloc possible. Avec un decoupage aux silences
     *  reels un bloc peut porter 40 mots et plus ; une avance de 24 tronquait
     *  la region de recherche et l'ancre decrochait au mot 82 (mesure du
     *  2026-07-30). Ce n'est pas un seuil de tolerance : c'est la taille de la
     *  fenetre de recherche, elle doit juste etre assez grande. */
    private val avanceMax: Int = 80,
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

        // UNE seule LCS sur toute la region : elle trouve d'elle-meme la
        // correspondance, il n'y a pas de « point de depart » a balayer.
        val (score, _, attestes) =
            apparier(entendus, attendus, min, entendusAvecFrames, max)
        if (score < minAppariements || attestes.isEmpty()) return null

        // ── LA CORRECTION DU 2026-07-30, ET LA MESURE QUI L'IMPOSE ──────────
        //
        // La bande partait du point de DEPART DU BALAYAGE (`s`), pas du premier
        // mot reellement ATTESTE. Un bloc qui contenait les mots 12 a 25 se
        // voyait donc reclamer les mots 0 a 25 : l'alignement force devait
        // placer douze mots absents, il les entassait sur les premieres frames,
        // et le chemin de Viterbi etait corrompu sur TOUT le bloc.
        //
        // Preuve directe, meme mot, meme session :
        //     f0 (18,00 s)  mot 2  gop= 0,00   entendu="كَفَرُوا۟"
        //     f2 (13,52 s)  mot 2  gop=-21,84  entendu=""      bande=0..25
        // Le modele lit parfaitement ; c'est la bande qui etait fausse.
        //
        // Les degats croissent avec la longueur du bloc : 36,61 % de non-verts
        // avec des fenetres de 6 s, 80,00 % avec des blocs de 18 s.
        //
        // La regle est donc : on ne demande a la DP QUE ce que le decodage
        // libre atteste. `margeAval` etait une marge inventee -- exactement le
        // genre de constante que ce projet paye a chaque fois.
        val i0 = attestes.keys.min()
        val i1 = attestes.keys.max()
        return Bande(
            i0 = i0,
            i1 = i1,
            confiance = score.toFloat() / entendus.size,
            recul = i0 < depart,
            attestes = attestes,
        )
    }

    /**
     * Appariement par ALIGNEMENT (plus longue sous-sequence commune), pas par
     * balayage glouton.
     *
     * CE QUI A CHANGE LE 2026-07-30, ET POURQUOI. La version precedente
     * avancait mot par mot et ABANDONNAIT apres 3 mots entendus non reconnus
     * d'affilee. Ce « 3 » etait un seuil que rien ne justifiait, et il a coute
     * exactement ce que coutent les seuils inventes : sur des blocs longs
     * (decoupage aux silences reels, ~40 mots par bloc), trois substitutions
     * groupees suffisaient a faire decrocher l'appariement, l'ancre restait
     * bloquee au mot 82 sur 295, et 153 observations seulement etaient
     * produites au lieu de 1440.
     *
     * Une LCS n'a besoin d'aucun seuil : les insertions (le modele entend un
     * mot de trop) et les suppressions (il en avale un) sont des trous du
     * chemin, pas des motifs d'abandon. Le cout est |entendus| x |region|,
     * soit quelques milliers de cases -- negligeable devant une inference.
     *
     * @return (nombre d'appariements, index attendu du dernier apparie,
     *   index attendu -> plage de frames ou il a ete entendu)
     */
    private fun apparier(
        entendus: List<String>,
        attendus: List<String>,
        depart: Int,
        avecFrames: List<Pair<Decodage.MotEntendu, String>>,
        fin: Int,
    ): Triple<Int, Int, Map<Int, IntRange>> {
        val n = entendus.size
        val m = fin - depart + 1
        if (n == 0 || m <= 0) return Triple(0, depart, emptyMap())

        val dp = Array(n + 1) { IntArray(m + 1) }
        for (i in n - 1 downTo 0) {
            for (j in m - 1 downTo 0) {
                dp[i][j] = if (correspond(entendus[i], attendus[depart + j])) {
                    dp[i + 1][j + 1] + 1
                } else {
                    maxOf(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        val attestes = HashMap<Int, IntRange>()
        var dernier = depart
        var i = 0
        var j = 0
        while (i < n && j < m) {
            if (correspond(entendus[i], attendus[depart + j])) {
                val f = avecFrames[i].first
                attestes[depart + j] = f.premiereFrame..f.derniereFrame
                dernier = depart + j
                i++; j++
            } else if (dp[i + 1][j] >= dp[i][j + 1]) i++ else j++
        }
        return Triple(dp[0][0], dernier, attestes)
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

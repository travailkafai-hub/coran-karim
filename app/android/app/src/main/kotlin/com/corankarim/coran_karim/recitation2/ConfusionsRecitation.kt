package com.corankarim.coran_karim.recitation2

/**
 * LES CONFUSIONS TELLES QUE LE PYTHON LES GENERE — port de
 * `benchmark/confusions_recitation.py::variantes`.
 *
 * ── POURQUOI UN SECOND GENERATEUR DE VARIANTES DANS CE PROJET ──────────────
 *
 * `fastconformer/ConfusableVariants.kt` existe deja et sert au rescoring de la
 * chaine v1. Il N'EST PAS interchangeable avec celui-ci, et les confondre
 * casserait la tete 3 sans que rien ne le signale. Trois divergences mesurees
 * en comparant les deux inventaires :
 *
 *   |                     | ConfusableVariants        | ici (= Python)          |
 *   |---------------------|---------------------------|-------------------------|
 *   | position substituee | TOUTES les occurrences    | la PREMIERE seulement   |
 *   | harakat             | 7 (avec les 3 tanwins)    | 4 (fatha/damma/kasra/sukun) |
 *   | paires de lettres   | table symetrisee a la main| la liste CONFUSABLES     |
 *
 * Chacune change le jeu de candidats, donc `alt` et `alt2`, donc deux des douze
 * caracteristiques de la tete. Une tete entrainee sur un jeu et interrogee sur
 * un autre ne rend pas une erreur : elle rend un nombre faux.
 *
 * ⇒ Celui-ci sert EXCLUSIVEMENT a la tete 3. `ConfusableVariants` reste la
 * source du rescoring v1, dont le rendement (80,8 % sur les lettres) a ete
 * mesure avec SA table a lui. Ne pas unifier les deux sans re-mesurer les deux.
 *
 * ── L'ORDRE DE LA TABLE EST CELUI DU PYTHON, PAS UN CHOIX ──────────────────
 *
 * La deduplication garde la PREMIERE apparition (`dict.fromkeys` cote Python,
 * LinkedHashSet ici). Reordonner la table changerait donc la liste produite sur
 * les mots ou deux regles engendrent la meme variante.
 */
object ConfusionsRecitation {

    /**
     * Paires de confusion, dans l'ordre exact de `CONFUSABLES`. Le pourcentage
     * est la part des clips ou la faute S'ENTEND reellement (18 195 clips,
     * controle du 2026-07-31) -- c'est une table de MESURES, pas de gout.
     *
     * ⚠️ La liste contient deja les deux sens pour la plupart des paires
     * (ط→ت ET ت→ط) et le generateur essaie DE TOUTE FACON les deux sens de
     * chaque entree. Ce doublon est dans le Python ; il est sans effet grace a
     * la deduplication, mais il faut le reproduire pour que l'ORDRE des
     * variantes reste le meme.
     */
    private val CONFUSABLES: List<Pair<Char, Char>> = listOf(
        'ط' to 'ت',   // 99 %
        'ت' to 'ط',   // 99 %
        'ض' to 'د',   // 99 %
        'د' to 'ض',   // 99 %
        'ق' to 'ك',   // 98 %
        'ك' to 'ق',   // 98 %
        'ص' to 'س',   // 98 %
        'ه' to 'ح',   // 97 %
        'ح' to 'ه',   // 97 %
        'ء' to 'ع',   // 97 %
        'ذ' to 'ز',   // 97 %
        'س' to 'ص',   // 96 %
        'ع' to 'ء',   // 95 %
        // Famille jim/ha/kha : ABSENTE du corpus d'origine, signalee par
        // l'utilisateur apres son propre test. Rendement inconnu.
        'ج' to 'ح', 'ح' to 'خ', 'ج' to 'خ',
    )

    /** QUATRE harakat, pas sept : le Python n'inclut PAS les tanwins ici. */
    private val HARAKAT_COURTES = charArrayOf('َ', 'ُ', 'ِ', 'ْ')

    /**
     * Toutes les confusions plausibles du mot : une lettre, ou une harakat.
     *
     * ⚠️ SUBSTITUTION DE LA PREMIERE OCCURRENCE SEULEMENT pour les lettres --
     * c'est `mot.find(src)` cote Python. Substituer toutes les occurrences
     * produirait des variantes que la tete n'a jamais vues.
     */
    fun variantes(mot: String): List<String> {
        val out = LinkedHashSet<String>()
        for ((a, b) in CONFUSABLES) {
            for ((src, dst) in listOf(a to b, b to a)) {
                val j = mot.indexOf(src)
                if (j >= 0) out.add(mot.substring(0, j) + dst + mot.substring(j + 1))
            }
        }
        for (k in mot.indices) {
            val c = mot[k]
            if (c in HARAKAT_COURTES) {
                for (h in HARAKAT_COURTES) {
                    if (h != c) out.add(mot.substring(0, k) + h + mot.substring(k + 1))
                }
            }
        }
        return out.toList()
    }
}

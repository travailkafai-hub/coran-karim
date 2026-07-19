package com.corankarim.coran_karim.fastconformer

/**
 * Variantes confusables a 1 edition d'un mot attendu — alimente le rescoring
 * NLL tete-a-tete par mot (cf. ForcedAligner, champ rescoreMargin).
 *
 * Valide OFFLINE avant ce branchement (2026-07-19, epoch14) :
 *  - benchmark/variant_rescoring_eval.py : NLL(prononce) bat NLL(canonique)
 *    dans 80,8% des fautes de lettres (GO), 49,6% harakat (quasi hasard).
 *  - benchmark/constrained_decoding_eval.py : en generant les candidats EN
 *    AVEUGLE (exactement ce que fait cette classe : sans connaitre la faute),
 *    le bon candidat est elu 1er parmi ~35 dans 82,1% des fautes de lettres,
 *    45,0% des fautes de harakat.
 *
 * L'inventaire (harakat substituables + paires de lettres confusables) est le
 * MEME que celui du generateur d'erreurs TTS du corpus mixed et du script
 * d'eval — si l'un evolue, mettre a jour l'autre.
 */
object ConfusableVariants {
    // Harakat substituables : fatha/damma/kasra/sukun + les trois tanwins.
    private const val HARAKAT = "ًٌٍَُِْ"

    // Paires de confusion observees dans le corpus d'erreurs TTS (err_detail
    // des clips kind=letter, rendues symetriques).
    private val CONFUSIONS: Map<Char, CharArray> = mapOf(
        'ء' to charArrayOf('ع'), 'ع' to charArrayOf('ء'),
        'ت' to charArrayOf('ط'), 'ط' to charArrayOf('ت'),
        'ح' to charArrayOf('ه'), 'ه' to charArrayOf('ح'),
        'د' to charArrayOf('ض'), 'ض' to charArrayOf('د'),
        'ذ' to charArrayOf('ز'), 'ز' to charArrayOf('ذ'),
        'س' to charArrayOf('ص'), 'ص' to charArrayOf('س'),
        'ق' to charArrayOf('ك'), 'ك' to charArrayOf('ق'),
    )

    /** Toutes les substitutions a 1 caractere du mot (jamais le mot lui-meme).
     *  Pas d'insertion/suppression : les erreurs du corpus de validation sont
     *  des substitutions, et chaque candidat supplementaire augmente le risque
     *  de faux positif (mesure : 2,77% des candidats battent le canonique a
     *  tort sur audio correct). */
    fun variantsOf(word: String): List<String> {
        val out = LinkedHashSet<String>()
        for (i in word.indices) {
            val ch = word[i]
            if (ch in HARAKAT) {
                for (h in HARAKAT) {
                    if (h != ch) out.add(word.substring(0, i) + h + word.substring(i + 1))
                }
            } else {
                CONFUSIONS[ch]?.forEach { c ->
                    out.add(word.substring(0, i) + c + word.substring(i + 1))
                }
            }
        }
        out.remove(word)
        return out.toList()
    }
}

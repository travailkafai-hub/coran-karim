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
        'ح' to charArrayOf('ه', 'ج', 'خ'), 'ه' to charArrayOf('ح'),
        'د' to charArrayOf('ض'), 'ض' to charArrayOf('د'),
        'ذ' to charArrayOf('ز'), 'ز' to charArrayOf('ذ', 'ر'),
        'س' to charArrayOf('ص'), 'ص' to charArrayOf('س'),
        'ق' to charArrayOf('ك'), 'ك' to charArrayOf('ق'),
        // Ajoutees le 2026-07-31 : ABSENTES du corpus d'erreurs TTS d'origine,
        // donc jamais dans cette table -- alors que ce sont des confusions
        // REELLES, rapportees par l'utilisateur sur ses propres recitations.
        //   ر/ز : « razaqnahoum » prononce « zazaqnahoum » (son cas exact) ;
        //   ج/ح/خ : « mon cas c'etait remplacer jim par ha ».
        // Sans elles, la regle est AVEUGLE a ces fautes par construction -- ce
        // qui ne se voit pas comme une erreur, seulement comme une absence de
        // detection, la pire facon de rater quelque chose.
        // ⚠️ Leur rendement n'est PAS mesure comme celui des sept paires
        // ci-dessus (80,8 % sur 854 clips) : elles n'etaient pas dans le corpus
        // de validation. A mesurer des qu'un corpus les contient.
        'ر' to charArrayOf('ز'), 
        'ج' to charArrayOf('ح', 'خ'),
        'خ' to charArrayOf('ح', 'ج'),
    )

    /**
     * Substitutions de LETTRE seulement. Ajoute le 2026-07-31 pour la chaine v2.
     *
     * POURQUOI SEPARER LETTRES ET HARAKAT. La note de 2026-07-19 ci-dessus le
     * disait deja : le rescoring bat le canonique dans 80,8 % des fautes de
     * LETTRES et 49,6 % des HARAKAT -- le hasard. Mesure du 2026-07-31 sur
     * audio reellement faute en contexte de phrase (189 phrases tenues a
     * l'ecart), detection a 2 % de collateral :
     *
     *     lettres + harakat melangees   21,2 %
     *     lettres seules                30,3 %
     *     harakat seules                 7,9 %
     *
     * Melanger les deux fait donc PERDRE 9 points sur les fautes de lettres :
     * une dizaine de candidats harakat quasi aleatoires polluent le maximum, et
     * chacun ajoute du risque de faux positif (« 2,77 % des candidats battent le
     * canonique a tort sur audio correct »). On calcule donc DEUX marges
     * separees plutot qu'une seule sur l'union.
     */
    fun lettresOf(word: String): List<String> {
        val out = LinkedHashSet<String>()
        for (i in word.indices) {
            CONFUSIONS[word[i]]?.forEach { c ->
                out.add(word.substring(0, i) + c + word.substring(i + 1))
            }
        }
        out.remove(word)
        return out.toList()
    }

    /** Substitutions de HARAKAT seulement (cf. [lettresOf] pour la raison de la
     *  separation). Signal faible -- 7,9 % de detection, a peine au-dessus du
     *  hasard -- a journaliser, pas a faire trancher seul. */
    fun harakatOf(word: String): List<String> {
        val out = LinkedHashSet<String>()
        for (i in word.indices) {
            val ch = word[i]
            if (ch in HARAKAT) {
                for (h in HARAKAT) {
                    if (h != ch) out.add(word.substring(0, i) + h + word.substring(i + 1))
                }
            }
        }
        out.remove(word)
        return out.toList()
    }

    /** Toutes les substitutions a 1 caractere du mot (jamais le mot lui-meme).
     *  Pas d'insertion/suppression : les erreurs du corpus de validation sont
     *  des substitutions, et chaque candidat supplementaire augmente le risque
     *  de faux positif (mesure : 2,77% des candidats battent le canonique a
     *  tort sur audio correct).
     *
     *  NOTE 2026-07-31 : conservee pour le chemin v1 qui l'utilise (rescoring
     *  diagnostique). La v2 utilise [lettresOf] et [harakatOf] separement --
     *  l'union fait perdre 9 points de detection, cf. [lettresOf]. */
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

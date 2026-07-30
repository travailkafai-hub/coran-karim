package com.corankarim.coran_karim.recitation2

/**
 * Les ecritures d'un MEME son.
 *
 * ── LE PROBLEME, MESURE LE 2026-07-30 ───────────────────────────────────────
 *
 * Sur une recitation professionnelle sans aucune faute, ces mots ressortaient
 * ORANGE :
 *     attendu فِرَٰشًا      entendu فِرَاشًا      gop -0,39 a -0,48
 *     attendu ٱلصَّوَٰعِقِ  entendu ٱلصوَٰعِقِ    gop -0,26 a -1,03
 *
 * Le alif suscrit (U+0670) et le alif ordinaire notent LA MEME VOYELLE LONGUE.
 * Le recitateur n'a pas fait de faute : il ne PEUT pas en faire une ici, les
 * deux ecritures se prononcent identiquement. Ce que la chaine mesurait, c'est
 * un desaccord d'ORTHOGRAPHE entre le texte de reference et ce que le modele a
 * appris a ecrire.
 *
 * ── POURQUOI CE N'EST PAS UNE TOLERANCE ─────────────────────────────────────
 *
 * Une tolerance elargit ce qu'on accepte comme prononciation : elle laisse
 * passer de vraies fautes. C'est ce qui a fait rejeter le relachement de la
 * regle de proportion ([MORT] mort_relachement_proportion : « un recitateur ne
 * disant que la moitie d'un mot etait valide »).
 *
 * Ici on ne touche pas au critere : on corrige la CIBLE. Deux graphies du meme
 * son sont la meme cible acoustique ; demander au modele de departager deux
 * ecritures indistinguables a l'oreille, c'est lui demander l'impossible et
 * appeler « faute » sa reponse. Aucune faute de prononciation ne peut etre
 * blanchie par cette liste, puisque toutes les variantes qu'elle produit se
 * prononcent EXACTEMENT comme l'original.
 *
 * ── CE QU'ELLE NE CONTIENT PAS, DELIBEREMENT ────────────────────────────────
 *
 * Aucune substitution de LETTRE (ص/س, ط/ت, ق/ك...) : celles-la changent le son,
 * ce sont de vraies fautes, et c'est le rescoring de variantes confusables qui
 * les traite (80,8 % sur 854 clips) -- un autre chantier, un autre but.
 * Aucune substitution de HARAKAT non plus : elles changent le son, et le signal
 * y est de toute facon au niveau du hasard ([MORT] mort_harakat_rescoring,
 * 49,6 % sur 954 clips).
 */
object Orthographe {

    /** Alif suscrit : meme voyelle longue que le alif ordinaire. */
    private const val ALIF_SUSCRIT = 'ٰ'

    /** Alif wasla : meme attaque que le alif ordinaire. */
    private const val ALIF_WASLA = 'ٱ'

    /** Madda suscrite, presente ou non selon l'edition. */
    private const val MADDA = 'ٓ'

    /** Ya suscrit / waw suscrit (petites lettres de recitation). */
    private const val YA_SUSCRIT = 'ۦ'
    private const val WAW_SUSCRIT = 'ۥ'

    /**
     * @return le mot canonique EN PREMIER, puis ses ecritures equivalentes.
     *   Liste bornee : au plus [MAX] entrees, pour que le cout reste negligeable
     *   devant une inference.
     */
    fun variantes(mot: String): List<String> {
        val out = LinkedHashSet<String>()
        out.add(mot)

        // 1) alif suscrit ecrit en alif plein  (فِرَٰشًا -> فِرَاشًا)
        if (mot.indexOf(ALIF_SUSCRIT) >= 0) {
            out.add(mot.replace(ALIF_SUSCRIT.toString(), "ا"))
            // 2) ... ou simplement absent (certaines editions ne le notent pas)
            out.add(mot.replace(ALIF_SUSCRIT.toString(), ""))
        }
        // 3) alif wasla ecrit en alif simple  (ٱلصَّوَٰعِقِ -> الصَّوَٰعِقِ)
        if (mot.indexOf(ALIF_WASLA) >= 0) {
            out.add(mot.replace(ALIF_WASLA.toString(), "ا"))
        }
        // 4) madda suscrite omise
        if (mot.indexOf(MADDA) >= 0) {
            out.add(mot.replace(MADDA.toString(), ""))
        }
        // 5) petites lettres de recitation, ecrites en lettre pleine
        if (mot.indexOf(WAW_SUSCRIT) >= 0) {
            out.add(mot.replace(WAW_SUSCRIT.toString(), "و"))
        }
        if (mot.indexOf(YA_SUSCRIT) >= 0) {
            out.add(mot.replace(YA_SUSCRIT.toString(), "ي"))
        }
        // 6) combinaison des deux plus frequentes
        if (mot.indexOf(ALIF_SUSCRIT) >= 0 && mot.indexOf(ALIF_WASLA) >= 0) {
            out.add(
                mot.replace(ALIF_SUSCRIT.toString(), "ا")
                    .replace(ALIF_WASLA.toString(), "ا")
            )
        }
        return out.take(MAX)
    }

    private const val MAX = 6
}

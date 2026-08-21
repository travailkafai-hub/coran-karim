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

    /** Soukoun : absence de voyelle. Note ou non selon le contexte (cf. (8)). */
    private const val SOUKOUN = 'ْ'

    /**
     * Signes de TAJWID contextuels : ils annoncent une regle (iqlab, ikhfa'),
     * ils n'ajoutent aucun phoneme au mot lui-meme. Le Mushaf les porte selon
     * le mot SUIVANT ; le modele, lui, ne les emet pratiquement jamais.
     *
     * U+06ED petit meem  : iqlab (tanwin ou noun sakina devant ba).
     * U+06E2 petit meem isole haut, U+06E0 petit rond : variantes d'edition.
     * U+0653 madda, U+0654/0655 hamza suscrite/souscrite ne sont PAS ici :
     * elles portent du son.
     */
    private val SIGNES_TAJWID = charArrayOf('ۭ', 'ۢ', 'ۡ', '۟', '۠')

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
        }
        // ── VARIANTE RETIREE LE 2026-07-30, ET POURQUOI ────────────────────
        // La version precedente generait aussi le mot avec l'alif suscrit
        // SUPPRIME, au motif que « certaines editions ne le notent pas ». C'est
        // faux du point de vue du SON : sans lui, la voyelle est BREVE. Cette
        // variante ne decrivait donc pas la meme prononciation -- elle
        // blanchissait un madd raccourci, c'est-a-dire une vraie faute de
        // tajwid, et exactement le genre de mot que l'application existe pour
        // signaler.
        // Trouve en repondant a la question « est-ce qu'on ne casse pas la
        // detection ? », pas par une mesure : aucune session de test ne
        // contenait de madd raccourci. Une variante ne rentre ici que si elle
        // se prononce STRICTEMENT pareil.
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
        // 7) MADD TENU PLUS LONGTEMPS : lettre d'allongement DOUBLEE
        //    (2026-08-06, idee utilisateur).
        //
        //    Le CTC emet un token par pic ; quand le recitateur tient un madd
        //    plus longtemps que la duree canonique, le decodage libre ecrit la
        //    lettre d'allongement DEUX FOIS. L'alignement force, lui, doit
        //    alors etaler les tokens de la forme canonique sur plus de frames,
        //    et son score MOYEN PAR FRAME baisse -- le mot sort orange alors
        //    qu'il est bien prononce.
        //
        //    MESURE (session v61, 2026-08-06, preset ADULTE donc sans tajwid) :
        //      mot 30 `عَآئِلًا` -> orange, gop=-1,18 forced=-1,52 free=-0,34,
        //      entendu `عَاآئِلًا` -- un alif de plus, seul ecart.
        //
        //    C'est bien la MEME PRONONCIATION, seulement plus tenue : la regle
        //    d'entree de ce fichier est donc respectee (« une variante ne
        //    rentre ici que si elle se prononce STRICTEMENT pareil »). Ce
        //    n'est pas symetrique du cas RETIRE en (2) : la, on blanchissait un
        //    madd RACCOURCI -- une voyelle breve la ou il faut une longue,
        //    c'est-a-dire une vraie faute. Ici la voyelle est longue et le
        //    reste ; seule sa duree depasse le canon, ce qui n'est une faute
        //    dans AUCUN preset (et surtout pas en mode adulte).
        //
        //    L'aligneur retient le MEILLEUR score parmi les variantes : si le
        //    recitateur n'allonge pas, la forme canonique gagne et rien ne
        //    change. Cette variante ne peut donc que rattraper un allongement,
        //    jamais degrader un mot normal.
        for (lettre in ALLONGEMENT) {
            val i = mot.indexOf(lettre)
            if (i >= 0) {
                out.add(mot.substring(0, i) + lettre + mot.substring(i))
                break // une seule variante de ce type, cf. MAX
            }
        }
        // 8) SOUKOUN FINAL, NOTE OU NON (2026-08-14, session Al-Fil).
        //
        //    MESURE : `تَرْمِيهِم` -> ORANGE, gop=-0,46 pour un seuil de vert a
        //    -0,45 -- il echoue a 0,01 pres. Le modele decode `تَرْمِيهِمْ`
        //    AVEC le soukoun dans TOUTES les fenetres du balayage (4 s et 6 s),
        //    avec free=-0,07 : il est certain de ce qu'il entend. Tout le cout
        //    est dans l'alignement force sur une graphie qu'il n'emet jamais.
        //    Le vocabulaire l'explique : U+0652 est present dans 242 des 1024
        //    tokens (`هُمْ`, `ُمْ`, `مْ`...), la finale nue y est marginale.
        //
        //    POURQUOI CE N'EST PAS UNE TOLERANCE (utilisateur, 2026-08-14) :
        //    « on doit avoir les deux options, avec soukoun present et absent,
        //    car les deux c'est la meme chose ». Le م est prononce dans les
        //    deux graphies ; le soukoun note seulement l'absence de voyelle
        //    apres lui. Le Mushaf le laisse nu a cause du mot SUIVANT (ikhfa'
        //    shafawi devant ba) -- une marque contextuelle, pas un son.
        //
        //    STRICTEMENT LIMITE A LA FINALE. A l'interieur d'un mot, ajouter ou
        //    retirer un soukoun CHANGE le son (consonne vocalisee ou non), donc
        //    ce serait blanchir une vraie faute -- exactement le piege qui a
        //    fait retirer la variante « alif suscrit supprime » en (2).
        val dernier = mot.lastOrNull()
        if (dernier == SOUKOUN) {
            if (mot.length >= 2) out.add(mot.dropLast(1))
        } else if (dernier != null && estLettre(dernier)) {
            out.add(mot + SOUKOUN)
        }
        // 9) SIGNES DE TAJWID CONTEXTUELS, ABSENTS DE LA CIBLE.
        //
        //    MESURE (meme session) : `مَّأْكُولٍۭ` -> ORANGE, gop=-0,69, le pire
        //    des quatre non-verts, avec margeH negative. Le petit meem U+06ED
        //    n'existe que dans UN token du vocabulaire : la cible reclamait un
        //    signe que le modele n'a pratiquement jamais vu.
        //
        //    Ces signes annoncent une REGLE (iqlab, ikhfa') qui depend du mot
        //    suivant ; ils n'ajoutent aucun phoneme au mot lui-meme. Leur
        //    realisation est l'affaire de la TETE 3, pas de la tete texte :
        //    les faire peser sur le `forced` melange deux questions et rend
        //    orange un mot correctement prononce.
        if (mot.any { SIGNES_TAJWID.contains(it) }) {
            out.add(mot.filterNot { SIGNES_TAJWID.contains(it) })
        }
        return out.take(MAX)
    }

    /** Lettres porteuses d'allongement (madd) : alif, waw, ya. */
    private val ALLONGEMENT = charArrayOf('ا', 'و', 'ي')

    /**
     * Vrai pour une LETTRE de base (pas un diacritique) : c'est ce qui permet
     * de savoir qu'un mot finit sur une consonne nue, donc qu'il peut aussi
     * s'ecrire avec un soukoun final.
     */
    private fun estLettre(c: Char): Boolean =
        c in 'ء'..'ي' || c in 'ٱ'..'ۓ' || c == ALIF_WASLA

    // 6 -> 7 : la variante « madd tenu » s'ajoutait aux six formes deja
    // generees.
    //
    // 7 -> 10 (2026-08-14) : les familles (8) et (9) ci-dessus en ajoutent
    // deux. Le plafond N'A PAS ete releve « pour faire de la place » mais
    // parce qu'il EVINCAIT DEJA en silence : un mot portant alif suscrit +
    // wasla + madda + waw + ya produisait 6 variantes plus la combinaison plus
    // le madd tenu, soit 8 entrees avec le canonique -- le madd tenu, genere en
    // dernier, tombait sans que rien ne le signale. `out.take(MAX)` coupe la
    // fin de la liste, donc toute famille ajoutee apres est la premiere perdue.
    //
    // Cout d'une variante : un treillis minuscule sur les SEULES frames du mot
    // (cf. `AligneurForce.forwardMoyenGraphe`), aucune passe d'encodeur
    // supplementaire. Passer de 7 a 10 est donc negligeable a l'echelle d'une
    // inference -- ce qui ne dispense pas de le verifier si le temps reel se
    // degrade.
    private const val MAX = 10
}

package com.corankarim.coran_karim.recitation2

/**
 * Decodage CTC glouton — "ce que le modele entend", sans aucune contrainte de
 * cible. Fonction pure, utilisee par la localisation (couche D) et pour le
 * champ `entendu` de chaque mot (couche E).
 *
 * Volontairement separe de l'alignement force : ce sont deux questions
 * differentes, et les confondre est a l'origine du [PIEGE] gop_vs_free — un
 * `gop` effondre avec un `free` proche de 0 signifie MAUVAISE POSITION, pas
 * mauvaise prononciation. La v2 rend cette distinction structurelle : le
 * decodage libre sert a savoir OU on est (couche D), l'alignement force a
 * savoir SI c'est juste (couche E).
 */
object Decodage {

    /** Ids emis (repetitions effondrees, blancs retires) sur [de, a] inclus. */
    fun ids(logprobs: Array<FloatArray>, blank: Int, de: Int = 0, a: Int = -1): IntArray {
        if (logprobs.isEmpty()) return IntArray(0)
        val fin = if (a in logprobs.indices) a else logprobs.size - 1
        val debut = de.coerceIn(0, maxOf(0, fin))
        val out = ArrayList<Int>(fin - debut + 1)
        var prec = -1
        for (t in debut..fin) {
            val m = argmax(logprobs[t])
            if (m != prec && m != blank) out.add(m)
            prec = m
        }
        return out.toIntArray()
    }

    /**
     * Plus longue suite de frames CONSECUTIVES portant le meme token non-blanc,
     * sur `[de, a]`. C'est la duree du son le plus longuement TENU du mot.
     *
     * ── POURQUOI CETTE MESURE EXISTE (2026-09-07) ─────────────────────────
     *
     * Demande utilisateur : « il faut rajouter le controle des durees pour ne
     * pas valider un madd de 2 harakat quand on en attend 4 ou 6 ».
     *
     * La grandeur dont on disposait, `DetectedRule.frames`, ne peut PAS servir
     * a cela. MESURE SUR 377 SESSIONS REELLES, maximum par (session, mot) --
     * donc deja le meilleur de toutes les coupes du mot, comme le fait
     * `dureesParMot` :
     *
     *     regle                     n    p25   med   p75    reste a 80 ms
     *     madda_necessary  (6 h.)  104    80   160   240        47,1 %
     *     madda_obligatory (4-5 h) 637    80   240   320        29,5 %
     *     madda_permissible(4-6 h) 600    80   240   320        29,8 %
     *
     * Deux constats la disqualifient. D'abord L'ORDRE EST INVERSE : le madd
     * NECESSAIRE, six harakat obligatoires, est mesure PLUS COURT que le madd
     * obligatoire qui en fait quatre. Ensuite, un tiers a la moitie des mots
     * plafonnent a UNE SEULE FRAME apres maximum sur toutes leurs coupes --
     * ce n'est donc pas un artefact de fenetrage qu'on pourrait ecarter.
     *
     * La cause est structurelle : `DetectedRule.frames` compte les frames ou
     * la TETE emet sa classe au-dessus du seuil. C'est la largeur du PIC DE
     * DETECTION, pas la duree du son. Un pic peut etre bref sur une voyelle
     * longue, et large sur une breve. Le projet l'avait deja paye en v329 :
     * ce critere « rejetait des detections a p=1,000 ».
     *
     * Chiffre du cout d'un seuil pose sur cette grandeur (madd CORRECTS
     * rejetes, hors observations a une frame) : 240 ms en rejette 23 a 44 %,
     * 320 ms en rejette 48 a 61 %. Il n'existe aucune fenetre utile.
     *
     * ── CE QUE CETTE FONCTION MESURE A LA PLACE ──────────────────────────
     *
     * Un madd est une voyelle TENUE. Sur le treillis CTC, une voyelle tenue
     * occupe des frames consecutives portant le meme token. On mesure donc la
     * plus longue de ces suites -- une grandeur acoustique, independante de la
     * tete tajwid et de ses seuils.
     *
     * ⚠️ OBSERVATION SEULE POUR L'INSTANT. Aucun verdict ne s'en sert : il
     * manque le seul element qui permettrait de poser un seuil, un corpus de
     * madd VOLONTAIREMENT raccourcis. Le rapport de validation de la tete
     * tajwid bute sur exactement la meme absence et l'ecrit :
     * `not_measured: "faute de tajwid reellement prononcee (aucun corpus
     * d'erreurs acoustiques valide)"`. Poser un seuil avant cet enregistrement
     * reviendrait a choisir un chiffre pour qu'il ait l'air raisonnable.
     *
     * ⚠️ CTC EST *PEAKY* : le modele marque la frame ou le token culmine, il
     * n'etale pas le son. Cette mesure sous-estime donc la tenue reelle, et
     * elle vaut surtout en COMPARAISON (meme mot, deux recitations) et non en
     * valeur absolue. C'est le meme piege que celui deja documente sur le
     * decoupage audio (cf. `AligneurForce.finDernierMotSur`).
     *
     * @return duree en frames (80 ms chacune), 0 si rien n'est emis.
     */
    fun tenueMax(logprobs: Array<FloatArray>, blank: Int,
                 de: Int = 0, a: Int = -1): Int {
        if (logprobs.isEmpty()) return 0
        val fin = if (a in logprobs.indices) a else logprobs.size - 1
        val debut = de.coerceIn(0, maxOf(0, fin))
        if (debut > fin) return 0
        var meilleur = 0
        var courant = 0
        var prec = -1
        for (i in debut..fin) {
            val m = argmax(logprobs[i])
            if (m == blank) { courant = 0; prec = -1; continue }
            courant = if (m == prec) courant + 1 else 1
            if (courant > meilleur) meilleur = courant
            prec = m
        }
        return meilleur
    }

    /** Texte detokenise ('▁' = debut de mot SentencePiece). */
    fun texte(pieces: List<String>, ids: IntArray): String {
        val sb = StringBuilder()
        for (id in ids) if (id < pieces.size) sb.append(pieces[id])
        return sb.toString().replace('▁', ' ').trim()
    }

    fun texte(logprobs: Array<FloatArray>, pieces: List<String>, blank: Int,
              de: Int = 0, a: Int = -1): String = texte(pieces, ids(logprobs, blank, de, a))

    /** Mots entendus, dans l'ordre (decoupage sur '▁'). */
    fun mots(logprobs: Array<FloatArray>, pieces: List<String>, blank: Int): List<String> =
        texte(logprobs, pieces, blank).split(' ').filter { it.isNotBlank() }

    /** Un mot entendu, AVEC les frames ou il a ete emis. */
    data class MotEntendu(val texte: String, val premiereFrame: Int, val derniereFrame: Int)

    /**
     * Mots entendus et leur position en frames.
     *
     * Les frames sont indispensables : c'est avec elles qu'on sait quel audio
     * est deja REVENDIQUE par un mot attendu, donc quel audio reste libre. Sans
     * cette information, l'alignement force place un mot ABSENT sur les frames
     * de son voisin et produit un verdict rouge sur un audio qui ne le contient
     * pas — defaut trouve par le banc le 2026-07-30.
     */
    fun motsAvecFrames(
        logprobs: Array<FloatArray>,
        pieces: List<String>,
        blank: Int,
    ): List<MotEntendu> {
        val out = ArrayList<MotEntendu>()
        val courant = StringBuilder()
        var debut = -1
        var fin = -1
        var prec = -1
        for (t in logprobs.indices) {
            val m = argmax(logprobs[t])
            if (m != prec && m != blank && m < pieces.size) {
                val piece = pieces[m]
                if (piece.startsWith("▁")) {
                    if (courant.isNotEmpty()) out.add(MotEntendu(courant.toString(), debut, fin))
                    courant.setLength(0)
                    courant.append(piece.removePrefix("▁"))
                    debut = t
                } else {
                    if (courant.isEmpty()) debut = t
                    courant.append(piece)
                }
            }
            // La plage doit couvrir la REPETITION du token, pas seulement la
            // frame de son emission. Sans ca, la fin d'un mot est sous-estimee
            // de toute la duree de son dernier token — et l'audio qu'il occupe
            // reellement apparait comme "libre", ce qui redonne un creneau
            // fictif au mot suivant (defaut trouve en instrumentant le banc le
            // 2026-07-30 : un mot saute restait juge rouge).
            if (m != blank && m < pieces.size && courant.isNotEmpty()) fin = t
            prec = m
        }
        if (courant.isNotEmpty()) out.add(MotEntendu(courant.toString(), debut, fin))
        return out.filter { it.texte.isNotBlank() }
    }

    fun argmax(frame: FloatArray): Int {
        var best = 0
        var v = frame[0]
        for (c in 1 until frame.size) if (frame[c] > v) { v = frame[c]; best = c }
        return best
    }

    /** log-probabilite du meilleur chemin libre sur la frame (le `free` du GOP). */
    fun maxLogprob(frame: FloatArray): Float {
        var v = frame[0]
        for (c in 1 until frame.size) if (frame[c] > v) v = frame[c]
        return v
    }
}

/**
 * Normalisation de COMPARAISON — uniquement pour apparier du texte entendu a du
 * texte attendu (couche D). Elle retire les harakat et les signes de waqf.
 *
 * Deux raisons mesurees :
 *  - le rescoring de variantes sur les HARAKAT sort a 49,6 % sur 954 clips,
 *    soit le hasard ([MORT] mort_harakat_rescoring) : une harakat ne porte pas
 *    assez de signal pour qu'on FONDE une decision de position dessus ;
 *  - [PIEGE] waqf : le modele emet `ۖ ۗ ۚ` comme des mots (26 occurrences sur
 *    une seule session) alors que le texte attendu les filtre. Le decalage est
 *    non deterministe. En v1 il etait absorbe par les rustines d'ancre ; ici il
 *    est traite au contrat de la couche D, jamais par reentrainement (le
 *    vocabulaire les contient deja).
 *
 * ATTENTION : cette normalisation ne doit JAMAIS servir au jugement. C'est
 * l'alignement force qui juge, sur les tokens exacts, harakat comprises.
 */
object NormalisationComparaison {
    private val aRetirer = setOf(
        'ً', 'ٌ', 'ٍ', 'َ', 'ُ', 'ِ', 'ّ', 'ْ',
        'ٓ', 'ٔ', 'ٕ', 'ٰ', 'ۡ', 'ـ',
        'ۖ', 'ۗ', 'ۘ', 'ۙ', 'ۚ', 'ۛ', 'ۜ',
        '۝', '۞', '۟', '۠', 'ۢ', 'ۣ', 'ۥ',
        'ۦ', 'ۧ', 'ۨ', '۩', '۪', '۫', '۬', 'ۭ',
    )

    fun normaliser(mot: String): String {
        val sb = StringBuilder(mot.length)
        for (c in mot) {
            if (c in aRetirer) continue
            sb.append(
                when (c) {
                    'آ', 'أ', 'إ', 'ٱ' -> 'ا' // alif + hamza -> alif
                    'ى' -> 'ي' // alif maqsura -> ya
                    'ة' -> 'ه' // ta marbuta -> ha
                    else -> c
                }
            )
        }
        return sb.toString()
    }
}

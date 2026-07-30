package com.corankarim.coran_karim.recitation2

/**
 * COUCHE E — ALIGNEMENT FORCE.
 *
 * CONTRAT : fonction PURE. Ne juge pas, ne verrouille pas, ne connait AUCUN
 * seuil de couleur. Elle mesure, elle ne decide pas.
 *
 * Methode : Viterbi CTC frame par frame sur le treillis etendu (blanc entre
 * chaque token). C'est la methode standard — `torchaudio.functional.forced_align`
 * fait la meme chose ; l'etat de l'art consulte le 2026-07-30 le confirme.
 *
 * ── LE CHAMP QUI PORTE TOUTE LA v2 : `interieur` ───────────────────────────
 *
 * `interieur` = les frames du mot ne touchent NI le bord gauche NI le bord
 * droit de la fenetre, marges comprises. La marge droite vaut le lookahead du
 * modele causal (13 frames = 1,04 s) : en deca, le modele n'a pas vu l'audio
 * posterieur dont il a besoin, et ses logprobs ne sont pas dans les conditions
 * d'entrainement.
 *
 * Seule une observation `interieur` a le droit de VOTER (couche G). C'est ce
 * seul champ qui remplace toute la famille de rustines de la v1 :
 * `MIN_FRAMES_FOR_JUDGMENT`, `deferredOnceIndex` ("2 chances max"), tolerance
 * aux fragments, tolerance au bleed prefixe, filet decodage-libre. Elles
 * existaient parce qu'un mot pouvait etre DEFINITIVEMENT coupe par une
 * frontiere de segment ; ici la fenetre continue de glisser et tout mot finit
 * interieur a au moins une fenetre. Le probleme qu'elles compensaient n'existe
 * plus, donc elles n'ont pas ete reecrites.
 *
 * Corollaire mesure ([MORT] mort_relachement_proportion) : un recitateur ne
 * disant que la MOITIE d'un mot ne peut plus etre valide, car un fragment
 * touche forcement un bord — il n'est donc jamais interieur, donc jamais
 * verrouille vert. La tolerance qui avait produit ce defaut n'a pas besoin
 * d'exister.
 *
 * ── LES TROIS SCORES ───────────────────────────────────────────────────────
 * `free`   : le modele est-il sur de ce qu'il entend ? (proche de 0 = certain)
 * `forced` : ce qu'il entend colle-t-il a la cible ?
 * `gop = forced - free` : l'ecart.
 *
 * [PIEGE] gop_vs_free : un `gop` effondre avec un `free` proche de 0 signifie
 * MAUVAISE POSITION, pas mauvaise prononciation (mesure du 2026-07-30 : mot 84
 * a gop=-5,48 avec free=-0,01, l'ancre avait un verset de retard). Les trois
 * scores sont donc TOUS remontes, jamais le seul gop.
 *
 * [PIEGE] gop_relatif : le gop reste RELATIF (attendu `صِرَٰطَ`, entendu
 * `سَرَٰطَ`, gop=-0,35 => vert, parce que le modele hesitait sur tout). La v2 ne
 * corrige PAS ce defaut : elle supprime les faux positifs nes du DECOUPAGE. Le
 * signal absolu est le rescoring de variantes sur les LETTRES (80,8 % sur 854
 * clips, marge mediane +3,80) — changement SEPARE, jamais melange a la base,
 * et JAMAIS etendu aux harakat (49,6 % = pile ou face).
 */
class AligneurForce(
    private val pieces: List<String>,
    private val blank: Int,
    private val margeGaucheFrames: Int = 2,
    private val margeDroiteFrames: Int = Horloge.LOOKAHEAD_FRAMES,
) {
    data class MotAligne(
        val index: Int,
        val premiereFrame: Int,
        val derniereFrame: Int,
        val frames: Int,
        val forced: Float,
        val free: Float,
        val gop: Float,
        val entendu: String,
        val interieur: Boolean,
        val couvert: Boolean,
        /**
         * Le mot n'a PAS DE CRENEAU : l'alignement force a du le poser sur de
         * l'audio deja revendique par un mot voisin reellement entendu.
         *
         * Ce champ existe a cause d'un defaut trouve par le banc le 2026-07-30 :
         * un mot que le recitateur SAUTE ressortait `Definitif(ROUGE)` avec
         * `gop = -11,99` et `free = -0,01`. Le modele etait CERTAIN de ce qu'il
         * entendait ; c'est juste que le mot n'y etait pas. La DP est obligee de
         * placer tous les mots qu'on lui donne : elle avait vole 3 frames au
         * voisin. Un rouge sur un audio qui ne contient pas le mot viole la
         * regle projet "aucun verdict sans preuve acoustique", et c'est le plus
         * grave des defauts possibles (l'app dit FAUX).
         *
         * Le discriminant n'est pas un seuil : c'est une GEOMETRIE. Un mot
         * reellement saute n'a pas de place entre ses voisins entendus ; un mot
         * SUBSTITUE, lui, occupe un vrai creneau — le recitateur y a dit quelque
         * chose. On compare donc la plage alignee du mot a l'audio laisse libre
         * par ses voisins attestes au decodage LIBRE. Aucune duree de reference,
         * aucune tolerance.
         */
        val sansCreneau: Boolean,
    )

    data class Resultat(
        val mots: List<MotAligne>,
        val bandeTronquee: Boolean,
    )

    private val neginf = -1e30f

    /**
     * @param tokensParMot tokens attendus, un tableau par mot de la bande
     * @param indexPremierMot index absolu (dans le texte attendu) du 1er mot
     * @param bordGaucheEstDebutDeSession le bord gauche de la fenetre est-il le
     *   VRAI debut de l'audio ? Si oui la marge gauche ne s'applique pas : il
     *   n'y a rien a tronquer avant le premier echantillon de la session.
     *
     *   Defaut trouve par le banc 2 le 2026-07-30 : sans cette distinction, le
     *   TOUT PREMIER mot d'une recitation n'etait jamais interieur, donc jamais
     *   verrouille, donc declare `Omis` alors qu'il avait ete parfaitement
     *   prononce et parfaitement aligne (gop 0,00 sur trois fenetres). La marge
     *   gauche existe pour ecarter une TRONCATURE, pas un bord ; les confondre
     *   fabriquait un faux "mot saute" a chaque session.
     */
    fun aligner(
        logprobs: Array<FloatArray>,
        tokensParMot: List<IntArray>,
        indexPremierMot: Int,
        bordGaucheEstDebutDeSession: Boolean = false,
        attestes: Map<Int, IntRange> = emptyMap(),
        /** Ecritures EQUIVALENTES de chaque mot (cf. [Orthographe]), parallele
         *  a [tokensParMot]. Le score retenu est le meilleur des ecritures :
         *  deux graphies du meme son sont la meme cible acoustique. */
        variantesParMot: List<List<IntArray>> = emptyList(),
    ): Resultat? {
        val t = logprobs.size
        if (t == 0 || tokensParMot.isEmpty()) return null

        // Bande trop longue pour la fenetre : on la RACCOURCIT au lieu d'echouer.
        // Les mots retires sont ceux de la fin — ils seront de toute facon au
        // bord droit, donc non interieurs, donc non juges.
        var mots = tokensParMot
        var tronquee = false
        while (mots.isNotEmpty() && framesMinimales(mots) > t) {
            mots = mots.subList(0, mots.size - 1)
            tronquee = true
        }
        if (mots.isEmpty()) return null

        val proprio = ArrayList<Int>()   // token -> index de mot (relatif a la bande)
        val tokens = ArrayList<Int>()
        mots.forEachIndexed { w, toks ->
            for (tk in toks) { tokens.add(tk); proprio.add(w) }
        }
        if (tokens.isEmpty()) return null

        val l = 2 * tokens.size + 1
        val s = IntArray(l) { if (it % 2 == 0) blank else tokens[it / 2] }

        val dp = Array(t) { FloatArray(l) { neginf } }
        val back = Array(t) { IntArray(l) { -1 } }

        dp[0][0] = logprobs[0][blank]
        if (l > 1) dp[0][1] = logprobs[0][s[1]]

        for (ti in 1 until t) {
            val lp = logprobs[ti]
            for (li in 0 until l) {
                var best = dp[ti - 1][li]
                var arg = li
                if (li >= 1 && dp[ti - 1][li - 1] > best) { best = dp[ti - 1][li - 1]; arg = li - 1 }
                if (li >= 2 && s[li] != blank && s[li] != s[li - 2] && dp[ti - 1][li - 2] > best) {
                    best = dp[ti - 1][li - 2]; arg = li - 2
                }
                if (best <= neginf) continue
                dp[ti][li] = best + lp[s[li]]
                back[ti][li] = arg
            }
        }

        var fin = l - 1
        if (l >= 2 && dp[t - 1][l - 2] > dp[t - 1][l - 1]) fin = l - 2
        if (dp[t - 1][fin] <= neginf) return null

        // Retro-propagation : quelle position du treillis occupe chaque frame.
        val chemin = IntArray(t)
        var cur = fin
        for (ti in t - 1 downTo 0) {
            chemin[ti] = cur
            if (ti > 0) cur = back[ti][cur]
        }

        val premiere = IntArray(mots.size) { -1 }
        val derniere = IntArray(mots.size) { -1 }
        val nb = IntArray(mots.size)
        val sommeForced = DoubleArray(mots.size)
        val sommeFree = DoubleArray(mots.size)

        for (ti in 0 until t) {
            val li = chemin[ti]
            if (li % 2 == 0) continue // blanc : n'appartient a aucun mot
            val w = proprio[li / 2]
            if (premiere[w] < 0) premiere[w] = ti
            derniere[w] = ti
            nb[w]++
            sommeForced[w] += logprobs[ti][s[li]].toDouble()
            sommeFree[w] += Decodage.maxLogprob(logprobs[ti]).toDouble()
        }

        val out = ArrayList<MotAligne>(mots.size)
        for (w in mots.indices) {
            val n = nb[w]
            var f = if (n > 0) (sommeForced[w] / n).toFloat() else 0f
            val fr = if (n > 0) (sommeFree[w] / n).toFloat() else 0f

            // ECRITURES EQUIVALENTES : sur les MEMES frames, on rescore les
            // graphies qui se prononcent identiquement et on garde la
            // meilleure. Ce n'est pas une tolerance -- le critere ne bouge pas,
            // c'est la cible qui cesse d'exiger une distinction inaudible.
            if (n > 0 && w < variantesParMot.size) {
                for (v in variantesParMot[w]) {
                    if (v.isEmpty()) continue
                    val alt = forwardMoyen(logprobs, premiere[w], derniere[w], v)
                    if (alt > f) f = alt
                }
            }
            val margeG = if (bordGaucheEstDebutDeSession) 0 else margeGaucheFrames
            val interieur = n > 0 &&
                premiere[w] >= margeG &&
                derniere[w] <= t - 1 - margeDroiteFrames
            val sansCreneau = n > 0 && sansCreneau(
                indexAbsolu = indexPremierMot + w,
                premiere = premiere[w],
                derniere = derniere[w],
                attestes = attestes,
                nbFrames = t,
            )
            out.add(
                MotAligne(
                    index = indexPremierMot + w,
                    premiereFrame = premiere[w],
                    derniereFrame = derniere[w],
                    frames = n,
                    forced = f,
                    free = fr,
                    gop = if (n > 0) f - fr else 0f,
                    entendu = if (n > 0) {
                        Decodage.texte(logprobs, pieces, blank, premiere[w], derniere[w])
                    } else "",
                    interieur = interieur,
                    couvert = n >= framesMinimales(listOf(mots[w])),
                    sansCreneau = sansCreneau,
                )
            )
        }
        return Resultat(out, tronquee)
    }

    /**
     * Forward CTC (log-somme) d'une sequence de tokens sur [de..a], ramene a
     * une moyenne PAR FRAME pour etre comparable au `forced` du chemin Viterbi.
     *
     * Second treillis, minuscule et local : a ne pas confondre avec celui
     * d'[aligner] -- meme piege qu'en v1, ou `ctcForwardNll` cohabitait avec la
     * DP principale.
     */
    private fun forwardMoyen(
        logprobs: Array<FloatArray>, de: Int, a: Int, tokens: IntArray,
    ): Float {
        if (de < 0 || a < de || tokens.isEmpty()) return neginf
        val l = 2 * tokens.size + 1
        val s = IntArray(l) { if (it % 2 == 0) blank else tokens[it / 2] }
        var prev = FloatArray(l) { neginf }
        prev[0] = logprobs[de][blank]
        if (l > 1) prev[1] = logprobs[de][s[1]]
        for (t in de + 1..a) {
            val cur = FloatArray(l) { neginf }
            val lp = logprobs[t]
            for (i in 0 until l) {
                var acc = prev[i]
                if (i >= 1) acc = logSomme(acc, prev[i - 1])
                if (i >= 2 && s[i] != blank && s[i] != s[i - 2]) {
                    acc = logSomme(acc, prev[i - 2])
                }
                if (acc > neginf) cur[i] = acc + lp[s[i]]
            }
            prev = cur
        }
        val fin = logSomme(prev[l - 1], if (l >= 2) prev[l - 2] else neginf)
        val n = (a - de + 1).coerceAtLeast(1)
        return fin / n
    }

    private fun logSomme(a: Float, b: Float): Float {
        if (a <= neginf) return b
        if (b <= neginf) return a
        val m = maxOf(a, b)
        return m + kotlin.math.ln(1.0 + kotlin.math.exp((-kotlin.math.abs(a - b)).toDouble())).toFloat()
    }

    /**
     * Le mot a-t-il eu un creneau a lui ?
     *
     * Un mot ATTESTE par le decodage libre en a un par definition. Sinon, on
     * regarde l'audio laisse libre entre son voisin atteste de gauche et celui
     * de droite : si la plage que la DP lui a attribuee deborde de cet
     * intervalle, c'est qu'elle a pris des frames appartenant a un mot
     * reellement entendu — le mot n'a pas ete prononce ici, il a ete POSE ici.
     *
     * Sans voisin atteste d'un cote, on ne conclut pas (retourne false) :
     * l'absence d'information n'est pas une preuve, dans un sens comme dans
     * l'autre.
     */
    private fun sansCreneau(
        indexAbsolu: Int,
        premiere: Int,
        derniere: Int,
        attestes: Map<Int, IntRange>,
        nbFrames: Int,
    ): Boolean {
        if (attestes.isEmpty()) return false
        if (attestes.containsKey(indexAbsolu)) return false
        val gauche = attestes.filterKeys { it < indexAbsolu }.maxByOrNull { it.key }
        val droite = attestes.filterKeys { it > indexAbsolu }.minByOrNull { it.key }
        if (gauche == null && droite == null) return false
        val borneG = gauche?.value?.last ?: -1
        val borneD = droite?.value?.first ?: nbFrames
        return premiere <= borneG || derniere >= borneD
    }

    /**
     * Minimum PHYSIQUE de frames : n tokens exigent au moins n frames, plus une
     * frame de blanc entre deux tokens identiques consecutifs (regle CTC).
     *
     * Sert a savoir si un mot a eu la PLACE d'exister, jamais a l'excuser.
     * [PIEGE] ctcmin_vs_plausible : en v1, `ctcMinFrames` CONDAMNE et
     * `plausibleMinFrames` EXCUSE — les interchanger a deja coute. La v2 n'a
     * pas de minimum "typique" : un mot qui n'a pas la place n'est pas juge,
     * il attend une fenetre ou il l'a. Il n'y a donc plus rien a excuser.
     */
    private fun framesMinimales(mots: List<IntArray>): Int {
        var n = 0
        var precedent = -1
        for (toks in mots) {
            for (tk in toks) {
                n++
                if (tk == precedent) n++ // blanc obligatoire entre deux tokens egaux
                precedent = tk
            }
        }
        return n
    }
}

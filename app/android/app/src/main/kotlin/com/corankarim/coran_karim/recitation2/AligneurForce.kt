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
        /**
         * `forced(mot attendu) - forced(meilleure confusion de LETTRE)`, sur les
         * MEMES frames. Null si le mot n'a aucune confusion possible.
         *
         * POURQUOI CE SIGNAL EXISTE, alors que le `gop` est deja la. Le `gop` se
         * compare a `free`, un maximum sur les 1025 classes : une borne si lache
         * que TOUS les mots corrects s'y ecrasent a exactement 0,000. Mesure du
         * 2026-07-31 sur audio reellement faute (189 phrases tenues a l'ecart),
         * detection a 2 % de collateral :
         *
         *     gop = forced - free            (ce que faisait la v2)     9 %
         *     forced - forced(confusion)                               24 %
         *     idem, variantes de LETTRE seules                         30 %
         *
         * Et surtout, la mediane d'un mot CORRECT passe de 0,000 a +1,79 : le
         * seuil cesse d'etre un reglage (-0,45 / -1,60) pour devenir ZERO, la
         * frontiere naturelle d'un rapport de vraisemblance. Positif = l'audio
         * prefere le mot attendu ; negatif = il prefere la confusion.
         *
         * L'IDEE N'EST PAS NEUVE DANS CE PROJET : elle est ecrite dans
         * ForcedAligner.WordResult.rescoreMargin depuis le 2026-07-19, validee
         * hors device, et jamais branchee -- « ne participe PAS au verdict tant
         * que le seuil n'est pas calibre sur device ». C'est cette calibration
         * qui manquait ; le 2026-07-31 l'a faite, et la reponse est zero.
         *
         * ⚠️ Les 80,8 % annonces en 2026-07-19 valaient sur des clips de mot
         * ISOLE. En contexte de phrase, meme regle, meme modele : 24-30 %. Les
         * deux chiffres sont vrais, ils ne mesurent pas la meme chose.
         */
        val margeLettres: Float? = null,
        /**
         * Idem contre les substitutions de HARAKAT. Mesure 2026-07-31 : 7,9 % de
         * detection, a peine au-dessus du hasard -- deja constate en 2026-07-19
         * (49,6 %, « quasi hasard »). JOURNALISE, ne tranche pas seul, et
         * surtout PAS fusionne avec [margeLettres] : l'union des deux jeux de
         * candidats fait tomber la detection de 30 % a 21 %.
         *
         * ⚠️ Ce « quasi hasard » vaut POUR CE MODELE, qui n'a jamais ete
         * entraine a distinguer deux harakat sur le meme squelette consonantique
         * -- pas pour la harakat en general. A REMESURER apres tout entrainement
         * qui touche a ca (contrastif, tete dediee). Une piste mesuree perdante
         * dans un contexte ne l'est pas dans tous.
         */
        val margeHarakat: Float? = null,
    )

    data class Resultat(
        val mots: List<MotAligne>,
        val bandeTronquee: Boolean,
    )

    private val neginf = -1e30f

    /** Piece -> identifiant, pour construire le graphe des ecritures. */
    private val idParPiece: Map<String, Int> =
        pieces.withIndex().associate { (i, p) -> p to i }

    /** Longueur de la plus longue piece : borne la recherche des aretes. */
    private val pieceMax: Int = pieces.maxOfOrNull { it.length } ?: 1

    /**
     * ── UN MOT N'A PAS UNE ECRITURE, IL EN A DES DIZAINES ──────────────────
     *
     * Graphe des decoupages de [texte] en pieces du vocabulaire : un noeud par
     * position de caractere, une arete par piece qui commence la. Les chemins
     * de ce graphe SONT toutes les tokenisations valides du mot.
     *
     * DEFAUT QUE CA CORRIGE (2026-08-06, Al-Baqara, session live) :
     *     mot=42 "كَفَرُوا۟" -> definitif:rouge | gop=-5.33 forced=-5.34
     *                            free=-0.01 frames=1 obs=4 entendu="كَفَ"
     * Le flux brut porte le mot ENTIER, lu parfaitement par le modele aux
     * largeurs 4 s et 6 s, et une fenetre de 11,76 s l'avait au centre avec
     * 11/11 mots interieurs. Ce n'etait donc ni le modele, ni le fenetrage,
     * ni un bord. La cible imposait la piece ENTIERE `▁كَفَرُوا۟` (le mot vaut
     * UN jeton dans `word_tokens.json`) alors que le modele avait EPELE le mot
     * sur cet audio. Le chemin force n'ayant nulle part ou poser ce jeton
     * unique, Viterbi l'a ecrase sur une frame -- et `entendu`, qui est le
     * decodage libre RESTREINT aux frames du mot, ne pouvait rendre qu'un
     * fragment.
     * Reproduit au banc (PlancherDureeTest), les deux echecs sont SYMETRIQUES :
     *     modele emet la piece entiere + cible piece entiere -> 8 frames, gop 0,00
     *     modele EPELLE                + cible piece entiere -> 1 frame, gop -11,99
     * Choisir un camp serait donc faux dans l'autre sens. La seule forme juste
     * est de proposer TOUTES les ecritures et de laisser l'audio trancher.
     *
     * AMPLEUR (mesuree sur le vocabulaire du modele deploye) : 4 678 mots sur
     * 19 001 ont une decomposition de dictionnaire DIFFERENTE du repli glouton
     * -- dont 184 qui valent un seul jeton. Ce n'est pas un cas particulier.
     *
     * POURQUOI ON NE LES ENUMERE PAS : un mot a 68 ecritures valides en
     * mediane, jusqu'a 1800. Mais elles sont les chemins d'un graphe de 12
     * noeuds et 19 aretes (medianes mesurees) -- la DP les parcourt toutes
     * sans jamais en lister une seule. Un fichier qui les listerait ferait a
     * la main, et mal, ce que le treillis fait gratuitement.
     *
     * COUT, chiffre sur une fenetre reelle du log (11,76 s, 11 mots) :
     * 99 etats -> 209, soit 14 553 -> 30 723 cases de DP. Quelques additions
     * chacune, contre ~850 ms d'inference d'encodeur sur la meme fenetre : le
     * DP etait deja un arrondi, il le reste. Il est donc paye sur TOUS les
     * mots, et c'est voulu -- on ne peut pas savoir a l'avance lequel posera
     * probleme, cela depend de ce que le modele a produit sur CET audio.
     *
     * @return (nombre de noeuds, aretes (depuis, vers, jeton)) ou null si le
     *   mot n'est pas decomposable (jamais observe : 0 cas sur 19 001).
     */
    private fun grapheEcritures(texte: String): Pair<Int, List<IntArray>>? {
        val s = "\u2581" + texte
        val n = s.length
        val aretes = ArrayList<IntArray>()
        val atteignable = BooleanArray(n + 1)
        atteignable[0] = true
        for (i in 0 until n) {
            if (!atteignable[i]) continue
            var j = minOf(n, i + pieceMax)
            while (j > i) {
                val id = idParPiece[s.substring(i, j)]
                if (id != null) { aretes.add(intArrayOf(i, j, id)); atteignable[j] = true }
                j--
            }
        }
        if (!atteignable[n]) return null
        // On elague les aretes qui ne menent nulle part : sans ca le treillis
        // porterait des etats morts, et la DP les visiterait pour rien.
        val utile = BooleanArray(n + 1)
        utile[n] = true
        for (k in aretes.indices.reversed()) {
            val e = aretes[k]
            if (utile[e[1]]) utile[e[0]] = true
        }
        return (n + 1) to aretes.filter { utile[it[0]] && utile[it[1]] }
    }

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
        /** CONCURRENTES de chaque mot — a ne pas confondre avec
         *  [variantesParMot]. Celles-la se prononcent AUTREMENT : leur score ne
         *  remplace jamais celui du mot attendu, il lui est SOUSTRAIT pour
         *  produire [MotAligne.margeLettres] / [MotAligne.margeHarakat]. */
        confusionsLettresParMot: List<List<IntArray>> = emptyList(),
        confusionsHarakatParMot: List<List<IntArray>> = emptyList(),
        /** Texte de chaque mot de la bande. Fourni => l'alignement explore
         *  TOUTES les ecritures du mot (cf. [grapheEcritures]) au lieu de la
         *  seule tokenisation de [tokensParMot]. Absent => comportement
         *  d'avant, a l'identique : le banc et les appels sans texte restent
         *  valides. */
        textesParMot: List<String> = emptyList(),
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

        // ── LE TREILLIS ────────────────────────────────────────────────────
        //
        // Deux formes, meme DP. Sans [textesParMot] on garde EXACTEMENT le
        // treillis lineaire d'avant (`[blanc, t1, blanc, t2, ...]`). Avec, on
        // aligne le MOT et non une tokenisation figee : les etats deviennent
        // le graphe de toutes ses ecritures (cf. [grapheEcritures]).
        //
        // Un etat = soit un BLANC pose sur un noeud du graphe, soit un JETON
        // pose sur une arete. Les transitions sont celles du CTC, transposees
        // du chemin lineaire au graphe : rester, passer au blanc suivant,
        // enchainer deux jetons sans blanc SI leurs identifiants different.
        val etatToken = ArrayList<Int>()   // jeton emis par l'etat (blank pour un blanc)
        val etatMot = ArrayList<Int>()     // mot proprietaire, -1 pour un blanc
        val preds = ArrayList<IntArray>()  // predecesseurs (hors boucle sur soi)
        var etatsDepart = IntArray(0)
        var etatsFin = IntArray(0)

        val avecTexte = textesParMot.size == mots.size &&
            textesParMot.all { it.isNotEmpty() }
        var graphes: List<Pair<Int, List<IntArray>>>? = null
        if (avecTexte) {
            val g = ArrayList<Pair<Int, List<IntArray>>>(mots.size)
            var complet = true
            for (m in textesParMot) {
                val gr = grapheEcritures(m)
                if (gr == null) { complet = false; break }
                g.add(gr)
            }
            // Un seul mot non decomposable et on retombe sur le treillis
            // lineaire pour TOUTE la bande : mieux vaut le comportement
            // d'avant, connu et mesure, qu'un melange des deux. Jamais observe
            // sur le vocabulaire deploye (0 mot sur 19 001), mais un texte
            // hors-Coran ou un modele futur pourraient l'atteindre.
            if (complet) graphes = g
        }

        if (graphes != null) {
            // Noeuds globaux : la fin d'un mot EST le debut du suivant.
            val offset = IntArray(mots.size + 1)
            for (w in mots.indices) offset[w + 1] = offset[w] + (graphes[w].first - 1)
            val nbNoeuds = offset[mots.size] + 1
            // Blancs d'abord (id = noeud), puis un etat par arete.
            for (v in 0 until nbNoeuds) { etatToken.add(blank); etatMot.add(-1) }
            val aretesGlob = ArrayList<IntArray>() // de, vers, jeton, mot
            for (w in mots.indices) {
                for (e in graphes[w].second) {
                    aretesGlob.add(intArrayOf(offset[w] + e[0], offset[w] + e[1], e[2], w))
                }
            }
            for (e in aretesGlob) { etatToken.add(e[2]); etatMot.add(e[3]) }
            val idArete = { k: Int -> nbNoeuds + k }
            // Aretes entrantes par noeud, pour construire les predecesseurs.
            val entrantes = Array(nbNoeuds) { ArrayList<Int>() }
            val sortantes = Array(nbNoeuds) { ArrayList<Int>() }
            aretesGlob.forEachIndexed { k, e ->
                entrantes[e[1]].add(k); sortantes[e[0]].add(k)
            }
            for (v in 0 until nbNoeuds) {
                preds.add(entrantes[v].map { idArete(it) }.toIntArray())
            }
            aretesGlob.forEachIndexed { k, e ->
                val p = ArrayList<Int>()
                p.add(e[0]) // le blanc pose sur le noeud de depart
                for (f in entrantes[e[0]]) {
                    // Deux jetons EGAUX consecutifs exigent un blanc entre eux.
                    if (aretesGlob[f][2] != e[2]) p.add(idArete(f))
                }
                preds.add(p.toIntArray())
            }
            etatsDepart = (listOf(0) + sortantes[0].map { idArete(it) }).toIntArray()
            etatsFin = (listOf(nbNoeuds - 1) +
                entrantes[nbNoeuds - 1].map { idArete(it) }).toIntArray()
        } else {
            val proprio = ArrayList<Int>()
            val tokens = ArrayList<Int>()
            mots.forEachIndexed { w, toks ->
                for (tk in toks) { tokens.add(tk); proprio.add(w) }
            }
            if (tokens.isEmpty()) return null
            val l = 2 * tokens.size + 1
            for (li in 0 until l) {
                val tk = if (li % 2 == 0) blank else tokens[li / 2]
                etatToken.add(tk)
                etatMot.add(if (li % 2 == 0) -1 else proprio[li / 2])
            }
            for (li in 0 until l) {
                val p = ArrayList<Int>()
                if (li >= 1) p.add(li - 1)
                if (li >= 2 && etatToken[li] != blank &&
                    etatToken[li] != etatToken[li - 2]) p.add(li - 2)
                preds.add(p.toIntArray())
            }
            etatsDepart = if (l > 1) intArrayOf(0, 1) else intArrayOf(0)
            etatsFin = if (l >= 2) intArrayOf(l - 1, l - 2) else intArrayOf(0)
        }

        val nbEtats = etatToken.size
        if (nbEtats == 0) return null
        val dp = Array(t) { FloatArray(nbEtats) { neginf } }
        val back = Array(t) { IntArray(nbEtats) { -1 } }
        for (st in etatsDepart) dp[0][st] = logprobs[0][etatToken[st]]

        for (ti in 1 until t) {
            val lp = logprobs[ti]
            for (st in 0 until nbEtats) {
                var best = dp[ti - 1][st]   // rester dans le meme etat
                var arg = st
                for (pr in preds[st]) {
                    val v = dp[ti - 1][pr]
                    if (v > best) { best = v; arg = pr }
                }
                if (best <= neginf) continue
                dp[ti][st] = best + lp[etatToken[st]]
                back[ti][st] = arg
            }
        }

        var fin = etatsFin[0]
        for (st in etatsFin) if (dp[t - 1][st] > dp[t - 1][fin]) fin = st
        if (dp[t - 1][fin] <= neginf) return null

        // Retro-propagation : quel etat occupe chaque frame.
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
            val st = chemin[ti]
            val w = etatMot[st]
            if (w < 0) continue // blanc : n'appartient a aucun mot
            if (premiere[w] < 0) premiere[w] = ti
            derniere[w] = ti
            nb[w]++
            sommeForced[w] += logprobs[ti][etatToken[st]].toDouble()
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
            // ── RATTRAPAGE CIBLE : LE MOT EST-IL ECRIT AUTREMENT ? ─────────
            //
            // Idee de l'utilisateur, dans sa forme BORNEE (2026-08-06). Ouvrir
            // toutes les ecritures dans le treillis PRINCIPAL a ete mesure
            // perdant (0,68 % -> 7,46 % sur le meme WAV) : la DP y deplace les
            // frontieres de tous les mots. Ici l'alignement global n'est pas
            // touche -- on rescore CE mot sur l'audio que ses voisins n'ont pas
            // revendique, et on ne garde le resultat que s'il est MEILLEUR.
            //
            // Le defaut vise (Al-Baqara, mot 42 `كَفَرُوا۟`) : la cible imposait
            // la piece ENTIERE (le mot vaut UN jeton sur 184 du dictionnaire)
            // alors que le modele avait EPELE le mot. Viterbi l'a ecrase sur
            // une frame -> gop=-5,33 avec free=-0,01, et un rouge sur un mot
            // parfaitement prononce.
            //
            // Un rescoring ne peut que RETIRER un faux rouge : il ne vole
            // aucune frame (la plage est bornee par les voisins attestes) et il
            // ne descend jamais le score (on prend le maximum).
            if (n > 0 && w < textesParMot.size && textesParMot[w].isNotEmpty()) {
                val deLibre = if (w > 0 && derniere[w - 1] >= 0)
                    (derniere[w - 1] + 1).coerceAtMost(premiere[w]) else 0
                val aLibre = if (w + 1 < mots.size && premiere[w + 1] >= 0)
                    (premiere[w + 1] - 1).coerceAtLeast(derniere[w]) else t - 1
                if (aLibre > derniere[w] || deLibre < premiere[w]) {
                    val alt = forwardMoyenGraphe(logprobs, deLibre, aLibre, textesParMot[w])
                    if (alt > neginf && alt > f) {
                        f = alt
                        // La plage retenue devient celle du mot : sans ca,
                        // `frames`, `entendu` et `interieur` continueraient de
                        // decrire l'alignement qu'on vient d'ecarter.
                        premiere[w] = deLibre
                        derniere[w] = aLibre
                        nb[w] = aLibre - deLibre + 1
                    }
                }
            }
            // CONCURRENTES : meme fenetre de frames, mais leur score est
            // SOUSTRAIT au lieu de remplacer. `f` est deja le meilleur des
            // ecritures equivalentes ci-dessus, donc la marge compare bien
            // « ce qui se prononce comme attendu » a « ce qui se prononce
            // autrement ». Cout : un treillis minuscule par candidat, sur les
            // seules frames du mot -- aucune passe d'encodeur supplementaire.
            fun marge(cands: List<List<IntArray>>): Float? {
                if (n <= 0 || w >= cands.size) return null
                var meilleur = neginf
                for (c in cands[w]) {
                    if (c.isEmpty()) continue
                    val s = forwardMoyen(logprobs, premiere[w], derniere[w], c)
                    if (s > meilleur) meilleur = s
                }
                return if (meilleur <= neginf) null else f - meilleur
            }
            val margeL = marge(confusionsLettresParMot)
            val margeH = marge(confusionsHarakatParMot)

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
                    margeLettres = margeL,
                    margeHarakat = margeH,
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
    /**
     * Comme [forwardMoyen], mais sur TOUTES les ecritures du mot au lieu d'une
     * seule (cf. [grapheEcritures]) -- et sur une plage de frames qu'on choisit.
     *
     * SERT AU RATTRAPAGE CIBLE, pas a l'alignement. Ouvrir les ecritures dans
     * le treillis PRINCIPAL a ete mesure PERDANT le 2026-08-06 (0,68 % ->
     * 7,46 % de mots non verts sur le meme WAV) : libre de re-epeler chaque
     * mot, la DP deplace les frontieres et les voisins paient. Ici l'alignement
     * global n'est pas touche -- on rescore UN mot deja condamne, sur l'audio
     * que ses voisins n'ont pas revendique. Un rescoring ne peut donc que
     * retirer un faux rouge, jamais en creer ni voler des frames.
     */
    private fun forwardMoyenGraphe(
        logprobs: Array<FloatArray>, de: Int, a: Int, texte: String,
    ): Float {
        if (de < 0 || a < de) return neginf
        val g = grapheEcritures(texte) ?: return neginf
        val (nbNoeuds, aretes) = g
        if (aretes.isEmpty()) return neginf
        val entrantes = Array(nbNoeuds) { ArrayList<Int>() }
        val sortantes = Array(nbNoeuds) { ArrayList<Int>() }
        aretes.forEachIndexed { k, e -> entrantes[e[1]].add(k); sortantes[e[0]].add(k) }
        val nbEtats = nbNoeuds + aretes.size
        fun jeton(st: Int) = if (st < nbNoeuds) blank else aretes[st - nbNoeuds][2]
        var prev = FloatArray(nbEtats) { neginf }
        prev[0] = logprobs[de][blank]
        for (k in sortantes[0]) prev[nbNoeuds + k] = logprobs[de][aretes[k][2]]
        for (t in de + 1..a) {
            val cur = FloatArray(nbEtats) { neginf }
            val lp = logprobs[t]
            for (v in 0 until nbNoeuds) {
                var acc = prev[v]
                for (k in entrantes[v]) acc = logSomme(acc, prev[nbNoeuds + k])
                if (acc > neginf) cur[v] = acc + lp[blank]
            }
            aretes.forEachIndexed { k, e ->
                var acc = prev[nbNoeuds + k]
                acc = logSomme(acc, prev[e[0]])
                for (f in entrantes[e[0]]) {
                    if (aretes[f][2] != e[2]) acc = logSomme(acc, prev[nbNoeuds + f])
                }
                if (acc > neginf) cur[nbNoeuds + k] = acc + lp[e[2]]
            }
            prev = cur
        }
        var fin = prev[nbNoeuds - 1]
        for (k in entrantes[nbNoeuds - 1]) fin = logSomme(fin, prev[nbNoeuds + k])
        if (fin <= neginf) return neginf
        val n = (a - de + 1).coerceAtLeast(1)
        return fin / n
    }

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
        // ── LA SENTINELLE NE SE DIVISE PAS (2026-08-06) ─────────────────────
        //
        // `fin` vaut [neginf] quand AUCUN chemin CTC n'existe. La diviser par
        // le nombre de frames en fait une valeur FINIE et plausible : sur
        // 3 frames, -1e30 / 3 = -3,33e29. Tous les gardes en aval testent
        // `<= neginf` (donc `<= -1e30`) et laissent alors passer cette
        // valeur -- la sentinelle cesse d'etre reconnaissable.
        //
        // CONSTATE EN PRODUCTION (log device, 2026-08-06, build v56) :
        //     margeL=3.333333383491554e+29
        // c'est-a-dire `f - (-3,33e29)`. La marge positive est benigne (le
        // Decideur ne condamne que sur marge NEGATIVE), mais le meme defaut
        // dans l'autre sens -- `f` sentinelle, concurrente normale -- produit
        // une marge massivement NEGATIVE et donc un ROUGE VERROUILLE SANS
        // AUCUNE PREUVE ACOUSTIQUE, ce que la regle projet interdit.
        //
        // MEME BUG, DEJA PAYE UNE FOIS : `Tete3Traits` comparait lui aussi le
        // score DIVISE a la sentinelle, « si bien qu'au-dela de 2 frames il ne
        // filtrait plus rien -- alt2 a -2,5e29 et un logit a 3,7e29 ». Corrige
        // la-bas le 2026-08-05, jamais ici. On filtre donc AVANT la division,
        // sur le score BRUT, et la sentinelle ressort intacte.
        if (fin <= neginf) return neginf
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

        // TEST DIRECT : les frames de ce mot appartiennent-elles a un AUTRE mot
        // que le decodage libre a effectivement entendu ?
        //
        // C'est la formulation exacte du defaut que l'utilisateur a nomme le
        // 2026-07-30 : « le GOP forced condamne alors que le free est
        // confiant ». Un `free` proche de 0 veut dire que le modele SAIT ce
        // qu'il entend ; si ce qu'il entend est un autre mot attendu, alors le
        // mot juge n'est pas la -- c'est une erreur de POSITION, pas de
        // prononciation, et aucun verdict ne peut en sortir.
        //
        // Preuve, meme session : mot 172 f37 gop=-14,18 entendu="ٱلْبَرْء",
        // c'est-a-dire l'audio du mot 170. La version precedente ne testait que
        // les bornes des voisins attestes les plus PROCHES ; quand ceux-la
        // manquaient dans le bloc, elle ne voyait rien.
        for ((autre, plage) in attestes) {
            if (autre == indexAbsolu) continue
            if (premiere <= plage.last && derniere >= plage.first) return true
        }

        // Repli : le mot deborde-t-il de l'espace laisse libre par ses voisins ?
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

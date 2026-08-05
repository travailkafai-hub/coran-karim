package com.corankarim.coran_karim.recitation2

/**
 * TETE 3 — LE CALCUL DES CARACTERISTIQUES, port fidele du Python.
 *
 * ── POURQUOI CE FICHIER EXISTE SEPAREMENT DE [Tete3] ───────────────────────
 *
 * [Tete3] ne fait qu'une multiplication de matrices : elle est juste ou fausse
 * de facon evidente. Le vrai risque est AILLEURS -- dans les 1036 nombres qu'on
 * lui donne. La tete a ete entrainee sur des grandeurs calculees par
 * `benchmark/tete_encodeur_ecart.py::caracteristiques`, et une divergence de
 * calcul ne leve aucune erreur : elle rend les poids denues de sens, et les
 * 47 % de detection mesures redeviennent du hasard.
 *
 * Isoler ce calcul le rend TESTABLE sans modele, sans audio et sans appareil :
 * `Tete3TraitsTest` rejoue un vecteur de reference produit par le Python
 * (`benchmark/reference_parite_tete3.py`) et compare valeur par valeur.
 *
 * ── CE QUE CE PORTAGE CORRIGE PAR RAPPORT A L'ETAT PRECEDENT ───────────────
 *
 * `ChaineRecitation.vecteurTete3` calculait jusqu'ici une APPROXIMATION,
 * documentee comme telle et volontairement cantonnee a l'observation :
 *
 *   | grandeur   | avant                                  | ici                |
 *   |------------|----------------------------------------|--------------------|
 *   | etat       | moyenne seule (512)                    | moyenne + ecart-type (1024) |
 *   | forced_f   | recopiait forced_v (Viterbi)           | vrai FORWARD CTC   |
 *   | alt/alt2   | 2 confusions de l'AligneurForce         | tout le jeu de variantes |
 *
 * Les trois divergeaient du Python. Aucune ne se voyait : le logit sortait, il
 * etait simplement faux. C'est exactement le piege paye deux jours de suite
 * (« le banc mesurait mon decoupage, pas l'app »).
 *
 * ── LES DEUX SCORES NE SONT PAS LE MEME CALCUL, ET C'EST VOULU ─────────────
 *
 * [scoreForce] somme TOUS les alignements possibles (forward, log-sum-exp) ;
 * [viterbiForce] ne garde que le MEILLEUR (max). Le Python fournit les deux a
 * la tete, et leur ECART est une caracteristique en soi : un mot dont le
 * meilleur chemin domine largement la somme est un mot dont l'alignement est
 * certain. Remplacer l'un par l'autre, comme on le faisait, detruit
 * silencieusement cette information.
 */
object Tete3Traits {

    /** Sentinelle du Python (`NEG = -1e30`) : « aucun alignement possible »,
     *  et non « tres mauvais score ». La distinction est la raison d'etre du
     *  filtre dans [caracteristiques] -- cf. le commentaire la-bas. */
    const val NEG = -1e30

    /** Nombre de grandeurs conditionnees par la cible, hors etat d'encodeur. */
    const val N_TRAITS = 12

    /** Noms dans l'ORDRE du Python (`tete_ecart_canonique.NOMS`). L'ordre EST
     *  le contrat : une permutation ne se verrait pas a l'execution. */
    val NOMS = listOf(
        "forced_v", "forced_f", "free", "alt", "alt2", "gopA", "gopC",
        "marge_alt", "n_frames", "n_tokens", "entropie", "pic_blanc",
    )

    private fun logAddExp(a: Double, b: Double): Double {
        if (a <= NEG && b <= NEG) return NEG
        val hi = if (a > b) a else b
        val lo = if (a > b) b else a
        return hi + Math.log1p(Math.exp(lo - hi))
    }

    /**
     * FORWARD CTC : log-somme de TOUS les alignements de [ids] sur [lp].
     * Port de `assainir_corpus_fautes.py::score_force`, meme sentinelle et
     * meme condition de faisabilite.
     *
     * @return [NEG] si l'audio est trop court pour la sequence -- il n'existe
     *   alors litteralement aucun chemin, ce n'est pas un mauvais score.
     */
    fun scoreForce(lp: Array<FloatArray>, ids: IntArray): Double {
        val t = lp.size
        if (t == 0) return NEG
        val v = lp[0].size
        val blank = v - 1
        val ext = IntArray(2 * ids.size + 1)
        ext[0] = blank
        for (i in ids.indices) { ext[2 * i + 1] = ids[i]; ext[2 * i + 2] = blank }
        val s = ext.size
        if (t < (s + 1) / 2) return NEG

        val sautOk = BooleanArray(s) { i ->
            i >= 2 && ext[i] != blank && ext[i] != ext[i - 2]
        }
        var a = DoubleArray(s) { NEG }
        a[0] = lp[0][ext[0]].toDouble()
        if (s > 1) a[1] = lp[0][ext[1]].toDouble()
        val suivant = DoubleArray(s)
        for (pas in 1 until t) {
            val frame = lp[pas]
            for (i in 0 until s) {
                var acc = a[i]
                if (i >= 1) acc = logAddExp(acc, a[i - 1])
                if (i >= 2 && sautOk[i]) acc = logAddExp(acc, a[i - 2])
                suivant[i] = acc + frame[ext[i]].toDouble()
            }
            System.arraycopy(suivant, 0, a, 0, s)
        }
        return if (s > 1) logAddExp(a[s - 1], a[s - 2]) else a[s - 1]
    }

    /**
     * VITERBI CONTRAINT : meilleur chemin unique. Port de
     * `gop_fenetre_etroite_vs_large.py::viterbi_force`.
     *
     * @return l'etiquette retenue par frame, ou null si aucun chemin n'existe.
     */
    fun viterbiForce(lp: Array<FloatArray>, ids: IntArray): IntArray? {
        val t = lp.size
        if (t == 0) return null
        val v = lp[0].size
        val blank = v - 1
        val ext = IntArray(2 * ids.size + 1)
        ext[0] = blank
        for (i in ids.indices) { ext[2 * i + 1] = ids[i]; ext[2 * i + 2] = blank }
        val s = ext.size
        if (t < (s + 1) / 2) return null

        val sautOk = BooleanArray(s) { i ->
            i >= 2 && ext[i] != blank && ext[i] != ext[i - 2]
        }
        var d = DoubleArray(s) { NEG }
        val bp = Array(t) { ByteArray(s) }
        d[0] = lp[0][ext[0]].toDouble()
        if (s > 1) d[1] = lp[0][ext[1]].toDouble()
        val suivant = DoubleArray(s)
        for (pas in 1 until t) {
            val frame = lp[pas]
            val ligne = bp[pas]
            for (i in 0 until s) {
                var meilleur = d[i]
                var arg = 0
                if (i >= 1 && d[i - 1] > meilleur) { meilleur = d[i - 1]; arg = 1 }
                if (i >= 2 && sautOk[i] && d[i - 2] > meilleur) { meilleur = d[i - 2]; arg = 2 }
                suivant[i] = meilleur + frame[ext[i]].toDouble()
                ligne[i] = arg.toByte()
            }
            System.arraycopy(suivant, 0, d, 0, s)
        }
        // Le Python choisit S-1 en cas d'EGALITE (`>=`) : le reproduire, sinon
        // deux chemins de meme score donneraient deux etiquetages differents.
        var etat = if (s == 1 || d[s - 1] >= d[s - 2]) s - 1 else s - 2
        val lab = IntArray(t)
        for (pas in t - 1 downTo 0) {
            lab[pas] = ext[etat]
            etat -= bp[pas][etat].toInt()
        }
        return lab
    }

    /**
     * Les 12 grandeurs conditionnees par la cible, dans l'ordre de [NOMS].
     *
     * @param lp logprobs des SEULES frames du mot (T x V)
     * @param tokensAttendus tokenisation du mot attendu
     * @param variantes tokenisations des confusions plausibles ; la liste
     *   complete du Python (`confusions_recitation.variantes`), pas un extrait
     * @return null si le mot n'est pas jugeable -- audio trop court pour la
     *   cible, ou aucune confusion scorable. C'est un ABSTENTION, pas un zero :
     *   rendre un vecteur par defaut ferait entrer du bruit dans la tete.
     */
    fun caracteristiques(
        lp: Array<FloatArray>,
        tokensAttendus: IntArray,
        variantes: List<IntArray>,
    ): FloatArray? {
        val t = lp.size
        if (t == 0) return null
        val n = if (t > 1) t else 1
        val lab = viterbiForce(lp, tokensAttendus) ?: return null

        var sommeForcee = 0.0
        for (pas in 0 until t) sommeForcee += lp[pas][lab[pas]].toDouble()
        val forcedV = sommeForcee / lab.size
        val forcedF = scoreForce(lp, tokensAttendus) / n

        var sommeLibre = 0.0
        for (pas in 0 until t) {
            var mx = lp[pas][0]
            for (c in 1 until lp[pas].size) if (lp[pas][c] > mx) mx = lp[pas][c]
            sommeLibre += mx.toDouble()
        }
        val free = sommeLibre / t

        // VARIANTES NON SCORABLES : ECARTEES, PAS NOTEES -1e30. Une variante
        // plus longue que l'audio n'a aucun alignement possible ; la faire
        // concourir avec la sentinelle produit des caracteristiques a -1e29.
        //
        // ⚠️ FILTRER LE SCORE BRUT, JAMAIS LE SCORE DIVISE. La premiere version
        // de ce code -- ici comme en Python -- divisait par `n` AVANT de
        // comparer a `NEG / 2` : des que le mot fait 3 frames ou plus,
        // -1e30/n > -5e29 et la sentinelle PASSAIT. Le test de parite l'a
        // attrape (`alt2` a -2,5e29, logit a 3,7e29) ; sans lui la tete aurait
        // tourne sur le telephone en rendant des logits astronomiques sur les
        // mots dont une confusion est plus longue que l'audio.
        val scores = variantes
            .map { scoreForce(lp, it) }
            .filter { it > NEG / 2 }
            .map { it / n }
            .sortedDescending()
        if (scores.isEmpty()) return null
        val alt = scores[0]
        val alt2 = if (scores.size > 1) scores[1] else alt

        var sommeEntropie = 0.0
        var picBlanc = 0
        val blank = lp[0].size - 1
        for (pas in 0 until t) {
            val frame = lp[pas]
            var mx = frame[0]
            var argmax = 0
            for (c in 1 until frame.size) if (frame[c] > mx) { mx = frame[c]; argmax = c }
            var somme = 0.0
            for (c in frame.indices) somme += Math.exp((frame[c] - mx).toDouble())
            var h = 0.0
            for (c in frame.indices) {
                val p = Math.exp((frame[c] - mx).toDouble()) / somme
                h -= p * Math.log(p + 1e-9)
            }
            sommeEntropie += h
            if (argmax == blank) picBlanc++
        }
        val entropie = sommeEntropie / t
        val partBlanc = picBlanc.toDouble() / t

        return floatArrayOf(
            forcedV.toFloat(), forcedF.toFloat(), free.toFloat(),
            alt.toFloat(), alt2.toFloat(),
            (forcedV - free).toFloat(), (forcedF - alt).toFloat(),
            (alt - alt2).toFloat(),
            n.toFloat(), tokensAttendus.size.toFloat(),
            entropie.toFloat(), partBlanc.toFloat(),
        )
    }

    /**
     * MOYENNE PUIS ECART-TYPE de l'etat d'encodeur sur les frames du mot,
     * concatenes -- l'ordre du Python (`np.concatenate([mean, std])`).
     *
     * POURQUOI L'ECART-TYPE COMPTE. La moyenne seule decrit la sante GENERALE
     * du mot ; or une faute ne porte le plus souvent que sur UNE lettre, que
     * les autres diluent. L'ecart-type dit s'il s'est passe quelque chose
     * QUELQUE PART, sans dire ou. Mesure : c'est ce qui a fait passer la tete
     * de 37 % a 47 % de detection.
     *
     * ⚠️ Ecart-type de POPULATION (diviseur T), comme `np.std` par defaut --
     * pas l'estimateur non biaise (T-1). Sur un mot de 5 frames l'ecart est de
     * 12 %, largement de quoi rendre la normalisation fausse.
     */
    fun etatMoyenEtEcartType(etat: Array<FloatArray>, f0: Int, f1: Int): FloatArray? {
        if (f1 <= f0 || f0 < 0 || f1 > etat.size) return null
        val dim = etat[f0].size
        val n = (f1 - f0).toDouble()
        val out = FloatArray(2 * dim)
        for (k in 0 until dim) {
            var somme = 0.0
            for (t in f0 until f1) somme += etat[t][k].toDouble()
            val moyenne = somme / n
            var variance = 0.0
            for (t in f0 until f1) {
                val e = etat[t][k].toDouble() - moyenne
                variance += e * e
            }
            out[k] = moyenne.toFloat()
            out[dim + k] = Math.sqrt(variance / n).toFloat()
        }
        return out
    }
}

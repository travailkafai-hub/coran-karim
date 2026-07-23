package com.corankarim.coran_karim.fastconformer

/**
 * Alignement force CTC + score GOP (Goodness of Pronunciation).
 *
 * Principe (refonte 2026-07-11, remplace le diff textuel flou cote Dart) : le
 * texte a reciter est CONNU d'avance -- au lieu de decoder librement puis
 * comparer les textes (chemin expose au biais du modele qui "corrige" vers le
 * texte canonique, et source des ~10 regles ad hoc accumulees dans
 * recitation_provider.dart), on aligne de force la sequence de tokens attendue
 * sur les log-probabilites du modele (programmation dynamique CTC classique,
 * type torchaudio.functional.forced_align), et on juge chaque mot par l'ECART
 * entre deux scores mesures sur les MEMES frames :
 *
 *   forced = logprob moyenne du chemin force (le mot attendu, harakat comprises)
 *   free   = logprob moyenne du meilleur token par frame (ce que le modele
 *            prefererait dire, sans contrainte)
 *   gop    = forced - free   (toujours <= 0 ; proche de 0 = l'audio soutient
 *            pleinement le mot attendu ; tres negatif = le modele est bien
 *            plus sur d'avoir entendu AUTRE CHOSE)
 *
 * Les harakat sont des tokens BPE distincts dans notre vocabulaire (modele
 * "pcd") : une fatha au lieu d'une kasra effondre la logprob du chemin force
 * precisement sur les frames de la voyelle fautive -- detection a la harakat
 * pres, la ou le diff textuel devait deviner apres coup si une difference de
 * mots decodes etait une voyelle ou du bruit ASR. Et le signal survit au biais
 * du modele : meme quand l'argmax "corrige" vers le mot canonique, l'hesitation
 * reste visible dans les probabilites sous-jacentes.
 *
 * Les scores ne sont mesures QUE sur les frames ou le chemin force est dans un
 * etat TOKEN (pas blank) : les frames blank sont partagees par les deux chemins
 * (gop ~= 0) et ne feraient que diluer le signal.
 */
class ForcedAligner(
    private val vocab: List<String>,
    private val blankId: Int,
) {

    // Tokens contenant un SYMBOLE DE REGLE TAJWID (zone privee Unicode
    // U+E000..U+F8FF) -- 41 pieces sur 1024 dans le vocabulaire du modele
    // stage1b-260h.
    //
    // POURQUOI ILS SONT EXCLUS DU CALCUL DE `free` (correctif 2026-07-20) :
    // `gop = forced - free`, ou `free` = max par frame sur TOUTES les classes.
    // Le modele a appris a emettre ces symboles la ou il entend la regle. Sur
    // une recitation PARFAITE, il veut donc les emettre : `free` empoche ce
    // score eleve, alors que `forced` (contraint au texte NU, sans symboles)
    // ne le peut pas. Resultat : gop plonge sans AUCUNE faute du recitant.
    // Mesure hors device sur la recitation de l'utilisateur : forcer sa propre
    // transcription SANS symboles coute -177,8 contre AVEC (-8,53 -> -186,36).
    // L'ancien modele (mixed-e14) n'emettait aucun symbole -> cout 0, d'ou
    // "l'ancien modele ne bloque pas" constate par l'utilisateur.
    //
    // En excluant ces classes de `free`, on compare ce qui est comparable :
    // les deux chemins jouent sur le meme vocabulaire (lettres + harakat).
    // Les symboles restent DISPONIBLES dans le decodage libre du texte
    // (`greedyDecodeRange` -> `actual`), donc la verification du tajwid
    // continue de fonctionner -- elle est juste SEPAREE du jugement de
    // prononciation, comme demande.
    private val ruleSymbolTokens: BooleanArray = BooleanArray(vocab.size) { i ->
        vocab[i].any { c -> c.code in 0xE000..0xF8FF }
    }

    // CHADDA NU (2026-07-20 soir, constat device : "ٱللَّهِ"/"رَبِّ" bloquent
    // encore APRES le correctif symboles ci-dessous). Verifie sur le
    // tokenizer du modele stage1b-260h : le chadda (gemination, U+0651) est
    // souvent tokenise SEUL, sans lettre ni voyelle -- "ٱللَّهِ" -> [ٱل, لَ,
    // ّ, هِ], "رَبِّ" -> [رَ, بِ, ّ]. Ce n'est PAS une harakat (voyelle) :
    // c'est un signe de duree qui s'entend comme un ALLONGEMENT de la meme
    // consonne, sans signature acoustique propre distincte -- une piece de
    // vocabulaire sans veritable evenement articulatoire qui lui corresponde
    // en propre. Mesure hors device ET confirme sur device : "ٱللَّهِ" reste
    // a gop -13/-14 (identique a l'ANCIEN modele mixed-e14, qui ne connait
    // meme pas les symboles de regles) MEME sur une recitation correcte --
    // ce n'est donc ni une regression du modele 260h ni un residu du
    // probleme symboles, mais un defaut structurel prealable de
    // l'alignement force sur ce token isole, present dans les DEUX modeles.
    // A NE PAS CONFONDRE avec les harakat seules (fatha/kasra/damma,
    // id=936/938/940 dans le vocab teste) : celles-la doivent rester jugees
    // SANS exception (l'utilisateur exige leur controle strict, cf. exemple
    // rabbi/rabbo). Seul le chadda SANS voyelle accolee est exclu ici ; les
    // variantes chadda+voyelle fusionnees en un seul token (ex. "ِّ") portent
    // une vraie info de voyelle et restent jugees normalement.
    private val bareShaddaTokens: BooleanArray = BooleanArray(vocab.size) { i ->
        vocab[i].replace("▁", "") == "ّ"
    }

    // SUITE DU CORRECTIF CI-DESSUS (2026-07-20 soir) : exclure les symboles du
    // MAX de `free` ne suffisait pas. Mesure hors device, meme audio, meme mot,
    // ancien modele (mixed-e14, ne connait pas les symboles) contre nouveau
    // (stage1b-260h) : sur "يَوْمِ" (mot SANS aucune regle tajwid attendue),
    // gop ancien = -0,03 (parfait), gop nouveau = -20,09 (catastrophique). Le
    // mot recoit ~20% de masse de probabilite parasite sur des classes-symboles
    // MEME LA OU AUCUNE REGLE N'EST ATTENDUE (mesure directe : 0,2033 de masse
    // moyenne par frame) -- le nouveau modele a simplement moins de confiance
    // nette partout depuis qu'il partage son vocabulaire avec 40 classes
    // supplementaires. Cette masse ampute directement log P(bon token) dans
    // `forced` (jamais touche par le premier correctif), pas seulement le MAX
    // de `free`. D'ou stripRuleSymbolMass ci-dessous : on retire la masse des
    // 40 classes-symboles et on RENORMALISE les classes restantes (equivalent
    // exact a masquer leurs logits a -infini AVANT le softmax), applique a la
    // DP forcee ET a wordForcedSum/wordFreeSum -- jamais au decodage LIBRE
    // (`actual`/`entendu`), qui doit continuer a pouvoir emettre ces symboles
    // pour que la verification tajwid (unrealizedRulesFor cote Dart) fonctionne.
    // Gain mesure sur "يَوْمِ" : -20,09 -> -9,59. Reel mais INCOMPLET : l'ecart
    // avec l'ancien modele (-0,03) ne se referme pas entierement -- une partie
    // de la difference entre les deux modeles reste inexpliquee a ce stade.
    // Trouvaille separee, meme mesure : les mots a lettre doublee/chadda
    // (ٱللَّهِ, رَبِّ) restent mal alignes dans les DEUX modeles (ancien ET
    // nouveau) -- pas une regression du modele 260h ni de ces correctifs, un
    // defaut preexistant de l'alignement force sur les lettres doublees,
    // jamais mesure avant aujourd'hui.
    private fun stripRuleSymbolMass(logprobs: Array<FloatArray>): Array<FloatArray> {
        return Array(logprobs.size) { ti ->
            val lp = logprobs[ti]
            var maxKept = Float.NEGATIVE_INFINITY
            for (c in lp.indices) {
                if (c < ruleSymbolTokens.size && ruleSymbolTokens[c]) continue
                if (lp[c] > maxKept) maxKept = lp[c]
            }
            var sumExp = 0.0
            for (c in lp.indices) {
                if (c < ruleSymbolTokens.size && ruleSymbolTokens[c]) continue
                sumExp += Math.exp((lp[c] - maxKept).toDouble())
            }
            val logNorm = maxKept + Math.log(sumExp)
            FloatArray(lp.size) { c ->
                if (c < ruleSymbolTokens.size && ruleSymbolTokens[c]) Float.NEGATIVE_INFINITY
                else (lp[c] - logNorm).toFloat()
            }
        }
    }

    companion object {
        private const val TAG = "ForcedAligner"

        // Bug corrige 2026-07-14 : sur un segment FIGE (final=true), le mot a
        // la frontiere peut n'avoir recu que 1-2 frames de pur silence/
        // transition -- la coupure du segment (pause detectee ou borne 12s)
        // tombe juste AVANT que le mot ne soit reellement prononce. La DP
        // doit alors expliquer ces frames de silence en forcant quand meme
        // le token attendu dessus, produisant un score catastrophique
        // (observe sur device : gop=-8.51, entendu="") pour un mot par
        // ailleurs parfaitement reconnu dans le segment SUIVANT -- mais comme
        // final=true verrouille immediatement (cf. runAlignment, l'audio de
        // ce segment ne sera plus jamais reanalyse), le mauvais jugement
        // restait fige pour toujours. Sous ce seuil, le mot frontiere n'est
        // plus inclus dans les resultats CE COUP-CI (ni jugee ni verrouille)
        // -- mais SEULEMENT si l'audio disponible apres le dernier mot
        // confirme est lui-meme quasi nul (cf. plus bas, MIN_FRAMES_FOR_JUDGMENT
        // sert desormais a mesurer l'"opportunite laissee" au mot, pas ses
        // propres frames). Distinction cruciale (remarque utilisateur
        // 2026-07-14) : si beaucoup d'audio suit deja le dernier mot confirme
        // (le recitateur a clairement continue a parler) et que le modele
        // n'arrive QUAND MEME PAS a placer ce mot, ce n'est PAS un artefact de
        // coupure -- c'est un vrai signal d'erreur (mot rate/saute), qui doit
        // etre juge ROUGE immediatement, pas differe. ~80ms/frame en pratique
        // -> 3 frames = 240ms.
        private const val MIN_FRAMES_FOR_JUDGMENT = 3

        // ─────────────────────────────────────────────────────────────────
        // BLOCAGE D'ALIGNEMENT SUR CHECKPOINT PEU CONFIANT — journal des
        // tentatives (2026-07-16). Historique conserve DELIBEREMENT, y compris
        // les impasses : chaque piste ci-dessous a l'air d'une bonne idee sur
        // le papier et a couté un cycle build+deploiement+test device pour
        // etre invalidee. Ne pas les re-tenter sans lire pourquoi elles ont
        // echoue.
        //
        // ── LE PROBLEME ──
        // Sur le checkpoint tajweed (encore en entrainement), la confiance
        // par-token est structurellement plus basse que sur "pcd" : gop
        // typique -5 a -9 contre ~0, MEME sur des mots correctement prononces.
        // Consequence algorithmique, pas un reglage de seuil : dans la
        // recherche du meilleur etat final PARTIEL, la DP compare a FRAME
        // EGALE le cout de "forcer les tokens attendus" contre "rester dans
        // l'etat blank". Si le token attendu est peu confiant meme quand il a
        // ete reellement prononce, rester en blank devient moins cher
        // qu'avancer -> bestEnd se bloque en arriere de la parole reelle. Le
        // segment fige (final=true) verrouille ensuite ce mauvais resultat
        // pour toujours (son audio n'est jamais reanalyse), et les mots
        // au-dela n'ont ZERO frame -> aucune ligne GOP -> jamais colories.
        //
        // ── TENTATIVE 1 (14h13) — penalite blank sur TOUS les blancs — ECHEC
        // Soustraire une constante au cout d'emission de l'etat blank pendant
        // la recherche du chemin, pour decourager le repli sur blank.
        // Resultat device : a mal-aligne un mot sur l'audio RESIDUEL d'un mot
        // precedent -- l'etat 0 doit pouvoir absorber GRATUITEMENT l'audio des
        // mots deja traites qui traine encore dans un buffer reanalyse apres
        // un recul d'ancre (cf. "ancre d'alignement deplacee" dans
        // BufferedTranscriber). Observe : "rabbi" plaque sur les frames de
        // "al-hamdu lillahi", gop=-15, entendu=mauvais mot.
        //
        // ── TENTATIVE 2 (14h22) — penalite blank sur blancs INTERNES — ECHEC
        // Meme idee, mais en exemptant l'etat 0 pour corriger la tentative 1.
        // Resultat device : a reintroduit EXACTEMENT le blocage originel sur
        // le tout premier mot d'un segment -- l'etat 0 n'est pas seulement
        // l'etat "residu", c'est aussi l'etat de depart NORMAL quand anchor=0.
        // Observe : frontiere=0 mots=0 sur un segment fige avec audio present.
        //
        // LECON DES DEUX : une penalite par-FRAME sur un etat topologique
        // (blank) ne peut PAS distinguer "audio residuel legitime a sauter" de
        // "vraie parole peu confiante a forcer" -- les deux ont la meme forme
        // (etat blank prolonge). Toute variante de penalite blank rejouera ce
        // dilemme. Abandonne comme famille de solutions.
        //
        // ── TENTATIVE 3 (14h32) — retry force vers l'etat final (s-1) — ECHEC
        // Sur segment fige stagnant, refaire le backtrace depuis le tout
        // dernier etat pour forcer une couverture complete. Echec SILENCIEUX :
        // la liste candidate va jusqu'a 80 mots (maxAlignWords, un plafond de
        // securite, PAS un objectif), or un segment de 2-3s ne peut pas
        // physiquement atteindre l'etat final de 80 mots -> score -infini ->
        // backtrace degenere, aucune correction, log strictement identique a
        // avant le fix. Piege : ressemblait a "le fix ne marche pas" alors que
        // le fix ne s'executait jamais.
        //
        // ── TENTATIVE 4 (14h45) — retry vers maxReachable — ABANDONNE
        // Corrige la tentative 3 en visant l'etat le plus loin ATTEIGNABLE
        // (score fini) plutot que s-1. Compile et deploye, mais abandonne
        // avant validation au profit du mecanisme retenu : maxReachable est
        // une borne PHYSIQUE, pas une preuve -- sur une recitation lente, des
        // frames suffisantes pour emettre des tokens ne prouvent pas qu'ils
        // ont ete prononces, donc risque de sur-avancer et de juger des mots
        // jamais dits.
        //
        // ── RETENU (14h50) — position attestee par le decodage LIBRE ──
        // Constat device decisif : la legende "entendu" (decodage libre,
        // argmax par frame sur les MEMES logprobs) suivait parfaitement la
        // recitation pendant que le coloriage (DP forcee) restait bloque. Le
        // decodage libre ne souffre pas du blocage parce qu'il decide frame
        // par frame independamment -- il n'a jamais l'option "rester en
        // arriere" qui piege la DP cumulative.
        //
        // Donc : le decodage libre atteste JUSQU'OU le recitateur est alle
        // (position) et la DP forcee garde son seul vrai role, JUGER la
        // justesse (harakat, sin/sad) sur les mots ainsi situes.
        //
        // POINT CRITIQUE A NE JAMAIS CASSER : le decodage libre ne doit
        // JAMAIS decider du rouge/vert. Le modele, entraine sur le Coran,
        // "corrige" vers la forme canonique dans son argmax -- juger sur son
        // texte ferait disparaitre precisement les erreurs qu'on veut voir
        // (une fatha lue a la place d'une kasra ressort canonique). Seul le
        // gop voit l'hesitation sous-jacente. Le decodage libre ne dit QUE
        // "le bloc va jusqu'ici".
        private const val RETRY_STALL_MIN_FRAMES = MIN_FRAMES_FOR_JUDGMENT

        // Rescoring NLL : padding (frames) ajoute de part et d'autre de la
        // fenetre attribuee au mot par la DP. ~80ms/frame.
        private const val RESCORE_PAD_FRAMES = 2

        // Fenetre de recherche (en tokens du decodage libre) pour retrouver un
        // token attendu. Bornee : au-dela, un match est plus probablement une
        // coincidence lointaine qu'un vrai alignement. Assez large pour sauter
        // le residu audio des mots deja traites qui traine en tete de buffer
        // apres un recul d'ancre.
        private const val FREE_MATCH_LOOKAHEAD = 12
    }

    /** Resultat par mot. [index] est l'index ABSOLU dans le texte attendu complet.
     *  [rescoreMargin]/[rescoreHeard] : rescoring NLL tete-a-tete (2026-07-19,
     *  valide offline cf. ConfusableVariants) — NLL(mot attendu) - NLL(meilleure
     *  variante confusable), calcule sur la fenetre de frames du mot. Marge > 0 :
     *  une variante explique MIEUX l'audio que le mot attendu (signal ABSOLU,
     *  la ou le gop est relatif et aveugle quand le modele est convaincu du
     *  canonique : forced == free => gop=0 => vert a tort). Null si non calcule
     *  (pas de variantes fournies, passe non finale, ou cible infaisable).
     *  SIGNAL DIAGNOSTIQUE pour l'instant : logge cote Dart ([GOP] rescore=...),
     *  ne participe PAS au verdict tant que le seuil n'est pas calibre sur
     *  device (les marges par-fenetre n'ont pas la meme echelle que les marges
     *  par-clip mesurees offline). */
    data class WordResult(
        val index: Int,
        val gop: Double,
        val forced: Double,
        val covered: Boolean,
        val actual: String,
        val rescoreMargin: Double? = null,
        val rescoreHeard: String? = null,
    )

    /**
     * [frontier] : index ABSOLU du premier mot que l'audio ne couvre PAS
     * completement (= le mot "en cours" cote UI). Les mots avant frontier sont
     * juges fiables ; le mot a frontier peut apparaitre dans [words] avec
     * covered=false (partiellement entendu, a ne pas juger sur un apercu).
     * [deferredIndex] : index ABSOLU du mot exclu de [words] par le garde-fou
     * MIN_FRAMES_FOR_JUDGMENT sur ce passage (null si aucun mot differe) --
     * l'appelant (BufferedTranscriber) doit le repasser en [forceJudgeIndex]
     * au prochain appel FINAL pour garantir un jugement au plus tard a la
     * 2e tentative (ne jamais differer indefiniment le meme mot).
     */
    data class Result(
        val frontier: Int,
        val words: List<WordResult>,
        val deferredIndex: Int? = null,
    )

    /**
     * Aligne les mots attendus (tokens par mot, a partir de l'ancre [anchor],
     * indices absolus) sur [logprobs] (T frames x vocab+1). L'alignement est
     * PARTIEL : le meilleur etat final peut etre au milieu de la sequence --
     * l'audio ne contient peut-etre que les premiers mots (c'est la frontiere).
     * Retourne null si rien d'alignable (pas de frames, pas de tokens).
     */
    fun align(
        logprobs: Array<FloatArray>,
        wordTokens: List<IntArray>,
        anchor: Int,
        forceJudgeIndex: Int = -1,
        isFinal: Boolean = false,
        // Variantes confusables par mot (parallele a wordTokens) : (texte, ids).
        // Fournies -> rescoring NLL par mot sur les passes FINALES uniquement
        // (les apercus sont re-analyses de toute facon, et c'est le verdict
        // final qu'on cherche a fiabiliser -- pas de cout DP inutile par passe).
        wordVariants: List<List<Pair<String, IntArray>>>? = null,
    ): Result? {
        val t = logprobs.size
        if (t == 0 || wordTokens.isEmpty()) return null

        // Utilise pour TOUT ce qui juge la prononciation (DP forcee, gop,
        // rescoring) -- jamais pour le decodage libre (`actual`/`entendu`),
        // qui reste sur `logprobs` brut pour continuer a exposer les symboles
        // de regles tajwid. Cf. stripRuleSymbolMass plus haut.
        val scoringLp = stripRuleSymbolMass(logprobs)

        // Sequence plate de tokens + mot proprietaire de chaque token.
        val flat = ArrayList<Int>()
        val owner = ArrayList<Int>()
        wordTokens.forEachIndexed { w, toks ->
            for (tok in toks) {
                flat.add(tok)
                owner.add(w)
            }
        }
        val n = flat.size
        if (n == 0) return null
        // Etats etendus CTC : [blank, tok0, blank, tok1, ..., tokN-1, blank]
        // etat 2i = blank AVANT le token i ; etat 2i+1 = token i.
        val s = 2 * n + 1

        val negInf = Double.NEGATIVE_INFINITY
        var prev = DoubleArray(s) { negInf }
        var cur = DoubleArray(s) { negInf }
        // Retro-pointeurs : 0 = rester, 1 = depuis s-1, 2 = depuis s-2 (saut de
        // blank entre deux tokens differents).
        val bp = Array(t) { ByteArray(s) }

        fun emit(ti: Int, si: Int): Double {
            val lp = scoringLp[ti]
            return if (si % 2 == 0) lp[blankId].toDouble()
            else lp[flat[(si - 1) / 2]].toDouble()
        }

        prev[0] = emit(0, 0)
        if (s > 1) prev[1] = emit(0, 1)

        for (ti in 1 until t) {
            for (si in 0 until s) {
                var best = prev[si]
                var from: Byte = 0
                if (si >= 1 && prev[si - 1] > best) {
                    best = prev[si - 1]; from = 1
                }
                if (si >= 3 && si % 2 == 1 &&
                    flat[(si - 1) / 2] != flat[(si - 3) / 2] &&
                    prev[si - 2] > best
                ) {
                    best = prev[si - 2]; from = 2
                }
                cur[si] = if (best == negInf) negInf else best + emit(ti, si)
                bp[ti][si] = from
            }
            val tmp = prev; prev = cur; cur = tmp
            java.util.Arrays.fill(cur, negInf)
        }

        // Fin PARTIELLE : meilleur etat final sur TOUS les etats (pas seulement
        // le dernier) -- l'audio peut s'arreter au milieu du texte attendu. Le
        // chemin qui explique le mieux l'audio gagne naturellement : rester en
        // arriere pendant que de la parole existe force des blanks a logprob
        // faible sur ces frames.
        var bestEnd = 0
        var bestVal = prev[0]
        for (si in 1 until s) {
            if (prev[si] > bestVal) {
                bestVal = prev[si]; bestEnd = si
            }
        }
        if (bestVal == negInf) return null

        val w = wordTokens.size

        // Backtrace + agregation par mot + jugement, pour un etat final
        // donne. Factorise pour permettre une seconde tentative "couverture
        // complete" (cf. RETRY_STALL_MIN_FRAMES) sans refaire la DP.
        fun buildFrom(endState: Int): Pair<Result, Int> {
            val path = IntArray(t)
            var siCur = endState
            for (ti in t - 1 downTo 0) {
                path[ti] = siCur
                if (ti > 0) siCur -= bp[ti][siCur]
            }

            val wordFirstFrame = IntArray(w) { -1 }
            val wordLastFrame = IntArray(w) { -1 }
            val wordForcedSum = DoubleArray(w)
            val wordFreeSum = DoubleArray(w)
            val wordFrames = IntArray(w)

            for (ti in 0 until t) {
                val si = path[ti]
                if (si % 2 == 0) continue
                val tokIdx = (si - 1) / 2
                val wIdx = owner[tokIdx]
                if (wordFirstFrame[wIdx] < 0) wordFirstFrame[wIdx] = ti
                wordLastFrame[wIdx] = ti
                // Chadda nu (cf. bareShaddaTokens plus haut) : sa frame est
                // toujours comptee dans les bornes du mot (texte affiche
                // inchange) mais JAMAIS dans le gop -- meme logique que les
                // frames blank, exclues plus bas via `si % 2 == 0`.
                val expectedTok = flat[tokIdx]
                if (expectedTok < bareShaddaTokens.size && bareShaddaTokens[expectedTok]) continue
                // scoringLp (deja masque+renormalise, cf. stripRuleSymbolMass) :
                // corrige `forced` en plus de `free` -- la simple exclusion du
                // MAX ci-dessous ne suffisait pas, cf. commentaire 2026-07-20 soir.
                val lp = scoringLp[ti]
                wordForcedSum[wIdx] += lp[expectedTok].toDouble()
                // Le max ignore quand meme explicitement les colonnes-symboles
                // (deja a -infini apres renormalisation, mais garde-fou
                // redondant volontaire si jamais un cas limite flottant les
                // laissait finis) : une regle bien realisee ne doit jamais
                // faire monter `free` et donc chuter le gop d'un mot
                // pourtant parfaitement recite.
                var mx = Float.NEGATIVE_INFINITY
                for (c in lp.indices) {
                    if (c < ruleSymbolTokens.size && ruleSymbolTokens[c]) continue
                    if (lp[c] > mx) mx = lp[c]
                }
                wordFreeSum[wIdx] += mx.toDouble()
                wordFrames[wIdx]++
            }

            // Frontiere : etat 2i (blank avant token i) => tokens 0..i-1
            // termines, prochain a dire = i ; etat 2i+1 => token i en cours.
            // Index du token frontiere = endState / 2 (division entiere).
            val frontierTok = endState / 2
            val frontierWordRel = if (frontierTok >= n) w else owner[frontierTok]

            val results = ArrayList<WordResult>(w)
            var deferredIndex: Int? = null
            var lastUsedFrame = -1
            for (wi in 0 until w) {
                if (wordFrames[wi] == 0) {
                    // Bug corrige 2026-07-16 (revue de code, confirme par un
                    // cas device reel : 17 tentatives consecutives sur le
                    // meme mot, l'ancre n'avancant jamais) -- CE break
                    // s'executait AVANT tout check de forceJudgeIndex, donc
                    // meme un mot force en 2e chance qui obtient ENCORE zero
                    // frame de la DP ressortait sans jugement ET sans
                    // deferredIndex -> BufferedTranscriber remettait
                    // deferredOnceIndex a -1 (BufferedTranscriber.kt:200),
                    // effacant toute memoire que ce mot etait en attente :
                    // le mot pouvait boucler differer->oublier->differer a
                    // l'infini, jamais tranche.
                    //
                    // Fix en deux temps, pour couvrir le cycle complet :
                    //  - si ce mot est PRECISEMENT celui qu'on force (2e
                    //    chance) et qu'il n'a TOUJOURS aucune frame, c'est
                    //    le signal d'erreur le plus fort possible (le
                    //    meilleur chemin de la DP n'a litteralement aucune
                    //    place pour lui) -> jugement DEFINITIF ici (error),
                    //    sans repasser par le differe qui echouerait pareil.
                    //  - sinon (1ere fois que ce mot n'a aucune frame), le
                    //    marquer differe comme le cas "trop peu
                    //    d'opportunite" plus bas -- sinon il disparaissait
                    //    des `results` sans JAMAIS entrer dans le mecanisme
                    //    des 2 chances, silencieusement, a chaque appel.
                    if (anchor + wi == forceJudgeIndex) {
                        results.add(WordResult(
                            anchor + wi, -20.0, -20.0, wi < frontierWordRel, ""))
                    } else {
                        deferredIndex = anchor + wi
                    }
                    break
                }
                val covered = wi < frontierWordRel
                if (!covered && anchor + wi != forceJudgeIndex) {
                    // Opportunite laissee a ce mot = audio disponible depuis
                    // la fin du dernier mot CONFIRME (pas ses propres frames
                    // a lui -- cf. commentaire MIN_FRAMES_FOR_JUDGMENT) : s'il
                    // ne reste quasi rien, le segment s'est juste arrete tot
                    // (artefact de coupure) -> on differe. S'il reste
                    // beaucoup d'audio et que le modele n'y place quand meme
                    // pas ce mot, c'est un vrai signal d'erreur -> on laisse
                    // passer, jugee normalement plus bas.
                    val prevLastFrame = if (wi > 0) wordLastFrame[wi - 1] else -1
                    val framesSincePrev = (t - 1) - prevLastFrame
                    if (framesSincePrev < MIN_FRAMES_FOR_JUDGMENT) {
                        deferredIndex = anchor + wi
                        break
                    }
                }
                val forced = wordForcedSum[wi] / wordFrames[wi]
                val free = wordFreeSum[wi] / wordFrames[wi]
                val actual = greedyDecodeRange(logprobs, wordFirstFrame[wi], wordLastFrame[wi])
                var rescoreMargin: Double? = null
                var rescoreHeard: String? = null
                if (isFinal && wordVariants != null && wi < wordVariants.size &&
                    wordVariants[wi].isNotEmpty() && wordTokens[wi].isNotEmpty()
                ) {
                    // Fenetre du mot elargie de quelques frames : la DP rend
                    // parfois la main au mot suivant un peu tot (cf. bug
                    // "validation globale" ci-dessous) -- le padding redonne aux
                    // candidats les frames de bord. Tous les candidats sont
                    // scores sur la MEME fenetre : comparaison equitable.
                    val rf = maxOf(0, wordFirstFrame[wi] - RESCORE_PAD_FRAMES)
                    val rt = minOf(t - 1, wordLastFrame[wi] + RESCORE_PAD_FRAMES)
                    val nllExpected = ctcForwardNll(scoringLp, rf, rt, wordTokens[wi])
                    if (nllExpected.isFinite()) {
                        var bestNll = Double.POSITIVE_INFINITY
                        var bestText: String? = null
                        for ((text, toks) in wordVariants[wi]) {
                            if (toks.isEmpty()) continue
                            val nll = ctcForwardNll(scoringLp, rf, rt, toks)
                            if (nll < bestNll) {
                                bestNll = nll; bestText = text
                            }
                        }
                        if (bestText != null && bestNll.isFinite()) {
                            rescoreMargin = nllExpected - bestNll
                            rescoreHeard = bestText
                        }
                    }
                }
                results.add(WordResult(anchor + wi, forced - free, forced, covered, actual,
                    rescoreMargin, rescoreHeard))
                lastUsedFrame = maxOf(lastUsedFrame, wordLastFrame[wi])
            }
            return Result(anchor + frontierWordRel, results, deferredIndex) to lastUsedFrame
        }

        val (natural, naturalLastFrame) = buildFrom(bestEnd)

        if (isFinal) {
            // Decodage libre du segment ENTIER, calcule une seule fois --
            // reutilise ci-dessous par la validation globale ET par le filet
            // de secours existant (stall).
            val free = greedyTokenIds(logprobs, 0, t - 1)

            // ── Validation GLOBALE prioritaire (idee utilisateur 2026-07-16 soir) ──
            // Bug reel observe sur device, MEME passe/memes logprobs :
            //   segment ENTIER (decodage libre, sans frontiere) : "بَلَوْنَـٰهُمْ"
            //   correct et complet.
            //   mot ISOLE (actual = greedyDecodeRange borne aux frames que LA DP
            //   a attribuees a ce mot) : "بَلَـٰهُمْ", TRONQUE -- la DP avait rendu
            //   la main au mot suivant un peu trop tot (confiance faible sur la
            //   fin du mot), amputant la plage de frames de ce mot precis.
            //   Le gop lui-meme etait bon (-0.01, quasi parfait) : SEUL le texte
            //   `actual`, tronque, faisait declencher spellsDifferentWord cote
            //   Dart (le texte tronque ne "matche" plus l'attendu) -> jugement
            //   "unclear" au lieu de "correct" pour un mot pourtant bien recite.
            //
            // Fix CIBLE : si le decodage libre GLOBAL confirme la totalite des
            // `w` mots attendus (wordSpansFromFree renvoie une plage pour
            // CHACUN, aucun mot manquant) ET que `natural` couvre deja tous
            // les mots (rien n'a ete laisse de cote, juste potentiellement mal
            // decoupe) -- on ne touche PAS au score gop/forced (qui garde
            // toute sa sensibilite habituelle, y compris sur les harakat) --
            // on remplace SEULEMENT le texte `actual` de chaque mot par celui
            // du decodage libre global, qui n'a jamais ete borne par une
            // frontiere de frames fragile.
            //
            // Compromis assume (pas une regression nouvelle) : la tolerance de
            // wordSpansFromFree (>=50% des tokens d'un mot retrouves, meme
            // regle que coveredWordsFromFree ci-dessous) peut laisser un mot
            // "confirme" meme si UN token (ex. une harakat) differe legerement
            // -- mais gop reste le seul juge du VERDICT ici, donc cette
            // tolerance n'affecte QUE le texte affiche, pas la couleur.
            //
            // Bug corrige 2026-07-16 (constate sur device : jamais declenchee
            // en usage reel, malgre des cas ou elle aurait du s'appliquer) --
            // la condition comparait natural.words.size a `w` = wordTokens.size,
            // qui est la fenetre de LOOKAHEAD complete (jusqu'a maxAlignWords=80
            // mots futurs, cf. BufferedTranscriber), pas le nombre de mots
            // reellement prononces dans ce segment audio de quelques secondes.
            // Exiger que les 80 mots de la fenetre soient TOUS confirmes par le
            // decodage libre ne peut essentiellement jamais arriver. La bonne
            // portee est `natural.words.size` lui-meme (les mots pour lesquels
            // la DP a deja trouve des preuves, correctes ou non) : on ne valide
            // QUE ce sous-ensemble deja couvert, jamais au-dela.
            val spans = if (natural.words.isNotEmpty())
                wordSpansFromFree(free, wordTokens.take(natural.words.size)) else null
            if (spans != null) {
                val corrected = natural.words.map { r ->
                    val wi = r.index - anchor
                    if (wi in spans.indices) r.copy(actual = decodeFreeSpan(free, spans[wi])) else r
                }
                DiagnosticLog.log(TAG,
                    "validation globale : texte 'actual' recalcule via decodage libre " +
                            "(${natural.words.size} mots confirmes, ancre=$anchor)")
                return Result(natural.frontier, corrected, natural.deferredIndex)
            }

            // Filet de secours pilote par le decodage LIBRE (cf. companion
            // object). Seulement quand il reste de l'audio non explique apres
            // le dernier mot obtenu, et que le decodage libre atteste
            // STRICTEMENT plus de mots que la DP n'en a couverts.
            if (natural.words.size < w) {
                val framesSinceLast = (t - 1) - naturalLastFrame
                if (framesSinceLast >= RETRY_STALL_MIN_FRAMES) {
                    val attested = coveredWordsFromFree(free, wordTokens)
                    if (attested > natural.words.size) {
                        // Etat = dernier token du dernier mot atteste. Non
                        // atteignable (score -infini) => on ne force pas : le
                        // backtrace serait degenere.
                        var lastTok = -1
                        for (i in owner.indices) if (owner[i] == attested - 1) lastTok = i
                        val target = if (lastTok >= 0) 2 * lastTok + 1 else -1
                        if (target in 0 until s && prev[target] != negInf) {
                            val (byFree, _) = buildFrom(target)
                            if (byFree.words.size > natural.words.size) {
                                DiagnosticLog.log(TAG,
                                    "blocage rattrape par decodage libre : DP=${natural.words.size} mot(s) " +
                                            "-> atteste=$attested (ancre=$anchor)")
                                return byFree
                            }
                        }
                    }
                }
            }
        }
        return natural
    }

    /** -log P(tokens | frames [from..toIncl]) sous le CTC : algorithme forward
     *  standard (somme sur TOUS les chemins, log-sum-exp) sur les etats etendus
     *  [blank, tok0, blank, ..., tokN-1, blank] -- equivalent Kotlin de
     *  torch.nn.functional.ctc_loss(reduction="sum"), le MEME calcul que la
     *  validation offline (benchmark/variant_rescoring_eval.py /
     *  constrained_decoding_eval.py). Distinct de la DP Viterbi de align()
     *  (meilleur chemin) : ici on veut la probabilite totale de la sequence,
     *  comparable entre candidats. POSITIVE_INFINITY si infaisable (fenetre
     *  trop courte pour la sequence) -- jamais 0, qui serait faussement
     *  "excellent" (cf. zero_infinity=False cote Python, meme raison). */
    private fun ctcForwardNll(
        logprobs: Array<FloatArray>,
        from: Int,
        toIncl: Int,
        tokens: IntArray,
    ): Double {
        val nTok = tokens.size
        val tLen = toIncl - from + 1
        if (nTok == 0 || tLen <= 0) return Double.POSITIVE_INFINITY
        val s = 2 * nTok + 1
        val negInf = Double.NEGATIVE_INFINITY

        fun logAdd(a: Double, b: Double): Double {
            if (a == negInf) return b
            if (b == negInf) return a
            val m = if (a > b) a else b
            val n = if (a > b) b else a
            return m + Math.log1p(Math.exp(n - m))
        }

        fun emit(ti: Int, si: Int): Double {
            val lp = logprobs[from + ti]
            return if (si % 2 == 0) lp[blankId].toDouble()
            else lp[tokens[(si - 1) / 2]].toDouble()
        }

        var prev = DoubleArray(s) { negInf }
        var cur = DoubleArray(s)
        prev[0] = emit(0, 0)
        if (s > 1) prev[1] = emit(0, 1)
        for (ti in 1 until tLen) {
            for (si in 0 until s) {
                var acc = prev[si]
                if (si >= 1) acc = logAdd(acc, prev[si - 1])
                if (si >= 3 && si % 2 == 1 &&
                    tokens[(si - 1) / 2] != tokens[(si - 3) / 2]
                ) {
                    acc = logAdd(acc, prev[si - 2])
                }
                cur[si] = if (acc == negInf) negInf else acc + emit(ti, si)
            }
            val tmp = prev; prev = cur; cur = tmp
        }
        // Fin valide : dernier blank OU dernier token.
        val total = logAdd(prev[s - 1], if (s >= 2) prev[s - 2] else negInf)
        return if (total == negInf) Double.POSITIVE_INFINITY else -total
    }

    /** IDs de tokens du decodage LIBRE sur [from..toIncl] : argmax par frame,
     *  repetitions collapsees, blanks retires (sequence CTC greedy classique).
     *  Sert de PREUVE de position (cf. companion object) -- jamais de jugement. */
    private fun greedyTokenIds(logprobs: Array<FloatArray>, from: Int, toIncl: Int): IntArray {
        val ids = ArrayList<Int>()
        var prevBest = -1
        for (ti in from..toIncl) {
            val frame = logprobs[ti]
            var best = 0
            var bestVal = frame[0]
            for (c in 1 until frame.size) {
                if (frame[c] > bestVal) { bestVal = frame[c]; best = c }
            }
            if (best != prevBest && best != blankId) ids.add(best)
            prevBest = best
        }
        return ids.toIntArray()
    }

    /** Combien de mots attendus (depuis l'ancre, dans l'ordre) le decodage
     *  LIBRE atteste avoir entendu. Tolerant : un mot compte des que la MOITIE
     *  de ses tokens est retrouvee dans l'ordre -- le modele produit
     *  regulierement des variantes proches (observe : "وَٱلْمْدُ" pour
     *  "ٱلْحَمْدُ"), et exiger un match exact ferait echouer le rattrapage
     *  precisement quand il sert. Le balayage est monotone et borne
     *  (FREE_MATCH_LOOKAHEAD) : le residu audio de mots deja traites en tete
     *  de buffer (apres un recul d'ancre) est naturellement saute, ses tokens
     *  ne matchant pas le mot attendu courant. */
    private fun coveredWordsFromFree(free: IntArray, wordTokens: List<IntArray>): Int {
        var fi = 0
        var covered = 0
        for (toks in wordTokens) {
            if (toks.isEmpty()) break
            var matched = 0
            var lastHit = -1
            var probe = fi
            for (tok in toks) {
                var j = probe
                val limit = minOf(free.size, probe + FREE_MATCH_LOOKAHEAD)
                while (j < limit && free[j] != tok) j++
                if (j < limit) {
                    matched++; probe = j + 1; lastHit = j
                }
            }
            if (lastHit < 0 || matched * 2 < toks.size) break
            fi = lastHit + 1
            covered++
        }
        return covered
    }

    /** Comme [coveredWordsFromFree] (meme regle de tolerance, 50% des tokens
     *  d'un mot retrouves dans l'ordre), mais retourne en plus la plage
     *  d'indices dans [free] associee a CHAQUE mot -- permet d'extraire un
     *  texte `actual` qui ne depend PAS des frontieres de frames choisies par
     *  la DP (cf. validation globale dans align()). Tout-ou-rien : retourne
     *  null des qu'UN mot n'est pas confirme (pas de plage partielle fiable). */
    private fun wordSpansFromFree(free: IntArray, wordTokens: List<IntArray>): List<IntRange>? {
        var fi = 0
        val spans = ArrayList<IntRange>(wordTokens.size)
        for (toks in wordTokens) {
            if (toks.isEmpty()) return null
            var matched = 0
            var firstHit = -1
            var lastHit = -1
            var probe = fi
            for (tok in toks) {
                var j = probe
                val limit = minOf(free.size, probe + FREE_MATCH_LOOKAHEAD)
                while (j < limit && free[j] != tok) j++
                if (j < limit) {
                    matched++; probe = j + 1; lastHit = j
                    if (firstHit < 0) firstHit = j
                }
            }
            if (lastHit < 0 || matched * 2 < toks.size) return null
            spans.add(firstHit..lastHit)
            fi = lastHit + 1
        }
        return spans
    }

    /** Detokenise une plage d'indices dans un tableau de tokens LIBRES (deja
     *  collapse par greedyTokenIds -- pas de blanks/repetitions a filtrer ici). */
    private fun decodeFreeSpan(free: IntArray, span: IntRange): String {
        val sb = StringBuilder()
        for (i in span) {
            val id = free[i]
            if (id < vocab.size) sb.append(vocab[id])
        }
        return sb.toString().replace('▁', ' ').trim()
    }

    /** Decodage glouton LIBRE restreint a une plage de frames [from..toIncl] --
     *  donne "ce que le modele a reellement entendu" sur la plage du mot. */
    private fun greedyDecodeRange(logprobs: Array<FloatArray>, from: Int, toIncl: Int): String {
        val ids = greedyTokenIds(logprobs, from, toIncl)
        val sb = StringBuilder()
        for (id in ids) if (id < vocab.size) sb.append(vocab[id])
        return sb.toString().replace('▁', ' ').trim()
    }
}

/**
 * Tokenizer BPE pour l'alignement force. Source PRIMAIRE : dictionnaire
 * mot -> IDs precalcule avec le VRAI tokenizer NeMo (SentencePiece),
 * cf. benchmark/build_word_token_lookup.py -- couvre tout le vocabulaire
 * coranique (18k+ mots, verifie 2026-07-11), zero risque de divergence avec
 * ce que le modele a reellement appris a predire. Repli : correspondance
 * gloutonne la plus longue sur les pieces du vocabulaire, pour un mot absent
 * du dictionnaire (texte hors-Coran, ex. Arabic Speech Corpus si jamais
 * utilise ici, ou dictionnaire pas encore deploye/a jour) -- verifie
 * coincider avec le vrai tokenizer sur plusieurs mots testes, mais reste une
 * approximation, jamais la source de verite si le dictionnaire est present.
 * Le texte d'entree doit etre normalise comme le corpus d'entrainement
 * (ArabicNormalizer.normalizeTraining cote Dart -- PAS normalizeStrict, qui
 * fusionne des lettres que le modele distingue, cf. FONCTIONNALITES_FUTURES.md §5.3).
 */
class CtcTokenizer(vocab: List<String>, private val wordLookup: Map<String, IntArray>? = null) {
    companion object {
        private const val TAG = "CtcTokenizer"
    }

    private val pieceToId = HashMap<String, Int>(vocab.size * 2)
    private val maxPieceLen: Int
    private var lookupHits = 0
    private var lookupMisses = 0

    init {
        var maxLen = 1
        vocab.forEachIndexed { id, piece ->
            pieceToId[piece] = id
            if (piece.length > maxLen) maxLen = piece.length
        }
        maxPieceLen = maxLen
        if (wordLookup != null) {
            DiagnosticLog.log(TAG, "dictionnaire mot->tokens charge : ${wordLookup.size} mots")
        }
    }

    fun tokenizeWord(word: String): IntArray {
        wordLookup?.get(word)?.let {
            lookupHits++
            return it
        }
        if (wordLookup != null) {
            lookupMisses++
            DiagnosticLog.log(TAG, "mot absent du dictionnaire precalcule, repli greedy : \"$word\" " +
                    "(hits=$lookupHits misses=$lookupMisses)")
        }
        return tokenizeWordGreedy(word)
    }

    /** Tokenisation SILENCIEUSE pour les variantes confusables generees
     *  (rescoring NLL, cf. ConfusableVariants) : quasi aucune n'existe dans le
     *  dictionnaire precalcule (mots volontairement hors-Coran) -- logger
     *  chaque repli en ferait des milliers par sourate. Meme calcul que
     *  tokenizeWord, sans logs ni compteurs. Le greedy est une approximation
     *  du vrai tokenizer (verifie coincider sur les mots testes) ; la
     *  validation offline utilisait le vrai tokenizer -- ecart possible a
     *  surveiller si les marges device semblent incoherentes. */
    fun tokenizeVariantQuiet(word: String): IntArray {
        wordLookup?.get(word)?.let { return it }
        return tokenizeWordGreedy(word)
    }

    /** Repli : correspondance gloutonne la plus longue (prefixe "▁" = debut de
     *  mot SentencePiece). Caracteres hors vocabulaire ignores avec un log. */
    private fun tokenizeWordGreedy(word: String): IntArray {
        val target = "▁$word"
        val ids = ArrayList<Int>(target.length)
        var pos = 0
        while (pos < target.length) {
            var matched = false
            var len = minOf(maxPieceLen, target.length - pos)
            while (len >= 1) {
                val id = pieceToId[target.substring(pos, pos + len)]
                if (id != null) {
                    ids.add(id); pos += len; matched = true; break
                }
                len--
            }
            if (!matched) {
                DiagnosticLog.log(TAG, "caractere hors vocab ignore : '${target[pos]}' dans \"$word\"")
                pos++
            }
        }
        return ids.toIntArray()
    }
}

/** Charge le dictionnaire mot->IDs precalcule (JSON plat {mot: [ids...]}).
 *  Retourne null si absent/invalide -- CtcTokenizer se rabat alors entierement
 *  sur le greedy (comportement identique a avant l'introduction du lookup). */
fun loadWordTokenLookup(path: String): Map<String, IntArray>? {
    return try {
        val json = org.json.JSONObject(java.io.File(path).readText(Charsets.UTF_8))
        val map = HashMap<String, IntArray>(json.length() * 2)
        val keys = json.keys()
        while (keys.hasNext()) {
            val word = keys.next()
            val arr = json.getJSONArray(word)
            val ids = IntArray(arr.length()) { arr.getInt(it) }
            map[word] = ids
        }
        map
    } catch (e: Exception) {
        DiagnosticLog.log("CtcTokenizer", "echec chargement word_tokens.json ($path): ${e.message}")
        null
    }
}

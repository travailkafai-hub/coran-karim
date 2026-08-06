package com.corankarim.coran_karim.recitation2

/**
 * COUCHE D — LOCALISATION.
 *
 * Repond a UNE question : quelle tranche du texte attendu cette fenetre
 * couvre-t-elle ?
 *
 * CONTRAT :
 *  - entree : logprobs de la fenetre, texte attendu, dernier mot verrouille ;
 *  - AUCUN effet de bord. D ne deplace aucun etat global, ne verrouille rien,
 *    n'abandonne aucun mot, ne connait aucun seuil de couleur ;
 *  - peut repondre `null` ("je ne sais pas") — la fenetre ne produit alors
 *    aucun jugement. C'est un resultat legitime, pas un echec a compenser.
 *
 * TROIS DEFAUTS DE LA v1 QUE CE CONTRAT SUPPRIME :
 *
 * 1. [PIEGE] resync_avant_seulement — `findResyncOffset` ne cherchait QU'EN
 *    AVANT (`bestOff > anchor`). Un recitateur qui REPETE ne pouvait
 *    structurellement pas etre suivi, et le banc (audio lineaire) ne pouvait
 *    pas produire le cas. Ici la recherche est BORNEE DES DEUX COTES
 *    ([reculMax] / [avanceMax]).
 *
 * 2. La regression v22 (`305db63`, 8,16 % -> 13,40 %, annulee) venait du
 *    COUPLAGE "deplacer l'ancre" => "les mots derriere sont perdus". Ici les
 *    deux operations sont decorrelees : deplacer la bande n'abandonne rien.
 *    Les mots depasses restent dans le registre de preuves, eligibles a
 *    n'importe quelle fenetre ulterieure — et leur audio est toujours dans le
 *    flux brut. Il n'y a plus d'ancre mutable dont l'erreur se propage : la
 *    position est REESTIMEE a chaque fenetre depuis l'acoustique, jamais
 *    incrementee depuis l'historique.
 *
 * 3. La comparaison porte sur du TEXTE, pas sur des ids de tokens — piste
 *    mesuree `4606d64` (Maryam 15,46 % -> 9,18 %, rouges 10 -> 6), restee sans
 *    objet en v1 parce que `RESYNC_ACTIF` etait passe a false.
 */
class Localisateur(
    private val pieces: List<String>,
    private val blank: Int,
    private val reculMax: Int = 12,
    /** Doit couvrir le PLUS LONG bloc possible. Avec un decoupage aux silences
     *  reels un bloc peut porter 40 mots et plus ; une avance de 24 tronquait
     *  la region de recherche et l'ancre decrochait au mot 82 (mesure du
     *  2026-07-30). Ce n'est pas un seuil de tolerance : c'est la taille de la
     *  fenetre de recherche, elle doit juste etre assez grande. */
    private val avanceMax: Int = 80,
    private val margeAval: Int = 3,
    /**
     * Nombre d'appariements exiges pour accepter une position.
     *
     * Etait a 2 SANS AUCUNE JUSTIFICATION ECRITE -- contrairement a [reculMax]
     * et [avanceMax], qui portent chacun leur mesure. C'etait donc une valeur
     * par defaut, pas une decision mesuree.
     *
     * CE QUE 2 COUTAIT (device, 234 fenetres, 2026-08-02) : 67 fenetres
     * refusees = 29 %, dont 60 en `score-insuffisant`. Le detail montre des
     * fenetres qui n'avaient decode QU'UN mot : `entendus=1` -- elles ne
     * pouvaient donc mathematiquement jamais atteindre 2, quel que soit le
     * modele. Une fenetre de 4 s moins 1,04 s de contexte droit ne porte que
     * 1 a 3 mots au debit de ce recitateur.
     *
     * POURQUOI 1 N'EST PAS UN ASSOUPLISSEMENT DU JUGEMENT (raisonnement
     * utilisateur, 2026-08-02) : une bande n'est qu'une HYPOTHESE de position.
     * Pour FIGER un mot, le Decideur exige que le decodage libre l'ait emis
     * exactement la ou l'alignement force le place (« deux mesures
     * independantes valent deux fenetres »). Une bande mal placee n'obtient
     * pas cet accord : le mot reste Provisoire et la fenetre suivante le
     * corrige. Le doute se reforme donc tout seul -- le mecanisme existe deja,
     * porte par l'attestation et non par ce compteur.
     *
     * RISQUE RESIDUEL, a surveiller dans la mesure : des couleurs provisoires
     * qui clignotent (le contrat l'autorise), et surtout un mot tres frequent
     * (`مِن`, `إِن`) qui place la bande au hasard dans une region de 92 mots.
     * Le juge est le TAUX DE MOTS NON VERTS, pas le nombre de refus.
     *
     * ── PORTAGE SUR CETTE BRANCHE (2026-08-04) ────────────────────────────
     * Mesure qui l'impose ICI, sourate 2, depart v1, 150 s, 3 passes :
     *   branche `streaming` (minAppariements = 1) : 4,5 % de fenetres
     *     refusees, 1,68 % de mots non verts ;
     *   cette branche (minAppariements = 2)       : 26,0 % de fenetres
     *     refusees, 9,24 % de mots non verts (7,77 / 9,24 / 9,24).
     * L'ecart etait PREEXISTANT et n'avait rien a voir avec la tete 3 ni avec
     * le modele a trois tetes -- les deux ont ete innocentes par la mesure
     * (tete 3 coupee : taux inchange ; logprobs des deux modeles identiques
     * au bit pres sur 20 s de recitation reelle).
     */
    private val minAppariements: Int = 1,
) {
    /**
     * @param i0 premier mot attendu couvert par la fenetre (inclus)
     * @param i1 dernier mot attendu couvert (inclus)
     * @param confiance appariements / mots entendus, dans [0,1]
     * @param recul vrai si la bande part EN ARRIERE du dernier mot verrouille
     *   (le recitateur repete) — journalise, jamais silencieux.
     * @param attestes index de mot attendu -> plage de frames ou le DECODAGE
     *   LIBRE l'a effectivement entendu. C'est la seule preuve positive qu'un
     *   mot a ete PRONONCE ; l'alignement force, lui, place toujours tous les
     *   mots qu'on lui donne, prononces ou non.
     */
    data class Bande(
        val i0: Int,
        val i1: Int,
        val confiance: Float,
        val recul: Boolean,
        val attestes: Map<Int, IntRange>,
        /**
         * Mots dont le decodage libre a emis le texte EXACT, harakat comprises.
         *
         * [attestes] sert a LOCALISER : il compare des mots normalises (sans
         * harakat), parce que les harakat sont peu fiables pour retrouver une
         * position. Mais un appariement normalise NE PROUVE PAS que le mot est
         * juste -- deux mots qui ne different que par une harakat s'y
         * confondent.
         *
         * DEFAUT TROUVE PAR L'UTILISATEUR EN SE SERVANT DE L'APP (2026-07-30) :
         * « j'ai fait des fautes deliberees, il les colorie [vert] alors que le
         * texte entendu en bas montre bien que j'ai mal dit le mot ». Le
         * decodage libre entendait la faute, l'attestation normalisee la
         * gommait, et la regle « atteste + vert => definitif » verrouillait un
         * vert sur UNE seule observation.
         *
         * Normaliser pour TROUVER, comparer exactement pour CONFIRMER.
         */
        val attestesExacts: Set<Int>,
    )

    /**
     * @param framesMinParMot minimum PHYSIQUE de frames pour un mot donne
     *   (n tokens => n frames). Sert a savoir combien de mots peuvent tenir
     *   dans l'audio libre en tete de bloc -- rien de plus.
     */
    fun localiser(
        logprobs: Array<FloatArray>,
        motsAttendus: List<String>,
        dernierVerrouille: Int,
        framesMinParMot: ((Int) -> Int)? = null,
    ): Bande? {
        if (motsAttendus.isEmpty() || logprobs.isEmpty()) return null
        val entendusAvecFrames = Decodage.motsAvecFrames(logprobs, pieces, blank)
            .map { it to NormalisationComparaison.normaliser(it.texte) }
            .filter { it.second.isNotEmpty() }
        if (entendusAvecFrames.isEmpty()) return null
        val entendus = entendusAvecFrames.map { it.second }

        val attendus = motsAttendus.map { NormalisationComparaison.normaliser(it) }
        val depart = (dernierVerrouille + 1).coerceIn(0, motsAttendus.size - 1)
        val min = (depart - reculMax).coerceAtLeast(0)
        val max = (depart + avanceMax).coerceAtMost(motsAttendus.size - 1)

        // UNE seule LCS sur toute la region : elle trouve d'elle-meme la
        // correspondance, il n'y a pas de « point de depart » a balayer.
        val (score, _, attestes) =
            apparier(entendus, attendus, min, entendusAvecFrames, max,
                     framesMinParMot)
        if (score < minAppariements || attestes.isEmpty()) return null

        // UN SEUL APPARIEMENT SUR UN MOT QUI SE REPETE NE SUFFIT PAS
        // (2026-08-05). Ne touche PAS a [minAppariements] (=1), deja mesure
        // et retenu contre 2 (4,5% de fenetres refusees / 1,68% de mots non
        // verts, contre 26% / 9,24% -- cf. le commentaire de
        // [minAppariements]). Ce meme commentaire nommait deja le risque
        // sans le traiter : « un mot tres frequent (`مِن`, `إِن`) qui place
        // la bande au hasard dans une region de 92 mots ».
        //
        // MESURE QUI L'IMPOSE (session live, 2026-08-05) : le recitateur
        // repete "إِنَّ" (mot 40, verset 2:6) pendant plus d'une minute sans
        // que l'ancre n'avance -- `minAppariements=1` a laisse un unique
        // appariement fortuit sur "إِن"/"مِن" ailleurs dans la region de
        // recherche (]min,max], 92 mots) poser toute la bande au mauvais
        // endroit, HORS de la vraie position. Avec un seul mot attendu comme
        // preuve, rien ne distingue laquelle de ses occurrences est la bonne.
        //
        // Avec DEUX appariements concordants, la SEQUENCE elle-meme leve
        // l'ambiguite (la LCS exige que le second mot suive le premier dans
        // le bon ordre relatif) -- on ne touche donc qu'au cas score == 1.
        if (score == 1) {
            val seulIdx = attestes.keys.first()
            val texte = attendus[seulIdx]
            val repetitions = (min..max).count { attendus[it] == texte }
            if (repetitions > 1) return null
        }
        // Attestation EXACTE : le texte brut entendu est-il, caractere pour
        // caractere, le mot attendu ? C'est la seule qui vaut preuve.
        val exacts = HashSet<Int>()
        for ((idx, plage) in attestes) {
            val brut = entendusAvecFrames.firstOrNull {
                it.first.premiereFrame == plage.first &&
                    it.first.derniereFrame == plage.last
            }?.first?.texte ?: continue
            if (brut == motsAttendus[idx]) exacts.add(idx)
        }

        // ── LA CORRECTION DU 2026-07-30, ET LA MESURE QUI L'IMPOSE ──────────
        //
        // La bande partait du point de DEPART DU BALAYAGE (`s`), pas du premier
        // mot reellement ATTESTE. Un bloc qui contenait les mots 12 a 25 se
        // voyait donc reclamer les mots 0 a 25 : l'alignement force devait
        // placer douze mots absents, il les entassait sur les premieres frames,
        // et le chemin de Viterbi etait corrompu sur TOUT le bloc.
        //
        // Preuve directe, meme mot, meme session :
        //     f0 (18,00 s)  mot 2  gop= 0,00   entendu="كَفَرُوا۟"
        //     f2 (13,52 s)  mot 2  gop=-21,84  entendu=""      bande=0..25
        // Le modele lit parfaitement ; c'est la bande qui etait fausse.
        //
        // Les degats croissent avec la longueur du bloc : 36,61 % de non-verts
        // avec des fenetres de 6 s, 80,00 % avec des blocs de 18 s.
        //
        // La regle est donc : on ne demande a la DP QUE ce que le decodage
        // libre atteste. `margeAval` etait une marge inventee -- exactement le
        // genre de constante que ce projet paye a chaque fois.
        var i0 = attestes.keys.min()
        val i1 = attestes.keys.max()

        // ── EXTENSION VERS L'ARRIERE : l'audio libre EN TETE de bloc ────────
        //
        // La bande allait du PREMIER au DERNIER mot atteste. Un mot dont le
        // decodage libre ne dit rien -- parce qu'il tombe au tout debut du bloc,
        // ou parce que le modele l'a mal lu -- n'entrait donc PAS dans la bande,
        // alors que SON AUDIO ETAIT DANS LE BLOC. Il n'avait aucune chance
        // d'etre juge la, et les blocs suivants le posaient sur l'audio du
        // voisin (correctement rejete par `sansCreneau`) : il finissait `omis`.
        //
        // MESURE QUI L'IMPOSE (2026-07-30, roles des telephones permutes) :
        // deux blocs de mots consecutifs perdus, 150-156 et 201-205, tous avec
        // `bord/sansCreneau`, `entendu=""` et `free` entre -0,01 et -0,22 -- le
        // modele etait CERTAIN, ces mots n'etaient simplement pas dans la
        // bande. Meme signature que le bloc 68-75 de Yusuf.
        //
        // Le critere est le meme que celui de `sansCreneau`, pris a l'envers :
        // s'il reste des frames LIBRES avant le premier mot atteste, les mots
        // qui le precedent peuvent y tenir -- autant qu'elles en portent, pas
        // un de plus. Aucune marge inventee.
        if (framesMinParMot != null) {
            var libres = attestes[i0]!!.first
            var candidat = i0 - 1
            while (candidat >= 0 && candidat > dernierVerrouille) {
                val besoin = framesMinParMot(candidat)
                if (besoin <= 0 || besoin > libres) break
                libres -= besoin
                i0 = candidat
                candidat--
            }
        }
        return Bande(
            i0 = i0,
            i1 = i1,
            confiance = score.toFloat() / entendus.size,
            recul = i0 < depart,
            attestes = attestes,
            attestesExacts = exacts,
        )
    }

    /**
     * Appariement par ALIGNEMENT (plus longue sous-sequence commune), pas par
     * balayage glouton.
     *
     * CE QUI A CHANGE LE 2026-07-30, ET POURQUOI. La version precedente
     * avancait mot par mot et ABANDONNAIT apres 3 mots entendus non reconnus
     * d'affilee. Ce « 3 » etait un seuil que rien ne justifiait, et il a coute
     * exactement ce que coutent les seuils inventes : sur des blocs longs
     * (decoupage aux silences reels, ~40 mots par bloc), trois substitutions
     * groupees suffisaient a faire decrocher l'appariement, l'ancre restait
     * bloquee au mot 82 sur 295, et 153 observations seulement etaient
     * produites au lieu de 1440.
     *
     * Une LCS n'a besoin d'aucun seuil : les insertions (le modele entend un
     * mot de trop) et les suppressions (il en avale un) sont des trous du
     * chemin, pas des motifs d'abandon. Le cout est |entendus| x |region|,
     * soit quelques milliers de cases -- negligeable devant une inference.
     *
     * @return (nombre d'appariements, index attendu du dernier apparie,
     *   index attendu -> plage de frames ou il a ete entendu)
     */
    /**
     * ── L'HORODATAGE TRANCHE L'AMBIGUITE DES PASSAGES REPETES (2026-08-06) ──
     *
     * DEFAUT MESURE, session live (Al-Ma'un, 107). Le recitateur dit
     * `ٱلَّذِينَ هُمْ يُرَآءُونَ` (mots 24-26). Or la sourate contient
     * `ٱلَّذِينَ هُمْ` DEUX fois : mots 19-20 et 24-25. Deux alignements
     * expliquent alors l'audio avec le MEME nombre de correspondances (5) --
     * verifie en rejouant la DP sur les vrais mots :
     *     depart=19 -> LCS=5, retenu [19, 20, 26, 27, 28]   <- trou de 5 mots
     *     depart=24 -> LCS=5, retenu [24, 25, 26, 27, 28]   <- contigu
     * A egalite, la marche arriere prenait l'index le PLUS PETIT. D'ou, dans
     * le log :
     *     f=20/21/25  RECUL vers le mot 19 -- « le recitateur repete »
     *     f=22/24/32  SAUT REFUSE : trou de 3 mots apres le mot 23
     *                 (attestes=[27, 28]) -- ancre inchangee, rien n'est juge
     * L'ancre restait a 23 et les CINQ derniers mots de la sourate n'ont
     * jamais ete juges, alors que le flux brut les contient nettement
     * (`ٱلَّذِينَ هُمْ يُرَآءُونَ` a 26-30 s, `وَيَمْنَعُونَ ٱلْمَاعُونَ` a
     * 30-34 s). Meme signature sur les trois recitations analysees ce jour-la.
     *
     * CE QUI LEVE L'AMBIGUITE, ET CE N'EST PAS UNE PREFERENCE. Sauter de
     * l'index `a` a l'index `b` laisse les mots `a+1..b-1` non entendus ; leur
     * prononciation exige un minimum PHYSIQUE de frames ([framesMinParMot],
     * deja utilise pour la tete de bloc : n tokens => n frames). Si l'audio
     * qui separe les deux mots ENTENDUS n'en porte pas autant, l'alignement
     * n'est pas « moins probable » : il est IMPOSSIBLE. Entre `هُمْ` et
     * `يُرَآءُونَ` le decodage libre ne laisse qu'une fraction de seconde,
     * alors que `عَن صَلَاتِهِمْ سَاهُونَ ٱلَّذِينَ هُمْ` en demanderait plus
     * d'une seconde.
     *
     * CONTRAINTE DURE, PAS DEPARTAGE (decision utilisateur, 2026-08-06) : « le
     * saut n'est pas autorise, en plus c'est ce que je veux detecter pour
     * arreter la recitation et qu'il recite les mots reellement attendus ». Un
     * vrai saut ne doit donc PAS etre appariee -- l'ancre ne doit pas le
     * suivre en silence. Il tombe dans le decrochage, qui souffle les mots
     * omis : c'est la fonction meme de l'application.
     *
     * POURQUOI LA DP CHANGE DE FORME. La contrainte lie deux appariements
     * CONSECUTIFS ; une LCS classique dp[i][j] ne sait pas quel appariement
     * precede. La DP porte donc sur les CANDIDATS d'appariement (couples
     * (entendu, attendu) qui correspondent), typiquement quelques centaines --
     * la chaine la plus longue s'y calcule en O(candidats^2), soit bien moins
     * que la |entendus| x |region| d'avant sur un bloc long.
     *
     * [framesMinParMot] nul => aucune contrainte, comportement d'avant a
     * l'identique (le banc et les appels sans horodatage restent valides).
     */
    private fun apparier(
        entendus: List<String>,
        attendus: List<String>,
        depart: Int,
        avecFrames: List<Pair<Decodage.MotEntendu, String>>,
        fin: Int,
        framesMinParMot: ((Int) -> Int)? = null,
    ): Triple<Int, Int, Map<Int, IntRange>> {
        val n = entendus.size
        val m = fin - depart + 1
        if (n == 0 || m <= 0) return Triple(0, depart, emptyMap())

        // Candidats : (entendu i, attendu depart+j) qui correspondent. Ranges
        // par i croissant puis j croissant -- l'ordre de la recitation.
        val candI = ArrayList<Int>()
        val candJ = ArrayList<Int>()
        for (i in 0 until n) {
            for (j in 0 until m) {
                if (correspond(entendus[i], attendus[depart + j])) {
                    candI.add(i); candJ.add(j)
                }
            }
        }
        if (candI.isEmpty()) return Triple(0, depart, emptyMap())

        // Somme prefixe du minimum physique de frames, pour obtenir en O(1) le
        // cout d'un saut de `a+1` a `b-1`.
        val cumul = IntArray(m + 1)
        if (framesMinParMot != null) {
            for (j in 0 until m) {
                cumul[j + 1] = cumul[j] + framesMinParMot(depart + j).coerceAtLeast(0)
            }
        }

        /** L'audio entre deux mots ENTENDUS peut-il porter les mots attendus
         *  qui les separent ? Deux voisins immediats : rien a porter. */
        fun possible(iA: Int, jA: Int, iB: Int, jB: Int): Boolean {
            if (framesMinParMot == null || jB == jA + 1) return true
            val besoin = cumul[jB] - cumul[jA + 1]
            if (besoin <= 0) return true
            val dispo = avecFrames[iB].first.premiereFrame -
                avecFrames[iA].first.derniereFrame
            return dispo >= besoin
        }

        // Chaine la plus longue : meilleur[c] = longueur en partant de c.
        val k = candI.size
        val meilleur = IntArray(k) { 1 }
        val suivant = IntArray(k) { -1 }
        for (c in k - 1 downTo 0) {
            for (d in c + 1 until k) {
                if (candI[d] <= candI[c] || candJ[d] <= candJ[c]) continue
                if (!possible(candI[c], candJ[c], candI[d], candJ[d])) continue
                if (meilleur[d] + 1 > meilleur[c]) {
                    meilleur[c] = meilleur[d] + 1
                    suivant[c] = d
                }
            }
        }
        // A egalite de longueur, on garde le candidat de PLUS PETIT index --
        // le comportement d'avant, inchange volontairement : la contrainte
        // temporelle suffit a trancher le cas mesure, et deplacer en meme
        // temps la regle de departage rendrait la mesure inattribuable.
        var tete = 0
        for (c in 1 until k) if (meilleur[c] > meilleur[tete]) tete = c

        val attestes = HashMap<Int, IntRange>()
        var dernier = depart
        var c = tete
        while (c >= 0) {
            val f = avecFrames[candI[c]].first
            attestes[depart + candJ[c]] = f.premiereFrame..f.derniereFrame
            dernier = depart + candJ[c]
            c = suivant[c]
        }
        return Triple(meilleur[tete], dernier, attestes)
    }

    /** Egalite exacte apres normalisation, ou prefixe long (>= 3 lettres) —
     *  un mot tronque par le decodage libre ne doit pas casser la LOCALISATION
     *  (il sera de toute facon juge par l'alignement force, pas ici).
     *
     *  ── LE SQUELETTE SUFFIT A LOCALISER (2026-08-06, idee utilisateur) ─────
     *
     *  Le prefixe ne rattrape QUE les troncatures : une seule lettre fausse AU
     *  MILIEU cassait tout l'appariement, alors que le mot restait
     *  reconnaissable.
     *
     *  MESURE QUI L'IMPOSE (log device 07:49:30-07:49:39, mot 26 وَوَجَدَكَ) :
     *  le decodage libre a produit QUATRE lectures instables du meme son --
     *  `ووجسك`, `ووجتك`, `ووجزسك` -- jamais le `د`. Aucune ne passait le
     *  prefixe (divergence en 4e position), donc AUCUNE bande : ancre figee au
     *  mot 25 pendant 12 s, decrochage, puis cinq SAUT REFUSE quand le
     *  localisateur est parti accrocher les mots 31-35. Le mot etait pourtant
     *  bien dit -- c'est la reconnaissance qui hesitait, pas le recitateur.
     *
     *  POURQUOI CE N'EST PAS UN ASSOUPLISSEMENT DU JUGEMENT. Une bande n'est
     *  qu'une HYPOTHESE DE POSITION (cf. le commentaire de [minAppariements]).
     *  Le verrouillage, lui, continue d'exiger l'attestation EXACTE, harakat
     *  comprises (`attestesExacts`, compare le texte BRUT au mot attendu) --
     *  ce chemin-la n'est pas touche. On rend donc le localisateur capable de
     *  dire « c'est ce mot-la » sans lui donner le droit de dire « il est
     *  juste ». Le graphe porte deja la regle : « normaliser pour TROUVER,
     *  comparer exactement pour CONFIRMER ».
     *
     *  LE CRITERE, ET POURQUOI DEUX CONDITIONS. La plus longue sous-sequence
     *  commune (les lettres partagees DANS L'ORDRE) doit valoir au moins
     *  3 lettres ET couvrir 60 % du mot attendu. Les deux sont necessaires :
     *  3 lettres seules suffiraient sur presque n'importe quel mot long (faux
     *  appariement garanti sur un texte qui se repete), et un pourcentage seul
     *  laisserait passer des mots de 2-3 lettres sur une seule lettre commune
     *  -- exactement le piege des mots frequents (`مِن`, `إِن`) deja nomme.
     *
     *  ⛔ TENTE PUIS RETIRE LE MEME JOUR -- MESURE A L'APPUI, NE PAS REFAIRE
     *  SANS BANC. Deux formes ont ete essayees et REFUTEES :
     *
     *  (1) sous-sequence commune >= 3 lettres ET >= 60 % du mot attendu.
     *      Teste d'abord sur 10 cas CHOISIS PAR MOI, tous des variantes d'un
     *      meme mot : ca passait. Puis teste sur les 227 mots attendus REELS
     *      extraits des logs de session, toutes paires : **1119 paires de mots
     *      DIFFERENTS s'appariaient** alors qu'elles ne le faisaient pas avant
     *      -- `ءامنوا`~=`كانوا` (lcs 4/5), `ءامنا`~=`الناس` (3/5),
     *      `ءانذرتهم`~=`انهم` (4/4). Cause : la sous-sequence ignore les
     *      lettres INTERCALEES, donc deux mots sans rapport partagent
     *      facilement un squelette.
     *
     *  (2) une seule substitution, meme longueur, >= 4 lettres. Bien meilleur
     *      (30 faux appariements au lieu de 1119) mais toujours dangereux :
     *      il apparie `تقهر`~=`تنهر`, deux mots de la MEME sourate 93 a quatre
     *      mots d'ecart (versets 9 et 10), et `اليس`~=`اليك`. Un faux
     *      appariement sur un mot voisin pose la bande au mauvais endroit --
     *      precisement le blocage qu'on cherchait a supprimer.
     *
     *  (3) SOCLE sans l'article `ال` et sans proclitiques (idee utilisateur :
     *      « le socle du mot, exclu AL »). Meilleur que (1) -- 48 faux
     *      appariements a 60 %, 7 a 100 % -- mais DEGRADE le cas cible : sans
     *      analyse morphologique, retirer un `و` initial mange la RACINE des
     *      mots ou il en fait partie. `ووجدك` (racine وجد) devient `جدك`, donc
     *      la comparaison ne porte plus que sur 3 lettres et `جسك`~`جدك` tombe
     *      a 2/3 = 67 %. Effet de bord constate au passage : `الله` devient
     *      `له`. Heuristique a rejeter sans vrai stemmer.
     *
     *  ── LE TABLEAU, MESURE SUR LES MOTS REELS DES SESSIONS ────────────────
     *      critere                        faux appariements   rattrape ووجدك
     *      sous-sequence 3 + 60 %                197              oui
     *      1 substitution, >= 4 lettres            4              partiel
     *      socle sans AL, 60 %                    48              NON (degrade)
     *      socle sans AL, 100 %                    7              non
     *      PREFIXE seul                            0              non
     *      >>> 1 LETTRE D'ECART, mot >= 5          2              OUI  <<<
     *
     *  RETENU : « une lettre d'ecart » (distance d'edition <= 1), qui accepte
     *  la lettre remplacee ET la lettre manquante. Les 2 faux restants sont
     *  intrinseques : `متربة`~`مقربة` (une lettre les separe vraiment) et
     *  `والذين`~`الذين` (le waw de conjonction, deux formes du meme mot que
     *  l'alignement force departagera). A 2 lettres d'ecart on retombe a 18
     *  faux : la marge est etroite, ne pas y toucher sans refaire la mesure.
     *
     *  Mesure faite en fenetre REELLE de recherche (-12/+80) et non toutes
     *  paires : l'utilisateur a justement objecte que l'appariement ne balaie
     *  que la region en cours. Resserrer la fenetre n'aide PAS -- meme a 2
     *  mots d'ecart il reste 9 faux appariements, et ce sont les pires
     *  (`الرحمن`~`الرحيم`, `والضحى`~`والليل` : voisins immediats). L'arabe
     *  coranique met cote a cote des mots au squelette proche ; la proximite
     *  AUGMENTE l'ambiguite au lieu de la reduire.
     *
     *  LECON DE METHODE : n'evaluer un critere d'appariement que sur le
     *  VOCABULAIRE REEL, dans la FENETRE REELLE, toutes paires confondues --
     *  jamais sur des exemples choisis pour reussir. Le texte coranique se
     *  repete, c'est ce qui rend tout assouplissement couteux.
     *
     *  Le cas qui motivait tout ca (mot 26 `وَوَجَدَكَ` decode `ووجسك` /
     *  `ووجتك` / `ووجزسك`, ancre figee 12 s le 2026-08-06) reste donc NON
     *  RESOLU ici. Piste a instruire au banc (`BancFluxBrut`) et non a l'oeil,
     *  cf. `[MESURE] 83 % des refus de localisation = fenetre trop pauvre` :
     *  la vraie cause est peut-etre la FENETRE donnee au decodage libre, pas
     *  le critere de comparaison. */
    private fun correspond(entendu: String, attendu: String): Boolean {
        if (entendu == attendu) return true
        val n = minOf(entendu.length, attendu.length)
        if (n >= 3 && entendu.regionMatches(0, attendu, 0, n)) return true
        // (4) UNE SEULE LETTRE D'ECART -- la forme RETENUE (idee utilisateur :
        // « une lettre d'écart, ce n'est pas grave »). Mesuree la meilleure des
        // cinq essayees : 2 faux appariements dans la fenetre reelle, contre
        // 197 pour la sous-sequence. Elle accepte la lettre REMPLACEE comme la
        // lettre MANQUANTE -- c'est ce qui la distingue de « meme longueur, 1
        // substitution » et lui fait rattraper `ودك` -> `ودعك` (ع avale).
        // Plancher a 5 lettres : en dessous, une lettre d'ecart change trop la
        // proportion du mot (`الم`/`لم`, `من`/`ما`).
        if (attendu.length < MIN_LETTRES_EDITION) return false
        return distanceEdition(entendu, attendu) <= MAX_EDITION
    }

    /** Distance de Levenshtein BORNEE : des que l'ecart de longueur depasse
     *  [MAX_EDITION] la reponse est connue, on ne calcule rien. Sur des mots de
     *  quelques lettres le cout est negligeable devant une inference. */
    private fun distanceEdition(a: String, b: String): Int {
        if (kotlin.math.abs(a.length - b.length) > MAX_EDITION) return MAX_EDITION + 1
        var prec = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            val cur = IntArray(b.length + 1)
            cur[0] = i
            for (j in 1..b.length) {
                val sub = prec[j - 1] + if (a[i - 1] == b[j - 1]) 0 else 1
                cur[j] = minOf(prec[j] + 1, cur[j - 1] + 1, sub)
            }
            prec = cur
        }
        return prec[b.length]
    }

    private companion object {
        /** Une lettre d'ecart, pas deux : a 2, les faux appariements passent de
         *  2 a 18 sur le meme vocabulaire (`ءامنوا`~`كانوا`, `الرحيم`~`الرحمن`). */
        const val MAX_EDITION = 1
        /** Mot attendu assez long pour qu'une lettre d'ecart reste un detail.
         *  A 4 lettres on rattrape deja `ألم`~`أليم` ; a 5 il ne reste que deux
         *  faux, tous deux intrinsequement ambigus (`متربة`~`مقربة`, et
         *  `والذين`~`الذين` que l'alignement force tranchera de toute facon). */
        const val MIN_LETTRES_EDITION = 5
    }
}

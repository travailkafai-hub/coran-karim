package com.corankarim.coran_karim.recitation2

/** Les trois couleurs de l'app : vert = correct, orange = douteux, rouge = faux. */
enum class Couleur { VERT, ORANGE, ROUGE }

/**
 * Statut d'un mot. `OMIS` n'est PAS une couleur : c'est "le recitateur est passe
 * outre, et on peut le prouver". Sans ce statut, un mot saute redevient
 * invisible — c'etait le vrai defaut de v22 (`305db63`), ou les mots enjambes
 * quittaient silencieusement le denominateur.
 */
sealed class Statut {
    object Inconnu : Statut()
    data class Provisoire(val couleur: Couleur) : Statut()
    data class Definitif(val couleur: Couleur) : Statut()
    object Omis : Statut()
}

/**
 * COUCHE G — DECISION.
 *
 * CONTRAT :
 *  - SEUL endroit du systeme ou vit un seuil. Aucune autre couche n'en connait ;
 *  - MONOTONIE : un verdict definitif ne change plus jamais. Un provisoire peut
 *    changer ;
 *  - une observation ne compte que si elle est INTERIEURE (couche E) ;
 *  - jamais de verdict sur absence de donnee, jamais de verdict par defaut.
 *
 * ── LA REGLE, ET CE QU'ELLE REMPLACE ───────────────────────────────────────
 *
 * PROVISOIRE des la 1re observation interieure ; DEFINITIF quand [k] = 2
 * observations interieures issues de fenetres DISTINCTES donnent la meme
 * couleur (stable-prefix rule).
 *
 * En v1 : `lock = p.isFinal || (judged == correct && !deferredTajwid)`. Un mot
 * juge correct sur un simple APERCU etait fige immediatement — consequence
 * mesuree : [PIEGE] verrou_sur_apercu, "la majorite des mots sont verrouilles
 * sur des apercus, donc sur un audio INCOMPLET". Ici il n'existe aucun chemin
 * qui verrouille sur une seule observation, ni sur une observation de bord.
 *
 * ── LE CALENDRIER, CHIFFRE (W = 6 s, hop = 1,5 s) ──────────────────────────
 * Soit `t` l'instant ou le mot finit d'etre prononce :
 *   + 1,04 s  contexte droit du modele causal
 *   + 0 a 1,5 s  attente de la prochaine fenetre de la grille
 *   + ~0,4 s  inference (mesure : 413 ms pour 5,7 s de buffer)
 *   = PROVISOIRE a t + 1,4 a 2,9 s
 *   + 1,5 s  seconde observation interieure
 *   = DEFINITIF a t + 2,9 a 4,4 s
 *
 * Ce delai est CONSTANT : il ne depend ni de la longueur d'un segment, ni du
 * rythme des pauses, ni de la duree deja recitee. C'est une propriete de
 * conception, pas une consequence a constater. Reference v1 mesuree dans le
 * log : `VALIDATION retard=10435ms` puis `8463ms`.
 */
class Decideur(
    private val seuilCorrect: Float = -0.45f,
    private val seuilDouteux: Float = -1.60f,
    /** Frontiere de la marge de confusion. ZERO n'est pas un reglage : c'est le
     *  point ou l'audio cesse de preferer le mot attendu et se met a preferer
     *  une confusion. Expose pour que la recette puisse le balayer, pas pour
     *  qu'on l'ajuste a l'oeil. */
    private val seuilMargeRouge: Float = 0f,
    private val k: Int = 2,
    private val motsPosterieursPourOmission: Int = 3,
    /**
     * Mots qui ne doivent JAMAIS recevoir de verdict : Bismillah non recitee,
     * et surtout tout ce qui PRECEDE le point d'entree quand on rejoint une
     * sourate en cours (mode priere).
     *
     * ── LE DECIDEUR NE LES CONNAISSAIT PAS (corrige 2026-08-07) ─────────────
     *
     * `nonJugeables` etait passe a [ChaineRecitation] et n'y servait qu'au
     * COMPTAGE DES TROUS. La regle d'omission ci-dessous, elle, l'ignorait
     * completement -- elle declare `Omis` tout mot jamais atteste des lors
     * qu'assez de mots posterieurs sont definitifs.
     *
     * MESURE (session 18:48, Maryam, entree au mot 86 = 19:10) : 151 verdicts,
     * AUCUN mot jamais juge, la recitation reelle (86..150) integralement
     * verte -- et 123 mots declares `Omis`, tous d'indice 0 a 85, c'est-a-dire
     * l'ouverture de la sourate que le recitant n'avait pas a dire.
     * Ces faux `Omis` alimentaient ensuite les trous, donc le souffleur.
     */
    private val nonJugeables: Set<Int> = emptySet(),
    /** De combien de mots la recitation doit avoir depasse un mot avant qu'on
     *  accepte de le condamner. Ce n'est pas une tolerance sur le critere :
     *  c'est le refus de conclure tant que la preuve peut encore arriver. */
    private val depassement: Int = 3,
) {
    private val definitifs = HashMap<Int, Couleur>()

    /**
     * Oublie les verdicts DEFINITIFS a partir du mot [depuis] (inclus).
     *
     * ── POURQUOI (specification utilisateur 2026-08-07) ──────────────────────
     * « Si decrochage est detecte, le plus logique c'est de repeter depuis ce
     * decrochage et attendre que la personne repete. » Attendre suppose de
     * pouvoir REJUGER les mots concernes : tant qu'ils restent figes, la
     * repetition du recitant ne peut produire aucun nouveau verdict et
     * l'attente serait sans objet.
     *
     * On ne touche QUE ce qui est apres le point de reprise : tout ce que le
     * recitant a deja dit et fait valider avant reste acquis. C'est la
     * difference avec `reinitialiser()`, qui efface tout -- et c'est pour ca
     * que cette methode existe plutot que de recreer la chaine (recreation =
     * perte de TOUS les verdicts de la session, inacceptable en cours de
     * recitation).
     */
    fun oublierDepuis(depuis: Int) {
        definitifs.keys.filter { it >= depuis }.forEach { definitifs.remove(it) }
    }
    private val omis = HashSet<Int>()

    /** Meilleure couleur PROVISOIRE vue pour chaque mot. Cf. le bloc « SENS
     *  UNIQUE » : un provisoire ne se degrade jamais, une fenetre qui tronque
     *  un mot n'ayant pas a ecraser celle qui l'avait entendu entier. */
    private val meilleurProvisoire = HashMap<Int, Couleur>()

    /** @return statut courant de chaque mot ayant au moins une observation. */
    fun statuts(registre: RegistreDePreuves, nbMots: Int): Map<Int, Statut> {
        val out = HashMap<Int, Statut>()

        for (i in 0 until nbMots) {
            val dejaFige = definitifs[i]
            if (dejaFige != null) { out[i] = Statut.Definitif(dejaFige); continue }

            val votantes = registre.observationsVotantes(i)
            if (votantes.isEmpty()) continue

            val couleurs = votantes.map { couleur(it) }
            val fenetres = votantes.map { it.fenetreId }

            // ── DEUX MESURES INDEPENDANTES VALENT DEUX FENETRES ─────────────
            //
            // Le decodage libre ne connait pas le texte attendu ; l'alignement
            // force, si. Quand les deux disent la meme chose sur le meme audio
            // -- le libre a entendu CE mot a CET endroit, et le force lui donne
            // un bon score -- on tient deux preuves independantes, pas une.
            //
            // Ce n'est pas une tolerance ajoutee : c'est la reconnaissance
            // qu'exiger deux FENETRES etait une approximation de « exiger deux
            // preuves ». Mesure qui l'impose (2026-07-30) : les mots 170, 171,
            // 174, 205, 67 etaient lus PARFAITEMENT dans leur propre enonce
            // (gop 0,00, texte exact, atteste) puis degrades par le bloc de
            // FUSION qui les tronquait (« ٱلْبَرْ » pour « ٱلْبَرْقُ »). La 2e
            // fenetre apportait une preuve SYSTEMATIQUEMENT moins bonne, et
            // faisait perdre l'accord.
            // L'ATTESTATION VAUT AUSSI AU BORD. Un mot au bord d'un bloc est
            // suspect parce qu'il pourrait etre TRONQUE ; mais si le decodage
            // libre l'a emis ENTIER, il ne l'est pas -- l'attestation repond
            // deja a la question que la marge posait.
            // Mesure : le mot 67 etait lu gop=0,00 avec son texte EXACT et
            // ressortait quand meme `Omis`, faute d'observation interieure.
            //
            // Remarque de methode (utilisateur, 2026-07-30) : ce changement,
            // MESURE SEUL, ne bouge pas le taux. Il est garde quand meme --
            // « une amelioration non mesuree + une autre, ca peut marcher ».
            // La regle « un changement sans effet mesurable n'a pas sa place
            // dans la chaine critique » vient du retrait de
            // FRONTIER_KEEP_SECONDS (2026-07-29), ou l'hypothese avait ete
            // REFUTEE en plus d'etre sans effet. Ce n'est pas le cas ici : la
            // justification tient, seul le gain immediat manque.
            val nette = registre.observations(i).lastOrNull {
                it.atteste && !it.sansCreneau && it.entendu.isNotBlank()
            }
            // REGRESSION MESUREE LE 2026-07-31, recette s2 : en laissant la
            // marge de confusion peser ici, les mots qu'elle fait sortir du
            // vert ne se verrouillent plus, restent provisoires, et la logique
            // d'omission les ramasse. Resultat : `omis` 5 -> 13, dont le mot
            // 205 `ٱلَّذِى` ENTENDU IDENTIQUE, gop 0,00, declare NON PRONONCE.
            // Les faux positifs de la marge devenaient donc INVISIBLES : ils ne
            // s'affichaient pas en rouge, ils se deguisaient en « vous n'avez
            // pas dit ce mot » -- le pire verdict possible, et indiscernable
            // d'un vrai saut dans le log.
            // La regle `nette` repose sur DEUX mesures independantes qui
            // concordent (decodage libre + alignement force) ; la marge est une
            // TROISIEME question, elle n'a pas a annuler cette preuve. Elle
            // garde tout son effet par le chemin normal a deux fenetres.
            if (nette != null && couleurSansMarge(nette) == Couleur.VERT) {
                definitifs[i] = Couleur.VERT
                out[i] = Statut.Definitif(Couleur.VERT)
                continue
            }

            // k dernieres observations, de fenetres DISTINCTES, toutes d'accord.
            if (votantes.size >= k) {
                val dernieres = couleurs.takeLast(k)
                val idsDistincts = fenetres.takeLast(k).toSet().size == k
                if (idsDistincts && dernieres.all { it == dernieres.first() }) {
                    // ── UN NON-VERT NE SE FIGE QUE QUAND LE RECITATEUR EST
                    //    PASSE A LA SUITE ────────────────────────────────────
                    //
                    // La conception d'origine posait trois conditions au
                    // verrouillage ; la troisieme -- « au moins un mot
                    // posterieur a recu des frames » -- n'avait jamais ete
                    // implementee. Elle manquait, et ca se voit :
                    //     mot 171 f36 gop=-12,66  f37 gop=-18,34  -> ROUGE fige
                    //             f39 gop=  0,00 entendu="يَخْطَفُ"  (trop tard)
                    //     mot 172 f36 gop=-11,14  f37 gop=-14,18  -> ROUGE fige
                    //             f39 gop= -4,20 entendu correct
                    // Les deux premieres observations avaient `free` proche de
                    // 0 et `entendu` vide : signature de MAUVAISE POSITION, pas
                    // de mauvaise prononciation ([PIEGE] gop_vs_free). La
                    // monotonie figeait donc une erreur de position.
                    //
                    // Un VERT reste immediat : il est deja atteste deux fois, et
                    // faire attendre un mot juste degrade le temps reel pour
                    // rien. Un NON-VERT, lui, accuse quelqu'un : il attend que
                    // le mot ne puisse plus etre reobserve.
                    val couleurRetenue = dernieres.first()
                    val recitateurPasse = registre.indexMaxVotant() >= i + depassement
                    if (couleurRetenue == Couleur.VERT || recitateurPasse) {
                        definitifs[i] = couleurRetenue
                        out[i] = Statut.Definitif(couleurRetenue)
                        continue
                    }
                }
            }
            // ── SENS UNIQUE : UN PROVISOIRE NE SE DEGRADE JAMAIS ────────────
            //
            // Decision utilisateur du 2026-07-31 : « je veux implementer un
            // seul sens, meme sur les jugements partiels avant le definitif ».
            //
            // MESURE QUI LA MOTIVE. Le code portait deja le constat, avec les
            // numeros : « les mots 170, 171, 174, 205, 67 etaient lus
            // PARFAITEMENT dans leur propre enonce (gop 0,00, texte exact,
            // atteste) puis DEGRADES par le bloc de FUSION qui les tronquait
            // (ٱلْبَرْ pour ٱلْبَرْقُ) ». Le mot 170 est ressorti orange dans la
            // recette du 2026-07-31 avec exactement la meme troncature --
            // ٱلْبَرْقُ entendu ٱلْبَرْءُ. Sept jours, meme defaut.
            //
            // Le CURSEUR GLISSANT aggrave le probleme : il produit une fenetre
            // toutes les 3 s au lieu d'une par silence, donc beaucoup plus
            // d'occasions qu'une fenetre defavorable arrive APRES une bonne.
            //
            // Une observation qui TRONQUE un mot n'apporte pas une information
            // meilleure que celle qui l'avait entendu ENTIER : elle en apporte
            // une MOINS BONNE. La laisser ecraser la premiere revient a
            // preferer la pire preuve disponible.
            //
            // ⚠️ CE QUE CA COUTE, ET C'EST ASSUME : un mot reellement mal
            // prononce qui recevrait UNE observation verte par accident
            // resterait vert jusqu'a son verrouillage. Le garde-fou est que ces
            // observations sont deja filtrees (interieures, avec creneau) et
            // que le VERROUILLAGE, lui, exige toujours deux fenetres
            // distinctes concordantes -- le sens unique ne touche QUE
            // l'affichage provisoire, jamais le verdict definitif.
            val rang = { c: Couleur -> when (c) {
                Couleur.VERT -> 2; Couleur.ORANGE -> 1; Couleur.ROUGE -> 0 } }
            val nouvelle = couleurs.last()
            val gardee = meilleurProvisoire[i]
            val retenue = if (gardee == null || rang(nouvelle) > rang(gardee))
                nouvelle else gardee
            meilleurProvisoire[i] = retenue
            out[i] = Statut.Provisoire(retenue)
        }

        // OMISSION : preuve POSITIVE que le recitateur est passe outre — au
        // moins N mots POSTERIEURS sont definitifs alors que celui-ci n'a jamais
        // recu d'observation votante. Ce n'est pas un verdict par absence de
        // donnee : c'est un constat sur des mots qui, eux, ont leur preuve.
        val definitifsTries = definitifs.keys.sorted()
        for (i in 0 until nbMots) {
            if (out[i] != null || omis.contains(i)) {
                if (omis.contains(i) && out[i] == null) out[i] = Statut.Omis
                continue
            }
            // Un mot qu'on n'a jamais eu a reciter ne peut pas etre « omis ».
            if (i in nonJugeables) continue
            val posterieurs = definitifsTries.count { it > i }
            if (posterieurs >= motsPosterieursPourOmission) {
                // ── SECOURS : AVANT DE DIRE « PAS PRONONCE », REGARDER L'AUDIO ──
                //
                // MESURE QUI L'IMPOSE (2026-07-31, deux recettes confrontees au
                // WAV par verifier_non_verts_v2.py) : des mots declares `Omis`
                // sont BEL ET BIEN dans l'audio --
                //   mot 228 « وَإِن »  -> le WAV dit « وَإِن كُنتُمْ فِى رَ »
                //   mot 205 « ٱلَّذِى » -> « ٱلَّذِى جَعَلَ لَكُمُ ٱلْأَرْضَ »
                //   mot 220 « رِزْقًا » -> « رِزْقًا لَّكُمْ فَلَا »
                //   mot  67 « أَلَآ »  -> « أَلَآ », gop 0,00, texte EXACT
                // `Omis` est le verdict le plus grave que l'app puisse rendre :
                // elle affirme que le recitateur n'a pas dit un mot qu'il a dit.
                // La regle projet « aucun verdict sans preuve » vaut donc aussi
                // dans ce sens-la. Le critere d'omission etait purement
                // POSITIONNEL -- trois mots plus loin sont juges, donc celui-ci
                // est perdu -- sans jamais regarder l'audio du mot lui-meme.
                //
                // NE COUTE QUE SUR LES MOTS CONDAMNES (3 a 7 sur 295), jamais
                // sur les autres : on est deja dans la branche d'omission.
                //
                // ── POURQUOI VERT, ET NON `couleur(preuve)` ──────────────────
                // Premiere version : selectionner sur `atteste` puis juger sur
                // le gop. INCOHERENT, releve par l'utilisateur -- on retient un
                // mot PARCE QU'IL EST PROUVE, puis on le colorie orange en
                // contredisant cette preuve.
                // Or `atteste` est DEJA l'attestation EXACTE
                // (`bande.attestesExacts`, cf. ChaineRecitation) : le decodage
                // LIBRE a emis ce mot, a cet endroit, sans qu'on le lui
                // demande, et son texte coincide exactement. C'est une mesure
                // INDEPENDANTE de l'alignement force, et c'est la preuve la
                // plus forte dont la chaine dispose. Il n'y a plus rien a
                // juger : le mot est vert.
                // ⚠️ EXACTE et non normalisee : le graphe porte deja
                // [PIEGE] attestation_normalisee -- « normaliser pour TROUVER,
                // comparer exactement pour CONFIRMER ». Un fragment
                // (ٱلْبَرْقُ entendu ٱلْبَرْءُ) ne doit PAS declencher ce secours.
                val preuve = registre.observations(i).lastOrNull {
                    it.atteste && it.entendu.isNotBlank() && !it.sansCreneau
                }
                if (preuve != null) {
                    definitifs[i] = Couleur.VERT
                    out[i] = Statut.Definitif(Couleur.VERT)
                    continue
                }
                omis.add(i)
                out[i] = Statut.Omis
            }
        }
        return out
    }

    /**
     * Deux questions, pas une.
     *
     * `gop = forced - free` demande « le modele est-il sur de ce qu'il
     * entend ? ». `free` etant un maximum sur les 1025 classes, c'est une borne
     * si lache que TOUS les mots corrects s'y ecrasent a exactement 0,000 --
     * d'ou [seuilCorrect] et [seuilDouteux], regles a la main. Pire : quand le
     * modele est CONVAINCU du canonique alors que le recitateur a dit autre
     * chose, `forced == free`, donc `gop = 0`, donc VERT A TORT. C'est
     * exactement ce que l'utilisateur constatait en faisant des fautes
     * deliberees.
     *
     * [margeLettres] demande autre chose : « l'audio prefere-t-il le mot
     * attendu, ou sa confusion la plus plausible ? ». Deux hypotheses
     * CONTRAINTES, donc comparables, et une frontiere naturelle : ZERO.
     * [seuilMargeRouge] est expose pour que la recette puisse le balayer, mais
     * sa valeur par defaut n'est pas un reglage.
     *
     * Mesure 2026-07-31, audio reellement faute, 189 phrases tenues a l'ecart,
     * detection a 2 % de collateral : gop 9 %, marge de lettre 30 %.
     *
     * ON AJOUTE, ON NE REMPLACE PAS. Le gop voit des choses que la marge ne
     * peut pas voir : un mot saute, un mot completement autre -- la marge ne
     * compare qu'a une vingtaine de confusions a une lettre. Consequence
     * assumee : les faux positifs des deux mecanismes s'additionnent, le
     * collateral passe d'environ 2 % a ~4 %. C'est le prix de la detection, et
     * il doit etre lu sur la recette, pas suppose.
     */
    /** La couleur SANS la marge de confusion — c'est-a-dire la regle d'avant.
     *  Sert au verrouillage par preuves concordantes, que la marge ne doit pas
     *  pouvoir annuler (cf. la regression du 2026-07-31 documentee plus haut). */
    fun couleurSansMarge(o: RegistreDePreuves.Observation): Couleur = when {
        o.gop >= seuilCorrect -> Couleur.VERT
        o.gop >= seuilDouteux -> Couleur.ORANGE
        else -> Couleur.ROUGE
    }

    fun couleur(o: RegistreDePreuves.Observation): Couleur = when {
        o.margeLettres != null && o.margeLettres < seuilMargeRouge -> Couleur.ROUGE
        o.gop >= seuilCorrect -> Couleur.VERT
        o.gop >= seuilDouteux -> Couleur.ORANGE
        else -> Couleur.ROUGE
    }

    fun reinitialiser() {
        definitifs.clear()
        omis.clear()
        meilleurProvisoire.clear()
    }
}

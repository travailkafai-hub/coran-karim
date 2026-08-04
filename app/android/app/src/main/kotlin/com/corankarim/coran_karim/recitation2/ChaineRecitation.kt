package com.corankarim.coran_karim.recitation2

/**
 * L'ORCHESTRATEUR : A -> B -> C -> D -> E -> F -> G.
 *
 * Il ne contient AUCUNE logique de decision. Son seul role est de faire
 * circuler les objets entre des couches qui ne se connaissent pas.
 *
 * Le graphe designe `runAlignment` (reecrit 7 fois) et `OVERLAP_SECONDS`
 * (6 fois) comme les points ou le code n'a JAMAIS converge, et les nomme
 * "la frontiere mal decoupee entre alignement, secours et gestion d'ancre".
 * C'est cette frontiere qui disparait ici : il n'y a plus ni secours (le
 * recouvrement des fenetres fait le travail EN AMONT), ni ancre mutable (la
 * position est reestimee a chaque fenetre), et l'alignement est une fonction
 * pure qui ne connait ni l'un ni l'autre.
 *
 * CE QUI N'EXISTE PLUS, et pourquoi ce n'est pas une omission :
 *   gel / borne dure 12 s / findCutOffset / targetSeconds  -> plus de coupe
 *   RescueBuffer / fenetreDeRecherche / secoursMeilleur     -> recouvrement
 *   findResyncOffset / RESYNC_ACTIF / rattrapage borne      -> couche D
 *   MIN_FRAMES_FOR_JUDGMENT / deferredOnceIndex / fragments -> `interieur`
 * Chacun de ces mecanismes compensait un defaut de segmentation. La
 * segmentation ayant disparu, les reintroduire serait le signal que le
 * probleme est revenu — pas un correctif.
 */
class ChaineRecitation(
    private val front: FrontAcoustique,
    private val tokeniser: (String) -> IntArray,
    /** Tokenise une CONFUSION generee (mot volontairement hors-Coran). Separe de
     *  [tokeniser] parce que ces mots ne sont presque jamais dans le
     *  dictionnaire precalcule : logger chaque repli en ferait des milliers par
     *  sourate (piege deja documente dans CtcTokenizer.tokenizeVariantQuiet).
     *  Par defaut on retombe sur [tokeniser] — les tests JVM n'ont pas besoin
     *  de la distinction. */
    private val tokeniserConfusion: (String) -> IntArray = tokeniser,
    /** Confusions de LETTRE d'un mot. Injectee plutot qu'importee : le paquet
     *  recitation2 ne doit pas dependre de `fastconformer`. */
    private val confusionsLettres: (String) -> List<String> = { emptyList() },
    /** Confusions de HARAKAT. Signal faible sur le modele actuel (7,9 %), tenu
     *  SEPARE des lettres : leur union fait tomber la detection de 30 a 21 %. */
    private val confusionsHarakat: (String) -> List<String> = { emptyList() },
    private val constructeur: ConstructeurDeFenetres = ConstructeurDeFenetres(),
    private val localisateur: Localisateur = Localisateur(front.pieces, front.blank),
    private val aligneur: AligneurForce = AligneurForce(front.pieces, front.blank),
    private val decideur: Decideur = Decideur(),
    private val fluxBrut: FluxBrut = FluxBrut(),
    private val journal: ((String) -> Unit)? = null,
    /** TETE 3 (ecart canonique), OPTIONNELLE. Cf. Tete3.kt : tant que la
     *  parite des 12 scores n'est pas verifiee sur device, sa sortie est
     *  seulement JOURNALISEE -- elle ne doit influencer aucun statut. */
    private val tete3: Tete3? = null,
) {
    private var motsAttendus: List<String> = emptyList()
    private var tokensAttendus: List<IntArray> = emptyList()
    private var variantesAttendues: List<List<IntArray>> = emptyList()
    private var confusionsLettresAttendues: List<List<IntArray>> = emptyList()
    private var confusionsHarakatAttendues: List<List<IntArray>> = emptyList()
    private val registre = RegistreDePreuves()
    private var statutsCourants: Map<Int, Statut> = emptyMap()

    /** Dernier mot DEFINITIF — sert de point de depart a la localisation, sans
     *  jamais interdire un recul (le recitateur a le droit de repeter). */
    private var dernierDefinitif = -1

    /** Derniere bande etablie par une fenetre FERMEE sur un silence. Les
     *  apercus la reutilisent au lieu d'en calculer une sur un audio tronque
     *  (cf. la mesure dans [traiter]). */
    private var derniereBande: Localisateur.Bande? = null

    /** De combien de mots un apercu regarde AU-DELA de la derniere bande sure.
     *  Assez pour couvrir ce qui vient d'etre dit entre deux apercus (3 s de
     *  recitation posee), pas assez pour que la DP ait a placer des mots
     *  lointains -- c'est cet entassement qui corrompait la bande. */
    private val motsEnAvanceApercu = 6

    data class Changement(val motIndex: Int, val statut: Statut)

    // ── DECROCHAGE : le recitateur recite AUTRE CHOSE (2026-08-01) ──────────
    //
    // L'INFORMATION EXISTAIT DEJA ET ETAIT JETEE. Quand le recitateur quitte
    // le texte, le localisateur ne trouve aucune correspondance et rend
    // `null` ; `traiter` se contentait de journaliser `bande=inconnue` puis
    // de sortir. Preuve relevee sur le telephone de l'utilisateur le
    // 2026-08-01, apres qu'il a enchaine sur la sourate 112 en pleine
    // Al-Baqara -- ONZE fenetres consecutives, ~14 s, texte parfaitement
    // reconnu, et rien ne s'est declenche :
    //     f=19 bande=inconnue entendu="قُلْ هُوَ ٱللَّهُ أَحَدٌ"
    //     f=24 bande=inconnue entendu="ٱللَّهُ ٱلصَّمَدُ"
    //     f=27 bande=inconnue entendu="لَمْ يَلِدْ وَلَمْ يُولَدْ"
    //
    // LE CRITERE, LU DIRECTEMENT DANS CES LIGNES -- aucun seuil invente :
    //   bande inconnue + entendu VIDE      -> silence (f=21, f=22), on ignore
    //   bande inconnue + entendu NON VIDE  -> il dit quelque chose qui n'est
    //                                         pas le texte -> decrochage
    //
    // Pourquoi DEUX fenetres et pas une : une fenetre isolee peut etre un
    // fragment tronque en bord d'apercu (cf. le commentaire de `traiter` sur
    // la queue cachee au localisateur) ; deux fenetres d'affilee sur du texte
    // etranger ne s'expliquent plus par un artefact de decoupage.
    //
    // CE MECANISME N'A AUCUN EFFET SUR LE JUGEMENT : il ne touche ni le
    // registre, ni le decideur, ni les statuts. Il compte, et il signale.
    private var fenetresHorsTexte = 0
    private var decrochageDejaSignale = false
    /** Au moins une fenetre s'est localisee depuis le debut de la session. */
    private var dejaLocaliseUneFois = false

    /**
     * Dernier mot DEFINITIF au moment du decrochage : c'est de la que le
     * recitateur doit etre repris, pas du mot 0. Sans ca l'ecran rejouait le
     * tout premier mot (mesure 2026-08-01 : `ancre=0 "بِسْمِ"`), qui plus est
     * dans la Bismillah -- ou `_verseContaining` rend `null`, donc aucun audio
     * ne partait et le declenchement etait invisible.
     */
    var motDuDecrochage: Int = -1
        private set

    /** Nombre de fenetres consecutives hors texte avant de signaler. */
    private val fenetresAvantDecrochage = 2

    /**
     * Trou maximal accepte entre le dernier mot definitif et le debut de la
     * bande. Deux, parce qu'un mot mal dit peut en contaminer un second par
     * decoulement (raisonnement de l'utilisateur, 2026-08-01) -- au-dela,
     * c'est un vrai saut, l'ancre ne doit pas suivre.
     */
    private val sautMaxMots = 2

    /**
     * Vrai quand le recitateur s'est manifestement ecarte du texte attendu.
     * Remis a faux des qu'une fenetre se localise a nouveau -- l'appelant est
     * donc prevenu UNE fois par decrochage, pas a chaque fenetre.
     */
    var decrochage: Boolean = false
        private set

    /** A appeler apres avoir traite le signal (evite de le rejouer). */
    fun accuserDecrochage() {
        decrochage = false
    }

    fun definirTexte(mots: List<String>) {
        motsAttendus = mots
        tokensAttendus = mots.map(tokeniser)
        // Ecritures equivalentes (cf. Orthographe) : la premiere entree est le
        // mot canonique, deja couvert par la DP -- on ne garde que les autres.
        variantesAttendues = mots.map { m ->
            Orthographe.variantes(m).drop(1).map(tokeniser).filter { it.isNotEmpty() }
        }
        // CONCURRENTES : elles se prononcent AUTREMENT. Leur score sert a
        // repondre « l'audio prefere-t-il le mot attendu ou sa confusion la plus
        // plausible ? » -- une question a frontiere naturelle (zero), la ou le
        // gop contre le decodage libre ecrase tous les mots corrects a 0,000 et
        // impose des seuils regles a la main.
        confusionsLettresAttendues = mots.map { m ->
            confusionsLettres(m).map(tokeniserConfusion).filter { it.isNotEmpty() }
        }
        confusionsHarakatAttendues = mots.map { m ->
            confusionsHarakat(m).map(tokeniserConfusion).filter { it.isNotEmpty() }
        }
        decideur.reinitialiser()
        dernierDefinitif = -1
        fenetresHorsTexte = 0
        decrochageDejaSignale = false
        dejaLocaliseUneFois = false
        decrochage = false
        motDuDecrochage = -1
        statutsCourants = emptyMap()
        journal?.invoke("[v2] cible = ${mots.size} mots")
    }

    val preuves: RegistreDePreuves get() = registre

    /**
     * Statuts courants. A LIRE ICI, jamais en rejouant un [Decideur] neuf sur
     * le registre : la couche G est STATEFUL par contrat (un verdict definitif
     * ne change plus jamais), donc une reevaluation en bloc apres coup ne
     * reproduit PAS ce qu'a vu l'utilisateur. Piege tombe dans le banc lui-meme
     * le 2026-07-30 : un mot verrouille VERT ressortait "rouge provisoire" a la
     * relecture, parce que la relecture ne voyait que les 2 dernieres preuves.
     */
    val statuts: Map<Int, Statut> get() = statutsCourants
    val brut: FluxBrut get() = fluxBrut

    /**
     * Point d'entree unique de l'audio.
     * @return les mots dont le statut a CHANGE depuis l'appel precedent.
     */
    fun alimenter(pcm: FloatArray): List<Changement> {
        fluxBrut.ajouter(pcm)
        val changements = ArrayList<Changement>()
        for (fenetre in constructeur.alimenter(pcm)) {
            traiter(fenetre)
        }
        val nouveaux = decideur.statuts(registre, motsAttendus.size)
        for ((i, s) in nouveaux) {
            if (statutsCourants[i] != s) changements.add(Changement(i, s))
            if (s is Statut.Definitif && i > dernierDefinitif) dernierDefinitif = i
        }
        statutsCourants = nouveaux
        return changements
    }

    /**
     * Fin de session : derniere analyse de la queue d'audio, hors grille.
     * Sans cet appel, les derniers mots resteraient PROVISOIRES a jamais — la
     * grille de fenetres cesse d'avancer des que le recitateur se tait
     * (defaut trouve par le banc 2, cf. [ConstructeurDeFenetres.terminer]).
     */
    fun terminer(): List<Changement> {
        val changements = ArrayList<Changement>()
        for (fenetre in constructeur.terminer()) traiter(fenetre)
        val nouveaux = decideur.statuts(registre, motsAttendus.size)
        for ((i, s) in nouveaux) {
            if (statutsCourants[i] != s) changements.add(Changement(i, s))
        }
        statutsCourants = nouveaux
        return changements
    }

    private fun traiter(fenetre: Fenetre) {
        if (motsAttendus.isEmpty()) return
        // UN SEUL appel au modele pour les trois sorties (cf. FrontAcoustique) :
        // logprobs pour le jugement, tajwid pour la tete 2 -- null sur un
        // modele a une seule tete, la chaine reste alors identique a avant.
        val sorties = front.sorties(fenetre.echantillons)
        val logprobs = sorties.logprobs
        if (logprobs.isEmpty()) return

        // LE LOCALISATEUR NE VOIT PAS LA QUEUE TRONQUEE DE L'APERCU.
        //
        // TROIS ESSAIS ONT ECHOUE EN AGISSANT SUR LA BANDE (2026-07-31) :
        //   apercu 2 s, bande libre     :  2,2 s / 52,44 %
        //   apercu 3 s, bande figee     : 11,1 s /  3,29 %
        //   apercu 3 s, ancre + 6 mots  :  8,5 s / 46,52 %
        //   (reference sans apercu      : 10,2 s /  2,61 %)
        // Tous traitaient le SYMPTOME (la bande decroche) au lieu de la cause.
        //
        // LA CAUSE, MESUREE : 95 % des erreurs etaient dans trois blocs
        // CONSECUTIFS, avec `entendu` vide et `free` proche de 0 -- le modele
        // entend bien, on lui demande les mauvais mots. Un apercu est coupe EN
        // PLEINE PAROLE : son dernier mot sort en FRAGMENT, et c'est ce
        // fragment que la LCS de localisation prend pour un mot atteste.
        //
        // On cache donc simplement cette queue au localisateur. Le jugement,
        // lui, garde toutes les frames : l'aligneur a deja sa propre marge
        // droite et sait ne pas juger un mot du bord. Le localisateur, non --
        // c'est la qu'il manquait quelque chose.
        val pourLocaliser = if (fenetre.apercu &&
            logprobs.size > Horloge.LOOKAHEAD_FRAMES * 2) {
            logprobs.copyOfRange(0, logprobs.size - Horloge.LOOKAHEAD_FRAMES)
        } else logprobs

        val bande = localisateur.localiser(
            pourLocaliser, motsAttendus, dernierDefinitif,
            framesMinParMot = { i -> tokensAttendus.getOrNull(i)?.size ?: 0 },
        )
        if (bande == null) {
            // Resultat legitime : la fenetre ne dit rien de la position. Aucun
            // jugement n'en sort — regle "aucun verdict sans preuve acoustique".
            val entenduLibre = Decodage.texte(logprobs, front.pieces, front.blank)
            journal?.invoke("[v2] f=${fenetre.id} bande=inconnue " +
                "entendu=\"$entenduLibre\" horsTexte=$fenetresHorsTexte " +
                "dejaSignale=$decrochageDejaSignale")
            // Decrochage (cf. le commentaire de `fenetresHorsTexte`) : on ne
            // compte QUE les fenetres ou quelque chose a ete entendu. Une
            // fenetre muette est un silence, pas une recitation etrangere.
            // Trois garde-fous, tous imposes par la MESURE du 2026-08-01 sur le
            // telephone (premiere version du detecteur) :
            //
            // (a) TANT QU'AUCUNE FENETRE NE S'EST JAMAIS LOCALISEE, on ne peut
            //     pas parler de decrochage : le recitateur n'a pas encore
            //     commence. Sans ca, le log montrait
            //     `f=3 DECROCHAGE ... entendu="مٓ"` -- un fragment de demarrage.
            //
            // (b) UNE SEULE ALERTE tant qu'il n'est pas revenu dans le texte.
            //     Sans ca : quatre declenchements en cinq secondes sur la meme
            //     sourate 112 (f=13, f=16, f=17...), le compteur repartant a
            //     zero apres chaque signalement.
            if (entenduLibre.isNotBlank() && dejaLocaliseUneFois) {
                fenetresHorsTexte++
                if (fenetresHorsTexte >= fenetresAvantDecrochage && !decrochageDejaSignale) {
                    decrochage = true
                    decrochageDejaSignale = true
                    motDuDecrochage = dernierDefinitif
                    journal?.invoke("[v2] f=${fenetre.id} DECROCHAGE : " +
                        "$fenetresHorsTexte fenetres hors texte, " +
                        "dernier definitif=$dernierDefinitif, " +
                        "dernier entendu=\"$entenduLibre\"")
                }
            }
            return
        }
        // ── SAUT REFUSE (2026-08-01, demande utilisateur) ───────────────────
        //
        // « Je ne veux pas sauter du tout. Ce qu'on autorise, c'est qu'un mot
        // dit faux soit juge orange -- et par decoulement il peut en toucher
        // deux. Donc on autorise une validation avec un saut de 2 mots. »
        //
        // MESURE QUI L'IMPOSE (log du telephone, 2026-08-01) : le recitateur
        // passe du mot 11 au mot 22 (dix mots sautes, plusieurs lignes) et la
        // chaine suit sans broncher --
        //     18:50:31 mot=11 -> definitif:vert
        //     18:50:47 mot=22 -> provisoire:orange   <- saut accepte
        //     18:51:19 mot=13, 14 -> definitif:vert  <- valides APRES coup
        //
        // CE QU'ON NE TOUCHE PAS, ET POURQUOI. `avanceMax` (80) reste
        // inchange : ce n'est pas « de combien on autorise a sauter » mais
        // « jusqu'ou on cherche ». Un bloc peut porter 40 mots ; a 24 la
        // region de recherche etait tronquee et l'ancre decrochait au mot 82
        // sur 295 (mesure 2026-07-30, cf. le commentaire de `avanceMax`).
        // On borne donc le TROU accepte, pas la recherche.
        //
        // Le RECUL n'est pas concerne (ecart negatif) : un mot valide avant
        // ses predecesseurs -- cas normal, le 3e mot d'un souffle peut etre
        // definitif avant les deux premiers -- reste traite par `bande.recul`.
        // OU EST LE SAUT, EXACTEMENT (mesure du 2026-08-01, 2e essai). Une
        // premiere version comparait `bande.i0` au dernier mot definitif :
        // elle ne voyait RIEN, parce que le saut n'est pas au DEBUT de la
        // bande mais A L'INTERIEUR. Log qui le prouve -- une seule passe
        // valide le mot 10 puis le mot 19, la LCS ayant apparie les deux
        // extremites en ignorant 11..18 :
        //     19:04:48 mot=10 -> definitif:vert
        //     19:04:48 mot=19 -> definitif:vert
        //     19:04:57 mot=20..28 -> omis
        // On regarde donc l'ecart entre deux mots ATTESTES CONSECUTIFS (les
        // seuls que le decodage libre a reellement entendus), et aussi
        // l'ecart entre le dernier definitif et la premiere attestation.
        val attestesTries = bande.attestes.keys.sorted()
        var trou = 0
        var trouApres = -1
        if (attestesTries.isNotEmpty()) {
            if (dernierDefinitif >= 0) {
                trou = attestesTries.first() - (dernierDefinitif + 1)
                trouApres = dernierDefinitif
            }
            for (k in 1 until attestesTries.size) {
                val ecart = attestesTries[k] - attestesTries[k - 1] - 1
                if (ecart > trou) {
                    trou = ecart
                    trouApres = attestesTries[k - 1]
                }
            }
        }
        // Exception au TOUT DEBUT (aucun mot encore definitif) : on ne sait
        // pas ou le recitateur commence, et commencer au verset 2 sans dire
        // la Bismillah est legitime (constate a chaque session de test).
        if (dernierDefinitif >= 0 && trou > sautMaxMots) {
            journal?.invoke("[v2] f=${fenetre.id} SAUT REFUSE : trou de $trou mots " +
                "apres le mot $trouApres (attestes=${attestesTries.take(6)}...), " +
                "dernier definitif=$dernierDefinitif, max=$sautMaxMots " +
                "-- ancre inchangee, rien n'est juge")
            if (dejaLocaliseUneFois) {
                fenetresHorsTexte++
                if (fenetresHorsTexte >= fenetresAvantDecrochage && !decrochageDejaSignale) {
                    decrochage = true
                    decrochageDejaSignale = true
                    motDuDecrochage = dernierDefinitif
                    journal?.invoke("[v2] f=${fenetre.id} DECROCHAGE (saut) : " +
                        "dernier definitif=$dernierDefinitif")
                }
            }
            return
        }
        // Une fenetre s'est localisee : le recitateur est (re)venu dans le
        // texte. (c) C'est SEULEMENT ici que l'alerte se re-arme -- pas apres
        // un simple decompte.
        dejaLocaliseUneFois = true
        fenetresHorsTexte = 0
        decrochageDejaSignale = false
        if (bande.recul) {
            journal?.invoke("[v2] f=${fenetre.id} RECUL vers le mot ${bande.i0} " +
                "(dernier definitif = $dernierDefinitif) — le recitateur repete")
        }

        val tokens = tokensAttendus.subList(bande.i0, bande.i1 + 1)
        val res = aligneur.aligner(
            logprobs, tokens, bande.i0,
            bordGaucheEstDebutDeSession = fenetre.travailDebut == 0L,
            attestes = bande.attestes,
            variantesParMot = variantesAttendues.subList(bande.i0, bande.i1 + 1),
            confusionsLettresParMot =
                confusionsLettresAttendues.subList(bande.i0, bande.i1 + 1),
            confusionsHarakatParMot =
                confusionsHarakatAttendues.subList(bande.i0, bande.i1 + 1),
        ) ?: return

        // ON REMONTE LA FRONTIERE DU DERNIER MOT SUR AU CONSTRUCTEUR.
        //
        // Inversion de l'ordre : au lieu de couper puis aligner, on aligne puis
        // on coupe a une frontiere CONNUE. L'energie ne porte pas cette
        // information -- une occlusive arabe a une phase peu energique au
        // MILIEU d'un mot -- et le projet l'a mesure : 47,4 % des coupes
        // tombaient en plein mot, et 19 des 22 mots non verts en etaient les
        // victimes.
        //
        // On ne remonte QUE des mots INTERIEURS : un mot du bord peut etre
        // tronque, sa `derniereFrame` ne serait pas sa vraie fin. Et on garde
        // une marge d'une frame, l'alignement CTC etant peaky (il marque le pic
        // du token, pas l'etendue du son) -- c'est ce defaut qui a tue le
        // montage audio dans ce projet.
        res.mots.lastOrNull { it.interieur && it.frames > 0 }?.let { dernier ->
            val fin = fenetre.absoluDeFrame(dernier.derniereFrame + 1)
            if (fin > 0) constructeur.frontiereMotSure(fin)
        }

        for (m in res.mots) {
            val debutAbs = if (m.frames > 0) fenetre.absoluDeFrame(m.premiereFrame) else -1L
            val finAbs = if (m.frames > 0) fenetre.absoluDeFrame(m.derniereFrame) else -1L
            // TETE 2 : la frame est CAPITALE pour attribuer une regle au bon
            // mot (cf. FastConformerCtc.decodeTajwid) -- on decoupe donc
            // exactement sur les memes bornes que celles retenues pour
            // l'attestation du mot, pas sur la fenetre entiere.
            val reglesTajwid = if (m.frames > 0 && sorties.tajwid != null) {
                val debut = m.premiereFrame.coerceIn(0, sorties.tajwid.size)
                val fin = (m.derniereFrame + 1).coerceIn(debut, sorties.tajwid.size)
                front.decodeTajwid(sorties.tajwid.copyOfRange(debut, fin))
                    .map { it.ruleId }.distinct()
            } else emptyList()
            // TETE 3 : OBSERVATION SEULE (journal), cf. vecteurTete3 ci-dessous
            // -- ne touche ni Observation ni le statut.
            if (tete3 != null && sorties.etat != null && m.frames > 0) {
                val vec = vecteurTete3(m, sorties.etat, logprobs, tokensAttendus.getOrNull(m.index)?.size ?: 0)
                if (vec != null && vec.size == tete3.tailleEntree) {
                    val logit = tete3.logit(vec)
                    journal?.invoke("[t3] mot=${m.index} logit=${"%.3f".format(logit)} " +
                        "seuil2%=${"%.3f".format(tete3.seuil2Pct)} " +
                        (if (logit > tete3.seuil2Pct) "DEVIATION_SUSPECTEE" else "ok"))
                }
            }
            registre.ajouter(
                RegistreDePreuves.Observation(
                    fenetreId = fenetre.id,
                    motIndex = m.index,
                    gop = m.gop,
                    forced = m.forced,
                    free = m.free,
                    entendu = m.entendu,
                    margeLettres = m.margeLettres,
                    margeHarakat = m.margeHarakat,
                    frames = m.frames,
                    interieur = m.interieur && !m.sansCreneau,
                    couvert = m.couvert,
                    sansCreneau = m.sansCreneau,
                    // ATTESTATION EXACTE, pas normalisee : c'est elle qui a le
                    // droit de verrouiller un vert sur une seule observation.
                    atteste = bande.attestesExacts.contains(m.index),
                    fenetrePleine = fenetre.pleine,
                    debutAbs = debutAbs,
                    finAbs = finAbs,
                    reglesTajwid = reglesTajwid,
                )
            )
        }

        journal?.invoke(
            "[v2] f=${fenetre.id} duree=${"%.2f".format(fenetre.dureeSecondes)}s " +
                "bande=${bande.i0}..${bande.i1} conf=${"%.2f".format(bande.confiance)} " +
                "interieurs=${res.mots.count { it.interieur }}/${res.mots.size}" +
                if (res.bandeTronquee) " (bande tronquee)" else ""
        )
    }

    /**
     * TETE 3 : moyenne de l'etat d'encodeur sur les frames du mot (512) suivie
     * des 12 grandeurs conditionnees par la cible -- cf.
     * tete_encodeur_ecart.py::caracteristiques, meme ORDRE (parite = ordre).
     *
     * DEUX APPROXIMATIONS CONNUES, cf. graphe (2026-08-04), avant tout
     * branchement sur un verdict :
     *  - [forced_f] (score CTC FORWARD du Python) vaut ici [forced_v] (Viterbi) :
     *    aucun scoreur forward n'existe cote Kotlin.
     *  - [alt]/[alt2] viennent des DEUX meilleures confusions deja calculees
     *    par AligneurForce (une par LETTRE, une par HARAKAT), pas du jeu
     *    complet de `variantes()` du Python.
     * Les deux touchent des grandeurs deja passees par [tokeniserConfusion],
     * qui replie en glouton 33 % du temps (piege deja documente) -- une
     * degradation que l'entrainement Python (SentencePiece direct) n'a jamais
     * connue. D'ou : OBSERVATION SEULE, journalisee, aucun effet sur le statut.
     */
    private fun vecteurTete3(
        m: AligneurForce.MotAligne, etat: Array<FloatArray>, logp: Array<FloatArray>,
        idmSize: Int,
    ): FloatArray? {
        if (m.frames <= 0) return null
        val ml = m.margeLettres
        val mh = m.margeHarakat
        if (ml == null && mh == null) return null // aucune confusion plausible
        val confLettre = ml?.let { m.forced - it }
        val confHarakat = mh?.let { m.forced - it }
        val candidats = listOfNotNull(confLettre, confHarakat).sortedDescending()
        val alt = candidats[0]
        val alt2 = if (candidats.size > 1) candidats[1] else alt
        val forcedV = m.forced
        val forcedF = m.forced // APPROXIMATION, cf. doc ci-dessus

        val f0 = m.premiereFrame.coerceIn(0, minOf(etat.size, logp.size))
        val f1 = (m.derniereFrame + 1).coerceIn(f0, minOf(etat.size, logp.size))
        if (f1 <= f0) return null
        val dimEtat = etat[0].size
        val etatMoyen = FloatArray(dimEtat)
        for (t in f0 until f1) { val row = etat[t]; for (k in 0 until dimEtat) etatMoyen[k] += row[k] }
        for (k in 0 until dimEtat) etatMoyen[k] /= (f1 - f0)

        var entropieSomme = 0f
        var picBlancCompte = 0
        val blank = front.blank
        for (t in f0 until f1) {
            val frame = logp[t]
            var maxV = frame[0]; var maxI = 0
            for (c in 1 until frame.size) if (frame[c] > maxV) { maxV = frame[c]; maxI = c }
            var sommeExp = 0f
            for (v in frame) sommeExp += kotlin.math.exp((v - maxV).toDouble()).toFloat()
            var h = 0f
            for (v in frame) {
                val p = kotlin.math.exp((v - maxV).toDouble()).toFloat() / sommeExp
                h -= p * kotlin.math.ln((p + 1e-9f).toDouble()).toFloat()
            }
            entropieSomme += h
            if (maxI == blank) picBlancCompte++
        }
        val n = (f1 - f0)
        val entropie = entropieSomme / n
        val picBlanc = picBlancCompte.toFloat() / n

        val douze = floatArrayOf(
            forcedV, forcedF, m.free, alt, alt2,
            forcedV - m.free, forcedF - alt, alt - alt2,
            n.toFloat(), idmSize.toFloat(), entropie, picBlanc,
        )
        return etatMoyen + douze
    }

    /** Journalisation par mot — la trace qui manquait en v1 : le log disait ce
     *  que la chaine avait DECIDE, jamais POURQUOI. Ici chaque observation est
     *  restituable, avec sa fenetre et sa position dans le flux brut. */
    fun tracerMot(i: Int): String {
        val obs = registre.observations(i)
        if (obs.isEmpty()) return "mot $i : aucune observation"
        val sb = StringBuilder("mot $i (${motsAttendus.getOrNull(i)}) :\n")
        for (o in obs) {
            sb.append(
                "  f=${o.fenetreId} ${if (o.interieur) "INTERIEUR" else "bord     "} " +
                    "gop=${"%.2f".format(o.gop)} forced=${"%.2f".format(o.forced)} " +
                    "free=${"%.2f".format(o.free)} frames=${o.frames} " +
                    "entendu=\"${o.entendu}\" abs=[${o.debutAbs},${o.finAbs}]\n"
            )
        }
        sb.append("  statut = ${statutsCourants[i] ?: Statut.Inconnu}")
        return sb.toString()
    }
}

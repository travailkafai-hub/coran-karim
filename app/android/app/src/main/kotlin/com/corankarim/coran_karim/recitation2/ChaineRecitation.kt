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
    /**
     * CLOISONNEMENT CTL/REF (2026-08-05). Le mecanisme SAUT REFUSE (cf. plus
     * bas dans [traiter]) est correct pour la recitation NORMALE : c'est la
     * regle produit voulue -- pas de decrochage silencieux, un vrai trou doit
     * faire repeter le recitateur, pas avancer sans jugement.
     *
     * Il est en revanche la CAUSE MESUREE de la regression de l'ancre en
     * recitation de REFERENCE (bancs/recettes) : la mesure du 2026-08-05 sur
     * la meme sourate, meme depart, montre le temoin d'avant ce mecanisme
     * (commit ec04903) atteignant l'ancre 294, et deux temoins d'apres
     * (6f1e954, 90e4772) plafonnant a 209 puis 69, avec des dizaines de "SAUT
     * REFUSE" dans le journal. La cause : le refus ne bloque pas seulement le
     * trou, il jette TOUTE la fenetre, y compris les mots attestes de part et
     * d'autre -- alors qu'un trou de RECONNAISSANCE (le modele qui rate 3-4
     * mots) est frequent et normal, meme quand le recitateur dit tout juste.
     *
     * En reference, on n'a pas besoin d'imposer une repetition : on veut
     * juste MESURER jusqu'ou l'ancre suit. On revient donc au comportement
     * d'avant le 2026-08-01 pour cette session-la uniquement : aucun trou
     * n'est calcule, aucune fenetre n'est jetee pour cette raison.
     */
    /** Index de mots que l'application ne juge JAMAIS -- aujourd'hui la
     *  Bismillah inseree en tete de sourate (decision projet 2026-07-20).
     *
     *  Ils sont exclus du comptage de SAUT. Un mot qu'on refuse de juger par
     *  conception ne peut pas servir de preuve qu'on a saute quelque chose.
     *
     *  DEFAUT MESURE (2026-08-06, session live de l'utilisateur, build v79 --
     *  « j'ai recite puis pause puis play pour passer a une autre sourate,
     *  rien ne se passe »). Al-Kafirun terminee, ancre au mot 29 ; la cible
     *  insere la Bismillah de la sourate suivante aux mots 30-33. Le
     *  recitateur enchaine sur Al-Ikhlas et la chaine le VOIT parfaitement :
     *      f=30 SAUT REFUSE : trou de 4 mots apres le mot 29
     *           (attestes=[34, 35, 36, 37, 38])
     *  -- 34-38 = `قُلْ هُوَ ٱللَّهُ أَحَدٌ ٱللَّهُ`, confirme sur le flux brut.
     *  Mais l'ecart 29 -> 34 vaut 4 mots, au-dessus de [sautMaxMots] = 2 :
     *  fenetre jetee, VINGT fois de suite, jusqu'a la fin de la session.
     *  La Bismillah avait pourtant ete dite (`entendu="بِسْمِ"` trois fois) ;
     *  elle n'a pas pu etre placee parce qu'un mot SEUL qui se repete dans la
     *  zone de recherche est refuse par securite, et `بسم` y figure trois
     *  fois (sourates 112, 113, 114).
     *  CONSEQUENCE GENERALE : aucun recitateur ne pouvait franchir une
     *  frontiere de sourate -- la fonction « enchainer sur une autre sourate »
     *  etait cassee en entier.
     *  Fournis par Dart (`RecitedWord.isBasmala`), qui en est la seule
     *  autorite : la detecter en Kotlin sur le texte confondrait la Bismillah
     *  inseree avec le verset 1:1 d'Al-Fatiha, qui lui est bien recite. */
    private val nonJugeables: Set<Int> = emptySet(),
    private val referenceSession: Boolean = false,
    /**
     * SUIVRE UNE PRIERE (2026-08-07, specification utilisateur).
     *
     * « Il ne faut pas utiliser le localiseur de l'application de recitation
     * qui refuse le saut. La, les sauts seront autorises pour que l'aligneur
     * suive -- si par exemple des mots ne sont pas detectes, ou plusieurs, ou
     * il y a un probleme de voix, qu'on arrive a suivre. [...] Il va juste
     * reciter les mots qu'il pense qu'il y a un oubli, donc il faut poursuivre
     * le Coran, mais apres, il faut debloquer le saut. [...] Au lieu
     * d'attendre l'ancre comme dans les autres modes, juste on repete, mais
     * apres on active le saut et la localisation. »
     *
     * POURQUOI UNE BRANCHE ET NON UN SECOND LOCALISATEUR. Dupliquer le
     * localisateur donnerait deux codes qui divergent -- le projet a deja paye
     * ce prix (cf. les mecanismes de la v1 restes vivants et morts a la fois).
     * Ici le mecanisme refuse est UN SEUL : le rejet de fenetre sur trou trop
     * grand. On le debraye, on ne reecrit rien.
     *
     * CE QUI CHANGE, EXACTEMENT :
     *  - le trou n'est plus un motif de REJET : la fenetre est acceptee, la
     *    bande est posee, l'ancre suit le recitateur ;
     *  - le trou reste MESURE et REMONTE ([sautPresumeDe]/[sautPresumeA]) :
     *    c'est ce qui permet a l'app de souffler les mots probablement oublies.
     *
     * CE QUI NE CHANGE PAS : la recitation normale (`sautLibre = false`) garde
     * son refus intact -- c'est une regle produit voulue, mesuree, et elle
     * n'est pas touchee par ce parametre.
     */
    private val sautLibre: Boolean = false,
) {
    /**
     * Bornes du dernier trou constate quand [sautLibre] est actif : les mots
     * `sautPresumeDe + 1 .. sautPresumeA - 1` n'ont pas ete entendus alors que
     * le recitateur est deja plus loin.
     *
     * Ce N'EST PAS une accusation d'oubli -- « on ne sera pas sur qu'il a
     * vraiment rate » (utilisateur). C'est le signal qui permet de LUI SOUFFLER
     * le passage. Aucun verdict n'en decoule, aucune ancre ne recule.
     * Remis a -1 des qu'il a ete lu, pour ne souffler qu'une fois par trou.
     */
    /**
     * Vrai tant que la PREMIERE localisation apres une pose de cible n'a pas
     * eu lieu.
     *
     * ── LE DECALAGE D'ENTREE N'EST PAS UN OUBLI (2026-08-07) ────────────────
     *
     * Question de l'utilisateur : « une fois le verset detecte, faut-il
     * l'appliquer de suite ? entre-temps l'imam a avance ».
     *
     * Oui, il a avance -- et c'est inevitable : on reconnait un passage PARCE
     * QU'IL VIENT D'ETRE DIT. L'ancre posee est donc toujours un peu derriere.
     * Ce n'est pas grave en soi : le localisateur cherche dans
     * `[ancre - reculMax, ancre + avanceMax]`, soit -20/+80, il est quatre
     * fois plus tolerant vers l'avant et rattrape tout seul.
     *
     * CE QUI ETAIT GRAVE : ce rattrapage etait compte comme un TROU. Mesure du
     * 17:34 -- identification 25:43, ancre au mot 508, et sept secondes plus
     * tard `passage non entendu : mots 508..520`, tout le verset souffle alors
     * qu'il venait d'etre recite correctement. Les mots entre le point
     * d'entree et la position reelle n'ont jamais ete ATTENDUS ; les declarer
     * non entendus est un contresens.
     *
     * On saute donc le signalement sur la premiere localisation qui suit une
     * pose de cible. Une seule -- ensuite, un trou redevient un vrai trou.
     */
    private var premiereLocalisation = false

    /** Trou constate mais PAS ENCORE signale : on laisse une fenetre de plus
     *  pour le combler (cf. le commentaire dans [traiter]). */
    private var trouEnAttenteDe = -1
    private var trouEnAttenteA = -1
    private var idFenetreTrou = -1L

    var sautPresumeDe: Int = -1
    var sautPresumeA: Int = -1

    /**
     * Texte du DECODAGE LIBRE de la derniere fenetre traitee, quelle que soit
     * sa localisation (bande connue ou non).
     *
     * Existait deja mais n'etait que JOURNALISE (`entendu="..."`) : c'est la
     * matiere premiere de l'identification de sourate (« Shazam ») du mode
     * priere, et rien ne la remontait a Dart. Vide quand la fenetre ne porte
     * que du silence.
     */
    var dernierEntenduLibre: String = ""

    private var motsAttendus: List<String> = emptyList()
    private var tokensAttendus: List<IntArray> = emptyList()
    private var variantesAttendues: List<List<IntArray>> = emptyList()
    private var confusionsLettresAttendues: List<List<IntArray>> = emptyList()
    private var confusionsHarakatAttendues: List<List<IntArray>> = emptyList()

    /** Confusions de la TETE 3 — celles que le Python a utilisees pour
     *  l'entrainer, generees par [ConfusionsRecitation] et NON par
     *  [confusionsLettres]/[confusionsHarakat]. Les deux inventaires different
     *  (premiere occurrence contre toutes, quatre harakat contre sept) : les
     *  melanger rendrait `alt` et `alt2` faux sans rien signaler. */
    private var confusionsTete3: List<List<IntArray>> = emptyList()
    private val registre = RegistreDePreuves()
    private var statutsCourants: Map<Int, Statut> = emptyMap()

    /** Dernier mot DEFINITIF — sert de point de depart a la localisation, sans
     *  jamais interdire un recul (le recitateur a le droit de repeter). */
    private var dernierDefinitif = -1

    /**
     * Plus haut mot jamais ATTESTE par une fenetre, verrouille ou non
     * (2026-08-05). Distinct de [dernierDefinitif] : un mot peut etre vu par
     * le decodage libre plusieurs SECONDES avant que le Decideur l'ait
     * verrouille (2 fenetres distinctes concordantes, cf. Decideur.kt) --
     * verrouillage volontairement pas immediat, "un vert reste immediat"
     * n'empeche pas un delai residuel de deux passes.
     *
     * MESURE QUI L'IMPOSE (2026-08-05, session live) : le recitateur enchaine
     * vite, le mot 25 "وَمَآ" est ATTESTE (provisoire:vert) a 19:50:29.999,
     * mais reste `dernierDefinitif=24` le temps qu'il se verrouille. Deux
     * fenetres suivantes mesurent alors un trou de 3 puis 4 mots ENTRE LE MOT
     * 24 ET LES ATTESTATIONS SUIVANTES (27, 29, 30, 31) -- un trou qui
     * n'existe pas vraiment, puisque 25 est deja vu. SAUT REFUSE puis
     * DECROCHAGE se sont declenches sur un mot deja bon.
     *
     * Ne relache PAS la detection d'un vrai saut (10 mots jamais entendus,
     * cas du 2026-08-01) : ces mots ne sont attestes par AUCUNE fenetre,
     * [dernierAttesteVu] ne bouge donc pas pour eux.
     */
    private var dernierAttesteVu = -1

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

    /** Nombre de fenetres consecutives hors texte avant de signaler.
     *  Monte a 4 puis REVENU a 2 le 2026-08-05 : la cause du blocage sur
     *  "إِنَّ" etait la CIBLE trop courte (cible=40 mots, "إِنَّ" au mot 40
     *  n'existait pas dans motsAttendus), pas un manque de patience -- une
     *  fois la vraie cause identifiee, le filet de securite n'avait plus lieu
     *  d'etre (demande utilisateur). */
    /**
     * ── PORTE A 3 (demande utilisateur 2026-08-07) ──────────────────────────
     *
     * Annonce des le 2026-08-06 : « apres test, si 2 mots declenchent beaucoup
     * de blocage, je vais mettre 3 ». Le test a eu lieu : sur la soiree du
     * 2026-08-07, plusieurs decrochages a 2 fenetres se sont averes faux --
     * le mot 73 `بِمُؤْمِنِينَ` declare `definitif:vert` 5 ms apres l'alerte,
     * `مُصْلِحُونَ` valide par la fenetre suivante 500 ms plus tard.
     *
     * Maintenant que le decrochage est le SEUL mecanisme qui interrompt encore
     * (la correction sur erreur isolee a ete retiree le meme jour), le cout
     * d'un faux positif a change de nature : ce n'est plus une aide de trop,
     * c'est la seule interruption de la session, et elle doit etre juste.
     * Une fenetre de plus, c'est environ 1 s d'attente supplementaire pour une
     * exigence de preuve de 50 % superieure.
     *
     * L'historique de ce reglage est conserve ci-dessous : il porte la mesure
     * qui avait fait REDESCENDRE de 4 a 2, et la vraie cause d'alors (cible
     * trop courte) n'a rien a voir avec celle d'aujourd'hui.
     */
    private val fenetresAvantDecrochage = 3

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

    /**
     * DERNIER MOT REELLEMENT DIT, d'ou la reprise doit repartir (+1 cote
     * appelant) -- 2026-08-05.
     *
     * PAS `dernierDefinitif` seul : celui-ci est le dernier mot VERROUILLE, et
     * le verrouillage exige DEUX fenetres concordantes (cf. Decideur). Un mot
     * que le recitateur vient de prononcer, deja entendu et atteste a une
     * position valide, n'est donc pas encore definitif -- reprendre a
     * `dernierDefinitif + 1` fait REJOUER des mots qu'il a deja dits.
     *
     * SYMPTOME (utilisateur, 2026-08-05) : « quand il y a decrochage il repete
     * des mots que j'ai dit », « il choisit pas bien la ou j'ai vraiment
     * arrete ». Mesure, log 22:55:26 : `dernier definitif=12` -> reprise
     * annoncee au mot 13, alors que la recitation etait allee plus loin.
     *
     * `dernierAttesteVu` est le bon complement : depuis le 2026-08-05 il
     * n'avance QUE sur une fenetre ACCEPTEE (cf. la mise a jour apres le
     * contrôle de saut), donc il ne peut pas englober un saut refuse -- il
     * represente exactement « le plus loin ou le recitateur a ete entendu a
     * une position valide ». On prend le maximum des deux.
     */
    private fun pointDeReprise(): Int = maxOf(dernierDefinitif, dernierAttesteVu)

    /**
     * [positionDepart] : ou le recitateur EST DEJA suppose se trouver dans ce
     * texte (mode priere). Par defaut -1 = « on ne sait pas », comportement
     * historique : la recherche part du mot 0.
     *
     * ── POURQUOI CE PARAMETRE EXISTE (2026-08-07) ──────────────────────────
     *
     * Le localisateur cherche dans une fenetre BORNEE autour du dernier mot
     * verrouille : `depart = dernierVerrouille + 1`, region
     * `[depart - reculMax, depart + avanceMax]`. Sur une chaine neuve,
     * `dernierVerrouille = -1`, donc la region vaut 0..80.
     *
     * MESURE (session du 2026-08-07, 10:41) : le mode priere identifie la
     * sourate 9 et place l'imam au mot 1652 sur 2498. La chaine v2 recevait
     * bien les 2498 mots -- et cherchait entre 0 et 80. Resultat :
     * `bande=inconnue` sur TOUTES les fenetres, alors que le decodage libre
     * entendait parfaitement `لَهُمُ ٱلْخَيْرَٰتُ وَأُو۟لَـٰٓئِكَ هُمُ ٱلْمُ`,
     * qui est bien 9:88-89. Rien ne pouvait etre juge, le pointeur restait
     * fige, et le souffleur de silence partait au bout de 4 s -- l'imam se
     * faisait corriger alors qu'il recitait juste.
     *
     * L'identification CONNAIT cette position ; elle ne la transmettait pas.
     */
    fun definirTexte(mots: List<String>, positionDepart: Int = -1) {
        motsAttendus = emptyList()
        tokensAttendus = emptyList()
        variantesAttendues = emptyList()
        confusionsLettresAttendues = emptyList()
        confusionsHarakatAttendues = emptyList()
        confusionsTete3 = emptyList()
        decideur.reinitialiser()
        dernierDefinitif = -1
        dernierAttesteVu = -1
        fenetresHorsTexte = 0
        decrochageDejaSignale = false
        dejaLocaliseUneFois = false
        decrochage = false
        motDuDecrochage = -1
        sautPresumeDe = -1
        sautPresumeA = -1
        trouEnAttenteDe = -1
        trouEnAttenteA = -1
        idFenetreTrou = -1L
        dernierEntenduLibre = ""
        statutsCourants = emptyMap()
        ajouterMots(mots, journalCible = true)
        // La region de recherche du localisateur est calee sur
        // `dernierDefinitif + 1` (cf. la doc de cette fonction). En posant ce
        // champ, on dit a la chaine « il en est LA » sans rien verrouiller ni
        // juger : aucun statut n'est produit, seule la fenetre de recherche se
        // deplace. Le recul reste possible (`reculMax`), et si la position
        // fournie est fausse, `sautLibre` laisse la chaine se relocaliser
        // ailleurs -- c'est une indication, pas une contrainte.
        premiereLocalisation = true
        if (positionDepart > 0 && positionDepart < mots.size) {
            dernierDefinitif = positionDepart - 1
            journal?.invoke("[v2] position de depart indiquee : mot " +
                "$positionDepart/${mots.size} -- la recherche s'y cale au " +
                "lieu de partir du mot 0")
        }
    }

    /**
     * Ajoute des mots A LA SUITE de la cible actuelle, SANS RIEN
     * REINITIALISER (2026-08-05) : l'enchainement de page
     * (KaraokeRecitationScreen._maybeExtendNextPage) doit pouvoir agrandir
     * la cible EN COURS DE SESSION sans perdre l'ancre ni les mots deja
     * verrouilles.
     *
     * CAUSE MESUREE : l'ancien chemin (Dart `extendAlignmentTarget`) ne
     * touchait que le v1 -- `motsAttendus` (v2, celui qui pilote vraiment
     * l'ecran, cf. le PARAMS "CELUI QUI PEINT L'ECRAN") restait fige a sa
     * taille de DEPART pour toute la session. Constate : une cible de 40
     * mots chargee au demarrage restait a 40 mots meme apres que l'ecran ait
     * affiche 167 mots suite a un enchainement de page reussi
     * ("Enchaînement page 3 : +11 versets, +127 mots" cote Dart) -- tout mot
     * au-dela du 40e etait alors STRUCTURELLEMENT hors de portee du
     * localisateur/decideur (recherche et decrochage bornes par
     * `motsAttendus.size`), quel que soit le reglage de patience du
     * decrochage. Cinq correctifs ont ete tentes ce soir sur le SEUIL avant
     * de trouver que la cible elle-meme etait trop courte.
     */
    fun etendreTexte(motsSupplementaires: List<String>) {
        ajouterMots(motsSupplementaires, journalCible = false)
    }

    private fun ajouterMots(mots: List<String>, journalCible: Boolean) {
        if (mots.isEmpty()) return
        motsAttendus = motsAttendus + mots
        tokensAttendus = tokensAttendus + mots.map(tokeniser)
        // Ecritures equivalentes (cf. Orthographe) : la premiere entree est le
        // mot canonique, deja couvert par la DP -- on ne garde que les autres.
        variantesAttendues = variantesAttendues + mots.map { m ->
            Orthographe.variantes(m).drop(1).map(tokeniser).filter { it.isNotEmpty() }
        }
        // CONCURRENTES : elles se prononcent AUTREMENT. Leur score sert a
        // repondre « l'audio prefere-t-il le mot attendu ou sa confusion la plus
        // plausible ? » -- une question a frontiere naturelle (zero), la ou le
        // gop contre le decodage libre ecrase tous les mots corrects a 0,000 et
        // impose des seuils regles a la main.
        confusionsLettresAttendues = confusionsLettresAttendues + mots.map { m ->
            confusionsLettres(m).map(tokeniserConfusion).filter { it.isNotEmpty() }
        }
        confusionsHarakatAttendues = confusionsHarakatAttendues + mots.map { m ->
            confusionsHarakat(m).map(tokeniserConfusion).filter { it.isNotEmpty() }
        }
        // TETE 3 : son propre inventaire, cf. [confusionsTete3]. On NE filtre
        // PAS les tokenisations vides comme au-dessus -- le Python n'en ecarte
        // aucune, et une liste plus courte donnerait un autre `alt2`.
        if (tete3 != null) {
            confusionsTete3 = confusionsTete3 + mots.map { m ->
                ConfusionsRecitation.variantes(m).map(tokeniserConfusion)
            }
        }
        journal?.invoke(
            if (journalCible) "[v2] cible = ${motsAttendus.size} mots"
            else "[v2] cible etendue : +${mots.size} mots -> ${motsAttendus.size} mots"
        )
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
    /**
     * RECULE l'ancre au mot [mot] et rend leur liberte aux verdicts suivants.
     *
     * Specification utilisateur (2026-08-07) : sur un decrochage, l'audio est
     * joue ET « l'ancre revient au niveau du decrochage », puis on attend que
     * le recitant repete.
     *
     * ⚠️ NE RECREE PAS LA CHAINE. `definirTexte` remettrait tout a zero et
     * ferait perdre les verdicts de toute la session -- inacceptable en cours
     * de recitation. Ici on ne deplace que le point de reprise et on oublie
     * les verdicts POSTERIEURS, pour qu'ils puissent etre reprononces et
     * rejuges. Tout ce qui precede reste acquis.
     *
     * Sans effet en mode [sautLibre] (suivi de priere) : « l'ancre ne recule
     * jamais, il n'y a pas d'attente pour repeter » -- l'imam n'a aucune
     * obligation de reprendre, l'application le suit.
     */
    fun reculerAncre(mot: Int) {
        if (sautLibre) {
            journal?.invoke("[v2] recul d'ancre IGNORE (mode priere) : " +
                "l'ancre ne recule jamais dans ce mode")
            return
        }
        val cible = mot.coerceIn(0, maxOf(0, motsAttendus.size - 1))
        decideur.oublierDepuis(cible)
        dernierDefinitif = cible - 1
        dernierAttesteVu = minOf(dernierAttesteVu, cible - 1)
        fenetresHorsTexte = 0
        decrochageDejaSignale = false
        statutsCourants = statutsCourants.filterKeys { it < cible }
        journal?.invoke("[v2] ANCRE RECULEE au mot $cible -- " +
            "verdicts posterieurs oublies, le recitant peut repeter")
    }

    val statuts: Map<Int, Statut> get() = statutsCourants
    val brut: FluxBrut get() = fluxBrut

    /**
     * LA VOIX DU RECITATEUR SUR UNE PLAGE DE MOTS -- exactement l'audio qui a
     * servi a le juger (demande utilisateur 2026-08-06 : « quand je clique sur
     * le mot en erreur, pouvoir ecouter ce que j'ai dit »).
     *
     * POURQUOI C'EST LE MEME AUDIO, ET PAS UNE APPROXIMATION. Chaque
     * [RegistreDePreuves.Observation] porte `debutAbs`/`finAbs`, la position
     * EXACTE de la preuve dans le flux brut ; [FluxBrut] garde ce flux en
     * memoire (300 s) et [FluxBrut.extraire] refuse une plage sortie de
     * l'anneau plutot que de rendre un extrait tronque. Ce qu'on rejoue est
     * donc l'echantillon qui a produit le verdict -- pas un audio reconstitue,
     * pas un clip recolle. Le projet a deja paye la reconstitution par
     * concatenation de clips (2026-07-28 : 319,0 s de clips pour 310,2 s de
     * flux, donc des positions absolues fausses) : on ne recommence pas.
     *
     * ⚠️ Ne renvoie QUE des observations VOTANTES si possible, sinon toutes :
     * un mot ecarte (bord, sans creneau) a quand meme ete prononce, et c'est
     * precisement celui-la qu'on veut reecouter.
     *
     * @return les echantillons, ou `null` si aucun mot de la plage n'a de
     *   position connue, ou si l'audio est deja sorti de l'anneau.
     */
    fun voixSurPlage(motDebut: Int, motFin: Int): FloatArray? {
        var debut = Long.MAX_VALUE
        var fin = -1L
        for (i in motDebut..motFin) {
            for (o in registre.observations(i)) {
                if (o.debutAbs < 0 || o.finAbs < 0) continue
                if (o.debutAbs < debut) debut = o.debutAbs
                if (o.finAbs > fin) fin = o.finAbs
            }
        }
        if (fin < 0 || debut == Long.MAX_VALUE || fin <= debut) return null
        // Marge de respiration : le CTC est PEAKY (il marque le pic du token,
        // pas l'etendue du son), donc les bornes serrent le mot de trop pres --
        // sans marge on coupe l'attaque et la fin, et l'extrait devient
        // inecoutable. 0,25 s de chaque cote, borne au flux disponible.
        val marge = (Horloge.TAUX * 0.25).toLong()
        val d = maxOf(fluxBrut.premierDisponible, debut - marge)
        val f = minOf(fluxBrut.total, fin + marge)
        return fluxBrut.extraire(d, f)
    }

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
            // Remonte a l'appelant (cf. [dernierEntenduLibre]) : c'est la
            // matiere de l'identification de sourate du mode priere. Ecrit ici
            // et non plus bas -- ce point est atteint que la bande soit connue
            // ou non, et c'est justement quand elle est INCONNUE que ce texte
            // sert le plus (aucune cible encore identifiee).
            dernierEntenduLibre = entenduLibre
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
                // ENCORE EN COURS ? (2026-08-05) -- meme principe que le
                // garde-fou de SAUT REFUSE plus bas : si ce qui a ete entendu
                // contient deja un des tout prochains mots attendus, meme
                // sans avoir pu le POSITIONNER (bande=null), la chaine
                // travaille encore sur la bonne zone -- ce n'est pas du texte
                // etranger.
                //
                // MESURE QUI L'IMPOSE : session live, le recitateur a repete
                // "إِنَّ ٱلَّذِينَ كَفَرُوا۟" trois fois de suite apres un
                // decrochage sur "إِنَّ" (mot trop frequent pour se
                // positionner seul, cf. Localisateur.minAppariements). Les
                // fenetres suivantes entendaient bien "ٱلَّذِينَ كَفَرُوا۟
                // سَوَآءٌ عَلَيْهِمْ" -- les mots juste apres -- sans jamais
                // localiser "إِنَّ" lui-meme, et le compteur les comptait
                // quand meme comme hors texte, redeclenchant la correction en
                // boucle malgre une recitation juste.
                val prochains = (dernierDefinitif + 1..dernierDefinitif + 6)
                    .mapNotNull { motsAttendus.getOrNull(it) }
                    .map { NormalisationComparaison.normaliser(it) }
                val entenduNorm = NormalisationComparaison.normaliser(entenduLibre)
                // >= 2, PAS 3 (2026-08-05, bug corrige dans la meme session) :
                // "إِنَّ" normalise vaut "ان", DEUX caracteres -- avec un seuil
                // a 3 ce garde-fou excluait exactement le mot qu'il devait
                // proteger, et le decrochage a continue de se declencher sur
                // ce meme mot MALGRE la correction. Verifie : "من" normalise
                // vaut aussi 2 caracteres, aucun mot attendu ne normalise a 1
                // seul caractere dans ce texte.
                val encoreEnCours = prochains.any { it.length >= 2 && entenduNorm.contains(it) }
                // DIAGNOSTIC (2026-08-05) : le garde n'a pas intercepte un cas
                // ou l'entendu contenait pourtant "إِنَّ" -- cette ligne montre
                // dernierDefinitif et les mots compares pour trouver pourquoi,
                // au lieu de deviner. A retirer une fois la cause nommee.
                journal?.invoke("[v2] f=${fenetre.id} verif encoreEnCours : " +
                    "dernierDefinitif=$dernierDefinitif prochains=$prochains " +
                    "entenduNorm=\"$entenduNorm\" -> $encoreEnCours")
                if (!encoreEnCours) {
                    fenetresHorsTexte++
                    // VALEURS EN CLAIR (2026-08-05, demande utilisateur) :
                    // compteur et seuil affiches a CHAQUE increment, pas
                    // seulement au moment du declenchement.
                    journal?.invoke("[v2] f=${fenetre.id} horsTexte : " +
                        "fenetresHorsTexte=$fenetresHorsTexte " +
                        "fenetresAvantDecrochage=$fenetresAvantDecrochage " +
                        "decrochageDejaSignale=$decrochageDejaSignale")
                    if (fenetresHorsTexte >= fenetresAvantDecrochage && !decrochageDejaSignale) {
                        decrochage = true
                        decrochageDejaSignale = true
                        motDuDecrochage = pointDeReprise()
                        journal?.invoke("[v2] f=${fenetre.id} DECROCHAGE : " +
                            "$fenetresHorsTexte fenetres hors texte, " +
                            "dernier definitif=$dernierDefinitif, " +
                            "dernier atteste vu=$dernierAttesteVu, " +
                            "reprise apres le mot $motDuDecrochage, " +
                            "dernier entendu=\"$entenduLibre\"")
                    }
                } else {
                    journal?.invoke("[v2] f=${fenetre.id} hors texte mais encore en cours " +
                        "(entendu contient un mot proche), decrochage non compte")
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
        //
        // REFERENCE : ce calcul et le refus qui suit sont desactives -- cf.
        // le commentaire de [referenceSession] au constructeur. Comportement
        // d'avant le 2026-08-01 restaure pour cette session uniquement.
        val attestesTries = bande.attestes.keys.sorted()
        var trou = 0
        var trouApres = -1
        if (!referenceSession && attestesTries.isNotEmpty()) {
            // ancrePourTrou, PAS dernierDefinitif seul (2026-08-05) : cf.
            // le commentaire de [dernierAttesteVu]. Un mot deja atteste
            // par une fenetre precedente mais pas encore verrouille ne
            // doit pas compter comme un trou.
            val ancrePourTrou = maxOf(dernierDefinitif, dernierAttesteVu)
            // ── ON NE CHERCHE UN SAUT QU'AU-DELA DE L'ANCRE (2026-08-05) ────
            //
            // Un trou ENTRE DES MOTS DEJA VALIDES n'est pas un saut : le
            // recitateur les a deja dits, ils sont juges, ils sont derriere
            // l'ancre. Le modele les reentend souvent (repetition, fenetres
            // qui se recouvrent) et n'en atteste qu'une partie -- ce qui
            // FABRIQUAIT un trou purement artificiel.
            //
            // MESURE QUI L'IMPOSE (log device 23:14:46, verset 2:13, plainte
            // utilisateur « ca marche plus bien vers le verset 12, il m'a
            // coupe alors que je recite ») :
            //     f=110 SAUT REFUSE : trou de 5 mots apres le mot 97
            //     (attestes=[97, 103, 104, 105, 106, 107]), dernier definitif=108
            // Le trou 97->103 est ENTIEREMENT derriere l'ancre (108) : ces
            // mots etaient tous deja valides. Deux fenetres comme celle-ci de
            // suite, et le decrochage coupait une recitation juste.
            val pertinents = attestesTries.filter { it >= ancrePourTrou }
            // Nombre de mots JUGEABLES strictement entre [de] et [a] : c'est
            // la seule mesure honnete d'un saut (cf. [nonJugeables]).
            fun sautEntre(de: Int, a: Int): Int {
                var n = 0
                for (i in de + 1 until a) if (i !in nonJugeables) n++
                return n
            }
            if (dernierDefinitif >= 0 && pertinents.isNotEmpty()) {
                trou = sautEntre(ancrePourTrou, pertinents.first())
                trouApres = ancrePourTrou
            }
            for (k in 1 until pertinents.size) {
                val ecart = sautEntre(pertinents[k - 1], pertinents[k])
                if (ecart > trou) {
                    trou = ecart
                    trouApres = pertinents[k - 1]
                }
            }
            // NE PAS mettre a jour [dernierAttesteVu] ici : cf. plus bas,
            // APRES le contrôle de saut. Une fenetre REFUSEE ne doit pas
            // faire avancer la reference d'ancre, sinon elle blanchit son
            // propre saut.
        }
        // UNE BANDE A ETE TROUVEE : le recitateur EST dans le texte, donc
        // l'alerte de decrochage est armee -- meme si le contrôle de saut
        // ci-dessous refuse cette fenetre (2026-08-05).
        //
        // MESURE QUI L'IMPOSE : test live d'un saut delibere fait TOT dans la
        // session. `SAUT REFUSE : trou de 20 mots` s'est bien declenche des
        // f=4, mais AUCUN decrochage n'a suivi -- `dejaLocaliseUneFois`
        // n'etait pose que PLUS BAS, apres ce contrôle. Un saut present des
        // la premiere localisation ne pouvait donc structurellement jamais
        // decrocher : le drapeau restait faux precisement parce que la
        // fenetre etait refusee, et il fallait une fenetre ACCEPTEE pour
        // l'armer. Le poser ici enleve ce cercle vicieux sans rien affaiblir
        // -- il ne dit que « le recitateur a ete localise au moins une fois »,
        // ce qui est vrai des qu'une bande existe.
        dejaLocaliseUneFois = true
        // Exception au TOUT DEBUT (aucun mot encore definitif) : on ne sait
        // pas ou le recitateur commence, et commencer au verset 2 sans dire
        // la Bismillah est legitime (constate a chaque session de test).
        // ── MODE PRIERE : LE TROU SE SIGNALE, IL NE REFUSE PLUS ─────────────
        //
        // Specification utilisateur (2026-08-07) : « les sauts seront autorises
        // pour que l'aligneur suive [...] il va juste reciter les mots qu'il
        // pense qu'il y a un oubli [...] mais apres, il faut debloquer le saut
        // [...] au lieu d'attendre l'ancre comme dans les autres modes ».
        // Et, precise ensuite : « meme quand le saut est detecte on lance le
        // souffleur, mais apres c'est l'aligneur, on ne force pas a suivre ».
        //
        // On remonte donc les bornes du trou -- de quoi souffler le passage --
        // et on LAISSE LA FENETRE VIVRE : la bande est posee, l'ancre suit le
        // recitateur la ou il est reellement. Aucune ancre ne recule, aucune
        // attente qu'il repete, et surtout AUCUN replacement d'autorite sur
        // les mots souffles : apres le souffleur, c'est le localisateur qui
        // decide, librement.
        if (sautLibre && premiereLocalisation && trou > sautMaxMots) {
            journal?.invoke("[v2] f=${fenetre.id} trou de $trou mot(s) IGNORE : " +
                "premiere localisation apres pose de cible -- c'est le " +
                "decalage d'entree, pas un oubli du recitant")
            premiereLocalisation = false
        } else if (sautLibre && dernierDefinitif >= 0 && trou > sautMaxMots) {
            // ── ON ATTEND LA FENETRE SUIVANTE AVANT DE SOUFFLER ────────────
            //
            // MESURE (session 18:33) :
            //     f=9   SAUT ACCEPTE : trou de 7 mots apres le mot 749
            //     f=9   bande=755..760            -> souffleur declenche
            //     f=10  bande=749..761 interieurs=12/13   (600 ms plus tard)
            // Les mots 750..756 etaient bien la -- simplement dans la fenetre
            // d'APRES. Le souffleur a tranche 600 ms trop tot, sur un passage
            // correctement recite.
            //
            // Meme defaut que celui mesure le matin sur `مُصْلِحُونَ` : decider
            // sur une fenetre sans attendre celle qui leve le doute. Un trou
            // constate UNE fois n'est pas un trou : c'est un cadrage de
            // fenetre. On le met donc EN ATTENTE, et on ne le signale que si
            // la fenetre suivante ne l'a pas comble.
            if (trouEnAttenteDe < 0) {
                trouEnAttenteDe = trouApres
                trouEnAttenteA = trouApres + trou + 1
                // ⚠️ LE REPERE SE POSE ICI, PAS PLUS BAS (corrige 2026-08-07).
                // Premiere version : `idFenetreTrou` n'etait ecrit qu'APRES le
                // test de confirmation. Au moment du test il valait donc encore
                // -1, et `fenetre.id > -1` etait trivialement vrai : le trou
                // etait mis en attente PUIS confirme dans la MEME fenetre.
                // Mesure : `f=1 MIS EN ATTENTE` suivi de `f=1 SAUT CONFIRME`.
                // L'attente ne durait rien, et le souffleur partait quand meme.
                idFenetreTrou = fenetre.id
                journal?.invoke("[v2] f=${fenetre.id} trou de $trou mot(s) apres " +
                    "le mot $trouApres MIS EN ATTENTE -- on laisse la fenetre " +
                    "suivante le combler avant de souffler")
            }
        }
        // Le trou en attente a-t-il ete comble par CETTE fenetre ?
        if (sautLibre && trouEnAttenteDe >= 0) {
            val comble = (trouEnAttenteDe + 1 until trouEnAttenteA)
                .all { it in nonJugeables || bande.attestes.containsKey(it) ||
                       it <= dernierDefinitif }
            if (comble) {
                journal?.invoke("[v2] f=${fenetre.id} trou en attente COMBLE " +
                    "par cette fenetre -- aucun souffleur, ce n'etait qu'un " +
                    "cadrage de fenetre")
                trouEnAttenteDe = -1
                trouEnAttenteA = -1
            } else if (fenetre.id > idFenetreTrou) {
                sautPresumeDe = trouEnAttenteDe
                sautPresumeA = trouEnAttenteA
                journal?.invoke("[v2] f=${fenetre.id} SAUT CONFIRME (mode priere) : " +
                    "le trou apres le mot $trouEnAttenteDe n'a pas ete comble " +
                    "par la fenetre suivante -- souffleur")
                trouEnAttenteDe = -1
                trouEnAttenteA = -1
            }
        }
        if (!sautLibre && !referenceSession && dernierDefinitif >= 0 && trou > sautMaxMots) {
            // LA CHAINE PROGRESSE-T-ELLE ENCORE SUR CE TROU ? (2026-08-05)
            //
            // MESURE QUI L'IMPOSE : session live, mots 35-37 "مِّن رَّبِّهِمْ"
            // -- deux SAUT REFUSE consecutifs (f=35 puis f=36) ont declenche
            // un DECROCHAGE et une correction audio inutile, alors que
            // chacune des deux fenetres attestait des mots NOUVEAUX (36,37
            // puis 38,39) juste avant de se faire refuser. Verifie sur
            // l'audio brut : "مِّن رَّبِّهِمْ" etait bien dit, et verrouille
            // vert 6 s plus tard, SANS AUCUNE aide de la correction.
            //
            // Le compteur de decrochage ne distinguait pas "la chaine est
            // en train de resoudre le trou" de "la chaine a vraiment
            // abandonne" -- les deux ressemblent au meme SAUT REFUSE repete.
            // La difference est deja dans les donnees : si [dernierAttesteVu]
            // a avance cette fenetre-ci, une NOUVELLE preuve vient d'arriver,
            // le travail continue. Il ne stagne QUE si aucune fenetre
            // n'apporte plus rien de neuf -- c'est CE cas-la, et lui seul,
            // qui doit compter vers le decrochage.
            //
            // ── CE GARDE-FOU A ETE RETIRE LE 2026-08-05, ET POURQUOI ────────
            //
            // Il reposait sur "[dernierAttesteVu] a-t-il avance pendant cette
            // fenetre ?", ce qui exigeait de mettre la reference a jour AVANT
            // le contrôle de saut. Deux regressions successives en sont nees,
            // toutes deux trouvees par l'utilisateur en testant de VRAIS
            // sauts deliberes :
            //   1. un saut de 39 mots comptait comme « encore en cours »
            //      (f=61, trou de 30 mots, attesteVu 89 -> 128) -- corrige
            //      d'abord en bornant l'avancee a [motsEnAvanceApercu] ;
            //   2. surtout : une fenetre REFUSEE posait quand meme son point
            //      d'arrivee comme nouvelle reference, donc la fenetre
            //      SUIVANTE ne voyait plus aucun trou. Mesure : saut du mot
            //      14 au mot 27, ancre montee a 27, audio de correction joue
            //      sur le mot 28 -- APRES le saut -- au lieu du mot 15, la ou
            //      le recitateur avait quitte le texte. Le saut etait refuse
            //      pour le JUGEMENT et blanchi pour la POSITION.
            //
            // La reference n'avance donc plus que sur une fenetre ACCEPTEE
            // (cf. plus bas), ce qui rend ce garde-fou sans objet ici : sur
            // une fenetre refusee l'avancee vaut toujours zero.
            //
            // Le cas qu'il protegeait ("مِّن رَّبِّهِمْ" juge vert 6 s plus tard
            // sans aide) venait en grande partie de la CIBLE JAMAIS ETENDUE
            // (cf. `etendreTexte`, corrige le meme jour) -- a re-mesurer, et
            // a retraiter par la cause si le symptome revient, pas en
            // relachant le contrôle de saut.
            journal?.invoke("[v2] f=${fenetre.id} SAUT REFUSE : trou de $trou mots " +
                "apres le mot $trouApres (attestes=${attestesTries.take(6)}...), " +
                "dernier definitif=$dernierDefinitif, max=$sautMaxMots " +
                "-- ancre inchangee, rien n'est juge")
            if (dejaLocaliseUneFois) {
                fenetresHorsTexte++
                // VALEURS EN CLAIR (2026-08-05, demande utilisateur).
                journal?.invoke("[v2] f=${fenetre.id} horsTexte (saut) : " +
                    "fenetresHorsTexte=$fenetresHorsTexte " +
                    "fenetresAvantDecrochage=$fenetresAvantDecrochage " +
                    "decrochageDejaSignale=$decrochageDejaSignale")
                if (fenetresHorsTexte >= fenetresAvantDecrochage && !decrochageDejaSignale) {
                    decrochage = true
                    decrochageDejaSignale = true
                    motDuDecrochage = pointDeReprise()
                    journal?.invoke("[v2] f=${fenetre.id} DECROCHAGE (saut) : " +
                        "dernier definitif=$dernierDefinitif, " +
                        "dernier atteste vu=$dernierAttesteVu, " +
                        "reprise apres le mot $motDuDecrochage")
                }
            }
            return
        }
        // Une fenetre s'est localisee ET a passe le contrôle de saut : le
        // recitateur suit vraiment le texte. (c) C'est SEULEMENT ici que
        // l'alerte se RE-ARME -- pas apres un simple decompte. (Le drapeau
        // `dejaLocaliseUneFois`, lui, est pose plus haut des qu'une bande
        // existe, cf. le commentaire la-bas.)
        fenetresHorsTexte = 0
        decrochageDejaSignale = false
        // ── ET L'ALERTE ELLE-MEME S'EFFACE (corrige 2026-08-07) ────────────
        //
        // `decrochage` n'etait PAS remis a faux ici -- seuls le compteur et le
        // « deja signale » l'etaient. Or `alimenter()` traite plusieurs
        // fenetres par appel, et l'appelant ne lit `decrochage` qu'A LA FIN :
        // une alerte levee par une fenetre ANTERIEURE partait donc alors
        // qu'une fenetre plus recente venait de prouver le contraire.
        //
        // MESURE (session 18:57, recitation normale) :
        //     [V2] mot=73 "بِمُؤْمِنِينَ" -> definitif:VERT  gop=0,00
        //     18:57:01.840  Decrochage signale -- dernierDefinitif=72
        //     18:57:01.845  wordFailed ... status=WordStatus.correct
        // L'application corrigeait un mot qu'elle venait elle-meme de declarer
        // juste, 5 ms plus tot. L'utilisateur : « il n'attend pas le jugement
        // final ! » -- c'est exactement cela.
        //
        // Le garde-fou du 2026-07-25 (« le mot est-il encore faux ? ») ne
        // couvrait pas ce chemin : le decrochage entre avec `surSilence` et
        // saute la verification, parce qu'il est cense parler de la
        // recitation entiere et non d'un mot. Il faut donc l'annuler A LA
        // SOURCE, ici, ou l'on sait que le recitateur suit.
        decrochage = false
        motDuDecrochage = -1
        // SEULEMENT MAINTENANT (2026-08-05) : la fenetre a passe le contrôle
        // de saut, son attestation peut servir de reference aux suivantes.
        //
        // MESURE QUI L'IMPOSE : test live d'un saut delibere (mot 14 -> 27).
        // `dernierAttesteVu` etait mis a jour AVANT le contrôle, donc meme
        // une fenetre REFUSEE posait le point d'arrivee du saut (27) comme
        // nouvelle reference. La fenetre suivante calculait alors son trou
        // depuis 27 au lieu de 14 -- le saut avait disparu, l'ancre montait
        // a 27, et l'audio de correction repartait du mot 28 (APRES le
        // saut) au lieu du mot 15 (la ou le recitateur avait quitte le
        // texte). Le saut etait refuse pour le JUGEMENT mais blanchi pour la
        // POSITION.
        if (bande.attestes.isNotEmpty()) {
            dernierAttesteVu = maxOf(dernierAttesteVu, bande.attestes.keys.max())
        }
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
            // ── DESACTIVE : MESURE PERDANTE (2026-08-06) ───────────────────
            //
            // Passer le TEXTE fait explorer a l'aligneur TOUTES les ecritures
            // du mot (cf. AligneurForce.grapheEcritures) au lieu de la seule
            // tokenisation du dictionnaire. Ca corrige parfaitement le cas
            // isole -- banc : frames 1 -> 14, gop -11,99 -> 0,00 sur le mot
            // dont la cible imposait une piece que le modele n'avait pas
            // produite.
            //
            // MAIS LA MESURE D'ENSEMBLE LE REFUTE. Rejeu DETERMINISTE du meme
            // WAV Al-Baqara, meme binaire a ce parametre pres :
            //     sans le texte : 2/295 = 0,68 % de mots non verts
            //     avec le texte : 22/295 = 7,46 %
            // Onze fois plus. La tokenisation du dictionnaire ne genait donc
            // pas : elle CONTRAIGNAIT utilement. Libre de re-epeler chaque
            // mot, la DP trouve des chemins qui marquent bien localement mais
            // deplacent les frontieres de mots -- et les voisins paient.
            //
            // Le code de `grapheEcritures` est CONSERVE et non branche : il
            // porte la mesure, et l'idee reste bonne pour un usage BORNE (par
            // exemple n'ouvrir les ecritures que pour le mot dont le gop
            // s'effondre alors que `free` est proche de 0, au lieu de toute la
            // bande). C'est cette forme-la qu'il faudra mesurer, pas celle-ci.
            // ── LA FORME BORNEE A ECHOUE AUSSI (2026-08-06) ────────────────
            //
            // Troisieme tentative sur ce sujet, troisieme refutation. Rescorer
            // le SEUL mot condamne, sur l'audio libre entre ses voisins, en
            // gardant le maximum : 0,68 % -> 6,12 % de mots non verts sur le
            // meme WAV.
            //
            // POURQUOI, et c'est une erreur de conception de ma part : le score
            // est une MOYENNE PAR FRAME. Elargir la plage y ajoute des frames
            // de silence, dont la probabilite de blanc est elevee -- la moyenne
            // monte donc artificiellement, le rescoring gagne presque partout
            // et remplace de bons alignements par des plages larges vides de
            // sens. Comparer une moyenne sur 1 frame a une moyenne sur 12 n'est
            // pas une comparaison.
            //
            // Ce qu'il faudrait pour reessayer : un score COMPARABLE entre deux
            // plages de longueurs differentes (par exemple le score total du
            // seul chemin des jetons, silences exclus), et non une moyenne.
            // Tant que ce point n'est pas resolu, ne pas rebrancher.
            // textesParMot = motsAttendus.subList(bande.i0, bande.i1 + 1),
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

        // ETENDUE REELLE DE CHAQUE MOT, blancs compris (2026-08-04).
        //
        // `premiereFrame`/`derniereFrame` ne bornent QUE les frames ou le CTC a
        // EMIS les tokens du mot : AligneurForce ecarte explicitement les
        // blancs (« le blanc n'appartient a aucun mot »). Or le CTC est peaky
        // -- il claque ses tokens sur une ou deux frames et reste blanc sur
        // tout le reste du son. Mesure sur device : `إِنَّمَا` (quatre syllabes)
        // ressort avec `frames=1`, et `إِلَّآ` (qui porte un madd) avec
        // `frames=2`, tous deux PARFAITEMENT reconnus (gop=0,00, entendu
        // exact). Ces bornes mesurent donc des PICS D'EMISSION, pas une duree.
        //
        // Consequence pour la tete 2 : elle emet sa sigmoide sur la duree
        // REELLE de la regle, tandis qu'on la cherchait dans une fenetre de
        // 80 a 160 ms -- le madd tombait a cote, et l'app concluait « regle
        // attendue NON DETECTEE » sur les mots 76 `إِلَّآ` et 100 `إِنَّمَا`
        // alors que la regle etait bien la, juste en dehors de la fenetre.
        // C'etait un defaut de la FENETRE DE RECHERCHE, pas du recitateur.
        //
        // On borne donc chaque mot par ses voisins : du dernier pic du mot
        // precedent (exclu) au premier pic du suivant (exclu). Les blancs
        // reviennent ainsi au mot auquel ils appartiennent acoustiquement.
        // Cette etendue ne sert QU'A CHERCHER LES REGLES : les scores des
        // lettres (forced/free/gop) continuent d'etre calcules sur les seules
        // frames emises, strictement comme avant -- aucun verdict de lettre
        // ne change.
        val avecFrames = res.mots.filter { it.frames > 0 }
        val etendue = HashMap<Int, Pair<Int, Int>>(avecFrames.size)
        for ((k, m) in avecFrames.withIndex()) {
            val precedent = avecFrames.getOrNull(k - 1)
            val suivant = avecFrames.getOrNull(k + 1)
            val d = if (precedent == null) m.premiereFrame else precedent.derniereFrame + 1
            val f = if (suivant == null) m.derniereFrame + 1 else suivant.premiereFrame
            etendue[m.index] = Pair(minOf(d, m.premiereFrame), maxOf(f, m.derniereFrame + 1))
        }

        for (m in res.mots) {
            val debutAbs = if (m.frames > 0) fenetre.absoluDeFrame(m.premiereFrame) else -1L
            val finAbs = if (m.frames > 0) fenetre.absoluDeFrame(m.derniereFrame) else -1L
            // TETE 2 : la frame est CAPITALE pour attribuer une regle au bon
            // mot (cf. FastConformerCtc.decodeTajwid) -- on cherche donc dans
            // l'ETENDUE du mot (cf. `etendue` ci-dessus), et non dans ses
            // seules frames emises, qui ne durent qu'un ou deux pics.
            val reglesTajwid = if (m.frames > 0 && sorties.tajwid != null) {
                val bornes = etendue[m.index]
                val debut = (bornes?.first ?: m.premiereFrame)
                    .coerceIn(0, sorties.tajwid.size)
                val fin = (bornes?.second ?: (m.derniereFrame + 1))
                    .coerceIn(debut, sorties.tajwid.size)
                val detections = front.decodeTajwid(
                    sorties.tajwid.copyOfRange(debut, fin))
                // DUREE JOURNALISEE, JAMAIS JUGEE (2026-08-04). Le type d'un
                // madd (`wajib` / `tabi'i`) est une categorie GRAMMATICALE que
                // le texte connait deja ; l'acoustique ne peut repondre qu'a
                // « combien de temps a dure l'allongement ». On expose donc
                // cette duree pour pouvoir la MESURER sur du vrai audio avant
                // de decider si elle peut servir de critere -- pas l'inverse.
                if (detections.isNotEmpty()) {
                    journal?.invoke("[tajwidDuree] mot=${m.index} " +
                        detections.joinToString(" ") { d ->
                            val nom = front.nomsRegles.getOrNull(d.ruleId) ?: "?${d.ruleId}"
                            "$nom=${d.frames}f(${d.frames * 80}ms)"
                        })
                }
                detections.map { it.ruleId }.distinct()
            } else emptyList()
            // TETE 3 : OBSERVATION SEULE (journal), cf. vecteurTete3 ci-dessous
            // -- ne touche ni Observation ni le statut.
            if (tete3 != null && sorties.etat != null && m.frames > 0) {
                val vec = vecteurTete3(m, sorties.etat, logprobs)
                if (vec == null) {
                    // ABSTENTION, et elle se dit. Un mot sans variante scorable
                    // ou sans chemin force n'est pas « correct » : il est
                    // INJUGEABLE par cette tete. Sans cette ligne, la difference
                    // entre « la tete l'a vu bon » et « la tete n'a rien vu du
                    // tout » serait invisible dans le log -- exactement le
                    // « zero trace = zero execution » deja paye sur le secours.
                    journal?.invoke("[t3] mot=${m.index} ABSTENTION")
                } else if (vec.size != tete3.tailleEntree) {
                    // Taille incoherente = mauvais fichier de tete deploye. On
                    // le dit une bonne fois plutot que de laisser la tete se
                    // taire : c'est le cas ou l'app tournait avec une tete a
                    // 524 caracteristiques nourrie d'un vecteur d'un autre
                    // format, et rendait des logits denues de sens.
                    journal?.invoke("[t3] mot=${m.index} TETE INCOMPATIBLE : " +
                        "vecteur=${vec.size}, tete=${tete3.tailleEntree}")
                } else {
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
     * TETE 3 : le vecteur d'entree, calcule EXACTEMENT comme le Python qui a
     * entraine la tete -- cf. [Tete3Traits], teste par `Tete3TraitsTest` contre
     * un vecteur de reference produit sur un vrai audio par un vrai modele.
     *
     * ── CE QUE CETTE FONCTION CALCULAIT AVANT LE 2026-08-05, ET POURQUOI ────
     *
     * Elle rendait une APPROXIMATION, honnetement documentee comme telle et
     * cantonnee a l'observation faute de pouvoir faire mieux :
     *
     *   | grandeur | avant                        | maintenant              |
     *   |----------|------------------------------|-------------------------|
     *   | etat     | moyenne seule (512)          | moyenne + ecart-type (1024) |
     *   | forced_f | recopiait forced_v (Viterbi) | vrai forward CTC        |
     *   | alt/alt2 | 2 confusions de l'aligneur   | jeu complet de variantes |
     *
     * Les trois divergeaient du Python, et AUCUNE ne se voyait a l'execution :
     * la tete rendait un logit, il etait simplement faux. C'est ce que le
     * telephone a fait toute la journee du 2026-08-04 (lignes `[t3] logit=...`
     * du journal, produites sur des entrees sans rapport avec l'entrainement).
     *
     * ⇒ Le seul garde-fou possible est le test de parite, et il est desormais
     * la. Il a d'ailleurs immediatement attrape un defaut REEL et partage avec
     * le Python : le filtre de sentinelle comparait le score DIVISE par le
     * nombre de frames, si bien qu'au-dela de 2 frames il ne filtrait rien --
     * `alt2` a -2,5e29 et un logit a 3,7e29.
     *
     * ── TOUJOURS OBSERVATION SEULE ─────────────────────────────────────────
     *
     * La parite du CALCUL ne prouve pas la valeur du VERDICT : les 47 % de
     * detection ont ete mesures hors device, sur des fenetres decoupees par le
     * banc, avec les logprobs d'un modele PyTorch. Sur l'appareil les frames
     * viennent du localisateur et le modele est un export ONNX. Rien ne doit
     * dependre de cette tete tant qu'une recette ne l'a pas confirme.
     */
    private fun vecteurTete3(
        m: AligneurForce.MotAligne, etat: Array<FloatArray>, logp: Array<FloatArray>,
    ): FloatArray? {
        if (m.frames <= 0) return null
        val tokens = tokensAttendus.getOrNull(m.index) ?: return null
        if (tokens.isEmpty()) return null
        val variantes = confusionsTete3.getOrNull(m.index) ?: return null

        val borne = minOf(etat.size, logp.size)
        val f0 = m.premiereFrame.coerceIn(0, borne)
        val f1 = (m.derniereFrame + 1).coerceIn(f0, borne)
        if (f1 <= f0) return null

        // Les logprobs des SEULES frames du mot : le Python passe `tr = lp[f0:f1]`
        // a `caracteristiques`, jamais la fenetre entiere.
        val tranche = Array(f1 - f0) { logp[f0 + it] }
        val traits = Tete3Traits.caracteristiques(tranche, tokens, variantes) ?: return null
        val etatVec = Tete3Traits.etatMoyenEtEcartType(etat, f0, f1) ?: return null
        return etatVec + traits
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

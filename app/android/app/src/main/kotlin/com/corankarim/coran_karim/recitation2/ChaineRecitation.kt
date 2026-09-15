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
/** Duree MINIMALE qu'une regle de tajwid doit tenir pour etre comptee
 *  realisee (2026-09-02).
 *
 *  ── POURQUOI LA DUREE, ET PAS LA PROBABILITE ────────────────────────────
 *  Mesure du 2026-09-02, meme sourate (Al-Balad), deux recitations : celle
 *  de l'utilisateur s'efforcant de NE PAS appliquer le tajwid, et celle d'un
 *  recitateur professionnel qui l'applique.
 *
 *  Les POIDS de la tete ne separent pas les deux : 0,98-1,00 des deux cotes,
 *  9 ecarts sur 14 sous 0,05, et meme DEUX mots ou le professionnel sort un
 *  poids PLUS BAS. La tete dit « la regle est la », pas « elle est faite ».
 *
 *  Les DUREES, elles, separent nettement : mediane x2,0, total 3 600 ms
 *  contre 7 280 ms sur les memes 14 regles. C'est coherent avec ce qu'est le
 *  tajwid -- une ghunna se tient deux temps, un madd s'allonge, une qalqala
 *  resonne. Ce sont des durees, pas des presences.
 *
 *  ── D'OU VIENNENT CES CHIFFRES ──────────────────────────────────────────
 *  STRICT = 75e percentile du RECITATEUR PROFESSIONNEL, par regle, arrondi a
 *  la frame (80 ms). TOLERANT = la moitie, choix utilisateur du 2026-09-02
 *  (« strict p75 et tolerant on va dire 50 % »).
 *
 *  ⚠️ ECHANTILLON FAIBLE, a reprendre des qu'on a plus d'audio : n=16 pour
 *  qalaqah, mais n=1 pour iqlab, n=2 pour ghunnah, n=3 pour idgham_ghunnah.
 *  Un seuil tire d'une seule observation n'est pas une mesure, c'est un point.
 *  Les valeurs sont volontairement dans UNE table lisible plutot que dispersees
 *  dans le code, pour qu'un recalibrage soit un changement de chiffres.
 *
 *  Une regle absente de la table n'est PAS filtree (seuil 0) : on ne rejette
 *  jamais sur un seuil qu'aucune mesure ne fonde. */
object SeuilsDureeTajwid {
    /** (tolerant, strict) en ms, par regle.
     *
     *  ── RECALIBRE LE 2026-09-02, APRES UN PREMIER JEU TROP SEVERE ────────
     *  Le premier calibrage prenait le p75 du professionnel comme STRICT et
     *  sa moitie comme tolerant. Mesure immediate : le professionnel
     *  lui-meme ne passait qu'a 34 % en strict et 87 % en tolerant --
     *  autrement dit le mode « tolerant » refusait une regle sur huit a un
     *  recitateur qui les applique toutes. Signale par l'utilisateur :
     *  « tu l'as rendu trop exigeant, meme le dernier test recitateur vrai
     *  ne passe pas dans le tolerant ». Il avait raison, et l'erreur etait
     *  de calibrer par le HAUT de la distribution : un seuil place au p75
     *  rejette par construction 25 % de ce qu'il devrait accepter.
     *
     *  ── CE SUR QUOI CES CHIFFRES SONT MESURES ────────────────────────────
     *  Al-Afasy sur Al-Balad, WAV deterministe rejoue dans l'app, MODELE
     *  REELLEMENT DEPLOYE (le PC ne sait pas executer cet INT8 : ConvInteger
     *  en UINT8, absent d'onnxruntime CPU). n = 40 mesures pour qalaqah,
     *  37 pour le triplet du nun, 33 pour idgham_wo_ghunnah -- au lieu des
     *  1 a 3 du premier jeu.
     *
     *  TOLERANT = p10 du professionnel, STRICT = p25, arrondis a la frame
     *  (80 ms). Taux de passage VERIFIES sur lui : 95-100 % en tolerant,
     *  73-82 % en strict.
     *
     *  ⚠️ FAIT MESURE A CONNAITRE : meme chez le professionnel, le MINIMUM
     *  observe est 80 ms (une frame) sur presque toutes les regles. Aucun
     *  seuil au-dessus d'une frame ne peut donc accepter 100 % de ses
     *  detections -- une part d'entre elles sont des declenchements parasites
     *  qu'il ne « fait » pas non plus. C'est la raison pour laquelle on vise
     *  un percentile bas et non le minimum.
     *
     *  ── REGLES SANS SEUIL, ET POURQUOI ───────────────────────────────────
     *  Sous 8 mesures, aucun seuil n'est pose (0 = pas de filtre) :
     *  idgham_mutajanisayn (7), madda_necessary (3), ikhafa_shafawi (2),
     *  idgham_shafawi (2), ghunnah (2), idgham_mutaqaribayn (1). Un seuil
     *  tire d'une ou deux observations n'est pas une mesure. Elles passent
     *  donc comme avant, jusqu'a ce qu'on ait de l'audio pour les calibrer. */
    // ── DERIVES DE LA MOYENNE MESUREE SUR CINQ RECITATEURS (2026-09-03) ──
    //
    // Source : `transfert_2026-08-31/tajwid/seuils_tajwid_5reciteurs_jvm.json`
    // -- Ayman Sowaid, Husary, Abdul Basit Murattal, Minshawy Murattal,
    // As-Sudais, sur 90:1..20, decoupage de la VRAIE chaine de l'app
    // (BancFluxBrut / ConstructeurDeFenetres), pas d'une reimplementation.
    //
    // Regle posee par l'utilisateur : « le strict ne doit pas etre plus que la
    // moyenne mesuree ; strict a 90 % de la moyenne, tolere a 70 % ». Le
    // raisonnement tient : exiger PLUS que la moyenne de recitateurs
    // professionnels en rejetterait la moitie.
    //
    //   regle                moyenne   strict 90%   tolere 70%
    //   ghunnah               179 ms      161 ms       125 ms
    //   idgham_ghunnah        247 ms      222 ms       173 ms
    //   idgham_wo_ghunnah      83 ms       75 ms        58 ms
    //   ikhafa                247 ms      222 ms       173 ms
    //   iqlab                 247 ms      222 ms       173 ms
    //   madda_obligatory      113 ms      102 ms        79 ms
    //   madda_permissible     166 ms      149 ms       116 ms
    //   qalaqah               121 ms      109 ms        85 ms
    //
    // CE QUI CHANGE PAR RAPPORT AUX VALEURS PRECEDENTES (p10/p25 d'un banc
    // anterieur) : `madda_permissible` etait a 160 ms en strict alors que la
    // moyenne mesuree vaut 166 -- un professionnel y etait juge TROP COURT.
    // `ghunnah` n'etait pas calibree du tout et ne l'est plus par defaut.
    // `ikhafa`/`iqlab`/`idgham_ghunnah` passent de 320 a 222 ms en strict.
    //
    // ⚠️ Les neuf autres regles n'ont PAS de duree mesuree chez les cinq
    // (`duree_moyenne_s: null`) : elles restent hors de cette table, et
    // `minMs` rend 0 pour elles -- aucune exigence de duree, comme avant.
    // ── MESURES SUR UNE RECITATION REELLE (2026-09-03) ───────────────────
    //
    // Methode posee par l'utilisateur : « tu as une recitation de quelqu'un qui
    // applique surement le tajwid et une qui n'a pas voulu appliquer, cherche
    // entre les deux pour definir deux niveaux ». Deux prises de la meme
    // personne sur la meme sourate, intentions opposees : un jeu ETIQUETE.
    //
    // REFERENCE = mediane de TOUTES les regles attendues dans la prise « avec »
    // -- detectees, refusees par le seuil, ET refusees par la duree. Ne prendre
    // que les detectees serait un biais de selection : on ne compterait que les
    // rescapes. Erreur commise deux fois dans la journee avant d'etre vue.
    //
    // strict = 90 % de la reference, tolerant = 70 % -- le meme principe que
    // pour les seuils de probabilite, applique cette fois a la recitation
    // reelle et non a la moyenne de cinq professionnels.
    //
    //   regle                reference   strict   tolerant   n
    //   ghunnah                 480 ms   432 ms    336 ms    1
    //   idgham_ghunnah          800 ms   720 ms    560 ms    3
    //   idgham_wo_ghunnah       160 ms   144 ms    112 ms    3
    //   ikhafa                  480 ms   432 ms    336 ms    6
    //   iqlab                   720 ms   648 ms    504 ms    1
    //   madda_obligatory         80 ms    72 ms     56 ms    2
    //   madda_permissible       280 ms   252 ms    196 ms    2
    //   qalaqah                 160 ms   144 ms    112 ms    8
    //
    // ⚠️ EFFECTIFS FAIBLES, ET IL FAUT LE SAVOIR : une seule occurrence pour
    // `ghunnah` et `iqlab`, deux pour les madd. Ces valeurs decrivent UNE prise
    // de vingt versets. Elles remplacent des seuils cales sur cinq
    // professionnels dont on a mesure qu'ils refusaient des regles bel et bien
    // faites -- c'est un progres, pas une verite. A refaire sur une sourate
    // entiere.
    //
    // ⚠️ `qalaqah` reste le point noir : son signal est ANTI-CORRELE entre les
    // deux prises (p mediane 0,859 quand elle est appliquee contre 0,958 quand
    // elle ne l'est pas, sur 16 et 17 exemples). Ses seuils sont poses comme
    // les autres, mais elle ne devrait pas produire de verdict tant que ce
    // point n'est pas instruit -- elle faisait 10 des 14 mots violets.
    // ── CALES SUR LE MINIMUM REELLEMENT REALISE (2026-09-03) ─────────────
    //
    // Exigence de l'utilisateur, et c'est le bon critere : pour celui qui fait
    // bien le tajwid, les violets doivent passer -- un recitateur qui applique
    // les regles ne doit pas etre signale en erreur.
    //
    // La mediane ne suffisait pas : elle refusait la moitie des realisations.
    // On cale donc sur le MINIMUM observe sur deux prises ou les regles sont
    // appliquees, moins 10 % (strict) et 30 % (tolerant). Rien de ce qui a ete
    // reellement realise ne doit etre refuse.
    //
    //   regle                min observe   strict   tolerant   n
    //   ghunnah                    80 ms    72 ms     56 ms    2
    //   idgham_ghunnah            720 ms   648 ms    504 ms    3
    //   idgham_wo_ghunnah          80 ms    72 ms     56 ms    6
    //   ikhafa                     80 ms    72 ms     56 ms    8
    //   iqlab                     560 ms   504 ms    392 ms    2
    //   madda_obligatory           80 ms    72 ms     56 ms    3
    //   madda_permissible          80 ms    72 ms     56 ms    5
    //
    // CE QUE CELA COUTE, ET IL FAUT LE SAVOIR : la duree d'une detection tombe
    // par pas de 80 ms (une frame). Un minimum de 80 ms signifie donc "une
    // seule frame", et tout seuil au-dessus refuse cette realisation. Poser le
    // strict a 72 ms revient a NEUTRALISER le critere de duree pour six regles
    // sur sept -- seules idgham_ghunnah et iqlab, dont les realisations sont
    // longues, gardent un seuil qui filtre.
    //
    // Ce n'est PAS un critere deplace pour faire disparaitre un symptome : la
    // mesure dit que ces durees SONT celles d'une recitation correcte. C'est la
    // GRANULARITE de 80 ms qui rend le critere grossier -- un vrai filtre de
    // duree demanderait une resolution plus fine, pas un seuil plus haut.
    //
    // qalaqah n'y figure plus : elle n'est plus jugee du tout (cf.
    // _signalNonFiable cote Dart, son signal etant anti-correle).
    // ── SEUILS DE DUREE NEUTRALISES (2026-09-05) ──────────────────────────
    //
    // Ils rejetaient des detections PARFAITES. Mesure sur la session du
    // 2026-09-05, tete v7, 86 rejets :
    //
    //   mot=12 «وَوَالِدٍ»  idgham_ghunnah p=1,000  REJETEE 560ms < 648ms
    //   mot=22 «لَّن»       idgham_ghunnah p=1,000  REJETEE 480ms < 648ms
    //   mot=39 «وَلِسَانًا» idgham_ghunnah p=1,000  REJETEE 480ms < 648ms
    //   mot=9  «حِلٌّۢ»      iqlab          p=0,769  REJETEE 400ms < 504ms
    //
    // La tete voyait la regle a 1,000 et le filtre la jetait : d'ou
    // `idgham_ghunnah` a 13 % de detection et `iqlab` a 0 %, et 11 des 24
    // violets de la session -- sur une recitation ou la regle etait FAITE.
    //
    // POURQUOI CES SEUILS ETAIENT FAUX DES LE DEPART. Ils ont ete calibres le
    // 2026-09-03 sur la duree rendue par `decodeTajwid` -- le nombre de frames
    // CONSECUTIVES au-dessus du seuil. Or l'utilisateur avait lui-meme montre
    // le jour meme que cette grandeur ne mesure PAS le phenomene : « impossible
    // un madd obligatoire en 80 ms !! c'est sur 4 a 6 temps ! il y a un truc
    // qui cloche dans tes calculs ». On avait alors etabli que `frames` capte
    // le PIC de detection, pas la tenue de la regle -- et j'ai quand meme
    // calibre des seuils dessus, puis mesure trois fois de suite dessus.
    //
    // A 0, le filtre est inerte : c'est la PROBABILITE qui decide, seule
    // grandeur dont on ait verifie qu'elle mesure ce qu'elle pretend. La duree
    // reste JOURNALISEE (`[tajwidDuree]`) -- observation, jamais verdict, comme
    // elle aurait toujours du l'etre.
    //
    // Ne pas les remettre sans avoir d'abord etabli, sur du vrai audio, ce que
    // `frames` mesure exactement.
    // ── REMIS, SUR MESURE DE CINQ RECITATEURS REELS (2026-09-11) ──────────
    //
    // La condition posee juste au-dessus a recu une reponse : PC A a livre
    // `seuils_tajwid_avec_durees_5reciteurs.json` (transfert
    // 2026-09-11_production_v2), calibre sur CINQ recitateurs Hafs reels
    // -- Ayman Sowaid, Husary, Abdul Basit, Minshawy, As-Sudais, sourate 90 --
    // et surtout avec le VRAI decoupage de la chaine app
    // (BancFluxBrut/ConstructeurDeFenetres), pas des clips isoles. C'est la
    // premiere fois que ces durees viennent du meme regime que la production.
    //
    // Valeurs = `duree_moyenne_s` du fichier, x0,90 (strict) et x0,70
    // (tolerant) -- facteurs choisis par l'utilisateur, memes que ceux deja
    // employes pour ce meme reglage le 2026-09-03.
    //
    //   regle                moyenne   strict   tolerant
    //   madda_obligatory       200 ms   180 ms    140 ms
    //   madda_permissible      200 ms   180 ms    140 ms
    //   madda_normal           100 ms    90 ms     70 ms
    //   ghunnah                194 ms   175 ms    136 ms
    //   ikhafa                 179 ms   161 ms    125 ms
    //   idgham_ghunnah         154 ms   139 ms    108 ms
    //   iqlab                  134 ms   121 ms     94 ms
    //   idgham_wo_ghunnah      134 ms   121 ms     94 ms
    //   qalaqah                129 ms   116 ms     90 ms
    //
    // ⚠️ CE QUE LA GRANULARITE DE 80 ms EN FAIT REELLEMENT. Une detection ne
    // peut valoir que 0, 80, 160, 240 ms... Le seuil effectif est donc
    // l'arrondi SUPERIEUR au multiple de 80 :
    //
    //   madda_obligatory / madda_permissible / ghunnah / ikhafa
    //                              strict -> 3 frames (240 ms)
    //                              tolerant -> 2 frames (160 ms)
    //   idgham_ghunnah / iqlab / idgham_wo_ghunnah / qalaqah
    //                              strict ET tolerant -> 2 frames (160 ms)
    //   madda_normal               strict -> 2 frames (160 ms)
    //                              tolerant -> 1 frame  (80 ms)
    //
    // ⚠️ ET CE QU'IL FAUT SURVEILLER, parce que la mesure le dit deja. Le
    // rapport livre le MEME jour (`rapport_tenue_max_madd_v2_maxfenetres_
    // 2026-09-11.json`), qui corrige pourtant le biais de fenetre signale par
    // l'utilisateur, donne des medianes de 1 a 3 frames pour les madd et
    // conclut lui-meme :
    //     "ordre_attendu_respecte_sur_mediane": false
    // -- le madd LAZIM (6 harakat, le plus long par definition) y ressort plus
    // COURT que le permissible, et l'obligatoire le plus court des trois. Si
    // cette grandeur mesurait la tenue, cet ordre serait respecte par
    // construction. Le doute du 2026-09-05 n'est donc pas leve : `frames`
    // capte probablement toujours le pic, pas la tenue.
    //
    // Le risque concret est celui deja mesure le 2026-09-05 (86 rejets, dont
    // des `idgham_ghunnah` a p=1,000) : des regles REELLEMENT FAITES rejetees
    // parce que leur pic tient sur une frame. A surveiller en premier dans le
    // journal : les lignes `[tajwidDuree] ... REJETEE` sur une recitation
    // dont on sait que la regle est appliquee. Si elles reviennent, c'est
    // cette table qu'il faut revider -- pas un seuil a deplacer.
    //
    // Format : Pair(tolerant, strict), cf. `minMs` juste en dessous.
    /** ── SEUILS DE PROBABILITE : 0,80 STRICT / 0,50 TOLERANT (2026-09-11) ──
     *
     *  Decision utilisateur : « garde 0,5 pour le tolerant et mets 0,8 pour le
     *  strict ». Avant ce jour : 0,50 strict / 0,40 tolerant. Le strict
     *  exigeait donc a peine plus qu'un tirage a pile ou face pour affirmer
     *  qu'une regle est realisee, alors que la mesure des cinq recitateurs
     *  montre des confiances naturelles bien plus hautes.
     *
     *  Ces deux constantes sont les VALEURS REELLES appliquees -- c'est
     *  `facteurProba` juste en dessous qui fait la conversion vers ce
     *  qu'attend le decodeur. Ecrire 1,60 ici (le facteur equivalent) avait
     *  ete la premiere version, et elle rendait le code illisible : on y
     *  lisait 1,60 pour un seuil qui vaut 0,80. */
    const val P_STRICT = 0.80f
    const val P_TOLERANT = 0.50f

    /** Seuil ecrit dans `seuils_tajwid.json` pour les 14 regles jugees.
     *
     *  `decodeTajwid` ne prend pas un seuil mais un FACTEUR : il multiplie le
     *  seuil de chaque classe par ce qu'on lui passe (en log). Pour obtenir
     *  exactement [P_STRICT] / [P_TOLERANT], on divise donc par la valeur du
     *  fichier. */
    private const val P_FICHIER = 0.50f

    /** Le facteur a passer a `decodeTajwid` pour obtenir le seuil voulu.
     *
     *  ⚠️ SUPPOSE QUE LE FICHIER DONNE [P_FICHIER]. C'est le cas du pack
     *  deploye (0,50 sur les 14 regles jugees, 1,10 sur les 3 portees par le
     *  texte -- ces dernieres sont protegees par le garde `seuilBrut >= 0f`
     *  de `decodeTajwid`, le facteur ne les rallume pas).
     *
     *  Si un jour on adopte `seuils_tajwid_avec_durees_5reciteurs.json`
     *  (livre le 2026-09-11, non adopte), qui porte 0,999 sur huit regles,
     *  ce calcul devient faux : 0,999 x 1,60 = 1,60, soit une probabilite
     *  impossible -- la regle ne serait PLUS JAMAIS detectee, et en silence.
     *  Il faudra alors passer `decodeTajwid` a un seuil absolu plutot qu'a un
     *  facteur (trois autres appelants s'en servent avec la valeur par
     *  defaut, c'est pour eux qu'on ne l'a pas fait tout de suite). */
    fun facteurProba(strict: Boolean): Float =
        (if (strict) P_STRICT else P_TOLERANT) / P_FICHIER

    private val SEUILS_MS = mapOf(
        // `madda_necessary` ALIGNEE SUR LES AUTRES MADD (2026-09-11, demande
        // utilisateur : « pareil pour madd necessary »). Le fichier des cinq
        // recitateurs ne lui donne aucune duree (`null`) -- elle serait donc
        // restee SANS exigence, ce qui n'a pas de sens : le madd lazim tient
        // 6 harakat, le plus long des trois, et il aurait ete le seul a
        // passer quelle que soit sa duree.
        //
        // Valeur alignee sur l'obligatoire et le permissible plutot que
        // deduite : la theorie voudrait un seuil PLUS haut (6 temps contre
        // 4-5), mais aucune mesure ne le fonde ici, et inventer un chiffre
        // plus severe rejetterait des realisations correctes. Le jour ou une
        // duree est mesuree pour elle, c'est cette ligne qu'on ajuste.
        "madda_necessary" to Pair(140, 180),
        "madda_obligatory" to Pair(140, 180),
        "madda_permissible" to Pair(140, 180),
        "madda_normal" to Pair(70, 90),
        "ghunnah" to Pair(136, 175),
        "ikhafa" to Pair(125, 161),
        "idgham_ghunnah" to Pair(108, 139),
        "iqlab" to Pair(94, 121),
        "idgham_wo_ghunnah" to Pair(94, 121),
        "qalaqah" to Pair(90, 116),
        // Sans duree mesuree dans le fichier (`duree_moyenne_s: null`) :
        // ikhafa_shafawi, idgham_shafawi, idgham_mutajanisayn,
        // idgham_mutaqaribayn, laam_shamsiyah, ham_wasl, slnt. Absentes de la
        // table -> `minMs` rend 0 -> aucune exigence de duree, exactement
        // comme avant. On ne rejette jamais sur un chiffre qu'aucune mesure
        // ne fonde. (`madda_necessary` etait de cette liste jusqu'au
        // 2026-09-11 : elle en sort par alignement, cf. sa ligne plus haut.)
    )


    /** @param nom nom de la regle tel que `rules.json` le donne.
     *  @param strict rigueur choisie dans l'ecran Reciter.
     *  @return duree minimale en ms, 0 si la regle n'est pas calibree. */
    fun minMs(nom: String, strict: Boolean): Int {
        val s = SEUILS_MS[nom] ?: return 0
        return if (strict) s.second else s.first
    }
}

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
    /** Ecritures equivalentes. Par defaut = chemin historique Hafs. */
    private val variantesOrthographe: (String) -> List<String> = Orthographe::variantes,
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
    /** Instrumentation du vote A/B/C. Aucun effet sur les statuts ou l'ancre.
     * Les poids CTC bruts doivent etre mesures sur les erreurs ET les temoins. */
    private val observerVoteFenetres: Boolean = false,
    /** TETE 3 (ecart canonique), OPTIONNELLE. Cf. Tete3.kt : tant que la
     *  parite des 12 scores n'est pas verifiee sur device, sa sortie est
     *  seulement JOURNALISEE -- elle ne doit influencer aucun statut. */
    private val tete3: Tete3? = null,
    /** Candidate sur le MEME vecteur, journal seulement, aucun effet sur le verdict. */
    private val tete3Comparaison: Tete3? = null,
    /** Tete Hafs verifiee reservee au jugement experimental par occurrence. */
    private val tete3Jugement: Tete3? = null,
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
    /** Rigueur du tajwid au moment de creer la chaine. Passee au constructeur
     *  plutot que laissee au defaut : une chaine recreee en cours de session
     *  (nouvelle cible, changement de mode) doit repartir sur le choix de
     *  l'utilisateur, pas sur le defaut. */
    tajwidStrictInitial: Boolean = true,
) {
    /** Rigueur du tajwid, poussee par `v2SetFusion(tajwidStrict:)`.
     *  STRICT par defaut : c'est la valeur qu'avait le commutateur « Rigueur
     *  de la correction » quand il a ete retire le 2026-08-10, et partir en
     *  tolerant changerait le comportement de qui n'y touche jamais. */
    @Volatile var tajwidStrict: Boolean = tajwidStrictInitial

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

    /**
     * Position (`travailDebut`) de la fenetre qui a produit [dernierEntenduLibre].
     *
     * AJOUTE (2026-08-28) -- BUG CONFIRME PAR LOG DEVICE : les fenetres ne sont
     * PAS toujours traitees dans l'ordre chronologique de l'audio (un apercu de
     * parole recente peut etre journalise avant qu'un bloc plus ancien ne soit
     * finalise -- mesure : travailDebut 209920 -> 200960 -> 131840 sur 3 appels
     * consecutifs). Cote Dart, `_libreRecent` empilait chaque bribe dans l'ORDRE
     * D'ARRIVEE, jamais dans l'ordre chronologique -- le texte envoye a
     * l'identification de sourate en mode priere pouvait donc melanger fin de
     * sourate precedente et debut de la suivante, dans le desordre. Cette
     * position permet a Dart d'IGNORER toute bribe anterieure a la derniere
     * acceptee plutot que de tout empiler aveuglement.
     */
    var dernierEntenduLibrePosition: Long = -1L

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

    /** Probabilite et seuil de CHAQUE regle, par index de mot.
     *
     *  Lu par le plugin pour les transmettre a l'ecran : la fiche d'un mot rate
     *  montre alors une barre par regle, avec le seuil marque dessus -- « rate
     *  de justesse » (0,48 contre 0,50) se distingue enfin de « pas faite du
     *  tout » (0,10). Idee de l'utilisateur le 2026-09-05, nee du defaut trouve
     *  le meme jour : cette difference n'etait visible QUE dans le journal, en
     *  croisant trois types de lignes.
     *
     *  Ecrase a chaque nouvelle observation du mot : la derniere fait foi,
     *  comme pour le verdict. */
    val probasParMot = HashMap<Int, Map<String, Pair<Float, Float>>>()

    /** Regles vues AU MOINS UNE FOIS sur ce mot, toutes observations
     *  confondues -- cf. `probasParMot` pour le pourquoi. Le plugin les ajoute
     *  aux regles votantes : une detection franche ne doit pas se perdre parce
     *  qu'elle est tombee dans une fenetre qui n'a pas vote. */
    val reglesVuesParMot = HashMap<Int, MutableSet<Int>>()

    /** Duree maximale observee pour chaque regle, par mot, en millisecondes.
     *
     *  ── LE MAX DE CHAQUE GRANDEUR, SEPAREMENT (2026-09-05) ────────────────
     *
     *  Precision de l'utilisateur, apres la regle du maximum : « si 0,3 avec
     *  100 ms puis 0,7 avec 60 ms -> 0,7 et 100 ms, et on donne le verdict ».
     *
     *  On ne retient donc PAS le couple de la meilleure observation, mais le
     *  meilleur de chaque grandeur. C'est le bon choix : ce sont deux mesures
     *  independantes d'une meme realite, chacune degradee par un aspect
     *  different du fenetrage. Une fenetre qui coupe la fin du mot rend une
     *  duree trop courte sans abimer la probabilite ; une fenetre qui n'attrape
     *  que le bord rend l'inverse. Prendre le meilleur des deux, c'est
     *  reconstituer ce que le recitateur a reellement fait a partir de vues
     *  partielles -- aucune ne le montre en entier.
     *
     *  La duree n'est plus un critere de verdict depuis v329 (elle rejetait des
     *  detections a p=1,000). Elle est conservee pour le journal, l'affichage,
     *  et le jour ou l'on saura mesurer la tenue d'une regle. */
    val dureesParMot = HashMap<Int, MutableMap<Int, Int>>()

    /** Mots dont les regles vues se sont ENRICHIES depuis le dernier envoi.
     *
     *  ── UN VERDICT TAJWID PEUT ETRE CORRIGE (2026-09-05) ──────────────────
     *
     *  Mesure qui l'a impose, mot 39 `وَلِسَانًا` :
     *      17:01:23.168  verdict rendu -> VIOLET « idgham_ghunnah manquante »
     *      17:01:27.769  idgham_ghunnah p=1,000 sur 400 ms
     *      17:01:28.458  idgham_ghunnah p=1,000 sur 480 ms
     *
     *  La regle est detectee 4,6 s APRES le verdict, et trois fois de suite a
     *  1,000. Prendre le maximum des observations ne suffisait donc pas : au
     *  moment de trancher, la detection n'existait pas encore. La chaine
     *  verrouille le mot des que la fenetre avance, alors que la tete tajwid
     *  continue de l'observer dans les fenetres suivantes.
     *
     *  Decision utilisateur : « il faut juste rajouter que si on trouve que
     *  c'est ok, on peut corriger le verdict ». C'est le sens AUTORISE de la
     *  regle du projet -- « jamais un vert ne passe rouge » : on n'aggrave
     *  jamais un verdict rendu, on ne fait que reparer une accusation injuste.
     *
     *  Le mot est donc re-emis vers Dart, avec les regles enrichies ; c'est
     *  Dart qui sait lesquelles etaient ATTENDUES et qui retirera le violet. */
    val motsAReemettre = HashSet<Int>()

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
     * Ou proposer l'AIDE au moment d'un decrochage. Ce n'est pas toujours
     * [pointDeReprise] : en priere, un trou encore non resolu prime.
     *
     * ── LE SOUFFLEUR SOUFFLAIT LE VERSET SUIVANT (2026-09-08) ─────────────
     *
     * Analyse ChGPT sur session device du 2026-09-08 (An-Nisa, build v379).
     * Le recitant n'a pas dit 4:4 ; le souffleur lui a joue 4:5.
     *
     *     19:34:56.031  f=34 trou de 14 mot(s) apres le mot 71 MIS EN ATTENTE
     *     19:34:56.044  bande 68..86        <- attestation AU-DELA du trou
     *     19:34:58.568  DECROCHAGE : dernier definitif=70, dernier atteste vu=86,
     *                                 reprise apres le mot 86
     *     19:34:58.740  Souffleur : passage 87..87, verset 4:5
     *
     * CAUSE : `dernierAttesteVu` avance jusqu'a 86 sur la bande, alors que le
     * trou 72..85 reste EN ATTENTE. `maxOf(70, 86)` rend donc 86, et le pont
     * Dart ajoute 1 -> 87, premier mot de 4:5. Or une attestation au-dela d'un
     * trou n'est pas une preuve que les mots precedents ont ete reconnus : les
     * mots 72 et 73 etaient restes `provisoire:rouge`, et 74..85 n'ont recu
     * aucun verdict.
     *
     * L'information manquante etait deja la, memorisee dans [trouEnAttenteDe].
     * On la prefere donc, quand elle existe.
     *
     * ── CE QUI RESTE INCHANGE, ET POURQUOI C'EST DELIBERE ─────────────────
     *
     *  - [pointDeReprise] n'est PAS modifie. Remplacer globalement `maxOf` par
     *    `dernierDefinitif` reintroduirait les retards d'aide de l'ete, quand
     *    le jugement arrive apres la localisation (cf. sa propre doc : « aide
     *    annoncee au mot 13 alors que la recitation etait allee plus loin »).
     *  - Conditionne a `sautLibre`, donc au MODE PRIERE seul. La recitation
     *    controlee et les sessions de reference gardent leur comportement au
     *    caractere pres -- verifie par les tests `normal recitation still
     *    refuses a gap` et `reference recitation still resumes after its
     *    furthest attestation`.
     *  - Le trou n'est PAS transforme en verdict d'omission : `sautPresumeDe`
     *    reste a -1. On propose d'entendre le passage, on n'accuse pas de
     *    l'avoir saute -- le recitant peut fort bien l'avoir dit sans que la
     *    chaine l'entende.
     *
     * Specifie par les huit tests de `ChaineRecitationPriereTest`, ecrits par
     * ChGPT avant ce correctif : ils rejouent la session du 2026-09-08 sans
     * ONNX, en Hafs ET en Warsh.
     */
    private fun pointDAide(): Int {
        if (!sautLibre || trouEnAttenteDe < 0) return pointDeReprise()
        // Le pont Dart ajoute 1 : rendre le mot AVANT le trou fait donc
        // commencer l'aide sur son premier mot manquant.
        return trouEnAttenteDe
    }

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
        dernierEntenduLibrePosition = -1L
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
            variantesOrthographe(m).drop(1).map(tokeniser).filter { it.isNotEmpty() }
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
        if (tete3 != null || tete3Jugement != null) {
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

    /** Les scores affiches doivent accompagner la lecture qui a gagne. */
    fun observationRetenue(i: Int): RegistreDePreuves.Observation? =
        if (decideur.votePondere) decideur.preuveRetenue(i)
        else registre.observationsVotantes(i).lastOrNull()
            ?: registre.observationsPourJugement(i).lastOrNull()

    private val mesurerVote: Boolean get() = observerVoteFenetres || decideur.votePondere

    private fun contexteVote(fermeture: Boolean = false): Decideur.ContexteVote? =
        if (decideur.votePondere) Decideur.ContexteVote(motsAttendus,
            constructeur.debutMinimalFenetreFuture, fermeture, variantesOrthographe) else null

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
    /**
     * ⚠️ EXCEPTION AJOUTEE LE 2026-09-07 : le refus ci-dessous vaut toujours
     * pour les appels ORDINAIRES, mais [repartirApresSouffle] fait desormais
     * reculer l'ancre en mode priere -- uniquement apres qu'un souffle a ete
     * joue. Voir la note de cette methode pour la demande utilisateur qui
     * revoque, sur ce seul chemin, la specification du 2026-08-07.
     */
    fun reculerAncre(mot: Int) {
        if (sautLibre) {
            journal?.invoke("[v2] recul d'ancre IGNORE (mode priere) : " +
                "l'ancre ne recule jamais dans ce mode")
            return
        }
        val cible = mot.coerceIn(0, maxOf(0, motsAttendus.size - 1))
        // Clearing the colors alone let the next alimenter() restore old
        // greens from the append-only registry before the reciter repeated.
        // Archive evidence, but start judging only the next captured attempt.
        commencerTentative(cible)
        dernierDefinitif = cible - 1
        dernierAttesteVu = minOf(dernierAttesteVu, cible - 1)
        fenetresHorsTexte = 0
        decrochageDejaSignale = false
        statutsCourants = statutsCourants.filterKeys { it < cible }
        journal?.invoke("[v2] ANCRE RECULEE au mot $cible -- " +
            "nouvelle tentative depuis echantillon=${fluxBrut.total}, " +
            "preuves anterieures archivees, le recitant peut repeter")
    }

    val statuts: Map<Int, Statut> get() = statutsCourants
    val brut: FluxBrut get() = fluxBrut

    private fun commencerTentative(cible: Int) {
        registre.commencerTentative(cible, fluxBrut.total)
        decideur.oublierDepuis(cible, effacerProvisoires = true)
        // Account for even the partial capture block discarded at rewind:
        // the work clock must keep the absolute raw-audio sample positions.
        constructeur.repartirDeZero(fluxBrut.total)
        probasParMot.keys.removeAll { it >= cible }
        reglesVuesParMot.keys.removeAll { it >= cible }
        dureesParMot.keys.removeAll { it >= cible }
        motsAReemettre.removeAll { it >= cible }
    }

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
    /**
     * Plage temporelle FIABLE d'un mot : sa DERNIERE observation votante.
     *
     * « Votante » = `interieur` et `entendu` non vide -- exactement le filtre
     * du Decideur (`observationsVotantes`). C'est le coeur du correctif du
     * 2026-08-14 : l'audio qu'on fait ecouter doit etre celui sur lequel le
     * VERDICT a ete rendu, jamais une position que le jugement lui-meme
     * considere comme non fiable.
     *
     * La DERNIERE et non l'union de toutes : un mot repete, ou aligne par
     * erreur dans une fenetre lointaine, possede plusieurs observations
     * eloignees dans le temps. En prendre l'union etirait la plage sur tout
     * l'intervalle qui les separe.
     */
    private fun plageFiable(mot: Int): Pair<Long, Long>? {
        val o = registre.observations(mot).lastOrNull {
            !it.sansCreneau && it.debutAbs >= 0 && it.finAbs >= 0 &&
                it.interieur && it.entendu.isNotBlank()
        } ?: return null
        return o.debutAbs to o.finAbs
    }

    /**
     * ── L'EXTRAIT TOMBAIT A COTE DU MOT (corrige 2026-08-14) ────────────────
     *
     * Constat utilisateur : « parfois il y a un décalage, du coup on n'a pas le
     * bon audio du mot ». MESURE dans le journal du jour -- un extrait couvre
     * DEUX mots (le mot et son predecesseur), il devrait donc durer 1 a 2 s :
     *
     *     mots 18..19 : 1,06 s     mots 23..24 : 2,02 s      (normal)
     *     mots 20..21 : 4,42 s                               (deja suspect)
     *     mots  6..7  : 12,10 s    mots 18..19 : 15,62 s     (ABERRANT)
     *
     * CAUSE : la version precedente prenait le `min(debutAbs)` et le
     * `max(finAbs)` sur TOUTES les observations, SANS AUCUN FILTRE -- pas meme
     * `sansCreneau`, que le Decideur exclut pourtant explicitement pour juger.
     * Une seule observation mal placee (mot aligne par erreur dans une fenetre
     * lointaine, ou repetition du passage) suffisait a etirer l'intervalle sur
     * tout l'espace qui les separe : l'extrait demarrait alors sur un autre
     * passage, et l'utilisateur entendait un autre mot.
     *
     * TROIS GARDES, du plus precis au plus grossier :
     *  1. positions FIABLES uniquement (cf. [plageFiable]) ;
     *  2. le mot demande est l'ANCRE : sans plage fiable pour lui, on rend
     *     `null` plutot qu'un extrait construit sur ses seuls voisins ;
     *     ⚠️ ASSOUPLIE LE 2026-09-12, cf. [entreLesVoisins] : le refus sec
     *     restait juste pour un mot PRONONCE mal situe (le cas de 2026-08-14,
     *     ou l'extrait tombait sur un autre passage), mais il rendait muet
     *     tout mot `omis` -- or c'est precisement celui qu'on veut entendre.
     *     Le repli ne construit rien sur des voisins LOINTAINS : il se limite
     *     aux deux mots JUXTAPOSES, ce qui borne l'extrait par construction.
     *  2 bis. si le mot n'a aucune plage fiable MAIS que ses deux voisins
     *     immediats en ont une, l'extrait est l'intervalle entre eux ;
     *  3. le contexte gauche n'est ajoute que s'il est CONTIGU, et la duree
     *     totale est plafonnee en rognant le DEBUT -- jamais la fin, qui porte
     *     le mot demande.
     */
    fun voixSurPlage(motDebut: Int, motFin: Int): FloatArray? {
        // `null` plutot qu'un extrait bati sur les seuls voisins : l'appelant
        // (FastConformerCtcPlugin) journalise deja l'indisponibilite. Cette
        // classe ne journalise rien -- c'est la couche natif pure.
        val ancre = plageFiable(motFin) ?: return entreLesVoisins(motFin)
        var debut = ancre.first
        var fin = ancre.second
        for (i in motDebut until motFin) {
            val p = plageFiable(i) ?: continue
            // Un mot de contexte prononce AILLEURS (inversion, reprise) n'a
            // rien a faire dans cet extrait : il n'apporte pas de contexte, il
            // ajoute du hors-sujet et decale ce qu'on entend.
            if (p.second < debut - CONTEXTE_MAX_ECH) continue
            if (p.first < debut) debut = p.first
            if (p.second > fin) fin = p.second
        }
        if (fin - debut > PLAGE_MAX_ECH) debut = fin - PLAGE_MAX_ECH
        if (fin <= debut) return null
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
     * ── LE MOT SE DEDUIT DE SES DEUX VOISINS (2026-09-12) ──────────────────
     *
     * Decision utilisateur, formulee ainsi : « si position non fiable, les deux
     * mots juxtaposes sont fiables, donc le son entre ces deux mots c'est le son
     * du mot » -- « on peut deduire ou le mot est dit si on sait deja les deux
     * mots a cote sont connus ».
     *
     * CE QUE LE JOURNAL MONTRAIT, et qui a motive la demande (session du
     * 2026-09-12, sourate An-Nasr, build v425) :
     *
     *     mot=4  "إِذَا"      -> definitif:vert | INT
     *     mot=5  "جَآءَ"      -> omis           | bord/sansCreneau
     *     mot=6  "نَصْرُ"     -> definitif:vert | INT
     *
     * Le mot manquant est ENCADRE par deux positions sures. L'audio situe entre
     * la fin de l'un et le debut de l'autre est, par construction, l'endroit ou
     * ce mot a ete dit -- ou celui ou il manque. Les deux reponses interessent
     * le recitateur, et aucune n'etait audible jusqu'ici.
     *
     * POURQUOI CELA NE REOUVRE PAS LE DEFAUT DU 2026-08-14 (extraits de 12,10 s
     * et 15,62 s tombant sur un autre passage) : ce defaut venait de l'UNION
     * d'observations eloignees pour un mot bel et bien prononce. Ici on ne prend
     * l'union de rien -- deux mots ADJACENTS ne peuvent enfermer qu'un seul mot,
     * et l'intervalle est plafonne. La garde d'origine reste entiere pour tous
     * les autres cas.
     *
     * TROIS REFUS, tous silencieux (l'appelant journalise deja) :
     *  - un voisin immediat sans position fiable : on ne sait plus ou chercher ;
     *  - un intervalle vide ou negatif : les deux voisins se chevauchent, il n'y
     *    a rien entre eux ;
     *  - un intervalle au-dela de [PLAGE_MAX_ECH] : une pause, une reprise ou un
     *    decrochage s'est glisse la. On rend `null` PLUTOT QUE DE ROGNER, parce
     *    qu'ici rogner reviendrait a deviner de quel cote du trou le mot se
     *    trouve -- exactement ce qu'on ne sait pas.
     */
    private fun entreLesVoisins(mot: Int): FloatArray? {
        // `observations` est une Map : un index negatif ou hors bornes rend une
        // liste vide, donc `plageFiable` rend `null`. Pas de garde a ajouter.
        val avant = plageFiable(mot - 1) ?: return null
        val apres = plageFiable(mot + 1) ?: return null
        var debut = avant.second
        var fin = apres.first
        // ── LE SILENCE EST UNE REPONSE, PAS UNE PANNE (2026-09-12) ────────────
        //
        // Demande utilisateur : « peut-etre c'est vraiment omis et du coup il
        // n'y aura rien [...] si le decoupage montre qu'il y avait rien, ca
        // veut dire qu'il y avait rien ». Rendre `null` quand les deux voisins
        // se touchent afficherait « Audio plus disponible » -- un message de
        // PANNE la ou le vide est justement le RESULTAT cherche. On rend donc
        // la jonction elle-meme : le recitateur entend qu'il est passe d'un mot
        // a l'autre sans rien entre les deux, ce qui confirme l'omission au
        // lieu de laisser croire a un defaut de l'application.
        if (fin <= debut) {
            val centre = (avant.second + apres.first) / 2
            debut = centre
            fin = centre
        }
        if (fin - debut > PLAGE_MAX_ECH) return null
        // La marge mord volontairement sur la fin du mot precedent et sur
        // l'attaque du suivant : c'est ce qui rend le trou ECOUTABLE (« tu es
        // passe de إِذَا directement a نَصْرُ »). Sans elle, un mot reellement
        // saute ne donnerait qu'un silence nu, impossible a situer.
        // 0,4 s de chaque cote, et non les 0,25 s de [voixSurPlage] : ici la
        // marge ne sert pas a rattraper le piquage du CTC, elle est le SEUL
        // contenu audible quand le trou est court ou nul. Trop courte, on
        // n'entendrait ni la fin du mot d'avant ni l'attaque de celui d'apres,
        // donc rien de reconnaissable.
        val marge = (Horloge.TAUX * 0.4).toLong()
        val d = maxOf(fluxBrut.premierDisponible, debut - marge)
        val f = minOf(fluxBrut.total, fin + marge)
        if (f <= d) return null
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
        val nouveaux = decideur.statuts(registre, motsAttendus.size, contexteVote())
        for ((i, s) in nouveaux) {
            if (statutsCourants[i] != s) changements.add(Changement(i, s))
            if (s is Statut.Definitif && i > dernierDefinitif) dernierDefinitif = i
        }
        // ── LES MOTS DONT LE TAJWID S'EST ENRICHI (2026-09-05) ────────────
        //
        // Leur STATUT n'a pas change -- il reste `correct` cote natif, c'est
        // Dart qui pose le violet -- donc la boucle ci-dessus ne les emet pas.
        // On les ajoute explicitement : sans cela, une regle detectee apres le
        // verdict reste invisible, et le violet injuste demeure a l'ecran.
        for (i in motsAReemettre) {
            if (changements.none { it.motIndex == i }) {
                nouveaux[i]?.let { changements.add(Changement(i, it)) }
            }
        }
        motsAReemettre.clear()
        statutsCourants = nouveaux
        return changements
    }

    /**
     * Fin de session : derniere analyse de la queue d'audio, hors grille.
     * Sans cet appel, les derniers mots resteraient PROVISOIRES a jamais — la
     * grille de fenetres cesse d'avancer des que le recitateur se tait
     * (defaut trouve par le banc 2, cf. [ConstructeurDeFenetres.terminer]).
     */
    /**
     * A appeler quand le souffleur a fini de parler : la chaine oublie l'audio
     * qui a servi a detecter le decrochage, et repart sur ce que le recitant
     * va dire maintenant.
     *
     * Cf. [ConstructeurDeFenetres.repartirDeZero] pour la mesure qui l'impose.
     * Ici on ajoute l'oubli des etats de SAUT : sans cela, le trou mis en
     * attente juste avant le souffle ressortirait a la premiere fenetre
     * suivante et declencherait un second souffleur sur un passage que le
     * recitant est justement en train de reprendre.
     *
     * La cible et l'archive brute sont conservees. Les statuts et les preuves
     * actives a partir du mot de reprise repartent sur une nouvelle tentative.
     * Les anciennes observations restent disponibles pour l'audit et l'ecoute.
     */
    fun repartirApresSouffle(motDeReprise: Int) {
        trouEnAttenteDe = -1
        trouEnAttenteA = -1
        idFenetreTrou = -1L
        sautPresumeDe = -1
        sautPresumeA = -1
        dernierEntenduLibre = ""
        dernierEntenduLibrePosition = -1L
        // ── ET L'ANCRE RECULE, VERDICTS COMPRIS (2026-09-07) ───────────────
        //
        // PREMIERE VERSION, CORRIGEE LE JOUR MEME : je ne purgeais que l'audio
        // et j'ecrivais « la cible et les verdicts restent ». C'etait le
        // contraire de ce qu'il fallait. L'utilisateur, mot pour mot :
        //
        //   « L'ancre arrive au mot 40. Puis moi je parle, du coup l'aligneur
        //   va l'aligner au mot 60. Donc j'ai dit 60, 61, 63, 65 : ils se sont
        //   COLORIES dans mon ecran, alors qu'il y a un gap. Le souffleur dit
        //   OK mot 40, 41, 42. Mais a ce stade-la, L'ANCRE DOIT RECULER, et il
        //   faut remettre a zero ce qui a ete dit -- c'est comme si rien
        //   n'etait dit, les validations deja validees, il faut les jeter et
        //   reecouter pour se repositionner. Parce que la, comme il reste
        //   colorie, l'ancre est toujours avec eux, et le souffleur commence
        //   par me dire le mot 66, 67, 68. Non. »
        //
        // CE QUE CELA REVOQUE, ET C'EST DELIBERE : la specification du
        // 2026-08-07 disait « aucun recul d'ancre, aucune attente qu'il
        // repete » (cf. [reculerAncre], qui refuse encore le recul quand
        // `sautLibre`). Elle reste vraie POUR LES AUTRES CHEMINS -- rien ne
        // fait reculer l'ancre a cause d'un simple trou, et rien n'attend que
        // le recitant repete. Ce chemin-ci est le seul ou le recul est demande,
        // parce qu'un souffle vient d'etre joue : la position d'ou l'on soufflait
        // est, par construction, celle ou le recitant en etait vraiment.
        //
        // Le recul n'est PAS une attente : l'ancre repart de la, et le
        // localisateur la replace librement des la premiere fenetre suivante,
        // ou que le recitant en soit. « Reecouter pour se repositionner ».
        val cible = motDeReprise.coerceIn(0, maxOf(0, motsAttendus.size - 1))
        // Like a controlled rewind, the hint starts a new acoustic attempt.
        commencerTentative(cible)
        dernierDefinitif = cible - 1
        dernierAttesteVu = minOf(dernierAttesteVu, cible - 1)
        fenetresHorsTexte = 0
        decrochageDejaSignale = false
        statutsCourants = statutsCourants.filterKeys { it < cible }
        journal?.invoke("[v2] REPART APRES SOUFFLE : ancre reculee au mot " +
            "$cible, nouvelle tentative depuis echantillon=${fluxBrut.total}, " +
            "preuves anterieures archivees, et l'audio qui a " +
            "servi a reperer le decrochage est oublie -- on reecoute pour se " +
            "repositionner")
    }

    /**
     * Nom de famille correspondant a une regle de l'ordre APP (`rules.json`).
     *
     * Les deux nomenclatures coincident partout SAUF sur les madd : la tete
     * fine ne connait qu'une famille `madd`, la la ou `rules.json` porte
     * `madda_necessary` / `madda_obligatory` / `madda_permissible` /
     * `madda_normal`. On ramene donc les quatre a `madd` pour pouvoir
     * comparer -- c'est exactement ce que le PC A a du corriger de son cote
     * en construisant sa mesure d'accord.
     */
    private fun familleDeNomApp(nom: String): String =
        if (nom.startsWith("madda_")) "madd" else nom

    fun terminer(): List<Changement> {
        val changements = ArrayList<Changement>()
        for (fenetre in constructeur.terminer()) traiter(fenetre)
        // ── UN TROU EN ATTENTE MEURT AVEC LA SESSION, ET IL FAUT LE DIRE ────
        // (2026-09-07)
        //
        // Le mecanisme d'attente (cf. `trouEnAttenteDe` dans [traiter]) laisse
        // une fenetre de plus pour combler le trou avant de souffler. A la
        // fermeture, cette fenetre n'existera jamais : le trou reste en
        // attente pour toujours, `sautPresumeDe` n'est jamais pose, et AUCUNE
        // trace ne dit pourquoi le souffleur s'est tu.
        //
        // MESURE QUI L'IMPOSE (session 11:52, build v373) :
        //     11:52:43.619  RELACHE effective -- micro detenu=false
        //     11:52:43.895  f=50 trou de 66 mot(s) apres le mot 101 MIS EN ATTENTE
        //     11:52:43.899  session fermee : 8 mot(s) finalise(s)
        // Le vrai saut de l'utilisateur, detecte 276 ms apres le relachement
        // du micro et enterre 4 ms plus tard. Une soiree a chercher pourquoi.
        //
        // ON NE SOUFFLE PAS ICI, VOLONTAIREMENT : la session est finie, le
        // micro est relache, l'ecran se referme. Souffler apres coup n'aide
        // personne. On ecrit seulement ce qui s'est passe.
        if (trouEnAttenteDe >= 0) {
            journal?.invoke("[v2] trou en attente apres le mot $trouEnAttenteDe " +
                "(jusqu'au mot $trouEnAttenteA) ABANDONNE : la session se ferme " +
                "avant la fenetre qui devait le confirmer -- aucun souffleur, " +
                "et ce n'est pas un defaut du detecteur")
            trouEnAttenteDe = -1
            trouEnAttenteA = -1
        }
        val nouveaux = decideur.statuts(registre, motsAttendus.size, contexteVote(fermeture = true))
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
            dernierEntenduLibrePosition = fenetre.travailDebut
            // ── DIAGNOSTIC AJOUTE (2026-08-28), CAUSE TROUVEE ────────────────
            // Constat utilisateur, mode priere : le texte libre reste bloque a
            // repeter la MEME phrase plusieurs fois de suite pendant la
            // recherche de la 2e sourate (log : "يَـٰٓأَيُّهَا" x6 en ~0,7 s).
            // Le journal instrumente (`travailDebut` ci-dessous) a montre que
            // les fenetres ne sont PAS toujours traitees dans l'ordre
            // chronologique de l'audio (mesure : travailDebut 209920 -> 200960
            // -> 131840 sur 3 appels consecutifs -- proprete reconnue de cette
            // couche, pas un bug ici). La VRAIE cause etait cote Dart :
            // `_libreRecent` (recitation_provider.dart) empilait chaque bribe
            // dans l'ordre d'ARRIVEE, jamais chronologique -- le texte envoye
            // a l'identification de sourate melangeait donc fin de sourate
            // precedente et debut de la suivante, dans le desordre.
            // [dernierEntenduLibrePosition] permet desormais a Dart d'ignorer
            // toute bribe anterieure a la derniere acceptee.
            // Pas de correctif ici -- mesure d'abord (regle projet), cf.
            // CLAUDE.md sur BufferedTranscriber : jamais de correctif de
            // segmentation sans preuve device prealable.
            journal?.invoke("[v2] f=${fenetre.id} bande=inconnue " +
                "entendu=\"$entenduLibre\" horsTexte=$fenetresHorsTexte " +
                "dejaSignale=$decrochageDejaSignale " +
                "travailDebut=${fenetre.travailDebut} " +
                "dureeS=${"%.2f".format(fenetre.dureeSecondes)} " +
                "apercu=${fenetre.apercu}")
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
                        motDuDecrochage = pointDAide()
                        journal?.invoke("[v2] f=${fenetre.id} DECROCHAGE : " +
                            "$fenetresHorsTexte fenetres hors texte, " +
                            "dernier definitif=$dernierDefinitif, " +
                            "dernier atteste vu=$dernierAttesteVu, " +
                            (if (sautLibre && trouEnAttenteDe >= 0)
                                "trou NON RESOLU apres le mot $trouEnAttenteDe " +
                                "(jusqu'a $trouEnAttenteA) -- l'aide y revient " +
                                "plutot qu'a l'attestation la plus lointaine, "
                             else "") +
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
            // ── UN TROU EST UNE ACCUSATION : IL SE FONDE SUR L'EXACT ────
            // (2026-09-08)
            //
            // Le projet porte deja le principe, ecrit dans `Localisateur.Bande`
            // apres un defaut trouve le 2026-07-30 : « Normaliser pour TROUVER,
            // comparer exactement pour CONFIRMER ». `attestes` compare des mots
            // SANS harakat -- assez pour se reperer, pas pour affirmer.
            //
            // Or un trou n'est pas un reperage : c'est ce qui declenche
            // « vous n'avez pas dit ces mots » et fait parler le souffleur. Il
            // releve donc du CONFIRMER.
            //
            // MESURE QUI L'IMPOSE (session du 2026-09-08, 21:03) --
            // l'utilisateur s'etait TU et attendait d'etre souffle :
            //
            //     21:03:53,85  mot 16 "ونساء" definitif:vert   <- son dernier mot
            //     21:03:54,92  f=4 bande=20..21 conf=0,50 interieurs=0/2
            //                  -> trou de 4 mots apres le mot 16 MIS EN ATTENTE
            //     21:03:59,60  souffleur : mots 17..20
            //
            // Les blocs PCM montrent le portier en train de jeter l'audio au
            // meme instant : la bande 20..21 a ete posee SUR DU SILENCE, avec
            // zero mot interieur sur deux. Le mot 48 a meme ete juge
            // `definitif:vert` alors que rien n'etait prononce.
            //
            // On exige donc que le mot qui FONDE le trou -- celui d'apres, qui
            // pretend prouver « il est deja la-bas » -- soit dans
            // `attestesExacts`. Un appariement seulement normalise ne suffit
            // plus a accuser.
            //
            // ⚠️ MODE PRIERE SEUL (`sautLibre`). Hors priere le trou sert a
            // REFUSER une fenetre, pas a souffler : le durcir changerait le
            // contrôle de saut de la recitation controlee, qui n'a rien
            // demande. Verifie par `normal recitation still refuses a gap`.
            val pertinents = attestesTries
                .filter { it >= ancrePourTrou }
                .filter { !sautLibre || it in bande.attestesExacts }
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
        // ── CE GARDE ATTENDAIT EN EMBUSCADE (corrige 2026-09-07) ───────────
        //
        // Sa doc dit « une seule [fenetre] -- ensuite, un trou redevient un
        // vrai trou ». L'implementation ne le faisait pas : `premiereLocalisation`
        // n'etait remis a faux QUE dans la branche ci-dessous, celle qui
        // rencontre un trou. Quand la premiere localisation se passait bien --
        // aucun trou, le cas NORMAL -- le drapeau restait arme toute la session
        // et avalait le PREMIER VRAI SAUT, quel qu'il soit.
        //
        // MESURE (session 11:52, build v373) :
        //     11:51:26  cible posee (sourate 4)        -> drapeau arme
        //     11:51:35  ancre relocalisee au mot 16    -> pas de trou, arme
        //     11:52:01  mot 43 juge definitif:vert     -> toujours arme
        //     11:52:04  f=23 trou de 28 mot(s) IGNORE : premiere localisation
        //               apres pose de cible
        // Un saut delibere, 38 secondes apres la pose de cible et bien apres
        // que l'ancre se soit localisee, classe « decalage d'entree ». Aucun
        // souffleur -- c'est le defaut signale : « j'ai recu aucun souffleur
        // alors que j'ai saute le texte ».
        //
        // On le consomme donc a la PREMIERE LOCALISATION, trou ou pas. Une
        // bande existe (`dejaLocaliseUneFois` vient d'etre pose juste au
        // dessus) : le decalage d'entree, s'il y en avait un, est derriere.
        val entreeDeCible = premiereLocalisation
        premiereLocalisation = false
        if (sautLibre && entreeDeCible && trou > sautMaxMots) {
            journal?.invoke("[v2] f=${fenetre.id} trou de $trou mot(s) IGNORE : " +
                "premiere localisation apres pose de cible -- c'est le " +
                "decalage d'entree, pas un oubli du recitant")
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
                    "suivante le combler avant de souffler " +
                    // De quoi juger APRES COUP si ce trou etait solide : la
                    // confiance de la bande et le nombre de mots confirmes
                    // exactement. Sans ces deux valeurs, un faux trou ne se
                    // distingue pas d'un vrai dans le journal (constat du
                    // 2026-09-08 : il a fallu croiser les blocs PCM pour
                    // etablir que la bande etait posee sur du silence).
                    "(bande ${bande.i0}..${bande.i1} conf=" +
                    "${"%.2f".format(bande.confiance)} " +
                    "exacts=${bande.attestesExacts.size}/${bande.attestes.size})")
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

        val libresPourVote = if (mesurerVote)
            Decodage.motsAvecFrames(logprobs, front.pieces, front.blank) else emptyList()
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
                // Meme regle que pour les durees : 0,90 de la moyenne
                // mesuree en strict, 0,70 en tolerant (2026-09-03).
                val detections = front.decodeTajwid(
                    sorties.tajwid.copyOfRange(debut, fin),
                    SeuilsDureeTajwid.facteurProba(tajwidStrict))
                // DUREE JOURNALISEE, JAMAIS JUGEE (2026-08-04). Le type d'un
                // madd (`wajib` / `tabi'i`) est une categorie GRAMMATICALE que
                // le texte connait deja ; l'acoustique ne peut repondre qu'a
                // « combien de temps a dure l'allongement ». On expose donc
                // cette duree pour pouvoir la MESURER sur du vrai audio avant
                // de decider si elle peut servir de critere -- pas l'inverse.
                // ── CE QUI N'A PAS ETE DETECTE, ET DE COMBIEN (2026-09-03)
                //
                // Question de l'utilisateur : « c'est le seuil ou la duree qui
                // filtre ? » -- impossible d'y repondre jusqu'ici. `decodeTajwid`
                // ne rend que les DETECTIONS : une classe qui culmine sous son
                // seuil ne produit aucun span, donc aucune ligne, donc aucune
                // probabilite. Les rejets par DUREE etaient journalises, ceux
                // par SEUIL ne l'etaient pas du tout.
                //
                // Pire, cela rendait toute statistique trompeuse : ne lire que
                // les lignes existantes revient a ne compter que les rescapes.
                // J'ai moi-meme conclu a tort « 100 % des detections passent le
                // seuil » a partir de ce biais de selection.
                //
                // On journalise donc les classes NON detectees dont la
                // probabilite maximale depasse 0,10 -- les « presque
                // detectees ». En dessous, la tete n'a rien vu du tout et la
                // ligne n'apprendrait rien : ce plancher evite d'ecrire dix-sept
                // classes par mot pour du bruit.
                run {
                    val vues = detections.map { it.ruleId }.toSet()
                    val maxima = front.probMaxParClasse(
                        sorties.tajwid.copyOfRange(debut, fin))
                    val fact = SeuilsDureeTajwid.facteurProba(tajwidStrict)
                    // ── LA PROBABILITE REMONTE JUSQU'A L'ECRAN (2026-09-05) ─
                    //
                    // Idee de l'utilisateur, nee du defaut qu'on venait de
                    // trouver : « rajouter sous la regle, pour les mots, un
                    // style barre de progression pour que le user sache ce
                    // qu'il a fait -- est-ce qu'il a rate de justesse ».
                    //
                    // La difference entre « pas faite » (p=0,10) et « ratee de
                    // peu » (p=0,48) etait INVISIBLE : il fallait extraire le
                    // journal et croiser trois types de lignes pour la voir. Un
                    // recitateur ne peut pas faire ca, et c'est pourtant la
                    // seule information qui lui dise s'il progresse.
                    //
                    // On retient donc, pour CHAQUE classe, sa probabilite et le
                    // seuil qu'elle devait franchir -- y compris les detectees,
                    // pour que la fiche puisse aussi montrer une reussite juste.
                    // ── LE MAXIMUM, PAS LA DERNIERE OBSERVATION ──────────
                    //
                    // Regle posee par l'utilisateur (2026-09-05), dans le
                    // prolongement d'un principe deja ecrit du projet -- « un
                    // vert ne passe jamais rouge » : « on garde le max de prob
                    // et max de duree -> verdict ».
                    //
                    // CE QUE CA CORRIGE, mesure sur Al-Balad : un mot est
                    // examine par PLUSIEURS fenetres qui se chevauchent. Sur
                    // `وَوَالِدٍ`, l'une voyait l'idgham a 1,00 pendant 560 ms
                    // et une autre ne le voyait pas -- et c'est celle qui ne
                    // voyait rien qui faisait le verdict. Quatre des dix
                    // violets de la session venaient de la : `حِلٌّۢ` (iqlab
                    // detecte a 0,99), `لَّن` et `وَلِسَانًا` (idgham a 1,00).
                    //
                    // Une regle VUE a ete faite : aucune observation ulterieure
                    // ne peut la « de-voir ». On accumule donc le maximum.
                    val avant = probasParMot[m.index]
                    probasParMot[m.index] = maxima.indices.associate { c ->
                        val nom = front.nomsRegles.getOrNull(c) ?: "?$c"
                        val p = maxima[c]
                        val ancien = avant?.get(nom)?.first ?: 0f
                        nom to Pair(maxOf(p, ancien), front.seuilRegle(c) * fact)
                    }
                    val sous = maxima.indices
                        .filter { it !in vues && maxima[it] > 0.10f }
                        .sortedByDescending { maxima[it] }
                        .joinToString(" ") { c ->
                            val nom = front.nomsRegles.getOrNull(c) ?: "?$c"
                            val seuil = front.seuilRegle(c) * fact
                            "$nom=${"%.3f".format(maxima[c])}/" +
                                "${"%.3f".format(seuil)}"
                        }
                    if (sous.isNotEmpty()) {
                        journal?.invoke(
                            "[tajwidSousSeuil] mot=${m.index} $sous")
                    }
                }
                if (detections.isNotEmpty()) {
                    val avantVues = reglesVuesParMot[m.index]?.toSet()
                    reglesVuesParMot.getOrPut(m.index) { HashSet() }
                        .addAll(detections.map { it.ruleId })
                    val d = dureesParMot.getOrPut(m.index) { HashMap() }
                    for (det in detections) {
                        val ms = det.frames * Horloge.MS_PAR_FRAME
                        d[det.ruleId] = maxOf(d[det.ruleId] ?: 0, ms)
                    }
                    // Le mot avait deja un verdict et on vient de voir une
                    // regle de plus : il doit repartir vers Dart pour que le
                    // violet puisse etre retire (cf. `motsAReemettre`).
                    if (avantVues != null &&
                        !avantVues.containsAll(detections.map { it.ruleId })) {
                        motsAReemettre.add(m.index)
                    }
                }
                // ── LES DEUX TETES, CONFRONTEES (2026-09-07) ──────────
                //
                // Demande utilisateur : « adapte, en premier lieu ce sera en
                // log ». La tete FINE (76 classes) est lue et remontee a ses
                // 11 familles, puis comparee a ce que la tete FAMILLE a
                // detecte sur LE MEME MOT et LES MEMES frames.
                //
                // Ce que la ligne donne, et que rien d'autre ne peut donner :
                // l'ACCORD des deux tetes sur du vrai usage. La mesure du PC A
                // (400 fenetres de corpus, 4 voix) dit que l'intersection
                // divise l'invention par 6 a 8 ; elle ne dit pas si cela tient
                // sur une recitation reelle, avec un micro de telephone et un
                // recitant qui hesite. C'est ce que la recette dira.
                //
                // ⚠️ OBSERVATION SEULE. `reglesTajwid` -- ce qui part vers
                // Dart et peint l'ecran -- ne vient QUE de la tete famille,
                // exactement comme avant ce jour. Rien n'est confronte pour
                // juger, seulement pour etre lu.
                //
                // Trois etats par famille, et c'est le troisieme qui interesse :
                //   accord      les deux la voient  -> ce que l'intersection garde
                //   familleSeule  elle seule        -> ce que l'intersection perdrait
                //   fineSeule     elle seule        -> ce que la famille ne voit pas
                val fine = sorties.tajwidFine
                if (fine != null && m.frames > 0 && front.nomsReglesFines.isNotEmpty()) {
                    val bornes = etendue[m.index]
                    val d0 = (bornes?.first ?: m.premiereFrame).coerceIn(0, fine.size)
                    val d1 = (bornes?.second ?: (m.derniereFrame + 1)).coerceIn(d0, fine.size)
                    if (d1 > d0) {
                        // Meme seuil que la tete famille (ln 0,5), faute de
                        // calibration propre a la tete fine : les seuils livres
                        // pour elle sont ceux du regime « 97 % » que son propre
                        // rapport declare inutilisable (91,5 % d'invention).
                        val seuilLog = Math.log(0.5).toFloat()
                        val vues = HashSet<String>()
                        for (f in d0 until d1) {
                            val ligne = fine[f]
                            for (c in ligne.indices) {
                                if (ligne[c] > seuilLog) {
                                    front.familleDeRegleFine(c)?.let { vues.add(it) }
                                }
                            }
                        }
                        val famille = detections.mapNotNull {
                            front.nomsRegles.getOrNull(it.ruleId)
                        }.map { familleDeNomApp(it) }.toHashSet()
                        val accord = famille.intersect(vues)
                        val familleSeule = famille - vues
                        val fineSeule = vues - famille
                        journal?.invoke("[tajwidFine] mot=${m.index} " +
                            "accord=${if (accord.isEmpty()) "-" else accord.sorted().joinToString(",")} " +
                            "familleSeule=${if (familleSeule.isEmpty()) "-" else familleSeule.sorted().joinToString(",")} " +
                            "fineSeule=${if (fineSeule.isEmpty()) "-" else fineSeule.sorted().joinToString(",")}")
                    }
                }
                // ── LA TENUE, A COTE DU PIC (2026-09-07) ──────────────
                //
                // Cf. `Decodage.tenueMax` pour la mesure qui l'impose : la
                // duree rendue par la tete est celle de son PIC, pas celle du
                // son. Les deux sont journalisees cote a cote pour qu'on
                // puisse enfin les comparer sur le meme mot -- c'est ce qui
                // dira si la tenue separe un madd de 2 harakat d'un madd de 6,
                // la ou le pic ne le fait pas.
                //
                // Observation seule : aucun verdict ne lit cette valeur.
                if (detections.isNotEmpty() && m.frames > 0) {
                    val tenue = Decodage.tenueMax(
                        logprobs, front.blank, m.premiereFrame, m.derniereFrame)
                    journal?.invoke("[tajwidTenue] mot=${m.index} " +
                        "tenue=${tenue}f(${tenue * Horloge.MS_PAR_FRAME}ms) " +
                        "surMot=${m.frames}f(${m.frames * Horloge.MS_PAR_FRAME}ms) " +
                        "regles=" + detections.joinToString(",") { d ->
                            front.nomsRegles.getOrNull(d.ruleId) ?: "?${d.ruleId}"
                        })
                }
                if (detections.isNotEmpty()) {
                    journal?.invoke("[tajwidDuree] mot=${m.index} " +
                        detections.joinToString(" ") { d ->
                            val nom = front.nomsRegles.getOrNull(d.ruleId) ?: "?${d.ruleId}"
                            // VALEUR + SEUIL, pas seulement la duree
                            // (2026-09-02, demande utilisateur : « tu ne m'as
                            // pas montre mes valeurs ? »). La probabilite
                            // etait DEJA calculee (DetectedRule.prob) et
                            // simplement jamais ecrite -- on ne pouvait donc
                            // pas distinguer une regle franchie de justesse
                            // d'une regle franchie largement, ni voir qu'un
                            // seuil etait aberrant.
                            // Le seuil EFFECTIVEMENT applique, pas le brut du
                            // fichier : la decision passe par le facteur de
                            // rigueur (0,90 strict / 0,70 tolerant, 2026-09-03).
                            // Journaliser le brut faisait lire « p=0,928/0,999 »
                            // sur une regle pourtant DETECTEE -- le journal
                            // mentait sur ce qu'il comparait, defaut deja
                            // signale une fois (« tu ne m'as pas montre mes
                            // valeurs »).
                            val seuil = front.seuilRegle(d.ruleId) *
                                (SeuilsDureeTajwid.facteurProba(tajwidStrict))
                            "$nom=${d.frames}f(${d.frames * 80}ms) " +
                                "p=${"%.3f".format(d.prob)}/${"%.3f".format(seuil)}"
                        })
                }
                // FILTRE DE DUREE (2026-09-02) -- c'est ici que la rigueur
                // agit. Avant, toute detection au-dessus du seuil de
                // PROBABILITE comptait comme regle realisee, quelle que soit
                // sa duree : une qalqala de 80 ms valait celle de 480 ms du
                // professionnel. Les poids ne distinguant pas les deux (cf.
                // SeuilsDureeTajwid), c'etait un tampon automatique.
                //
                // Une regle non calibree a un seuil de 0 : elle passe comme
                // avant. On ne rejette jamais sur un chiffre qu'aucune mesure
                // ne fonde.
                // ── LE MAX SUR TOUTES LES OBSERVATIONS, PAS LA DERNIERE ────
                //
                // Remarque utilisateur (2026-09-11), et elle porte : « comme le
                // mot est juge plusieurs fois, je ne sais pas si tu gardes le
                // max de duree pour une meilleure decision ». Il avait raison
                // de douter : ce filtre lisait `d.frames`, la seule observation
                // COURANTE, alors que `dureesParMot` accumule deja le maximum
                // par (mot, regle) quelques lignes plus haut.
                //
                // CE QUE CA CASSAIT. Un mot est vu par plusieurs fenetres
                // glissantes ; celle qui l'attrape par le bord n'en voit qu'un
                // fragment, donc une duree tronquee. Le filtre rejetait alors
                // une regle que la fenetre SUIVANTE voyait entiere.
                //
                // ET SURTOUT, L'INCOHERENCE DE CALIBRAGE. Les seuils remis le
                // 2026-09-11 (cf. `SeuilsDureeTajwid`) viennent d'un protocole
                // qui prend explicitement le MAX sur quatre decoupes par ancre
                // -- correction demandee par l'utilisateur le meme jour, « une
                // fenetre unique peut couper la voyelle a son bord ». Calibrer
                // sur un maximum et appliquer sur une observation unique rend
                // les seuils trop hauts par construction : c'est exactement le
                // regime qui avait produit 86 rejets de regles a p=1,000 le
                // 2026-09-05.
                //
                // `dureesParMot` est rempli plus haut dans CE meme passage
                // (l'observation courante y est donc deja incluse) ; le
                // `maxOf` garde la borne meme si l'ordre changeait un jour.
                detections.filter { d ->
                    val nom = front.nomsRegles.getOrNull(d.ruleId) ?: ""
                    val min = SeuilsDureeTajwid.minMs(nom, tajwidStrict)
                    val courante = d.frames * Horloge.MS_PAR_FRAME
                    val vue = maxOf(courante,
                        dureesParMot[m.index]?.get(d.ruleId) ?: 0)
                    val gardee = vue >= min
                    if (!gardee) {
                        journal?.invoke("[tajwidDuree] mot=${m.index} $nom " +
                            "REJETEE ${vue}ms < ${min}ms " +
                            "(${if (tajwidStrict) "strict" else "tolerant"}" +
                            ", max sur les observations ; courante=${courante}ms)")
                    }
                    gardee
                }.map { it.ruleId }.distinct()
            } else emptyList()
            // Keep the auxiliary score with its evidence instead of trying to
            // join unrelated log lines later. It does not replace a V2 status.
            var mesureTete3: Tete3.Mesure? = null
            var mesureTete3Jugement: Tete3.Mesure? = null
            var etatTete3 = "INDISPONIBLE"
            val tetePourFormat = tete3 ?: tete3Jugement
            if (tetePourFormat != null && sorties.etat != null && m.frames > 0) {
                val vec = vecteurTete3(m, sorties.etat, logprobs)
                if (vec == null) {
                    etatTete3 = "ABSTENTION"
                    // ABSTENTION, et elle se dit. Un mot sans variante scorable
                    // ou sans chemin force n'est pas « correct » : il est
                    // INJUGEABLE par cette tete. Sans cette ligne, la difference
                    // entre « la tete l'a vu bon » et « la tete n'a rien vu du
                    // tout » serait invisible dans le log -- exactement le
                    // « zero trace = zero execution » deja paye sur le secours.
                    journal?.invoke("[t3] mot=${m.index} ABSTENTION f=${fenetre.id} abs=[$debutAbs,$finAbs]")
                } else if (vec.size != tetePourFormat.tailleEntree) {
                    etatTete3 = "INCOMPATIBLE"
                    // Taille incoherente = mauvais fichier de tete deploye. On
                    // le dit une bonne fois plutot que de laisser la tete se
                    // taire : c'est le cas ou l'app tournait avec une tete a
                    // 524 caracteristiques nourrie d'un vecteur d'un autre
                    // format, et rendait des logits denues de sens.
                    journal?.invoke("[t3] mot=${m.index} TETE INCOMPATIBLE : " +
                        "vecteur=${vec.size}, tete=${tetePourFormat.tailleEntree}")
                } else {
                    mesureTete3 = tete3?.mesurer(vec)
                    mesureTete3Jugement = tete3Jugement?.mesurer(vec)
                    etatTete3 = mesureTete3?.statut ?: "NON_FINIE"
                    val score = mesureTete3?.logit?.toString() ?: "absent"
                    val seuil = mesureTete3?.seuil2Pct?.toString() ?: "absent"
                    journal?.invoke("[t3] mot=${m.index} logit=$score " +
                        "seuil2%=$seuil $etatTete3 f=${fenetre.id} abs=[$debutAbs,$finAbs]")
                    tete3Comparaison?.let { candidate ->
                        val comparee = candidate.mesurer(vec)
                        journal?.invoke("[t3-comparaison] " + org.json.JSONObject()
                            .put("mode", "observation").put("mot", m.index)
                            .put("fenetre", fenetre.id).put("tentative", registre.tentativeId)
                            .put("attendu", motsAttendus[m.index]).put("entendu", m.entendu)
                            .put("debutAbs", debutAbs).put("finAbs", finAbs)
                            .put("dimensions", vec.size).put("interieur", m.interieur)
                            .put("actuelle", mesureTete3?.logit ?: org.json.JSONObject.NULL)
                            .put("candidate", comparee?.logit ?: org.json.JSONObject.NULL)
                            .put("etatCandidate", comparee?.statut ?: "INCOMPATIBLE_OU_NON_FINIE")
                            .toString())
                    }
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
                    mesureTete3 = mesureTete3,
                    etatTete3 = etatTete3,
                    mesureTete3Jugement = mesureTete3Jugement,
                    lectureVote = if (mesurerVote) VoteFenetres.mesurer(
                        m, libresPourVote, logprobs, front.blank, fenetre) else null,
                )
            )
            if (mesurerVote) {
                val observations = registre.observationsPourJugement(m.index)
                val o = registre.observations(m.index).last()
                journal?.invoke(JournalVoteFenetres.observation(o,
                    motsAttendus.getOrNull(m.index), registre.tentativeId))
                journal?.invoke(JournalVoteFenetres.resultat(m.index, fenetre.id,
                    registre.tentativeId, VoteFenetres.calculer(observations)))
            }
        }

        journal?.invoke(
            "[v2] f=${fenetre.id} duree=${"%.2f".format(fenetre.dureeSecondes)}s " +
                "bande=${bande.i0}..${bande.i1} conf=${"%.2f".format(bande.confiance)} " +
                "interieurs=${res.mots.count { it.interieur }}/${res.mots.size}" +
                (if (res.bandeTronquee) " (bande tronquee)" else "") +
                // DIAGNOSTIC (2026-08-13) : le decodage LIBRE de la fenetre n'etait
                // journalise QUE quand bande=inconnue. Sur une fenetre FINALE dont
                // la bande recule au lieu d'atteindre le dernier mot, ce texte est
                // la seule facon de voir ce que le modele a reellement entendu sur
                // CETTE fenetre precise, plutot que de le deviner hors device sur
                // un decoupage reconstitue a la main.
                (if (!fenetre.apercu) " entendu=\"" +
                    Decodage.texte(logprobs, front.pieces, front.blank) + "\"" else "")
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
        // -- LA FORME DE L ETAT DEPEND DE LA TETE CHARGEE (2026-08-21) --
        //
        // La tete du modele a TROIS tetes attendait moyenne ET ecart-type
        // de l etat (2 x 512 + 12 = 1036 entrees, couche 0 de 128 x 1036).
        // Celle du modele a QUATRE tetes n attend que la MOYENNE
        // (512 + 12 = 524, couche 0 de 32 x 524, environ 16 833 parametres).
        //
        // On choisit d apres ce que la tete CHARGEE declare, au lieu de
        // figer une forme : c est la seule facon de revenir a l ancien
        // modele sans retoucher ce fichier, ce que la regle du projet
        // exige.
        //
        // CE QUI S EST PASSE SANS CE CHOIX : le code construisait toujours
        // 1036 valeurs. Face a la tete a 524, l ecart de taille etait
        // detecte plus haut et le calcul SAUTE -- la tete 3 etait donc
        // eteinte depuis le deploiement du nouveau modele, sans autre
        // trace qu une ligne de journal. Le garde a fait son travail ; il
        // ne remplace pas la correction.
        val dimEtat = etat[f0].size
        val attendu = (tete3 ?: tete3Jugement)?.tailleEntree ?: (2 * dimEtat + traits.size)
        val etatVec = (if (attendu == dimEtat + traits.size) {
            Tete3Traits.etatMoyen(etat, f0, f1)
        } else {
            Tete3Traits.etatMoyenEtEcartType(etat, f0, f1)
        }) ?: return null
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

    companion object {
        /**
         * Ecart maximal toleré entre un mot de CONTEXTE et le mot demandé, pour
         * que le contexte soit joint à l'extrait (cf. [voixSurPlage]).
         *
         * 3 s : au-delà, le mot n'a pas été prononcé juste avant celui qu'on
         * écoute -- c'est une autre lecture du passage (reprise, inversion), et
         * l'ajouter décale ce qu'on entend au lieu d'éclairer.
         */
        private val CONTEXTE_MAX_ECH = (Horloge.TAUX * 3.0).toLong()

        /**
         * Durée maximale d'un extrait, marges comprises.
         *
         * 8 s pour deux mots, ce qui est large : un mot coranique, même porté
         * par un madd de 6 harakat en récitation lente, dépasse rarement 3 s.
         * Ce plafond n'est pas un réglage à ajuster, c'est un garde-fou : il
         * rend structurellement impossibles les extraits de 12,10 s et 15,62 s
         * mesurés le 2026-08-14. Il rogne toujours le DEBUT -- la fin porte le
         * mot demandé, elle ne se touche pas.
         */
        private val PLAGE_MAX_ECH = (Horloge.TAUX * 8.0).toLong()
    }
}

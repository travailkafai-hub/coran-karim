import '../models/dua.dart';

/// Univers « Cœur & épreuves » — angoisse, maladie, peur, dette, colère,
/// deuil, repentir — et la collection « Duas du pèlerin » de l'univers sacré.
///
/// C'est l'univers le plus consulté dans un moment de détresse : les entrées
/// sont donc courtes en priorité, et le champ `virtue` y sert autant à
/// consoler qu'à documenter.
const kDuasCoeur = <Dua>[
  // ── Angoisse & tristesse ───────────────────────────────────────────────
  Dua(
    id: 'karb',
    titleFr: "L'invocation de la grande détresse",
    titleAr: 'دعاء الكرب',
    textAr:
        'لَا إِلَهَ إِلَّا اللَّهُ الْعَظِيمُ الْحَلِيمُ، لَا إِلَهَ إِلَّا اللَّهُ رَبُّ الْعَرْشِ الْعَظِيمِ، لَا إِلَهَ إِلَّا اللَّهُ رَبُّ السَّمَاوَاتِ وَرَبُّ الْأَرْضِ وَرَبُّ الْعَرْشِ الْكَرِيمِ',
    translationFr:
        "Il n'y a de divinité qu'Allah, l'Immense, le Longanime. Il n'y a de divinité qu'Allah, Seigneur du Trône immense. Il n'y a de divinité qu'Allah, Seigneur des cieux, Seigneur de la terre et Seigneur du Trône généreux.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    virtue: "Le Prophète ﷺ y avait recours dans les moments de détresse.",
    tags: ['angoisse'],
  ),
  Dua(
    id: 'hamm_hazan',
    titleFr: "Contre le souci et la tristesse",
    titleAr: 'دعاء الهم والحزن',
    textAr:
        'اللَّهُمَّ إِنِّي أَعُوذُ بِكَ مِنَ الْهَمِّ وَالْحَزَنِ، وَالْعَجْزِ وَالْكَسَلِ، وَالْبُخْلِ وَالْجُبْنِ، وَضَلَعِ الدَّيْنِ وَغَلَبَةِ الرِّجَالِ',
    translationFr:
        "Ô Allah, je cherche refuge auprès de Toi contre le souci et la tristesse, contre l'incapacité et la paresse, contre l'avarice et la lâcheté, contre le poids de la dette et la domination des hommes.",
    source: 'Rapporté par Al-Boukhari',
    virtue:
        "Anas rapporte l'avoir appliquée : « Allah dissipa mon souci et régla ma dette. »",
    tags: ['angoisse', 'dette'],
  ),
  Dua(
    id: 'anas_abduka',
    titleFr: "Quand la tristesse ne passe pas",
    titleAr: 'دعاء الهم والحزن الشديد',
    textAr:
        'اللَّهُمَّ إِنِّي عَبْدُكَ، ابْنُ عَبْدِكَ، ابْنُ أَمَتِكَ، نَاصِيَتِي بِيَدِكَ، مَاضٍ فِيَّ حُكْمُكَ، عَدْلٌ فِيَّ قَضَاؤُكَ، أَسْأَلُكَ بِكُلِّ اسْمٍ هُوَ لَكَ سَمَّيْتَ بِهِ نَفْسَكَ، أَوْ أَنْزَلْتَهُ فِي كِتَابِكَ، أَوْ عَلَّمْتَهُ أَحَدًا مِنْ خَلْقِكَ، أَوِ اسْتَأْثَرْتَ بِهِ فِي عِلْمِ الْغَيْبِ عِنْدَكَ، أَنْ تَجْعَلَ الْقُرْآنَ رَبِيعَ قَلْبِي، وَنُورَ صَدْرِي، وَجِلَاءَ حُزْنِي، وَذَهَابَ هَمِّي',
    translationFr:
        "Ô Allah, je suis Ton serviteur, fils de Ton serviteur, fils de Ta servante. Mon toupet est dans Ta main, Ton jugement s'applique à moi, Ton décret à mon égard est juste. Je Te demande par tout nom qui T'appartient, dont Tu T'es nommé Toi-même, ou que Tu as révélé dans Ton Livre, ou que Tu as enseigné à l'une de Tes créatures, ou que Tu as gardé pour Toi dans la science de l'invisible : fais du Coran le printemps de mon cœur, la lumière de ma poitrine, la dissipation de ma tristesse et la disparition de mon souci.",
    source: 'Rapporté par Ahmad et Ibn Ḥibbān',
    virtue:
        "« Allah dissipera son souci et remplacera sa tristesse par une joie. » On demanda : faut-il l'apprendre ? Il répondit : « Bien sûr, que celui qui l'entend l'apprenne. »",
    tags: ['angoisse'],
  ),
  Dua(
    id: 'rahmataka_arju',
    titleFr: "Ne me confie pas à moi-même",
    titleAr: 'اللهم رحمتك أرجو',
    textAr:
        'اللَّهُمَّ رَحْمَتَكَ أَرْجُو، فَلَا تَكِلْنِي إِلَى نَفْسِي طَرْفَةَ عَيْنٍ، وَأَصْلِحْ لِي شَأْنِي كُلَّهُ، لَا إِلَهَ إِلَّا أَنْتَ',
    translationFr:
        "Ô Allah, c'est Ta miséricorde que j'espère : ne me confie pas à moi-même, ne serait-ce que le temps d'un clin d'œil. Améliore toute ma situation. Il n'y a de divinité que Toi.",
    source: 'Rapporté par Abou Dawoud',
    tags: ['angoisse'],
  ),
  Dua(
    id: 'hasbunallah',
    titleFr: "Allah nous suffit",
    titleAr: 'حسبنا الله ونعم الوكيل',
    textAr: 'حَسْبُنَا اللَّهُ وَنِعْمَ الْوَكِيلُ',
    translit: "Ḥasbunā llāhu wa niʿma l-wakīl",
    translationFr: "Allah nous suffit, et quel excellent Garant !",
    source: 'Āl ʿImrān 3:173',
    virtue:
        "Dite par Ibrāhīm jeté au feu, et par les compagnons quand on leur annonça que l'ennemi se rassemblait contre eux.",
    tags: ['angoisse', 'peur'],
    surahNumber: 3,
    ayahNumber: 173,
  ),

  // ── Maladie & douleur ──────────────────────────────────────────────────
  Dua(
    id: 'visite_malade',
    titleFr: 'En visitant un malade',
    titleAr: 'دعاء عيادة المريض',
    textAr: 'لَا بَأْسَ، طَهُورٌ إِنْ شَاءَ اللَّهُ',
    translit: "Lā ba's, ṭahūrun in shā'a llāh",
    translationFr:
        "Pas de mal, c'est une purification, si Allah veut.",
    source: 'Rapporté par Al-Boukhari',
    tags: ['maladie'],
  ),
  Dua(
    id: 'shifa_sept',
    titleFr: 'Demander la guérison — sept fois',
    titleAr: 'دعاء الشفاء',
    textAr:
        'أَسْأَلُ اللَّهَ الْعَظِيمَ، رَبَّ الْعَرْشِ الْعَظِيمِ، أَنْ يَشْفِيَكَ',
    translit: "As'alu llāha l-ʿaẓīm, rabba l-ʿarshi l-ʿaẓīm, an yashfiyak",
    translationFr:
        "Je demande à Allah l'Immense, Seigneur du Trône immense, de te guérir.",
    source: 'Rapporté par Abou Dawoud et At-Tirmidhi — sept fois auprès du malade',
    virtue:
        "« Aucun serviteur ne rend visite à un malade dont le terme n'est pas arrivé et ne dit cela sept fois sans qu'Allah ne le guérisse. »",
    tags: ['maladie'],
    repeat: 7,
  ),
  Dua(
    id: 'ruqya_douleur',
    titleFr: "Sur l'endroit qui fait mal",
    titleAr: 'دعاء وجع الجسد',
    textAr: 'أَعُوذُ بِعِزَّةِ اللَّهِ وَقُدْرَتِهِ مِنْ شَرِّ مَا أَجِدُ وَأُحَاذِرُ',
    translationFr:
        "Je cherche refuge dans la puissance d'Allah et Sa capacité contre le mal que je ressens et que je redoute.",
    source: 'Rapporté par Mouslim — poser la main sur la douleur, dire « Bismillāh » trois fois puis ceci sept fois',
    tags: ['maladie'],
    repeat: 7,
  ),
  Dua(
    id: 'adhhib_bas',
    titleFr: 'Fais partir le mal',
    titleAr: 'اللهم رب الناس أذهب الباس',
    textAr:
        'اللَّهُمَّ رَبَّ النَّاسِ، أَذْهِبِ الْبَأْسَ، اشْفِ أَنْتَ الشَّافِي، لَا شِفَاءَ إِلَّا شِفَاؤُكَ، شِفَاءً لَا يُغَادِرُ سَقَمًا',
    translationFr:
        "Ô Allah, Seigneur des hommes, fais partir le mal. Guéris, car c'est Toi le Guérisseur. Il n'est de guérison que la Tienne — une guérison qui ne laisse aucune trace de maladie.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    tags: ['maladie'],
  ),

  // ── Peur & protection ──────────────────────────────────────────────────
  Dua(
    id: 'ennemi',
    titleFr: 'Face à un adversaire',
    titleAr: 'دعاء لقاء العدو',
    textAr:
        'اللَّهُمَّ إِنَّا نَجْعَلُكَ فِي نُحُورِهِمْ، وَنَعُوذُ بِكَ مِنْ شُرُورِهِمْ',
    translationFr:
        "Ô Allah, nous Te plaçons face à eux et nous cherchons refuge auprès de Toi contre leurs maux.",
    source: 'Rapporté par Abou Dawoud et An-Nasā\'ī',
    tags: ['peur'],
  ),
  Dua(
    id: 'cauchemar',
    titleFr: 'Après un mauvais rêve',
    titleAr: 'ما يفعل من رأى حلما مكروها',
    textAr:
        'يَنْفُثُ عَنْ يَسَارِهِ ثَلَاثًا، وَيَتَعَوَّذُ بِاللَّهِ مِنَ الشَّيْطَانِ وَمِنْ شَرِّ مَا رَأَى، وَلَا يُحَدِّثُ بِهَا أَحَدًا، وَيَتَحَوَّلُ عَنْ جَنْبِهِ الَّذِي كَانَ عَلَيْهِ',
    translationFr:
        "Souffler légèrement trois fois à sa gauche, chercher refuge auprès d'Allah contre le diable et contre le mal de ce qu'on a vu, n'en parler à personne, et changer de côté.",
    source: 'Rapporté par Mouslim',
    virtue: "« Alors il ne lui nuira pas. »",
    tags: ['peur', 'sommeil'],
  ),
  Dua(
    id: 'waswas',
    titleFr: 'Contre les insinuations du doute',
    titleAr: 'دعاء الوسوسة',
    textAr: 'آمَنْتُ بِاللَّهِ وَرُسُلِهِ. أَعُوذُ بِاللَّهِ مِنَ الشَّيْطَانِ الرَّجِيمِ',
    translationFr:
        "Je crois en Allah et en Ses messagers. Je cherche refuge auprès d'Allah contre le diable banni.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    virtue:
        "Le remède prescrit n'est pas de discuter la pensée mais de s'en détourner : « qu'il cesse » et qu'il se réfugie auprès d'Allah.",
    tags: ['peur'],
  ),

  // ── Dette & subsistance ────────────────────────────────────────────────
  Dua(
    id: 'dette_ikfini',
    titleFr: "Contre la dette qui étouffe",
    titleAr: 'دعاء قضاء الدين',
    textAr:
        'اللَّهُمَّ اكْفِنِي بِحَلَالِكَ عَنْ حَرَامِكَ، وَأَغْنِنِي بِفَضْلِكَ عَمَّنْ سِوَاكَ',
    translit: "Allāhumma kfinī biḥalālika ʿan ḥarāmik, wa aghninī bifaḍlika ʿamman siwāk",
    translationFr:
        "Ô Allah, fais que ce que Tu as rendu licite me suffise, sans avoir besoin de ce que Tu as interdit, et enrichis-moi de Ta grâce, sans avoir besoin d'un autre que Toi.",
    source: 'Rapporté par At-Tirmidhi',
    virtue:
        "« Même si tu avais une dette de la taille d'une montagne, Allah te permettrait de la régler. »",
    tags: ['dette'],
  ),
  Dua(
    id: 'istighfar_rizq',
    titleFr: "L'istighfār qui ouvre la subsistance",
    titleAr: 'الاستغفار والرزق',
    textAr:
        'فَقُلْتُ اسْتَغْفِرُوا رَبَّكُمْ إِنَّهُ كَانَ غَفَّارًا ۝ يُرْسِلِ السَّمَاءَ عَلَيْكُم مِّدْرَارًا ۝ وَيُمْدِدْكُم بِأَمْوَالٍ وَبَنِينَ وَيَجْعَل لَّكُمْ جَنَّاتٍ وَيَجْعَل لَّكُمْ أَنْهَارًا',
    translationFr:
        "J'ai dit : « Demandez pardon à votre Seigneur, car Il est Grand Pardonneur, pour qu'Il vous envoie du ciel des pluies abondantes, qu'Il vous accorde des biens et des enfants, et qu'Il vous donne des jardins et des rivières. »",
    source: 'Nūḥ 71:10-12',
    virtue:
        "Le lien entre le pardon demandé et la subsistance reçue est posé par le Coran lui-même.",
    tags: ['dette', 'istighfar'],
    surahNumber: 71,
    ayahNumber: 10,
  ),

  // ── Colère & discorde ──────────────────────────────────────────────────
  Dua(
    id: 'colere_taawwudh',
    titleFr: 'Quand la colère monte',
    titleAr: 'دعاء الغضب',
    textAr: 'أَعُوذُ بِاللَّهِ مِنَ الشَّيْطَانِ الرَّجِيمِ',
    translit: "Aʿūdhu billāhi mina sh-shayṭāni r-rajīm",
    translationFr: "Je cherche refuge auprès d'Allah contre le diable banni.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    virtue:
        "« Je connais une parole qui, s'il la disait, ferait partir ce qu'il éprouve. » S'y ajoutent : s'asseoir si l'on est debout, se taire, faire ses ablutions.",
    tags: ['colere'],
  ),
  Dua(
    id: 'akhlaq',
    titleFr: 'Guide-moi vers le meilleur caractère',
    titleAr: 'اللهم اهدني لأحسن الأخلاق',
    textAr:
        'اللَّهُمَّ اهْدِنِي لِأَحْسَنِ الْأَخْلَاقِ، لَا يَهْدِي لِأَحْسَنِهَا إِلَّا أَنْتَ، وَاصْرِفْ عَنِّي سَيِّئَهَا، لَا يَصْرِفُ عَنِّي سَيِّئَهَا إِلَّا أَنْتَ',
    translationFr:
        "Ô Allah, guide-moi vers le meilleur des caractères, nul ne guide vers le meilleur d'entre eux si ce n'est Toi. Et détourne de moi le mauvais caractère, nul ne l'écarte de moi si ce n'est Toi.",
    source: 'Rapporté par Mouslim',
    tags: ['colere'],
  ),

  // ── Deuil ──────────────────────────────────────────────────────────────
  Dua(
    id: 'istirja',
    titleFr: "À l'annonce d'un malheur",
    titleAr: 'الاسترجاع',
    textAr:
        'إِنَّا لِلَّهِ وَإِنَّا إِلَيْهِ رَاجِعُونَ. اللَّهُمَّ أْجُرْنِي فِي مُصِيبَتِي، وَأَخْلِفْ لِي خَيْرًا مِنْهَا',
    translit: "Innā lillāhi wa innā ilayhi rājiʿūn",
    translationFr:
        "Nous sommes à Allah et c'est à Lui que nous retournons. Ô Allah, récompense-moi dans mon épreuve et remplace-la-moi par un bien.",
    source: 'Al-Baqara 2:156 — et hadith rapporté par Mouslim',
    virtue:
        "Umm Salama la dit à la mort de son mari en pensant que personne ne valait mieux que lui — et Allah lui donna le Prophète ﷺ pour époux.",
    tags: ['deuil', 'angoisse'],
    surahNumber: 2,
    ayahNumber: 156,
  ),
  Dua(
    id: 'janaza',
    titleFr: 'Pour le défunt, dans la prière funéraire',
    titleAr: 'دعاء الصلاة على الميت',
    textAr:
        'اللَّهُمَّ اغْفِرْ لَهُ وَارْحَمْهُ، وَعَافِهِ وَاعْفُ عَنْهُ، وَأَكْرِمْ نُزُلَهُ، وَوَسِّعْ مُدْخَلَهُ، وَاغْسِلْهُ بِالْمَاءِ وَالثَّلْجِ وَالْبَرَدِ، وَنَقِّهِ مِنَ الْخَطَايَا كَمَا نَقَّيْتَ الثَّوْبَ الْأَبْيَضَ مِنَ الدَّنَسِ',
    translationFr:
        "Ô Allah, pardonne-lui, fais-lui miséricorde, préserve-le et efface ses fautes. Fais-lui un honorable accueil, élargis son entrée, lave-le avec l'eau, la neige et la grêle, et purifie-le de ses péchés comme Tu purifies le vêtement blanc de la souillure.",
    source: 'Rapporté par Mouslim',
    tags: ['deuil'],
  ),
  Dua(
    id: 'visite_tombes',
    titleFr: 'En visitant les tombes',
    titleAr: 'دعاء زيارة القبور',
    textAr:
        'السَّلَامُ عَلَيْكُمْ أَهْلَ الدِّيَارِ مِنَ الْمُؤْمِنِينَ وَالْمُسْلِمِينَ، وَإِنَّا إِنْ شَاءَ اللَّهُ بِكُمْ لَاحِقُونَ، نَسْأَلُ اللَّهَ لَنَا وَلَكُمُ الْعَافِيَةَ',
    translationFr:
        "Que la paix soit sur vous, habitants de ces demeures, croyants et musulmans. Nous vous rejoindrons, si Allah veut. Nous demandons à Allah la préservation pour nous et pour vous.",
    source: 'Rapporté par Mouslim',
    tags: ['deuil'],
  ),

  // ── Repentir & istighfār ───────────────────────────────────────────────
  Dua(
    id: 'istighfar_100',
    titleFr: 'Cent fois par jour',
    titleAr: 'الاستغفار مئة مرة',
    textAr: 'أَسْتَغْفِرُ اللَّهَ وَأَتُوبُ إِلَيْهِ',
    translit: "Astaghfiru llāha wa atūbu ilayh",
    translationFr: "Je demande pardon à Allah et je me repens à Lui.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    virtue:
        "« Ô gens, repentez-vous à Allah : moi-même je me repens à Lui cent fois par jour. » Le modèle le plus élevé demandait pardon plus que quiconque.",
    tags: ['istighfar'],
    repeat: 100,
  ),
  Dua(
    id: 'rabbi_ghfir_li',
    titleFr: 'Pardonne-moi et accepte mon repentir',
    titleAr: 'رب اغفر لي وتب علي',
    textAr:
        'رَبِّ اغْفِرْ لِي وَتُبْ عَلَيَّ، إِنَّكَ أَنْتَ التَّوَّابُ الرَّحِيمُ',
    translit: "Rabbi ghfir lī wa tub ʿalayy, innaka anta t-tawwābu r-raḥīm",
    translationFr:
        "Seigneur, pardonne-moi et accepte mon repentir. Tu es Celui qui accueille le repentir, le Miséricordieux.",
    source: 'Rapporté par Abou Dawoud et At-Tirmidhi — comptée cent fois dans une même assise',
    tags: ['istighfar'],
    repeat: 100,
  ),
  Dua(
    id: 'laylat_qadr',
    titleFr: 'La nuit du Destin',
    titleAr: 'دعاء ليلة القدر',
    textAr: 'اللَّهُمَّ إِنَّكَ عَفُوٌّ تُحِبُّ الْعَفْوَ فَاعْفُ عَنِّي',
    translit: "Allāhumma innaka ʿafuwwun tuḥibbu l-ʿafwa faʿfu ʿannī",
    translationFr:
        "Ô Allah, Tu es Celui qui efface, Tu aimes effacer : efface donc mes fautes.",
    source: 'Rapporté par At-Tirmidhi et Ibn Majah',
    virtue:
        "ʿĀʾisha demanda quoi dire si elle trouvait Laylat al-Qadr — c'est la réponse qu'elle reçut. À multiplier dans les dix dernières nuits du Ramadan.",
    tags: ['istighfar', 'nuit'],
  ),

  // ── Duas du pèlerin (univers sacré) ────────────────────────────────────
  Dua(
    id: 'talbiya',
    titleFr: 'La Talbiya',
    titleAr: 'التلبية',
    textAr:
        'لَبَّيْكَ اللَّهُمَّ لَبَّيْكَ، لَبَّيْكَ لَا شَرِيكَ لَكَ لَبَّيْكَ، إِنَّ الْحَمْدَ وَالنِّعْمَةَ لَكَ وَالْمُلْكَ، لَا شَرِيكَ لَكَ',
    translit: "Labbayka llāhumma labbayk, labbayka lā sharīka laka labbayk, inna l-ḥamda wa n-niʿmata laka wa l-mulk, lā sharīka lak",
    translationFr:
        "Me voici à Toi, ô Allah, me voici. Me voici, Tu n'as pas d'associé, me voici. La louange, le bienfait et la royauté T'appartiennent. Tu n'as pas d'associé.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    virtue:
        "Se dit dès l'entrée en état de sacralisation et se répète sans cesse — en montant, en descendant, à chaque rencontre — jusqu'au premier jet de cailloux pour le Hajj, ou jusqu'au début du ṭawāf pour la ʿUmra. Les hommes élèvent la voix, les femmes la gardent basse.",
    tags: ['pelerin'],
    repeat: 3,
  ),
  Dua(
    id: 'vue_kaaba',
    titleFr: 'En voyant la Kaʿba',
    titleAr: 'دعاء رؤية الكعبة',
    textAr:
        'اللَّهُمَّ زِدْ هَذَا الْبَيْتَ تَشْرِيفًا وَتَعْظِيمًا وَتَكْرِيمًا وَمَهَابَةً',
    translationFr:
        "Ô Allah, accrois pour cette Maison l'honneur, la grandeur, la noblesse et la vénération.",
    source:
        "Rapporté d'Ibn Jurayj sous forme mursal (chaîne incomplète) — pas de formule prophétique établie. L'usage recommandé est surtout d'invoquer librement à ce moment, l'invocation y étant réputée exaucée.",
    tags: ['pelerin'],
  ),
  Dua(
    id: 'zamzam',
    titleFr: 'En buvant l\'eau de Zamzam',
    titleAr: 'دعاء شرب ماء زمزم',
    textAr:
        'اللَّهُمَّ إِنِّي أَسْأَلُكَ عِلْمًا نَافِعًا، وَرِزْقًا وَاسِعًا، وَشِفَاءً مِنْ كُلِّ دَاءٍ',
    translationFr:
        "Ô Allah, je Te demande une science utile, une subsistance abondante et une guérison de tout mal.",
    source: 'Rapporté par Ad-Dāraquṭnī et Al-Hakim — invocation d\'Ibn ʿAbbās',
    virtue:
        "« L'eau de Zamzam est pour ce pour quoi on la boit. » (Ibn Majah) On boit debout, face à la qibla, en trois gorgées, et l'on formule son intention.",
    tags: ['pelerin', 'maladie'],
  ),
  Dua(
    id: 'safa_marwa',
    titleFr: 'Sur Ṣafā et Marwa',
    titleAr: 'الذكر على الصفا والمروة',
    textAr:
        'إِنَّ الصَّفَا وَالْمَرْوَةَ مِن شَعَائِرِ اللَّهِ ۝ أَبْدَأُ بِمَا بَدَأَ اللَّهُ بِهِ. اللَّهُ أَكْبَرُ، اللَّهُ أَكْبَرُ، اللَّهُ أَكْبَرُ، لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ، لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ، أَنْجَزَ وَعْدَهُ، وَنَصَرَ عَبْدَهُ، وَهَزَمَ الْأَحْزَابَ وَحْدَهُ',
    translationFr:
        "« Ṣafā et Marwa sont vraiment parmi les lieux sacrés d'Allah » — je commence par ce par quoi Allah a commencé. Allah est le plus Grand (×3). Il n'y a de divinité qu'Allah, Seul, sans associé ; à Lui la royauté, à Lui la louange, et Il est capable de toute chose. Il n'y a de divinité qu'Allah, Seul : Il a tenu Sa promesse, secouru Son serviteur et défait les coalisés à Lui seul.",
    source: 'Al-Baqara 2:158 — et hadith de Jābir rapporté par Mouslim',
    virtue:
        "Se dit face à la Kaʿba, en levant les mains, sur chacune des deux collines — trois fois, en invoquant librement entre chaque.",
    tags: ['pelerin'],
    surahNumber: 2,
    ayahNumber: 158,
  ),
  Dua(
    id: 'arafa',
    titleFr: "La meilleure invocation — jour de ʿArafa",
    titleAr: 'دعاء يوم عرفة',
    textAr:
        'لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ، وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ',
    translationFr:
        "Il n'y a de divinité qu'Allah, Seul, sans associé. À Lui la royauté, à Lui la louange, et Il est capable de toute chose.",
    source: 'Rapporté par At-Tirmidhi',
    virtue:
        "« La meilleure invocation est celle du jour de ʿArafa, et la meilleure parole que j'aie dite, moi et les prophètes avant moi, est celle-ci. » Le jour où Allah affranchit le plus de serviteurs du Feu.",
    tags: ['pelerin'],
    repeat: 100,
  ),
  Dua(
    id: 'salam_prophete',
    titleFr: 'Le salut au Prophète ﷺ à Médine',
    titleAr: 'السلام على النبي',
    textAr:
        'السَّلَامُ عَلَيْكَ يَا رَسُولَ اللَّهِ وَرَحْمَةُ اللَّهِ وَبَرَكَاتُهُ، السَّلَامُ عَلَيْكَ يَا أَبَا بَكْرٍ، السَّلَامُ عَلَيْكَ يَا عُمَرَ',
    translationFr:
        "Que la paix soit sur toi, ô Messager d'Allah, ainsi que la miséricorde d'Allah et Ses bénédictions. Que la paix soit sur toi, ô Abou Bakr. Que la paix soit sur toi, ô ʿUmar.",
    source: 'Pratique rapportée d\'Ibn ʿUmar (Mālik, Al-Muwaṭṭaʾ)',
    virtue:
        "La visite de la mosquée du Prophète ﷺ n'est pas un rite du Hajj : c'est une visite recommandée en soi, à tout moment de l'année.",
    tags: ['pelerin'],
  ),
];

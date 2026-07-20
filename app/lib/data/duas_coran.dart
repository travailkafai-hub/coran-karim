import '../models/dua.dart';

/// Univers « Le Coran » — les « Rabbanā », les invocations des prophètes,
/// les usages de lecture, le khatm, les versets de protection.
///
/// NOTE DE SOURCE, collection `khatm` (demande utilisateur 2026-07-20 :
/// « ce qu'on dit à la fin du Coran ») : il n'existe PAS d'invocation de
/// clôture du Coran authentiquement établie du Prophète ﷺ. Ce qui circule
/// sous le nom de « duʿāʾ khatm al-Qurʾān » (la longue formule
/// « اللهم ارحمني بالقرآن ») a une chaîne faible, et « ṣadaqa llāhu l-ʿaẓīm »
/// est un usage tardif, pas une sunna. En revanche la PRATIQUE d'invoquer en
/// achevant une lecture complète est solidement rapportée des compagnons
/// (Anas rassemblait sa famille). Les entrées ci-dessous le disent
/// explicitement dans `source` au lieu de laisser croire à un hadith —
/// mentir par omission sur une source serait pire que ne rien proposer.
///
/// Plusieurs versets de protection (Āyat al-Kursī, les Muʿawwidhāt, la fin
/// d'Al-Baqara) ne sont PAS redéclarés ici : ils vivent dans `duas_jour.dart`
/// et portent déjà le tag `protection_coran`. C'est tout l'intérêt des tags
/// multiples — une entrée, plusieurs points d'entrée, aucune duplication.
const kDuasCoran = <Dua>[
  // ── Les « Rabbanā » ────────────────────────────────────────────────────
  Dua(
    id: 'rabbana_hasana',
    titleFr: 'Le bien ici-bas et dans l\'au-delà',
    titleAr: 'ربنا آتنا في الدنيا حسنة',
    textAr:
        'رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً وَقِنَا عَذَابَ النَّارِ',
    translit: "Rabbanā ātinā fī d-dunyā ḥasanatan wa fī l-ākhirati ḥasanatan wa qinā ʿadhāba n-nār",
    translationFr:
        "Notre Seigneur, accorde-nous une belle part ici-bas et une belle part dans l'au-delà, et préserve-nous du châtiment du Feu.",
    source: 'Al-Baqara 2:201',
    virtue:
        "L'invocation que le Prophète ﷺ répétait le plus (Al-Boukhari). Elle se dit aussi entre le Coin yéménite et la Pierre noire, à chaque tour du ṭawāf.",
    tags: ['rabbana', 'pelerin'],
    surahNumber: 2,
    ayahNumber: 201,
  ),
  Dua(
    id: 'rabbana_la_tuzigh',
    titleFr: 'Ne laisse pas nos cœurs dévier',
    titleAr: 'ربنا لا تزغ قلوبنا',
    textAr:
        'رَبَّنَا لَا تُزِغْ قُلُوبَنَا بَعْدَ إِذْ هَدَيْتَنَا وَهَبْ لَنَا مِن لَّدُنكَ رَحْمَةً ۚ إِنَّكَ أَنتَ الْوَهَّابُ',
    translationFr:
        "Notre Seigneur, ne laisse pas nos cœurs dévier après que Tu nous as guidés, et accorde-nous Ta miséricorde : c'est Toi le Grand Donateur.",
    source: 'Āl ʿImrān 3:8',
    virtue:
        "Traditionnellement récitée en achevant une lecture complète du Coran : on demande de garder ce qu'on vient de recevoir.",
    tags: ['rabbana', 'khatm'],
    surahNumber: 3,
    ayahNumber: 8,
  ),
  Dua(
    id: 'rabbana_zalamna',
    titleFr: 'Nous avons lésé nos âmes',
    titleAr: 'ربنا ظلمنا أنفسنا',
    textAr:
        'رَبَّنَا ظَلَمْنَا أَنفُسَنَا وَإِن لَّمْ تَغْفِرْ لَنَا وَتَرْحَمْنَا لَنَكُونَنَّ مِنَ الْخَاسِرِينَ',
    translationFr:
        "Notre Seigneur, nous avons lésé nos âmes. Si Tu ne nous pardonnes pas et ne nous fais pas miséricorde, nous serons du nombre des perdants.",
    source: 'Al-Aʿrāf 7:23 — les mots d\'Adam et Ève après la faute',
    virtue: "Le premier repentir de l'histoire humaine, et le modèle de tous les autres.",
    tags: ['rabbana', 'prophetes', 'istighfar'],
    surahNumber: 7,
    ayahNumber: 23,
  ),
  Dua(
    id: 'rabbana_qurrata_ayun',
    titleFr: 'La joie des yeux',
    titleAr: 'ربنا هب لنا قرة أعين',
    textAr:
        'رَبَّنَا هَبْ لَنَا مِنْ أَزْوَاجِنَا وَذُرِّيَّاتِنَا قُرَّةَ أَعْيُنٍ وَاجْعَلْنَا لِلْمُتَّقِينَ إِمَامًا',
    translationFr:
        "Notre Seigneur, donne-nous, en nos épouses et nos descendants, la joie des yeux, et fais de nous un modèle pour les pieux.",
    source: 'Al-Furqān 25:74',
    tags: ['rabbana'],
    surahNumber: 25,
    ayahNumber: 74,
  ),
  Dua(
    id: 'rabbana_la_tuhammilna',
    titleFr: 'Ne nous impose pas ce que nous ne pouvons porter',
    titleAr: 'ربنا ولا تحملنا ما لا طاقة لنا به',
    textAr:
        'رَبَّنَا لَا تُؤَاخِذْنَا إِن نَّسِينَا أَوْ أَخْطَأْنَا ۚ رَبَّنَا وَلَا تَحْمِلْ عَلَيْنَا إِصْرًا كَمَا حَمَلْتَهُ عَلَى الَّذِينَ مِن قَبْلِنَا ۚ رَبَّنَا وَلَا تُحَمِّلْنَا مَا لَا طَاقَةَ لَنَا بِهِ ۖ وَاعْفُ عَنَّا وَاغْفِرْ لَنَا وَارْحَمْنَا ۚ أَنتَ مَوْلَانَا فَانصُرْنَا عَلَى الْقَوْمِ الْكَافِرِينَ',
    translationFr:
        "Notre Seigneur, ne nous tiens pas rigueur si nous oublions ou commettons une erreur. Notre Seigneur, ne nous charge pas d'un fardeau lourd comme Tu en as chargé ceux qui nous ont précédés. Notre Seigneur, ne nous impose pas ce que nous ne pouvons supporter. Efface nos fautes, pardonne-nous et fais-nous miséricorde. Tu es notre Maître : accorde-nous la victoire sur le peuple mécréant.",
    source: 'Al-Baqara 2:286',
    virtue: "Après chaque demande de ce verset, Allah répondit : « C'est accordé. » (Mouslim)",
    tags: ['rabbana', 'protection_coran'],
    surahNumber: 2,
    ayahNumber: 286,
  ),
  Dua(
    id: 'rabbana_sabran',
    titleFr: 'Déverse sur nous la patience',
    titleAr: 'ربنا أفرغ علينا صبرا',
    textAr:
        'رَبَّنَا أَفْرِغْ عَلَيْنَا صَبْرًا وَثَبِّتْ أَقْدَامَنَا وَانصُرْنَا عَلَى الْقَوْمِ الْكَافِرِينَ',
    translationFr:
        "Notre Seigneur, déverse sur nous la patience, affermis nos pas et donne-nous la victoire sur le peuple mécréant.",
    source: 'Al-Baqara 2:250 — les mots de Ṭālūt et des siens face à Goliath',
    tags: ['rabbana', 'angoisse'],
    surahNumber: 2,
    ayahNumber: 250,
  ),
  Dua(
    id: 'rabbana_maghfira',
    titleFr: 'Pardonne-nous nos péchés',
    titleAr: 'ربنا اغفر لنا ذنوبنا',
    textAr:
        'رَبَّنَا اغْفِرْ لَنَا ذُنُوبَنَا وَإِسْرَافَنَا فِي أَمْرِنَا وَثَبِّتْ أَقْدَامَنَا وَانصُرْنَا عَلَى الْقَوْمِ الْكَافِرِينَ',
    translationFr:
        "Notre Seigneur, pardonne-nous nos péchés et nos excès dans nos affaires, affermis nos pas et donne-nous la victoire sur le peuple mécréant.",
    source: 'Āl ʿImrān 3:147',
    tags: ['rabbana', 'istighfar'],
    surahNumber: 3,
    ayahNumber: 147,
  ),
  Dua(
    id: 'rabbana_frere',
    titleFr: 'Pour ceux qui nous ont précédés',
    titleAr: 'ربنا اغفر لنا ولإخواننا',
    textAr:
        'رَبَّنَا اغْفِرْ لَنَا وَلِإِخْوَانِنَا الَّذِينَ سَبَقُونَا بِالْإِيمَانِ وَلَا تَجْعَلْ فِي قُلُوبِنَا غِلًّا لِّلَّذِينَ آمَنُوا رَبَّنَا إِنَّكَ رَءُوفٌ رَّحِيمٌ',
    translationFr:
        "Notre Seigneur, pardonne-nous ainsi qu'à nos frères qui nous ont précédés dans la foi, et ne mets dans nos cœurs aucune rancune envers ceux qui ont cru. Notre Seigneur, Tu es Compatissant, Très Miséricordieux.",
    source: 'Al-Ḥashr 59:10',
    tags: ['rabbana', 'deuil', 'colere'],
    surahNumber: 59,
    ayahNumber: 10,
  ),
  Dua(
    id: 'rabbana_kahf',
    titleFr: 'Miséricorde et droiture',
    titleAr: 'ربنا آتنا من لدنك رحمة',
    textAr:
        'رَبَّنَا آتِنَا مِن لَّدُنكَ رَحْمَةً وَهَيِّئْ لَنَا مِنْ أَمْرِنَا رَشَدًا',
    translationFr:
        "Notre Seigneur, accorde-nous de Ta part une miséricorde et arrange pour nous ce qui est juste dans notre affaire.",
    source: 'Al-Kahf 18:10 — les mots des jeunes gens de la caverne',
    tags: ['rabbana', 'istikhara'],
    surahNumber: 18,
    ayahNumber: 10,
  ),

  // ── Invocations des prophètes ──────────────────────────────────────────
  Dua(
    id: 'dua_yunus',
    titleFr: "L'invocation de Yūnus",
    titleAr: 'دعاء ذي النون',
    textAr: 'لَّا إِلَٰهَ إِلَّا أَنتَ سُبْحَانَكَ إِنِّي كُنتُ مِنَ الظَّالِمِينَ',
    translit: "Lā ilāha illā anta subḥānaka innī kuntu mina ẓ-ẓālimīn",
    translationFr:
        "Il n'y a de divinité que Toi. Gloire à Toi ! J'ai été du nombre des injustes.",
    source: 'Al-Anbiyāʾ 21:87',
    virtue:
        "« Aucun musulman n'invoque par ces mots sans qu'Allah ne l'exauce. » (At-Tirmidhi) Prononcée depuis les ténèbres du ventre du poisson — d'où sa réputation d'invocation des situations sans issue.",
    tags: ['prophetes', 'angoisse', 'istighfar'],
    surahNumber: 21,
    ayahNumber: 87,
  ),
  Dua(
    id: 'dua_ayyub',
    titleFr: "L'invocation d'Ayyūb",
    titleAr: 'دعاء أيوب',
    textAr: 'أَنِّي مَسَّنِيَ الضُّرُّ وَأَنتَ أَرْحَمُ الرَّاحِمِينَ',
    translationFr:
        "Le mal m'a touché. Et Toi, Tu es le plus Miséricordieux des miséricordieux.",
    source: 'Al-Anbiyāʾ 21:83',
    virtue:
        "Après des années d'épreuve, il ne demande rien explicitement : il expose son état et rappelle qui est Allah. Une leçon de pudeur dans la plainte.",
    tags: ['prophetes', 'maladie', 'angoisse'],
    surahNumber: 21,
    ayahNumber: 83,
  ),
  Dua(
    id: 'dua_musa_sadr',
    titleFr: "L'invocation de Mūsā avant d'affronter Pharaon",
    titleAr: 'دعاء موسى',
    textAr:
        'رَبِّ اشْرَحْ لِي صَدْرِي ۝ وَيَسِّرْ لِي أَمْرِي ۝ وَاحْلُلْ عُقْدَةً مِّن لِّسَانِي ۝ يَفْقَهُوا قَوْلِي',
    translit: "Rabbi shraḥ lī ṣadrī wa yassir lī amrī",
    translationFr:
        "Seigneur, ouvre-moi ma poitrine, facilite ma mission, dénoue le nœud de ma langue afin qu'ils comprennent mes paroles.",
    source: 'Ṭāhā 20:25-28',
    virtue: "À dire avant de parler en public, de passer un examen, d'affronter une confrontation.",
    tags: ['prophetes', 'angoisse'],
    surahNumber: 20,
    ayahNumber: 25,
  ),
  Dua(
    id: 'dua_musa_faqir',
    titleFr: "Le besoin de Mūsā",
    titleAr: 'رب إني لما أنزلت إلي من خير فقير',
    textAr: 'رَبِّ إِنِّي لِمَا أَنزَلْتَ إِلَيَّ مِنْ خَيْرٍ فَقِيرٌ',
    translationFr:
        "Seigneur, je suis nécessiteux du bien que Tu feras descendre vers moi.",
    source: 'Al-Qaṣaṣ 28:24',
    virtue:
        "Dite seul, épuisé, sans nourriture ni abri. Il ne nomme pas son besoin — et tout lui fut donné : un toit, un travail, une famille.",
    tags: ['prophetes', 'dette'],
    surahNumber: 28,
    ayahNumber: 24,
  ),
  Dua(
    id: 'dua_zakariyya',
    titleFr: "L'invocation de Zakariyyā",
    titleAr: 'دعاء زكريا',
    textAr: 'رَبِّ لَا تَذَرْنِي فَرْدًا وَأَنتَ خَيْرُ الْوَارِثِينَ',
    translationFr:
        "Seigneur, ne me laisse pas seul, et Tu es le meilleur des héritiers.",
    source: 'Al-Anbiyāʾ 21:89',
    virtue: "Exaucée alors qu'il était très vieux et sa femme stérile.",
    tags: ['prophetes'],
    surahNumber: 21,
    ayahNumber: 89,
  ),
  Dua(
    id: 'dua_ibrahim_salat',
    titleFr: "L'invocation d'Ibrāhīm pour sa descendance",
    titleAr: 'دعاء إبراهيم',
    textAr:
        'رَبِّ اجْعَلْنِي مُقِيمَ الصَّلَاةِ وَمِن ذُرِّيَّتِي ۚ رَبَّنَا وَتَقَبَّلْ دُعَاءِ ۝ رَبَّنَا اغْفِرْ لِي وَلِوَالِدَيَّ وَلِلْمُؤْمِنِينَ يَوْمَ يَقُومُ الْحِسَابُ',
    translationFr:
        "Seigneur, fais de moi et de ma descendance des gens qui accomplissent la prière. Notre Seigneur, accepte mon invocation. Notre Seigneur, pardonne-moi, ainsi qu'à mes parents et aux croyants, le jour où sera dressé le compte.",
    source: 'Ibrāhīm 14:40-41',
    tags: ['prophetes', 'rabbana'],
    surahNumber: 14,
    ayahNumber: 40,
  ),
  Dua(
    id: 'dua_sulayman',
    titleFr: "L'invocation de Sulaymān",
    titleAr: 'دعاء سليمان',
    textAr:
        'رَبِّ أَوْزِعْنِي أَنْ أَشْكُرَ نِعْمَتَكَ الَّتِي أَنْعَمْتَ عَلَيَّ وَعَلَىٰ وَالِدَيَّ وَأَنْ أَعْمَلَ صَالِحًا تَرْضَاهُ وَأَدْخِلْنِي بِرَحْمَتِكَ فِي عِبَادِكَ الصَّالِحِينَ',
    translationFr:
        "Seigneur, inspire-moi de Te remercier pour le bienfait dont Tu m'as comblé ainsi que mes parents, et de faire une bonne œuvre que Tu agrées. Et fais-moi entrer, par Ta miséricorde, parmi Tes serviteurs vertueux.",
    source: 'An-Naml 27:19',
    virtue:
        "Prononcée non pas dans le manque mais dans l'abondance — l'invocation de celui à qui tout a été donné.",
    tags: ['prophetes'],
    surahNumber: 27,
    ayahNumber: 19,
  ),
  Dua(
    id: 'dua_yusuf',
    titleFr: "L'invocation de Yūsuf",
    titleAr: 'دعاء يوسف',
    textAr:
        'فَاطِرَ السَّمَاوَاتِ وَالْأَرْضِ أَنتَ وَلِيِّي فِي الدُّنْيَا وَالْآخِرَةِ ۖ تَوَفَّنِي مُسْلِمًا وَأَلْحِقْنِي بِالصَّالِحِينَ',
    translationFr:
        "Créateur des cieux et de la terre, Tu es mon protecteur ici-bas et dans l'au-delà. Fais-moi mourir soumis et fais-moi rejoindre les vertueux.",
    source: 'Yūsuf 12:101',
    tags: ['prophetes', 'deuil'],
    surahNumber: 12,
    ayahNumber: 101,
  ),
  Dua(
    id: 'dua_nuh_parents',
    titleFr: "L'invocation de Nūḥ pour ses parents",
    titleAr: 'دعاء نوح',
    textAr:
        'رَّبِّ اغْفِرْ لِي وَلِوَالِدَيَّ وَلِمَن دَخَلَ بَيْتِيَ مُؤْمِنًا وَلِلْمُؤْمِنِينَ وَالْمُؤْمِنَاتِ',
    translationFr:
        "Seigneur, pardonne-moi, ainsi qu'à mes parents, à celui qui entre en croyant dans ma maison, et à tous les croyants et croyantes.",
    source: 'Nūḥ 71:28',
    tags: ['prophetes', 'autrui'],
    surahNumber: 71,
    ayahNumber: 28,
  ),

  // ── Autour de la lecture ───────────────────────────────────────────────
  Dua(
    id: 'istiadha',
    titleFr: 'Avant d\'ouvrir le Muṣḥaf',
    titleAr: 'الاستعاذة والبسملة',
    textAr: 'أَعُوذُ بِاللَّهِ مِنَ الشَّيْطَانِ الرَّجِيمِ ۝ بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ',
    translit: "Aʿūdhu billāhi mina sh-shayṭāni r-rajīm — Bismi llāhi r-raḥmāni r-raḥīm",
    translationFr:
        "Je cherche refuge auprès d'Allah contre le diable banni. Au nom d'Allah, le Tout Miséricordieux, le Très Miséricordieux.",
    source: 'An-Naḥl 16:98',
    virtue:
        "L'istiʿādha ouvre toute récitation. La basmala s'ajoute au début de chaque sourate sauf At-Tawba.",
    tags: ['lecture_coran'],
  ),
  Dua(
    id: 'rabbi_zidni_ilma',
    titleFr: 'Seigneur, accrois mon savoir',
    titleAr: 'رب زدني علما',
    textAr: 'رَّبِّ زِدْنِي عِلْمًا',
    translit: "Rabbi zidnī ʿilmā",
    translationFr: 'Seigneur, accrois mon savoir.',
    source: 'Ṭāhā 20:114',
    virtue:
        "Le seul domaine dans lequel Allah ordonna à Son Prophète ﷺ de demander davantage.",
    tags: ['lecture_coran', 'rabbana'],
    surahNumber: 20,
    ayahNumber: 114,
  ),
  Dua(
    id: 'sujud_tilawa',
    titleFr: 'La prosternation de récitation',
    titleAr: 'سجود التلاوة',
    textAr:
        'سَجَدَ وَجْهِي لِلَّذِي خَلَقَهُ وَصَوَّرَهُ، وَشَقَّ سَمْعَهُ وَبَصَرَهُ بِحَوْلِهِ وَقُوَّتِهِ، فَتَبَارَكَ اللَّهُ أَحْسَنُ الْخَالِقِينَ',
    translationFr:
        "Ma face s'est prosternée devant Celui qui l'a créée et façonnée, et qui lui a ouvert l'ouïe et la vue par Sa force et Sa puissance. Béni soit Allah, le meilleur des créateurs.",
    source: 'Rapporté par At-Tirmidhi et An-Nasā\'ī',
    tags: ['lecture_coran'],
  ),
  Dua(
    id: 'kaffarat_majlis',
    titleFr: "En refermant — l'expiation de l'assemblée",
    titleAr: 'كفارة المجلس',
    textAr:
        'سُبْحَانَكَ اللَّهُمَّ وَبِحَمْدِكَ، أَشْهَدُ أَنْ لَا إِلَهَ إِلَّا أَنْتَ، أَسْتَغْفِرُكَ وَأَتُوبُ إِلَيْكَ',
    translit: "Subḥānaka llāhumma wa biḥamdik, ashhadu an lā ilāha illā ant, astaghfiruka wa atūbu ilayk",
    translationFr:
        "Gloire et louange à Toi, ô Allah. J'atteste qu'il n'y a de divinité que Toi. Je Te demande pardon et je me repens à Toi.",
    source: 'Rapporté par At-Tirmidhi et Abou Dawoud',
    virtue:
        "« Ce qui a eu lieu dans cette assemblée lui est pardonné. » Se dit en quittant toute réunion, y compris une séance de lecture.",
    tags: ['lecture_coran', 'autrui', 'istighfar'],
  ),

  // ── Khatm — fin du Coran ───────────────────────────────────────────────
  Dua(
    id: 'khatm_pratique',
    titleFr: 'Invoquer en achevant le Coran',
    titleAr: 'الدعاء عند ختم القرآن',
    textAr: 'كَانَ أَنَسٌ رَضِيَ اللَّهُ عَنْهُ إِذَا خَتَمَ الْقُرْآنَ جَمَعَ أَهْلَهُ وَدَعَا',
    translationFr:
        "Anas — qu'Allah l'agrée — rassemblait sa famille lorsqu'il achevait le Coran, puis invoquait.",
    source:
        "Pratique des compagnons rapportée par Ad-Dārimī et Ibn Abī Shayba. Aucune formule précise n'est établie du Prophète ﷺ : c'est le MOMENT qui est recommandé, pas un texte figé.",
    virtue:
        "Concrètement : à la fin de la dernière sourate, rassemble qui tu peux, et demande dans ta langue ce qui compte vraiment pour toi. On rapporte d'Ibn ʿAbbās : « à l'achèvement du Coran, l'invocation est exaucée ».",
    tags: ['khatm'],
  ),
  Dua(
    id: 'khatm_ihdina',
    titleFr: 'Recommencer aussitôt',
    titleAr: 'الحال المرتحل',
    textAr: 'الْحَالُّ الْمُرْتَحِلُ: الَّذِي يَضْرِبُ مِنْ أَوَّلِ الْقُرْآنِ إِلَى آخِرِهِ، كُلَّمَا حَلَّ ارْتَحَلَ',
    translationFr:
        "« Celui qui s'arrête et repart » : il parcourt le Coran du début à la fin, et chaque fois qu'il arrive, il repart.",
    source: 'Rapporté par At-Tirmidhi — interrogé sur la meilleure œuvre, le Prophète ﷺ répondit ainsi',
    virtue:
        "D'où l'usage d'enchaîner, après la dernière sourate, sur Al-Fātiḥa et les premiers versets d'Al-Baqara : la lecture ne se clôt pas, elle se relance.",
    tags: ['khatm'],
    surahNumber: 1,
    ayahNumber: 1,
  ),
  Dua(
    id: 'khatm_rahmani',
    titleFr: 'Fais du Coran ma lumière',
    titleAr: 'اللهم ارحمني بالقرآن',
    textAr:
        'اللَّهُمَّ ارْحَمْنِي بِالْقُرْآنِ، وَاجْعَلْهُ لِي إِمَامًا وَنُورًا وَهُدًى وَرَحْمَةً. اللَّهُمَّ ذَكِّرْنِي مِنْهُ مَا نَسِيتُ، وَعَلِّمْنِي مِنْهُ مَا جَهِلْتُ، وَارْزُقْنِي تِلَاوَتَهُ آنَاءَ اللَّيْلِ وَأَطْرَافَ النَّهَارِ، وَاجْعَلْهُ لِي حُجَّةً يَا رَبَّ الْعَالَمِينَ',
    translationFr:
        "Ô Allah, fais-moi miséricorde par le Coran ; fais-en pour moi un guide, une lumière, une direction et une miséricorde. Ô Allah, rappelle-moi ce que j'en ai oublié, enseigne-moi ce que j'en ignore, accorde-moi de le réciter aux heures de la nuit et aux extrémités du jour, et fais-en pour moi un argument en ma faveur, ô Seigneur des mondes.",
    source:
        "Formule très répandue dans les recueils d'adhkār, mais de chaîne FAIBLE (rapportée par Al-Bayhaqi dans Shuʿab al-īmān). À dire comme une invocation libre, sans lui attribuer un mérite prophétique établi.",
    tags: ['khatm'],
  ),
  Dua(
    id: 'khatm_hifz',
    titleFr: 'Contre l\'oubli de ce qu\'on a mémorisé',
    titleAr: 'دعاء الحفظ',
    textAr:
        'اللَّهُمَّ إِنِّي أَسْتَوْدِعُكَ مَا حَفِظْتُ وَمَا عَلَّمْتَنِي، فَرُدَّهُ عَلَيَّ عِنْدَ حَاجَتِي إِلَيْهِ',
    translationFr:
        "Ô Allah, je Te confie ce que j'ai mémorisé et ce que Tu m'as enseigné : rends-le-moi au moment où j'en aurai besoin.",
    source:
        "Invocation transmise par les gens de science (rapportée notamment par An-Nawawī dans Al-Adhkār), sans chaîne prophétique établie.",
    virtue:
        "Le Prophète ﷺ a mis en garde : « Prenez soin du Coran ! Par Celui qui tient mon âme, il s'échappe plus vite qu'un chameau de ses entraves. » (Al-Boukhari)",
    tags: ['khatm', 'lecture_coran'],
  ),

  // ── Versets de protection ──────────────────────────────────────────────
  Dua(
    id: 'fatiha_ruqya',
    titleFr: 'Al-Fātiḥa — la guérisseuse',
    titleAr: 'الفاتحة رقية',
    textAr:
        'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ ۝ الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ ۝ الرَّحْمَنِ الرَّحِيمِ ۝ مَالِكِ يَوْمِ الدِّينِ ۝ إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ ۝ اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ ۝ صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ',
    translationFr:
        "Au nom d'Allah, le Tout Miséricordieux, le Très Miséricordieux. Louange à Allah, Seigneur des mondes. Le Tout Miséricordieux, le Très Miséricordieux. Maître du Jour de la rétribution. C'est Toi que nous adorons et c'est Toi dont nous implorons secours. Guide-nous dans le droit chemin, le chemin de ceux que Tu as comblés de faveurs, non pas de ceux qui ont encouru Ta colère ni des égarés.",
    source: 'Al-Fātiḥa 1:1-7',
    virtue:
        "« Et qu'est-ce qui t'a fait savoir qu'elle est une guérison ? » — un compagnon guérit un homme piqué par un scorpion en la récitant (Al-Boukhari, Mouslim).",
    tags: ['protection_coran', 'maladie'],
    surahNumber: 1,
    ayahNumber: 1,
  ),
];

import '../models/dua.dart';

/// Univers « Le fil du jour » — réveil, matin, soir, sommeil, nuit.
///
/// Le catalogue est découpé par univers (`duas_jour`, `duas_priere`,
/// `duas_coran`, `duas_vie`, `duas_coeur`, `duas_sacre`) et réassemblé dans
/// `duas_data.dart`. Un seul fichier de ~1500 lignes devenait impossible à
/// relire ; découpé, chaque domaine se modifie sans toucher aux autres.
///
/// Rappel du modèle : une invocation porte des `tags` (plusieurs collections
/// possibles). Āyat al-Kursī est déclarée UNE fois ici et apparaît dans
/// matin + soir + sommeil + versets de protection — avant la refonte elle
/// était copiée-collée dans chaque catégorie.
const kDuasJour = <Dua>[
  // ── Au réveil ──────────────────────────────────────────────────────────
  Dua(
    id: 'reveil_hamd',
    titleFr: 'Les premiers mots au réveil',
    titleAr: 'ذكر الاستيقاظ',
    textAr: 'الْحَمْدُ لِلَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا وَإِلَيْهِ النُّشُورُ',
    translit: "Al-ḥamdu lillāhi lladhī aḥyānā baʿda mā amātanā wa ilayhi n-nushūr",
    translationFr:
        "Louange à Allah qui nous a rendus à la vie après nous avoir fait mourir, et c'est vers Lui qu'est la résurrection.",
    source: 'Rapporté par Al-Boukhari',
    virtue:
        "Le sommeil est présenté comme une petite mort : ouvrir les yeux sur cette phrase, c'est traiter chaque matin comme un sursis accordé.",
    tags: ['reveil'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/1.mp3',
  ),
  Dua(
    id: 'reveil_afani',
    titleFr: "Quand le corps répond encore",
    titleAr: 'دعاء رد الروح',
    textAr:
        'الْحَمْدُ لِلَّهِ الَّذِي عَافَانِي فِي جَسَدِي، وَرَدَّ عَلَيَّ رُوحِي، وَأَذِنَ لِي بِذِكْرِهِ',
    translationFr:
        "Louange à Allah qui m'a préservé dans mon corps, m'a rendu mon âme et m'a permis de L'évoquer.",
    source: 'Rapporté par At-Tirmidhi',
    tags: ['reveil'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/3.mp3',
  ),
  Dua(
    id: 'reveil_imran',
    titleFr: 'Les dix derniers versets d\'Āl ʿImrān',
    titleAr: 'خواتيم آل عمران',
    textAr:
        'إِنَّ فِي خَلْقِ السَّمَاوَاتِ وَالْأَرْضِ وَاخْتِلَافِ اللَّيْلِ وَالنَّهَارِ لَآيَاتٍ لِّأُولِي الْأَلْبَابِ',
    translationFr:
        "En vérité, dans la création des cieux et de la terre, et dans l'alternance de la nuit et du jour, il y a certes des signes pour les doués d'intelligence.",
    source: 'Āl ʿImrān 3:190 — le Prophète ﷺ les récitait en se levant la nuit (Al-Boukhari)',
    virtue:
        "Récités au réveil, ces versets font lever les yeux avant de lever le corps.",
    tags: ['reveil', 'nuit'],
    surahNumber: 3,
    ayahNumber: 190,
  ),

  // ── Adhkār du matin ────────────────────────────────────────────────────
  Dua(
    id: 'matin_asbahna',
    titleFr: 'Nous voici au matin',
    titleAr: 'ذكر الصباح',
    textAr:
        'أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ. رَبِّ أَسْأَلُكَ خَيْرَ مَا فِي هَذَا الْيَوْمِ وَخَيْرَ مَا بَعْدَهُ، وَأَعُوذُ بِكَ مِنْ شَرِّ مَا فِي هَذَا الْيَوْمِ وَشَرِّ مَا بَعْدَهُ',
    translationFr:
        "Nous voici au matin et le Royaume appartient à Allah. Louange à Allah. Il n'y a de divinité qu'Allah, Seul, sans associé. À Lui la royauté, à Lui la louange, et Il est capable de toute chose. Seigneur, je Te demande le bien de ce jour et le bien de ce qui suit, et je cherche refuge auprès de Toi contre le mal de ce jour et le mal de ce qui suit.",
    source: 'Rapporté par Mouslim',
    tags: ['matin'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/77.mp3',
  ),
  Dua(
    id: 'matin_bika',
    titleFr: "C'est par Toi que le jour se lève",
    titleAr: 'اللهم بك أصبحنا',
    textAr:
        'اللَّهُمَّ بِكَ أَصْبَحْنَا، وَبِكَ أَمْسَيْنَا، وَبِكَ نَحْيَا، وَبِكَ نَمُوتُ، وَإِلَيْكَ النُّشُورُ',
    translationFr:
        "Ô Allah, c'est par Toi que nous entrons dans le matin, par Toi que nous entrons dans le soir, par Toi que nous vivons, par Toi que nous mourons, et c'est vers Toi qu'est la résurrection.",
    source: 'Rapporté par At-Tirmidhi',
    tags: ['matin'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/78.mp3',
  ),
  Dua(
    id: 'sayyid_istighfar',
    titleFr: 'Sayyid al-Istighfār — le maître des demandes de pardon',
    titleAr: 'سيد الاستغفار',
    textAr:
        'اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَهَ إِلَّا أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، وَأَنَا عَلَى عَهْدِكَ وَوَعْدِكَ مَا اسْتَطَعْتُ، أَعُوذُ بِكَ مِنْ شَرِّ مَا صَنَعْتُ، أَبُوءُ لَكَ بِنِعْمَتِكَ عَلَيَّ، وَأَبُوءُ بِذَنْبِي فَاغْفِرْ لِي فَإِنَّهُ لَا يَغْفِرُ الذُّنُوبَ إِلَّا أَنْتَ',
    translationFr:
        "Ô Allah, Tu es mon Seigneur, il n'y a de divinité que Toi. Tu m'as créé et je suis Ton serviteur ; je m'en tiens à Ton pacte et à Ta promesse autant que je le peux. Je cherche refuge auprès de Toi contre le mal que j'ai commis. Je reconnais Ton bienfait sur moi et je reconnais mon péché : pardonne-moi, car nul ne pardonne les péchés sauf Toi.",
    source: 'Rapporté par Al-Boukhari',
    virtue:
        "« Celui qui la dit le jour avec conviction et meurt ce jour-là avant le soir entre au Paradis » — de même pour la nuit.",
    tags: ['matin', 'soir', 'istighfar'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/79.mp3',
  ),
  Dua(
    id: 'hasbiya_allah',
    titleFr: 'Allah me suffit',
    titleAr: 'حسبي الله',
    textAr:
        'حَسْبِيَ اللَّهُ لَا إِلَهَ إِلَّا هُوَ، عَلَيْهِ تَوَكَّلْتُ، وَهُوَ رَبُّ الْعَرْشِ الْعَظِيمِ',
    translit: "Ḥasbiya llāhu lā ilāha illā huwa, ʿalayhi tawakkaltu, wa huwa rabbu l-ʿarshi l-ʿaẓīm",
    translationFr:
        "Allah me suffit, il n'y a de divinité que Lui. C'est en Lui que je place ma confiance, et Il est le Seigneur du Trône immense.",
    source: 'Rapporté par Abou Dawoud — sept fois matin et soir',
    virtue: "« Allah lui suffira pour ce qui le préoccupe, de ce monde et de l'autre. »",
    tags: ['matin', 'soir', 'angoisse', 'peur'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/83.mp3',
    audioAsset: 'audio/duas/83_cut.mp3',
    repeat: 7,
  ),
  Dua(
    id: 'tahlil_100',
    titleFr: 'Le tahlīl — cent fois',
    titleAr: 'التهليل',
    textAr:
        'لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ',
    translit: "Lā ilāha illā llāhu waḥdahu lā sharīka lah, lahu l-mulku wa lahu l-ḥamdu wa huwa ʿalā kulli shay'in qadīr",
    translationFr:
        "Il n'y a de divinité qu'Allah, Seul, sans associé. À Lui la royauté, à Lui la louange, et Il est capable de toute chose.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    virtue:
        "Cent fois dans la journée : l'équivalent d'affranchir dix esclaves, cent bonnes actions inscrites, cent mauvaises effacées, et une protection contre le diable jusqu'au soir.",
    tags: ['matin', 'apres_priere'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/2.mp3',
    repeat: 100,
  ),
  Dua(
    id: 'subhanallah_bihamdih',
    titleFr: 'Gloire et louange à Allah',
    titleAr: 'التسبيح',
    textAr: 'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ',
    translit: "Subḥāna llāhi wa biḥamdih",
    translationFr: 'Gloire et pureté à Allah, et à Lui la louange.',
    source: 'Rapporté par Al-Boukhari et Mouslim',
    virtue:
        "« Celui qui la dit cent fois dans la journée voit ses péchés effacés, seraient-ils comme l'écume de la mer. »",
    tags: ['matin', 'soir'],
    repeat: 100,
  ),
  Dua(
    id: 'subhanallah_adada',
    titleFr: 'À la mesure de Sa création',
    titleAr: 'سبحان الله وبحمده عدد خلقه',
    textAr:
        'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ، عَدَدَ خَلْقِهِ، وَرِضَا نَفْسِهِ، وَزِنَةَ عَرْشِهِ، وَمِدَادَ كَلِمَاتِهِ',
    translationFr:
        "Gloire et louange à Allah, autant que le nombre de Ses créatures, autant que Sa satisfaction, autant que le poids de Son Trône et l'encre de Ses paroles.",
    source: 'Rapporté par Mouslim',
    virtue:
        "Quatre paroles qui pèsent plus lourd que tout ce que l'on aurait pu dire depuis l'aube.",
    tags: ['matin'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/94.mp3',
    audioAsset: 'audio/duas/94_cut.mp3',
    repeat: 3,
  ),
  Dua(
    id: 'istighfar_long',
    titleFr: 'Demande de pardon (formule complète)',
    titleAr: 'الاستغفار',
    textAr:
        'أَسْتَغْفِرُ اللَّهَ الْعَظِيمَ الَّذِي لَا إِلَهَ إِلَّا هُوَ، الْحَيُّ الْقَيُّومُ، وَأَتُوبُ إِلَيْهِ',
    translationFr:
        "Je demande pardon à Allah l'Immense, il n'y a de divinité que Lui, le Vivant, Celui qui subsiste par Lui-même, et je me repens à Lui.",
    source: 'Rapporté par Abou Dawoud et At-Tirmidhi',
    virtue: "« Ses péchés lui sont pardonnés, eût-il fui devant l'ennemi. »",
    tags: ['matin', 'soir', 'istighfar'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/250.mp3',
    repeat: 3,
  ),
  Dua(
    id: 'muawwidhat',
    titleFr: 'Les trois sourates protectrices',
    titleAr: 'المعوذات',
    textAr:
        'قُلْ هُوَ اللَّهُ أَحَدٌ ۝ اللَّهُ الصَّمَدُ ۝ لَمْ يَلِدْ وَلَمْ يُولَدْ ۝ وَلَمْ يَكُن لَّهُ كُفُوًا أَحَدٌ ۝ قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ ۝ مِن شَرِّ مَا خَلَقَ ۝ وَمِن شَرِّ غَاسِقٍ إِذَا وَقَبَ ۝ وَمِن شَرِّ النَّفَّاثَاتِ فِي الْعُقَدِ ۝ وَمِن شَرِّ حَاسِدٍ إِذَا حَسَدَ ۝ قُلْ أَعُوذُ بِرَبِّ النَّاسِ ۝ مَلِكِ النَّاسِ ۝ إِلَهِ النَّاسِ ۝ مِن شَرِّ الْوَسْوَاسِ الْخَنَّاسِ ۝ الَّذِي يُوَسْوِسُ فِي صُدُورِ النَّاسِ ۝ مِنَ الْجِنَّةِ وَالنَّاسِ',
    translationFr:
        "Dis : Il est Allah, Unique. Allah, Le Seul imploré pour ce que nous désirons. Il n'a jamais engendré ni été engendré, et nul n'est égal à Lui. — Dis : Je cherche protection auprès du Seigneur de l'aube naissante, contre le mal des êtres qu'Il a créés, contre le mal de l'obscurité quand elle s'approfondit, contre le mal de celles qui soufflent sur les nœuds, et contre le mal de l'envieux quand il envie. — Dis : Je cherche protection auprès du Seigneur des hommes, le Souverain des hommes, le Dieu des hommes, contre le mal du mauvais conseiller furtif qui souffle le mal dans les poitrines des hommes, qu'il soit djinn ou humain.",
    source: 'Al-Ikhlāṣ, Al-Falaq, An-Nās — trois fois matin et soir (Abou Dawoud, At-Tirmidhi)',
    virtue: "« Elles te suffiront contre toute chose. »",
    tags: ['matin', 'soir', 'sommeil', 'protection_coran', 'peur'],
    repeat: 3,
    surahNumber: 112,
    ayahNumber: 1,
    // Corrigé 2026-08-07 (constat utilisateur : seul 112:1 était lu) --
    // les trois sourates complètes, dans l'ordre où elles sont récitées.
    verseRanges: [(112, 1, 4), (113, 1, 5), (114, 1, 6)],
  ),
  Dua(
    id: 'ayat_kursi',
    titleFr: 'Āyat al-Kursī',
    titleAr: 'آية الكرسي',
    textAr:
        'اللَّهُ لَا إِلَهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ ۚ لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ ۚ لَّهُ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ ۗ مَن ذَا الَّذِي يَشْفَعُ عِندَهُ إِلَّا بِإِذْنِهِ ۚ يَعْلَمُ مَا بَيْنَ أَيْدِيهِمْ وَمَا خَلْفَهُمْ ۖ وَلَا يُحِيطُونَ بِشَيْءٍ مِّنْ عِلْمِهِ إِلَّا بِمَا شَاءَ ۚ وَسِعَ كُرْسِيُّهُ السَّمَاوَاتِ وَالْأَرْضَ ۖ وَلَا يَئُودُهُ حِفْظُهُمَا ۚ وَهُوَ الْعَلِيُّ الْعَظِيمُ',
    translationFr:
        "Allah, point de divinité à part Lui, le Vivant, Celui qui subsiste par Lui-même. Ni somnolence ni sommeil ne Le saisissent. À Lui appartient tout ce qui est dans les cieux et sur la terre. Qui peut intercéder auprès de Lui sans Sa permission ? Il connaît leur passé et leur futur, et ils n'embrassent de Sa science que ce qu'Il veut. Son Trône déborde les cieux et la terre, dont la garde ne Lui coûte aucune peine. Et Il est le Très-Haut, l'Immense.",
    source: 'Al-Baqara 2:255',
    virtue:
        "Récitée après chaque prière obligatoire : « rien ne le sépare du Paradis, sinon la mort » (An-Nasā'ī). Récitée au coucher, un gardien reste auprès de soi jusqu'au matin (Al-Boukhari).",
    tags: ['matin', 'soir', 'sommeil', 'apres_priere', 'protection_coran'],
    surahNumber: 2,
    ayahNumber: 255,
  ),
  Dua(
    id: 'bismillah_la_yadurr',
    titleFr: 'Au nom de Celui dont le Nom écarte tout mal',
    titleAr: 'بسم الله الذي لا يضر مع اسمه شيء',
    textAr:
        'بِسْمِ اللَّهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ وَهُوَ السَّمِيعُ الْعَلِيمُ',
    translit: "Bismi llāhi lladhī lā yaḍurru maʿa smihi shay'un fī l-arḍi wa lā fī s-samā'i wa huwa s-samīʿu l-ʿalīm",
    translationFr:
        "Au nom d'Allah, dont le Nom fait qu'aucune chose sur terre ni au ciel ne peut nuire. Il est l'Audient, l'Omniscient.",
    source: 'Rapporté par Abou Dawoud et At-Tirmidhi — trois fois matin et soir',
    virtue: "« Rien ne lui nuira. »",
    tags: ['matin', 'soir', 'peur'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/86.mp3',
    audioAsset: 'audio/duas/86_cut.mp3',
    repeat: 3,
  ),
  Dua(
    id: 'raditu_billah',
    titleFr: "J'agrée Allah pour Seigneur",
    titleAr: 'رضيت بالله ربا',
    textAr:
        'رَضِيتُ بِاللَّهِ رَبًّا، وَبِالْإِسْلَامِ دِينًا، وَبِمُحَمَّدٍ صَلَّى اللَّهُ عَلَيْهِ وَسَلَّمَ نَبِيًّا',
    translationFr:
        "J'agrée Allah pour Seigneur, l'Islam pour religion, et Muhammad — paix et bénédiction sur lui — pour Prophète.",
    source: 'Rapporté par Abou Dawoud — trois fois matin et soir',
    virtue: "« Il incombe à Allah de le satisfaire au Jour de la Résurrection. »",
    tags: ['matin', 'soir'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/87.mp3',
    audioAsset: 'audio/duas/87_cut.mp3',
    repeat: 3,
  ),
  Dua(
    id: 'afiya',
    titleFr: 'Demande de préservation',
    titleAr: 'دعاء العافية',
    textAr:
        'اللَّهُمَّ إِنِّي أَسْأَلُكَ الْعَفْوَ وَالْعَافِيَةَ فِي الدُّنْيَا وَالْآخِرَةِ، اللَّهُمَّ إِنِّي أَسْأَلُكَ الْعَفْوَ وَالْعَافِيَةَ فِي دِينِي وَدُنْيَايَ وَأَهْلِي وَمَالِي، اللَّهُمَّ اسْتُرْ عَوْرَاتِي وَآمِنْ رَوْعَاتِي',
    translationFr:
        "Ô Allah, je Te demande le pardon et la préservation dans ce monde et dans l'au-delà. Ô Allah, je Te demande le pardon et la préservation dans ma religion, ma vie ici-bas, ma famille et mes biens. Ô Allah, couvre ce que je voudrais cacher et apaise mes frayeurs.",
    source: 'Rapporté par Abou Dawoud et Ibn Majah',
    tags: ['matin', 'soir', 'peur'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/84.mp3',
  ),
  Dua(
    id: 'ya_hayyu_ya_qayyum',
    titleFr: 'Ô Vivant, ô Subsistant',
    titleAr: 'يا حي يا قيوم',
    textAr:
        'يَا حَيُّ يَا قَيُّومُ بِرَحْمَتِكَ أَسْتَغِيثُ، أَصْلِحْ لِي شَأْنِي كُلَّهُ، وَلَا تَكِلْنِي إِلَى نَفْسِي طَرْفَةَ عَيْنٍ',
    translit: "Yā Ḥayyu yā Qayyūm, biraḥmatika astaghīth",
    translationFr:
        "Ô Vivant, ô Subsistant, j'implore Ton secours par Ta miséricorde. Améliore toute ma situation et ne me confie pas à moi-même, ne serait-ce que le temps d'un clin d'œil.",
    source: 'Rapporté par An-Nasā\'ī et Al-Hakim',
    tags: ['matin', 'soir', 'angoisse'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/88.mp3',
  ),
  Dua(
    id: 'alim_al_ghayb',
    titleFr: "Connaisseur de l'invisible",
    titleAr: 'اللهم عالم الغيب والشهادة',
    textAr:
        'اللَّهُمَّ عَالِمَ الْغَيْبِ وَالشَّهَادَةِ، فَاطِرَ السَّمَاوَاتِ وَالْأَرْضِ، رَبَّ كُلِّ شَيْءٍ وَمَلِيكَهُ، أَشْهَدُ أَنْ لَا إِلَهَ إِلَّا أَنْتَ، أَعُوذُ بِكَ مِنْ شَرِّ نَفْسِي وَمِنْ شَرِّ الشَّيْطَانِ وَشِرْكِهِ',
    translationFr:
        "Ô Allah, Connaisseur de l'invisible et du visible, Créateur des cieux et de la terre, Seigneur et Souverain de toute chose : j'atteste qu'il n'y a de divinité que Toi. Je cherche refuge auprès de Toi contre le mal de mon âme et contre le mal du diable et de son association.",
    source: 'Rapporté par At-Tirmidhi et Abou Dawoud',
    tags: ['matin', 'soir'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/85.mp3',
  ),

  // ── Adhkār du soir ─────────────────────────────────────────────────────
  Dua(
    id: 'soir_amsayna',
    titleFr: 'Nous voici au soir',
    titleAr: 'ذكر المساء',
    textAr:
        'أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ. رَبِّ أَسْأَلُكَ خَيْرَ مَا فِي هَذِهِ اللَّيْلَةِ وَخَيْرَ مَا بَعْدَهَا، وَأَعُوذُ بِكَ مِنْ شَرِّ مَا فِي هَذِهِ اللَّيْلَةِ وَشَرِّ مَا بَعْدَهَا',
    translationFr:
        "Nous voici au soir et le Royaume appartient à Allah. Louange à Allah. Il n'y a de divinité qu'Allah, Seul, sans associé. À Lui la royauté, à Lui la louange, et Il est capable de toute chose. Seigneur, je Te demande le bien de cette nuit et le bien de ce qui suit, et je cherche refuge auprès de Toi contre le mal de cette nuit et le mal de ce qui suit.",
    source: 'Rapporté par Mouslim',
    tags: ['soir'],
  ),
  Dua(
    id: 'soir_ishhad',
    titleFr: 'Je Te prends à témoin',
    titleAr: 'الإشهاد المسائي',
    textAr:
        'اللَّهُمَّ إِنِّي أَمْسَيْتُ أُشْهِدُكَ، وَأُشْهِدُ حَمَلَةَ عَرْشِكَ، وَمَلَائِكَتَكَ، وَجَمِيعَ خَلْقِكَ، أَنَّكَ أَنْتَ اللَّهُ لَا إِلَهَ إِلَّا أَنْتَ وَحْدَكَ لَا شَرِيكَ لَكَ، وَأَنَّ مُحَمَّدًا عَبْدُكَ وَرَسُولُكَ',
    translationFr:
        "Ô Allah, au seuil de cette soirée je Te prends à témoin, ainsi que les porteurs de Ton Trône, Tes anges et toutes Tes créatures, que Tu es Allah, il n'y a de divinité que Toi, Seul, sans associé, et que Muhammad est Ton serviteur et Ton Messager.",
    source: 'Rapporté par Abou Dawoud — quatre fois',
    virtue: "« Allah l'affranchit du Feu. »",
    tags: ['soir'],
    repeat: 4,
  ),
  Dua(
    id: 'soir_kalimat',
    titleFr: 'Par les paroles parfaites d\'Allah',
    titleAr: 'أعوذ بكلمات الله التامات',
    textAr: 'أَعُوذُ بِكَلِمَاتِ اللَّهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَقَ',
    translit: "Aʿūdhu bikalimāti llāhi t-tāmmāti min sharri mā khalaq",
    translationFr:
        "Je cherche refuge dans les paroles parfaites d'Allah contre le mal de ce qu'Il a créé.",
    source: 'Rapporté par Mouslim — trois fois le soir',
    virtue: "« Rien ne lui nuira jusqu'au matin. » Également dite en s'arrêtant en voyage.",
    tags: ['soir', 'peur', 'voyage'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/97.mp3',
    audioAsset: 'audio/duas/97_cut.mp3',
    repeat: 3,
  ),
  Dua(
    id: 'soir_fitra',
    titleFr: "Sur la disposition originelle",
    titleAr: 'على الفطرة',
    textAr:
        'أَمْسَيْنَا عَلَى فِطْرَةِ الْإِسْلَامِ، وَعَلَى كَلِمَةِ الْإِخْلَاصِ، وَعَلَى دِينِ نَبِيِّنَا مُحَمَّدٍ صَلَّى اللَّهُ عَلَيْهِ وَسَلَّمَ، وَعَلَى مِلَّةِ أَبِينَا إِبْرَاهِيمَ حَنِيفًا مُسْلِمًا وَمَا كَانَ مِنَ الْمُشْرِكِينَ',
    translationFr:
        "Nous voici au soir sur la disposition naturelle de l'Islam, sur la parole de sincérité, sur la religion de notre Prophète Muhammad — paix et bénédiction sur lui — et sur la voie de notre père Abraham, monothéiste sincère et soumis, qui n'était pas du nombre des associateurs.",
    source: 'Rapporté par Ahmad',
    tags: ['soir'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/90.mp3',
  ),

  // ── Avant de dormir ────────────────────────────────────────────────────
  Dua(
    id: 'sommeil_bismika',
    titleFr: "En Ton nom je meurs et je vis",
    titleAr: 'باسمك اللهم أموت وأحيا',
    textAr: 'بِاسْمِكَ اللَّهُمَّ أَمُوتُ وَأَحْيَا',
    translit: "Bismika llāhumma amūtu wa aḥyā",
    translationFr: "Ô Allah, c'est en Ton nom que je meurs et que je vis.",
    source: 'Rapporté par Al-Boukhari',
    tags: ['sommeil'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/105.mp3',
  ),
  Dua(
    id: 'sommeil_aslamtu',
    titleFr: "Je remets mon âme entre Tes mains",
    titleAr: 'اللهم أسلمت نفسي إليك',
    textAr:
        'اللَّهُمَّ أَسْلَمْتُ نَفْسِي إِلَيْكَ، وَفَوَّضْتُ أَمْرِي إِلَيْكَ، وَوَجَّهْتُ وَجْهِي إِلَيْكَ، وَأَلْجَأْتُ ظَهْرِي إِلَيْكَ، رَغْبَةً وَرَهْبَةً إِلَيْكَ، لَا مَلْجَأَ وَلَا مَنْجَا مِنْكَ إِلَّا إِلَيْكَ، آمَنْتُ بِكِتَابِكَ الَّذِي أَنْزَلْتَ، وَبِنَبِيِّكَ الَّذِي أَرْسَلْتَ',
    translationFr:
        "Ô Allah, je remets mon âme entre Tes mains, je Te confie mon affaire, je tourne mon visage vers Toi, j'adosse mon dos à Toi, par désir de Toi et par crainte de Toi. Il n'est de refuge ni de salut contre Toi qu'auprès de Toi. Je crois en Ton Livre que Tu as révélé et en Ton Prophète que Tu as envoyé.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    virtue:
        "« Si tu meurs cette nuit-là, tu meurs sur la nature originelle. » Le Prophète ﷺ recommandait d'en faire les dernières paroles de la journée.",
    tags: ['sommeil'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/111.mp3',
  ),
  Dua(
    id: 'sommeil_baqara_285',
    titleFr: "Les deux derniers versets d'Al-Baqara",
    titleAr: 'خواتيم سورة البقرة',
    textAr:
        'آمَنَ الرَّسُولُ بِمَا أُنزِلَ إِلَيْهِ مِن رَّبِّهِ وَالْمُؤْمِنُونَ ۚ كُلٌّ آمَنَ بِاللَّهِ وَمَلَائِكَتِهِ وَكُتُبِهِ وَرُسُلِهِ لَا نُفَرِّقُ بَيْنَ أَحَدٍ مِّن رُّسُلِهِ ۚ وَقَالُوا سَمِعْنَا وَأَطَعْنَا ۖ غُفْرَانَكَ رَبَّنَا وَإِلَيْكَ الْمَصِيرُ',
    translationFr:
        "Le Messager a cru en ce qu'on a fait descendre vers lui de la part de son Seigneur, et les croyants aussi. Tous ont cru en Allah, en Ses anges, en Ses livres et en Ses messagers : « Nous ne faisons aucune distinction entre Ses messagers. » Et ils ont dit : « Nous avons entendu et obéi. Ton pardon, Seigneur ! Et vers Toi est le retour. »",
    source: 'Al-Baqara 2:285-286',
    virtue: "« Celui qui les récite la nuit, elles lui suffiront. » (Al-Boukhari, Mouslim)",
    tags: ['sommeil', 'protection_coran'],
    surahNumber: 2,
    ayahNumber: 285,
  ),
  Dua(
    id: 'tasbih_fatima',
    titleFr: 'Le tasbīḥ de Fāṭima',
    titleAr: 'تسبيح فاطمة',
    textAr: 'سُبْحَانَ اللَّهِ ﴿٣٣﴾ الْحَمْدُ لِلَّهِ ﴿٣٣﴾ اللَّهُ أَكْبَرُ ﴿٣٤﴾',
    translationFr:
        "Gloire à Allah (×33), Louange à Allah (×33), Allah est le plus Grand (×34) — au moment de se coucher.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    virtue:
        "Le Prophète ﷺ l'enseigna à sa fille qui demandait un serviteur : « Cela vaut mieux pour vous qu'un serviteur. »",
    tags: ['sommeil'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/69.mp3',
    audioAsset: 'audio/duas/69_cut.mp3',
    repeat: 33,
  ),
  Dua(
    id: 'sommeil_qini',
    titleFr: 'Préserve-moi de Ton châtiment',
    titleAr: 'اللهم قني عذابك',
    textAr: 'اللَّهُمَّ قِنِي عَذَابَكَ يَوْمَ تَبْعَثُ عِبَادَكَ',
    translationFr:
        "Ô Allah, préserve-moi de Ton châtiment le jour où Tu ressusciteras Tes serviteurs.",
    source: 'Rapporté par Abou Dawoud et At-Tirmidhi — trois fois, la main droite sous la joue',
    tags: ['sommeil'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/104.mp3',
    repeat: 3,
  ),

  // ── Veille de nuit ─────────────────────────────────────────────────────
  Dua(
    id: 'nuit_taarra',
    titleFr: "Si l'on se réveille au milieu de la nuit",
    titleAr: 'دعاء التعار من الليل',
    textAr:
        'لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ، الْحَمْدُ لِلَّهِ، وَسُبْحَانَ اللَّهِ، وَلَا إِلَهَ إِلَّا اللَّهُ، وَاللَّهُ أَكْبَرُ، وَلَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ. رَبِّ اغْفِرْ لِي',
    translationFr:
        "Il n'y a de divinité qu'Allah, Seul, sans associé. À Lui la royauté, à Lui la louange, et Il est capable de toute chose. Louange à Allah, gloire à Allah, il n'y a de divinité qu'Allah, Allah est le plus Grand, et il n'y a de force ni de puissance qu'en Allah. Seigneur, pardonne-moi.",
    source: 'Rapporté par Al-Boukhari',
    virtue:
        "« Celui qui dit cela puis invoque, il est exaucé ; et s'il fait ses ablutions et prie, sa prière est acceptée. »",
    tags: ['nuit'],
  ),
  Dua(
    id: 'nuit_istiftah_tahajjud',
    titleFr: "Ouverture de la prière de nuit",
    titleAr: 'دعاء استفتاح قيام الليل',
    textAr:
        'اللَّهُمَّ رَبَّ جِبْرَائِيلَ وَمِيكَائِيلَ وَإِسْرَافِيلَ، فَاطِرَ السَّمَاوَاتِ وَالْأَرْضِ، عَالِمَ الْغَيْبِ وَالشَّهَادَةِ، أَنْتَ تَحْكُمُ بَيْنَ عِبَادِكَ فِيمَا كَانُوا فِيهِ يَخْتَلِفُونَ، اهْدِنِي لِمَا اخْتُلِفَ فِيهِ مِنَ الْحَقِّ بِإِذْنِكَ، إِنَّكَ تَهْدِي مَنْ تَشَاءُ إِلَى صِرَاطٍ مُسْتَقِيمٍ',
    translationFr:
        "Ô Allah, Seigneur de Gabriel, de Michaël et d'Isrāfīl, Créateur des cieux et de la terre, Connaisseur de l'invisible et du visible : Tu juges entre Tes serviteurs sur ce en quoi ils divergeaient. Guide-moi, avec Ta permission, vers la vérité au sujet de ce qui fait l'objet de divergence. Tu guides qui Tu veux vers un chemin droit.",
    source: 'Rapporté par Mouslim',
    tags: ['nuit'],
    audioUrl: 'https://www.hisnmuslim.com/audio/ar/30.mp3',
  ),
  Dua(
    id: 'nuit_insomnie',
    titleFr: "Quand le sommeil ne vient pas",
    titleAr: 'دعاء الأرق',
    textAr:
        'اللَّهُمَّ غَارَتِ النُّجُومُ، وَهَدَأَتِ الْعُيُونُ، وَأَنْتَ حَيٌّ قَيُّومٌ، لَا تَأْخُذُكَ سِنَةٌ وَلَا نَوْمٌ، يَا حَيُّ يَا قَيُّومُ أَهْدِئْ لَيْلِي وَأَنِمْ عَيْنِي',
    translationFr:
        "Ô Allah, les étoiles se sont couchées, les yeux se sont apaisés, et Tu es le Vivant, le Subsistant, que ni somnolence ni sommeil ne saisissent. Ô Vivant, ô Subsistant, apaise ma nuit et endors mes yeux.",
    source: "Rapporté par Ibn as-Sunnī — chaîne faible, transmise dans les recueils d'adhkār ; à dire sans lui attribuer un mérite prophétique établi",
    tags: ['nuit', 'angoisse'],
  ),
  Dua(
    id: 'nuit_dernier_tiers',
    titleFr: "Le dernier tiers de la nuit",
    titleAr: 'النزول الإلهي',
    textAr: 'مَنْ يَدْعُونِي فَأَسْتَجِيبَ لَهُ، مَنْ يَسْأَلُنِي فَأُعْطِيَهُ، مَنْ يَسْتَغْفِرُنِي فَأَغْفِرَ لَهُ',
    translationFr:
        "« Qui M'invoque, que Je l'exauce ? Qui Me demande, que Je lui donne ? Qui Me demande pardon, que Je lui pardonne ? »",
    source: 'Hadith qudsī — Al-Boukhari et Mouslim',
    virtue:
        "Ce n'est pas une formule à réciter mais un moment à saisir : le dernier tiers de la nuit, l'invocation est ouverte. Dis ce que tu as, dans ta langue.",
    tags: ['nuit', 'istighfar'],
  ),
];

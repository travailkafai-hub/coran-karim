import '../models/dua.dart';

/// Univers « La prière » — ablutions, adhān, contenu de la prière, Ṣobḥ,
/// dhikr qui suit, Witr, vendredi, ʿAïd, istikhāra.
///
/// Les collections `sobh` et `aid` répondent à une demande explicite
/// (2026-07-20) : « ce qu'on dit dans ṣalāt Ṣobḥ », « ce qui est recommandé
/// dans la prière de l'Aïd ». Elles regroupent donc non seulement des
/// invocations mais aussi ce qui est PROPRE à ces prières (sourates
/// recommandées, takbīrs surnuméraires, sunna du jour) — sans ça on redonne
/// juste une liste de duas génériques et la question reste sans réponse.
const kDuasPriere = <Dua>[
  // ── Ablutions & adhān ──────────────────────────────────────────────────
  Dua(
    id: 'wudu_apres',
    titleFr: 'Après les ablutions',
    titleAr: 'دعاء بعد الوضوء',
    textAr:
        'أَشْهَدُ أَنْ لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، وَأَشْهَدُ أَنَّ مُحَمَّدًا عَبْدُهُ وَرَسُولُهُ. اللَّهُمَّ اجْعَلْنِي مِنَ التَّوَّابِينَ وَاجْعَلْنِي مِنَ الْمُتَطَهِّرِينَ',
    translationFr:
        "J'atteste qu'il n'y a de divinité qu'Allah, Seul, sans associé, et j'atteste que Muhammad est Son serviteur et Son Messager. Ô Allah, fais de moi ceux qui reviennent souvent à Toi et fais de moi ceux qui se purifient.",
    source: 'Rapporté par Mouslim et At-Tirmidhi',
    virtue: "« Les huit portes du Paradis lui sont ouvertes, il entre par celle qu'il veut. »",
    tags: ['avant_priere'],
  ),
  Dua(
    id: 'adhan_reponse',
    titleFr: "Répondre à l'appel",
    titleAr: 'إجابة المؤذن',
    textAr:
        'يُرَدَّدُ مَا يَقُولُ الْمُؤَذِّنُ، إِلَّا عِنْدَ «حَيَّ عَلَى الصَّلَاةِ» وَ«حَيَّ عَلَى الْفَلَاحِ» فَيُقَالُ: لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ',
    translationFr:
        "On répète ce que dit le muezzin, sauf à « Venez à la prière » et « Venez à la réussite » où l'on dit : il n'y a de force ni de puissance qu'en Allah.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    tags: ['avant_priere'],
  ),
  Dua(
    id: 'adhan_apres',
    titleFr: "Après l'appel à la prière",
    titleAr: 'دعاء بعد الأذان',
    textAr:
        'اللَّهُمَّ رَبَّ هَذِهِ الدَّعْوَةِ التَّامَّةِ، وَالصَّلَاةِ الْقَائِمَةِ، آتِ مُحَمَّدًا الْوَسِيلَةَ وَالْفَضِيلَةَ، وَابْعَثْهُ مَقَامًا مَحْمُودًا الَّذِي وَعَدْتَهُ',
    translationFr:
        "Ô Allah, Seigneur de cet appel parfait et de la prière qui va être accomplie, accorde à Muhammad le moyen d'accès et la faveur, et ressuscite-le dans la station louée que Tu lui as promise.",
    source: 'Rapporté par Al-Boukhari',
    virtue: "« Mon intercession lui est due au Jour de la Résurrection. »",
    tags: ['avant_priere'],
  ),
  Dua(
    id: 'entre_adhan_iqama',
    titleFr: "Entre l'adhān et l'iqāma",
    titleAr: 'الدعاء بين الأذان والإقامة',
    textAr: 'الدُّعَاءُ لَا يُرَدُّ بَيْنَ الْأَذَانِ وَالْإِقَامَةِ',
    translationFr: "« L'invocation n'est pas repoussée entre l'appel et l'annonce de la prière. »",
    source: 'Rapporté par Abou Dawoud et At-Tirmidhi',
    virtue:
        "Un créneau exaucé qui revient cinq fois par jour et que presque personne n'utilise. Demande librement, à voix basse.",
    tags: ['avant_priere'],
  ),
  Dua(
    id: 'mosquee_entree',
    titleFr: 'En entrant à la mosquée',
    titleAr: 'دعاء دخول المسجد',
    textAr:
        'بِسْمِ اللَّهِ، وَالصَّلَاةُ وَالسَّلَامُ عَلَى رَسُولِ اللَّهِ، اللَّهُمَّ افْتَحْ لِي أَبْوَابَ رَحْمَتِكَ',
    translationFr:
        "Au nom d'Allah, prière et salut sur le Messager d'Allah. Ô Allah, ouvre-moi les portes de Ta miséricorde.",
    source: 'Rapporté par Mouslim et Ibn Majah',
    tags: ['avant_priere'],
  ),
  Dua(
    id: 'mosquee_sortie',
    titleFr: 'En sortant de la mosquée',
    titleAr: 'دعاء الخروج من المسجد',
    textAr:
        'بِسْمِ اللَّهِ، وَالصَّلَاةُ وَالسَّلَامُ عَلَى رَسُولِ اللَّهِ، اللَّهُمَّ إِنِّي أَسْأَلُكَ مِنْ فَضْلِكَ، اللَّهُمَّ اعْصِمْنِي مِنَ الشَّيْطَانِ الرَّجِيمِ',
    translationFr:
        "Au nom d'Allah, prière et salut sur le Messager d'Allah. Ô Allah, je Te demande de Ta grâce. Ô Allah, protège-moi du diable banni.",
    source: 'Rapporté par Mouslim et Ibn Majah',
    tags: ['avant_priere'],
  ),

  // ── Pendant la prière ──────────────────────────────────────────────────
  Dua(
    id: 'istiftah_subhanaka',
    titleFr: "Invocation d'ouverture",
    titleAr: 'دعاء الاستفتاح',
    textAr:
        'سُبْحَانَكَ اللَّهُمَّ وَبِحَمْدِكَ، وَتَبَارَكَ اسْمُكَ، وَتَعَالَى جَدُّكَ، وَلَا إِلَهَ غَيْرُكَ',
    translationFr:
        "Gloire et louange à Toi, ô Allah. Béni soit Ton nom, exaltée soit Ta majesté, et il n'y a de divinité que Toi.",
    source: 'Rapporté par Abou Dawoud et At-Tirmidhi — après le takbīr initial, avant Al-Fātiḥa',
    tags: ['dans_priere'],
  ),
  Dua(
    id: 'istiftah_baid',
    titleFr: "Éloigne-moi de mes fautes",
    titleAr: 'اللهم باعد بيني وبين خطاياي',
    textAr:
        'اللَّهُمَّ بَاعِدْ بَيْنِي وَبَيْنَ خَطَايَايَ كَمَا بَاعَدْتَ بَيْنَ الْمَشْرِقِ وَالْمَغْرِبِ، اللَّهُمَّ نَقِّنِي مِنْ خَطَايَايَ كَمَا يُنَقَّى الثَّوْبُ الْأَبْيَضُ مِنَ الدَّنَسِ، اللَّهُمَّ اغْسِلْنِي مِنْ خَطَايَايَ بِالثَّلْجِ وَالْمَاءِ وَالْبَرَدِ',
    translationFr:
        "Ô Allah, éloigne-moi de mes fautes comme Tu as éloigné l'Orient de l'Occident. Ô Allah, purifie-moi de mes fautes comme on purifie le vêtement blanc de la souillure. Ô Allah, lave-moi de mes fautes par la neige, l'eau et la grêle.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    tags: ['dans_priere'],
  ),
  Dua(
    id: 'ruku',
    titleFr: "Dans l'inclinaison (rukūʿ)",
    titleAr: 'ذكر الركوع',
    textAr: 'سُبْحَانَ رَبِّيَ الْعَظِيمِ',
    translit: "Subḥāna rabbiya l-ʿaẓīm",
    translationFr: 'Gloire à mon Seigneur, l\'Immense.',
    source: 'Rapporté par Mouslim — trois fois au minimum',
    tags: ['dans_priere'],
    repeat: 3,
  ),
  Dua(
    id: 'relevement',
    titleFr: "En se relevant de l'inclinaison",
    titleAr: 'الرفع من الركوع',
    textAr:
        'سَمِعَ اللَّهُ لِمَنْ حَمِدَهُ. رَبَّنَا وَلَكَ الْحَمْدُ حَمْدًا كَثِيرًا طَيِّبًا مُبَارَكًا فِيهِ',
    translationFr:
        "Allah entend celui qui Le loue. Notre Seigneur, à Toi la louange, une louange abondante, excellente et bénie.",
    source: 'Rapporté par Al-Boukhari',
    virtue:
        "Le Prophète ﷺ vit « une trentaine d'anges se hâter à qui l'inscrirait en premier » lorsqu'un compagnon prononça cette formule.",
    tags: ['dans_priere'],
  ),
  Dua(
    id: 'sujud',
    titleFr: 'Dans la prosternation (sujūd)',
    titleAr: 'ذكر السجود',
    textAr: 'سُبْحَانَ رَبِّيَ الْأَعْلَى',
    translit: "Subḥāna rabbiya l-aʿlā",
    translationFr: 'Gloire à mon Seigneur, le Très-Haut.',
    source: 'Rapporté par Mouslim — trois fois au minimum',
    virtue:
        "« Le serviteur est le plus proche de son Seigneur lorsqu'il est prosterné : multipliez-y les invocations. »",
    tags: ['dans_priere'],
    repeat: 3,
  ),
  Dua(
    id: 'entre_sujud',
    titleFr: 'Entre les deux prosternations',
    titleAr: 'الجلوس بين السجدتين',
    textAr:
        'رَبِّ اغْفِرْ لِي، وَارْحَمْنِي، وَاهْدِنِي، وَاجْبُرْنِي، وَعَافِنِي، وَارْزُقْنِي، وَارْفَعْنِي',
    translationFr:
        "Seigneur, pardonne-moi, fais-moi miséricorde, guide-moi, répare ce qui est brisé en moi, préserve-moi, accorde-moi ma subsistance et élève-moi.",
    source: 'Rapporté par Abou Dawoud, At-Tirmidhi et Ibn Majah',
    tags: ['dans_priere'],
  ),
  Dua(
    id: 'tashahhud',
    titleFr: 'Le tashahhud',
    titleAr: 'التشهد',
    textAr:
        'التَّحِيَّاتُ لِلَّهِ وَالصَّلَوَاتُ وَالطَّيِّبَاتُ، السَّلَامُ عَلَيْكَ أَيُّهَا النَّبِيُّ وَرَحْمَةُ اللَّهِ وَبَرَكَاتُهُ، السَّلَامُ عَلَيْنَا وَعَلَى عِبَادِ اللَّهِ الصَّالِحِينَ، أَشْهَدُ أَنْ لَا إِلَهَ إِلَّا اللَّهُ وَأَشْهَدُ أَنَّ مُحَمَّدًا عَبْدُهُ وَرَسُولُهُ',
    translationFr:
        "Les salutations, les prières et les bonnes paroles appartiennent à Allah. Que la paix soit sur toi, ô Prophète, ainsi que la miséricorde d'Allah et Ses bénédictions. Que la paix soit sur nous et sur les serviteurs vertueux d'Allah. J'atteste qu'il n'y a de divinité qu'Allah et j'atteste que Muhammad est Son serviteur et Son Messager.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    tags: ['dans_priere'],
  ),
  Dua(
    id: 'salat_ibrahimiyya',
    titleFr: 'La prière sur le Prophète ﷺ',
    titleAr: 'الصلاة الإبراهيمية',
    textAr:
        'اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ وَعَلَى آلِ مُحَمَّدٍ، كَمَا صَلَّيْتَ عَلَى إِبْرَاهِيمَ وَعَلَى آلِ إِبْرَاهِيمَ، إِنَّكَ حَمِيدٌ مَجِيدٌ. اللَّهُمَّ بَارِكْ عَلَى مُحَمَّدٍ وَعَلَى آلِ مُحَمَّدٍ، كَمَا بَارَكْتَ عَلَى إِبْرَاهِيمَ وَعَلَى آلِ إِبْرَاهِيمَ، إِنَّكَ حَمِيدٌ مَجِيدٌ',
    translationFr:
        "Ô Allah, prie sur Muhammad et sur la famille de Muhammad comme Tu as prié sur Abraham et sur la famille d'Abraham : Tu es digne de louange et de gloire. Ô Allah, bénis Muhammad et la famille de Muhammad comme Tu as béni Abraham et la famille d'Abraham : Tu es digne de louange et de gloire.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    tags: ['dans_priere', 'joumoua'],
  ),
  Dua(
    id: 'avant_salam',
    titleFr: 'Avant le salut final — les quatre refuges',
    titleAr: 'الدعاء قبل السلام',
    textAr:
        'اللَّهُمَّ إِنِّي أَعُوذُ بِكَ مِنْ عَذَابِ جَهَنَّمَ، وَمِنْ عَذَابِ الْقَبْرِ، وَمِنْ فِتْنَةِ الْمَحْيَا وَالْمَمَاتِ، وَمِنْ شَرِّ فِتْنَةِ الْمَسِيحِ الدَّجَّالِ',
    translationFr:
        "Ô Allah, je cherche refuge auprès de Toi contre le châtiment de l'Enfer, contre le châtiment de la tombe, contre l'épreuve de la vie et de la mort, et contre le mal de l'épreuve de l'Antéchrist.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    virtue: "Le Prophète ﷺ ordonnait de s'en protéger avant chaque salut final.",
    tags: ['dans_priere'],
  ),
  Dua(
    id: 'dua_abu_bakr',
    titleFr: "L'invocation d'Abou Bakr dans la prière",
    titleAr: 'دعاء أبي بكر في الصلاة',
    textAr:
        'اللَّهُمَّ إِنِّي ظَلَمْتُ نَفْسِي ظُلْمًا كَثِيرًا، وَلَا يَغْفِرُ الذُّنُوبَ إِلَّا أَنْتَ، فَاغْفِرْ لِي مَغْفِرَةً مِنْ عِنْدِكَ، وَارْحَمْنِي إِنَّكَ أَنْتَ الْغَفُورُ الرَّحِيمُ',
    translationFr:
        "Ô Allah, je me suis fait beaucoup de tort à moi-même, et nul ne pardonne les péchés sauf Toi. Accorde-moi donc un pardon venant de Toi et fais-moi miséricorde : Tu es le Pardonneur, le Miséricordieux.",
    source: 'Rapporté par Al-Boukhari et Mouslim — enseignée à Abou Bakr pour sa prière',
    tags: ['dans_priere', 'istighfar'],
  ),

  // ── Ṣalāt as-Ṣobḥ ──────────────────────────────────────────────────────
  Dua(
    id: 'sobh_adhan',
    titleFr: "L'ajout propre à l'adhān de Ṣobḥ",
    titleAr: 'التثويب في أذان الفجر',
    textAr: 'الصَّلَاةُ خَيْرٌ مِنَ النَّوْمِ',
    translit: "Aṣ-ṣalātu khayrun mina n-nawm",
    translationFr: 'La prière est meilleure que le sommeil.',
    source: 'Rapporté par Abou Dawoud et An-Nasā\'ī — dit deux fois, uniquement à l\'appel de Ṣobḥ',
    virtue:
        "C'est la seule prière dont l'appel comporte cette phrase — l'appel lui-même reconnaît ce qu'elle coûte.",
    tags: ['sobh'],
  ),
  Dua(
    id: 'sobh_sunna',
    titleFr: 'Les deux unités avant Ṣobḥ',
    titleAr: 'سنة الفجر',
    textAr:
        'يُقْرَأُ فِيهِمَا: «قُلْ يَا أَيُّهَا الْكَافِرُونَ» فِي الرَّكْعَةِ الْأُولَى، وَ«قُلْ هُوَ اللَّهُ أَحَدٌ» فِي الثَّانِيَةِ',
    translationFr:
        "On y récite Al-Kāfirūn dans la première unité et Al-Ikhlāṣ dans la seconde.",
    source: 'Rapporté par Mouslim',
    virtue:
        "« Les deux unités de l'aube valent mieux que ce bas monde et tout ce qu'il contient. » Le Prophète ﷺ ne les délaissait jamais, ni en voyage ni en résidence.",
    tags: ['sobh'],
  ),
  Dua(
    id: 'sobh_apres_salam',
    titleFr: 'Juste après le salut de Ṣobḥ',
    titleAr: 'دعاء بعد صلاة الفجر',
    textAr:
        'اللَّهُمَّ إِنِّي أَسْأَلُكَ عِلْمًا نَافِعًا، وَرِزْقًا طَيِّبًا، وَعَمَلًا مُتَقَبَّلًا',
    translit: "Allāhumma innī as'aluka ʿilman nāfiʿan, wa rizqan ṭayyiban, wa ʿamalan mutaqabbalan",
    translationFr:
        "Ô Allah, je Te demande une science utile, une subsistance pure et une œuvre agréée.",
    source: 'Rapporté par Ibn Majah — dite après le salut final de la prière de l\'aube',
    virtue:
        "Trois demandes qui couvrent la journée entière : ce qu'on apprend, ce qu'on gagne, ce qu'on fait.",
    tags: ['sobh'],
  ),
  Dua(
    id: 'sobh_ajirni',
    titleFr: 'Préserve-moi du Feu — sept fois',
    titleAr: 'اللهم أجرني من النار',
    textAr: 'اللَّهُمَّ أَجِرْنِي مِنَ النَّارِ',
    translit: "Allāhumma ajirnī mina n-nār",
    translationFr: 'Ô Allah, préserve-moi du Feu.',
    source: 'Rapporté par Abou Dawoud — sept fois après Ṣobḥ et après Maghrib, avant de parler',
    tags: ['sobh', 'apres_priere'],
    repeat: 7,
  ),
  Dua(
    id: 'sobh_tahlil_10',
    titleFr: 'Le tahlīl dix fois après Ṣobḥ',
    titleAr: 'التهليل بعد الفجر',
    textAr:
        'لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ، يُحْيِي وَيُمِيتُ، وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ',
    translationFr:
        "Il n'y a de divinité qu'Allah, Seul, sans associé. À Lui la royauté, à Lui la louange. Il fait vivre et fait mourir, et Il est capable de toute chose.",
    source: 'Rapporté par At-Tirmidhi — dix fois après Ṣobḥ et après Maghrib',
    virtue:
        "Allah inscrit dix bonnes actions, efface dix mauvaises, élève de dix degrés, et cela vaut protection contre tout mal ce jour-là.",
    tags: ['sobh', 'apres_priere'],
    repeat: 10,
  ),
  Dua(
    id: 'sobh_ishraq',
    titleFr: "Rester assis jusqu'au lever du soleil",
    titleAr: 'صلاة الإشراق',
    textAr:
        'مَنْ صَلَّى الْغَدَاةَ فِي جَمَاعَةٍ ثُمَّ قَعَدَ يَذْكُرُ اللَّهَ حَتَّى تَطْلُعَ الشَّمْسُ ثُمَّ صَلَّى رَكْعَتَيْنِ',
    translationFr:
        "« Celui qui prie l'aube en groupe, puis reste assis à évoquer Allah jusqu'au lever du soleil, puis prie deux unités… »",
    source: 'Rapporté par At-Tirmidhi',
    virtue:
        "« …a la récompense d'un pèlerinage et d'une ʿUmra — complète, complète, complète. » C'est le moment naturel des adhkār du matin.",
    tags: ['sobh', 'matin'],
  ),
  Dua(
    id: 'sobh_vendredi',
    titleFr: 'Les sourates du Ṣobḥ du vendredi',
    titleAr: 'قراءة فجر الجمعة',
    textAr: 'سُورَةُ السَّجْدَةِ فِي الرَّكْعَةِ الْأُولَى، وَسُورَةُ الْإِنْسَانِ فِي الثَّانِيَةِ',
    translationFr:
        "Sourate As-Sajda dans la première unité, sourate Al-Insān dans la seconde.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    virtue:
        "Les deux sourates rappellent l'origine de l'homme et sa destination — le vendredi étant le jour où Adam fut créé et où l'Heure surviendra.",
    tags: ['sobh', 'joumoua'],
    surahNumber: 32,
    ayahNumber: 1,
  ),

  // ── Après la prière ────────────────────────────────────────────────────
  Dua(
    id: 'apres_astaghfir_salam',
    titleFr: 'Les premiers mots après le salut',
    titleAr: 'الاستغفار بعد الصلاة',
    textAr:
        'أَسْتَغْفِرُ اللَّهَ، أَسْتَغْفِرُ اللَّهَ، أَسْتَغْفِرُ اللَّهَ. اللَّهُمَّ أَنْتَ السَّلَامُ وَمِنْكَ السَّلَامُ، تَبَارَكْتَ يَا ذَا الْجَلَالِ وَالْإِكْرَامِ',
    translationFr:
        "Je demande pardon à Allah (×3). Ô Allah, Tu es la Paix et de Toi vient la paix. Béni sois-Tu, ô Détenteur de la majesté et de la générosité.",
    source: 'Rapporté par Mouslim',
    tags: ['apres_priere', 'istighfar'],
    repeat: 3,
  ),
  Dua(
    id: 'apres_tasbih_33',
    titleFr: 'Le chapelet des trente-trois',
    titleAr: 'التسبيح بعد الصلاة',
    textAr:
        'سُبْحَانَ اللَّهِ ﴿٣٣﴾ الْحَمْدُ لِلَّهِ ﴿٣٣﴾ اللَّهُ أَكْبَرُ ﴿٣٣﴾ ثُمَّ: لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ',
    translationFr:
        "Gloire à Allah (×33), Louange à Allah (×33), Allah est le plus Grand (×33), puis pour compléter la centaine : il n'y a de divinité qu'Allah, Seul, sans associé ; à Lui la royauté, à Lui la louange, et Il est capable de toute chose.",
    source: 'Rapporté par Mouslim',
    virtue:
        "« Ses péchés lui sont pardonnés, seraient-ils comme l'écume de la mer. » Le compteur ci-dessous suit les trois séries de 33.",
    tags: ['apres_priere'],
    repeat: 33,
  ),
  Dua(
    id: 'apres_ainni',
    titleFr: "Aide-moi à T'évoquer",
    titleAr: 'دعاء معاذ بن جبل',
    textAr: 'اللَّهُمَّ أَعِنِّي عَلَى ذِكْرِكَ، وَشُكْرِكَ، وَحُسْنِ عِبَادَتِكَ',
    translit: "Allāhumma aʿinnī ʿalā dhikrika wa shukrika wa ḥusni ʿibādatik",
    translationFr:
        "Ô Allah, aide-moi à T'évoquer, à Te remercier et à T'adorer de la meilleure manière.",
    source: 'Rapporté par Abou Dawoud — le Prophète ﷺ à Muʿādh ibn Jabal : « Je t\'aime, ne délaisse jamais cela après chaque prière »',
    tags: ['apres_priere'],
  ),
  Dua(
    id: 'apres_la_hawla',
    titleFr: "Il n'y a de force qu'en Allah",
    titleAr: 'لا حول ولا قوة إلا بالله',
    textAr:
        'لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ، لَا إِلَهَ إِلَّا اللَّهُ وَلَا نَعْبُدُ إِلَّا إِيَّاهُ، لَهُ النِّعْمَةُ وَلَهُ الْفَضْلُ وَلَهُ الثَّنَاءُ الْحَسَنُ',
    translationFr:
        "Il n'y a de force ni de puissance qu'en Allah. Il n'y a de divinité qu'Allah et nous n'adorons que Lui. À Lui le bienfait, à Lui la grâce, à Lui la belle louange.",
    source: 'Rapporté par Mouslim',
    tags: ['apres_priere'],
  ),

  // ── Witr & Qunūt ───────────────────────────────────────────────────────
  Dua(
    id: 'qunut_witr',
    titleFr: 'Le Qunūt du Witr',
    titleAr: 'دعاء القنوت',
    textAr:
        'اللَّهُمَّ اهْدِنِي فِيمَنْ هَدَيْتَ، وَعَافِنِي فِيمَنْ عَافَيْتَ، وَتَوَلَّنِي فِيمَنْ تَوَلَّيْتَ، وَبَارِكْ لِي فِيمَا أَعْطَيْتَ، وَقِنِي شَرَّ مَا قَضَيْتَ، فَإِنَّكَ تَقْضِي وَلَا يُقْضَى عَلَيْكَ، وَإِنَّهُ لَا يَذِلُّ مَنْ وَالَيْتَ، وَلَا يَعِزُّ مَنْ عَادَيْتَ، تَبَارَكْتَ رَبَّنَا وَتَعَالَيْتَ',
    translationFr:
        "Ô Allah, guide-moi parmi ceux que Tu as guidés, préserve-moi parmi ceux que Tu as préservés, prends-moi en charge parmi ceux dont Tu T'es chargé, bénis-moi dans ce que Tu m'as donné, et protège-moi du mal de ce que Tu as décrété. Car c'est Toi qui décrètes et nul ne décrète contre Toi. Celui que Tu soutiens n'est pas humilié et celui que Tu combats n'est pas honoré. Béni sois-Tu, notre Seigneur, et exalté sois-Tu.",
    source: 'Rapporté par Abou Dawoud, At-Tirmidhi et An-Nasā\'ī — enseignée par le Prophète ﷺ à Al-Ḥasan',
    tags: ['witr', 'nuit'],
  ),
  Dua(
    id: 'apres_witr',
    titleFr: 'Après le Witr',
    titleAr: 'الذكر بعد الوتر',
    textAr: 'سُبْحَانَ الْمَلِكِ الْقُدُّوسِ ﴿٣﴾ رَبِّ الْمَلَائِكَةِ وَالرُّوحِ',
    translationFr:
        "Gloire au Souverain, le Très-Saint (×3), Seigneur des anges et de l'Esprit — en élevant la voix à la troisième.",
    source: 'Rapporté par An-Nasā\'ī et Ad-Dāraquṭnī',
    tags: ['witr'],
    repeat: 3,
  ),
  Dua(
    id: 'witr_sourates',
    titleFr: 'Ce qui se récite dans le Witr',
    titleAr: 'قراءة الوتر',
    textAr:
        'سَبِّحِ اسْمَ رَبِّكَ الْأَعْلَى، ثُمَّ قُلْ يَا أَيُّهَا الْكَافِرُونَ، ثُمَّ قُلْ هُوَ اللَّهُ أَحَدٌ',
    translationFr:
        "Sourate Al-Aʿlā dans la première unité, Al-Kāfirūn dans la deuxième, Al-Ikhlāṣ dans la troisième.",
    source: 'Rapporté par Abou Dawoud, At-Tirmidhi et An-Nasā\'ī',
    tags: ['witr'],
    surahNumber: 87,
    ayahNumber: 1,
  ),

  // ── Vendredi ───────────────────────────────────────────────────────────
  Dua(
    id: 'joumoua_kahf',
    titleFr: 'La sourate Al-Kahf',
    titleAr: 'قراءة سورة الكهف',
    textAr: 'مَنْ قَرَأَ سُورَةَ الْكَهْفِ فِي يَوْمِ الْجُمُعَةِ أَضَاءَ لَهُ مِنَ النُّورِ مَا بَيْنَ الْجُمُعَتَيْنِ',
    translationFr:
        "« Celui qui récite la sourate Al-Kahf le jour du vendredi, une lumière l'éclaire d'un vendredi à l'autre. »",
    source: 'Rapporté par Al-Hakim et Al-Bayhaqi',
    virtue:
        "À lire entre le coucher du soleil du jeudi et celui du vendredi — la fenêtre est plus large qu'on ne croit.",
    tags: ['joumoua'],
    surahNumber: 18,
    ayahNumber: 1,
  ),
  Dua(
    id: 'joumoua_salat_nabi',
    titleFr: 'Multiplier la prière sur le Prophète ﷺ',
    titleAr: 'الإكثار من الصلاة على النبي',
    textAr: 'اللَّهُمَّ صَلِّ وَسَلِّمْ عَلَى نَبِيِّنَا مُحَمَّدٍ',
    translit: "Allāhumma ṣalli wa sallim ʿalā nabiyyinā Muḥammad",
    translationFr: 'Ô Allah, prie et accorde le salut sur notre Prophète Muhammad.',
    source: 'Rapporté par Abou Dawoud et Ibn Majah',
    virtue:
        "« Multipliez la prière sur moi le jour du vendredi, car vos prières me sont présentées. »",
    tags: ['joumoua'],
    repeat: 100,
  ),
  Dua(
    id: 'joumoua_heure',
    titleFr: "L'heure où l'invocation est exaucée",
    titleAr: 'ساعة الإجابة',
    textAr:
        'فِي يَوْمِ الْجُمُعَةِ سَاعَةٌ لَا يُوَافِقُهَا عَبْدٌ مُسْلِمٌ وَهُوَ قَائِمٌ يُصَلِّي يَسْأَلُ اللَّهَ شَيْئًا إِلَّا أَعْطَاهُ إِيَّاهُ',
    translationFr:
        "« Il y a le vendredi une heure où aucun serviteur musulman, debout en prière, ne demande quelque chose à Allah sans qu'Il ne le lui accorde. »",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    virtue:
        "Deux avis dominants sur ce moment : entre l'assise de l'imam et la fin de la prière, ou la dernière heure avant le coucher du soleil. D'où l'usage d'invoquer intensément en fin d'après-midi.",
    tags: ['joumoua'],
  ),
  Dua(
    id: 'joumoua_sourates',
    titleFr: 'Les sourates de la prière du vendredi',
    titleAr: 'قراءة صلاة الجمعة',
    textAr:
        'سُورَةُ الْجُمُعَةِ وَالْمُنَافِقُونَ، أَوْ سَبِّحِ اسْمَ رَبِّكَ الْأَعْلَى وَالْغَاشِيَةِ',
    translationFr:
        "Al-Jumuʿa et Al-Munāfiqūn, ou bien Al-Aʿlā et Al-Ghāshiya.",
    source: 'Rapporté par Mouslim',
    tags: ['joumoua'],
  ),

  // ── Prière de l'ʿAïd ───────────────────────────────────────────────────
  Dua(
    id: 'aid_takbir',
    titleFr: "Le takbīr de l'ʿAïd",
    titleAr: 'تكبير العيد',
    textAr:
        'اللَّهُ أَكْبَرُ، اللَّهُ أَكْبَرُ، لَا إِلَهَ إِلَّا اللَّهُ، وَاللَّهُ أَكْبَرُ، اللَّهُ أَكْبَرُ، وَلِلَّهِ الْحَمْدُ',
    translit: "Allāhu akbar, Allāhu akbar, lā ilāha illā llāh, wa llāhu akbar, Allāhu akbar, wa lillāhi l-ḥamd",
    translationFr:
        "Allah est le plus Grand, Allah est le plus Grand, il n'y a de divinité qu'Allah. Allah est le plus Grand, Allah est le plus Grand, et à Allah la louange.",
    source: 'Rapporté d\'Ibn Masʿūd et d\'Ibn ʿAbbās (Al-Boukhari le mentionne sans chaîne complète)',
    virtue:
        "Pour l'ʿAïd al-Fiṭr : depuis le coucher du soleil de la dernière nuit du Ramadan jusqu'à la prière. Pour l'ʿAïd al-Aḍḥā : dès l'entrée de Dhū l-Ḥijja, et à haute voix en allant à la prière.",
    tags: ['aid'],
    repeat: 10,
  ),
  Dua(
    id: 'aid_takbir_muqayyad',
    titleFr: 'Le takbīr lié aux prières (Aḍḥā)',
    titleAr: 'التكبير المقيد',
    textAr:
        'يُكَبَّرُ عَقِبَ كُلِّ صَلَاةٍ مَكْتُوبَةٍ مِنْ فَجْرِ يَوْمِ عَرَفَةَ إِلَى عَصْرِ آخِرِ أَيَّامِ التَّشْرِيقِ',
    translationFr:
        "On prononce le takbīr après chaque prière obligatoire, de l'aube du jour de ʿArafa jusqu'au ʿAṣr du dernier jour de Tashrīq (13 Dhū l-Ḥijja).",
    source: 'Pratique rapportée de ʿAlī et d\'Ibn Masʿūd — adoptée par les quatre écoles',
    virtue: "Vingt-trois prières de suite : c'est le dhikr le plus dense de l'année.",
    tags: ['aid'],
  ),
  Dua(
    id: 'aid_priere',
    titleFr: "Comment se prie l'ʿAïd",
    titleAr: 'صفة صلاة العيد',
    textAr:
        'رَكْعَتَانِ: سَبْعُ تَكْبِيرَاتٍ فِي الْأُولَى قَبْلَ الْقِرَاءَةِ، وَخَمْسٌ فِي الثَّانِيَةِ. يُقْرَأُ «سَبِّحِ اسْمَ رَبِّكَ الْأَعْلَى» وَ«الْغَاشِيَةِ»، أَوْ «ق» وَ«اقْتَرَبَتِ السَّاعَةُ»',
    translationFr:
        "Deux unités : sept takbīrs dans la première avant la récitation, cinq dans la seconde. On y récite Al-Aʿlā et Al-Ghāshiya, ou bien Qāf et Al-Qamar. Le sermon vient APRÈS la prière — contrairement au vendredi.",
    source: 'Rapporté par Abou Dawoud, At-Tirmidhi et Mouslim',
    tags: ['aid'],
  ),
  Dua(
    id: 'aid_sunan',
    titleFr: "Les usages du jour de l'ʿAïd",
    titleAr: 'سنن يوم العيد',
    textAr:
        'الِاغْتِسَالُ، وَلُبْسُ أَحْسَنِ الثِّيَابِ، وَالتَّطَيُّبُ، وَالْأَكْلُ تَمَرَاتٍ وِتْرًا قَبْلَ صَلَاةِ الْفِطْرِ، وَالْإِمْسَاكُ حَتَّى يَأْكُلَ مِنْ أُضْحِيَتِهِ فِي الْأَضْحَى، وَمُخَالَفَةُ الطَّرِيقِ',
    translationFr:
        "Se laver, mettre ses plus beaux vêtements, se parfumer, manger un nombre impair de dattes avant la prière de l'ʿAïd al-Fiṭr, s'abstenir de manger jusqu'après la prière pour l'ʿAïd al-Aḍḥā, et rentrer par un chemin différent de celui de l'aller.",
    source: 'Rapporté par Al-Boukhari et Ibn Majah',
    virtue:
        "Les femmes et les enfants sont invités à sortir vers le lieu de prière — y compris celles qui ne prient pas, pour assister au bien et au rassemblement.",
    tags: ['aid'],
  ),
  Dua(
    id: 'aid_tahniya',
    titleFr: "Se féliciter le jour de l'ʿAïd",
    titleAr: 'التهنئة بالعيد',
    textAr: 'تَقَبَّلَ اللَّهُ مِنَّا وَمِنْكُمْ',
    translit: "Taqabbala llāhu minnā wa minkum",
    translationFr: "Qu'Allah accepte de nous et de vous.",
    source: 'Pratique rapportée des compagnons (Ibn Ḥajar, Fatḥ al-Bārī)',
    tags: ['aid', 'autrui'],
  ),
  Dua(
    id: 'aid_sacrifice',
    titleFr: "Au moment du sacrifice",
    titleAr: 'دعاء الأضحية',
    textAr: 'بِسْمِ اللَّهِ وَاللَّهُ أَكْبَرُ، اللَّهُمَّ مِنْكَ وَلَكَ، اللَّهُمَّ تَقَبَّلْ مِنِّي',
    translationFr:
        "Au nom d'Allah, Allah est le plus Grand. Ô Allah, cela vient de Toi et Te revient. Ô Allah, accepte-le de moi.",
    source: 'Rapporté par Mouslim et Abou Dawoud',
    tags: ['aid'],
  ),

  // ── Istikhāra ──────────────────────────────────────────────────────────
  Dua(
    id: 'istikhara',
    titleFr: "L'invocation de consultation",
    titleAr: 'دعاء الاستخارة',
    textAr:
        'اللَّهُمَّ إِنِّي أَسْتَخِيرُكَ بِعِلْمِكَ، وَأَسْتَقْدِرُكَ بِقُدْرَتِكَ، وَأَسْأَلُكَ مِنْ فَضْلِكَ الْعَظِيمِ، فَإِنَّكَ تَقْدِرُ وَلَا أَقْدِرُ، وَتَعْلَمُ وَلَا أَعْلَمُ، وَأَنْتَ عَلَّامُ الْغُيُوبِ. اللَّهُمَّ إِنْ كُنْتَ تَعْلَمُ أَنَّ هَذَا الْأَمْرَ خَيْرٌ لِي فِي دِينِي وَمَعَاشِي وَعَاقِبَةِ أَمْرِي، فَاقْدُرْهُ لِي وَيَسِّرْهُ لِي ثُمَّ بَارِكْ لِي فِيهِ، وَإِنْ كُنْتَ تَعْلَمُ أَنَّ هَذَا الْأَمْرَ شَرٌّ لِي فِي دِينِي وَمَعَاشِي وَعَاقِبَةِ أَمْرِي، فَاصْرِفْهُ عَنِّي وَاصْرِفْنِي عَنْهُ، وَاقْدُرْ لِيَ الْخَيْرَ حَيْثُ كَانَ ثُمَّ أَرْضِنِي بِهِ',
    translationFr:
        "Ô Allah, je Te consulte par Ta science, je Te demande la force par Ta puissance et je Te demande de Ta grâce immense. Car Tu es capable et je ne le suis pas, Tu sais et je ne sais pas, et Tu es le Grand Connaisseur de l'invisible. Ô Allah, si Tu sais que cette affaire est un bien pour moi dans ma religion, ma vie et l'issue de mes affaires, décrète-la pour moi, facilite-la-moi puis bénis-la-moi. Et si Tu sais que cette affaire est un mal pour moi dans ma religion, ma vie et l'issue de mes affaires, détourne-la de moi et détourne-moi d'elle, puis décrète pour moi le bien où qu'il soit, puis fais que j'en sois satisfait.",
    source: 'Rapporté par Al-Boukhari',
    virtue:
        "Se prie en deux unités surérogatoires, puis on invoque en nommant l'affaire à la place de « cette affaire ». Le Prophète ﷺ l'enseignait « comme il enseignait une sourate du Coran ». Il n'y a pas de rêve à attendre : on invoque, puis on agit.",
    tags: ['istikhara'],
  ),
];

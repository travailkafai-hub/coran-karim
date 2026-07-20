import '../models/dua.dart';

/// Univers « La vie quotidienne » — repas, maison, sortie, voyage, météo,
/// rapports aux autres.
const kDuasVie = <Dua>[
  // ── Le repas ───────────────────────────────────────────────────────────
  Dua(
    id: 'repas_avant',
    titleFr: 'Avant de manger',
    titleAr: 'دعاء قبل الطعام',
    textAr: 'بِسْمِ اللَّهِ',
    translit: 'Bismi llāh',
    translationFr: "Au nom d'Allah.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    virtue:
        "Le Prophète ﷺ à un enfant : « Dis Bismillāh, mange de ta main droite et mange de ce qui est devant toi. »",
    tags: ['repas'],
  ),
  Dua(
    id: 'repas_oubli',
    titleFr: "Si l'on a oublié de commencer au nom d'Allah",
    titleAr: 'إذا نسي التسمية',
    textAr: 'بِسْمِ اللَّهِ أَوَّلَهُ وَآخِرَهُ',
    translit: "Bismi llāhi awwalahu wa ākhirah",
    translationFr: "Au nom d'Allah, au début et à la fin.",
    source: 'Rapporté par Abou Dawoud et At-Tirmidhi',
    tags: ['repas'],
  ),
  Dua(
    id: 'repas_apres',
    titleFr: 'Après le repas',
    titleAr: 'دعاء بعد الطعام',
    textAr:
        'الْحَمْدُ لِلَّهِ الَّذِي أَطْعَمَنِي هَذَا وَرَزَقَنِيهِ مِنْ غَيْرِ حَوْلٍ مِنِّي وَلَا قُوَّةٍ',
    translationFr:
        "Louange à Allah qui m'a nourri de ceci et me l'a accordé sans force ni puissance de ma part.",
    source: 'Rapporté par Abou Dawoud et At-Tirmidhi',
    virtue: "« Ses péchés passés lui sont pardonnés. »",
    tags: ['repas'],
  ),
  Dua(
    id: 'repas_hote',
    titleFr: 'Pour celui qui vous a nourri',
    titleAr: 'الدعاء لصاحب الطعام',
    textAr: 'اللَّهُمَّ بَارِكْ لَهُمْ فِيمَا رَزَقْتَهُمْ، وَاغْفِرْ لَهُمْ وَارْحَمْهُمْ',
    translationFr:
        "Ô Allah, bénis-les dans ce que Tu leur as accordé, pardonne-leur et fais-leur miséricorde.",
    source: 'Rapporté par Mouslim',
    tags: ['repas', 'autrui'],
  ),
  Dua(
    id: 'iftar',
    titleFr: 'En rompant le jeûne',
    titleAr: 'دعاء الإفطار',
    textAr: 'ذَهَبَ الظَّمَأُ، وَابْتَلَّتِ الْعُرُوقُ، وَثَبَتَ الْأَجْرُ إِنْ شَاءَ اللَّهُ',
    translit: "Dhahaba ẓ-ẓama'u, wabtallati l-ʿurūqu, wa thabata l-ajru in shā'a llāh",
    translationFr:
        "La soif est partie, les veines se sont humectées et la récompense est acquise, si Allah veut.",
    source: 'Rapporté par Abou Dawoud',
    virtue:
        "« Le jeûneur a, au moment de rompre, une invocation qui n'est pas repoussée. » (Ibn Majah)",
    tags: ['repas'],
  ),
  Dua(
    id: 'iftar_chez_autrui',
    titleFr: "Après avoir rompu le jeûne chez quelqu'un",
    titleAr: 'دعاء الصائم إذا أفطر عند قوم',
    textAr:
        'أَفْطَرَ عِنْدَكُمُ الصَّائِمُونَ، وَأَكَلَ طَعَامَكُمُ الْأَبْرَارُ، وَصَلَّتْ عَلَيْكُمُ الْمَلَائِكَةُ',
    translationFr:
        "Que les jeûneurs rompent toujours le jeûne chez vous, que les vertueux mangent de votre nourriture et que les anges prient sur vous.",
    source: 'Rapporté par Abou Dawoud et Ibn Majah',
    tags: ['repas', 'autrui'],
  ),
  Dua(
    id: 'boire_lait',
    titleFr: 'En buvant du lait',
    titleAr: 'دعاء شرب اللبن',
    textAr: 'اللَّهُمَّ بَارِكْ لَنَا فِيهِ وَزِدْنَا مِنْهُ',
    translationFr: "Ô Allah, bénis-le pour nous et donne-nous-en davantage.",
    source: 'Rapporté par At-Tirmidhi',
    tags: ['repas'],
  ),

  // ── La maison ──────────────────────────────────────────────────────────
  Dua(
    id: 'maison_sortie',
    titleFr: 'En sortant de chez soi',
    titleAr: 'دعاء الخروج من المنزل',
    textAr:
        'بِسْمِ اللَّهِ، تَوَكَّلْتُ عَلَى اللَّهِ، وَلَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ',
    translit: "Bismi llāh, tawakkaltu ʿalā llāh, wa lā ḥawla wa lā quwwata illā billāh",
    translationFr:
        "Au nom d'Allah, je place ma confiance en Allah, et il n'y a de force ni de puissance qu'en Allah.",
    source: 'Rapporté par Abou Dawoud et At-Tirmidhi',
    virtue:
        "« On te dit : tu es guidé, préservé et protégé — et le diable s'écarte de toi. »",
    tags: ['maison', 'sortie'],
  ),
  Dua(
    id: 'maison_entree',
    titleFr: 'En entrant chez soi',
    titleAr: 'دعاء دخول المنزل',
    textAr:
        'بِسْمِ اللَّهِ وَلَجْنَا، وَبِسْمِ اللَّهِ خَرَجْنَا، وَعَلَى اللَّهِ رَبِّنَا تَوَكَّلْنَا',
    translationFr:
        "Au nom d'Allah nous entrons, au nom d'Allah nous sortons, et c'est en Allah notre Seigneur que nous plaçons notre confiance.",
    source: 'Rapporté par Abou Dawoud',
    virtue:
        "Mentionner le nom d'Allah en entrant et en mangeant prive le diable du gîte et du repas (Mouslim).",
    tags: ['maison'],
  ),
  Dua(
    id: 'wc_entree',
    titleFr: 'En entrant aux toilettes',
    titleAr: 'دعاء دخول الخلاء',
    textAr: 'اللَّهُمَّ إِنِّي أَعُوذُ بِكَ مِنَ الْخُبُثِ وَالْخَبَائِثِ',
    translit: "Allāhumma innī aʿūdhu bika mina l-khubthi wa l-khabā'ith",
    translationFr:
        "Ô Allah, je cherche refuge auprès de Toi contre les démons mâles et femelles.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    tags: ['maison'],
  ),
  Dua(
    id: 'wc_sortie',
    titleFr: 'En sortant des toilettes',
    titleAr: 'دعاء الخروج من الخلاء',
    textAr: 'غُفْرَانَكَ',
    translit: 'Ghufrānak',
    translationFr: 'Ton pardon !',
    source: 'Rapporté par Abou Dawoud et At-Tirmidhi',
    tags: ['maison'],
  ),
  Dua(
    id: 'vetement',
    titleFr: 'En s\'habillant',
    titleAr: 'دعاء لبس الثوب',
    textAr:
        'الْحَمْدُ لِلَّهِ الَّذِي كَسَانِي هَذَا وَرَزَقَنِيهِ مِنْ غَيْرِ حَوْلٍ مِنِّي وَلَا قُوَّةٍ',
    translationFr:
        "Louange à Allah qui m'a vêtu de ceci et me l'a accordé sans force ni puissance de ma part.",
    source: 'Rapporté par Abou Dawoud et At-Tirmidhi',
    virtue: "« Ses péchés passés lui sont pardonnés. »",
    tags: ['maison'],
  ),
  Dua(
    id: 'vetement_neuf',
    titleFr: 'Pour celui qui porte un vêtement neuf',
    titleAr: 'الدعاء لمن لبس ثوبا جديدا',
    textAr: 'تُبْلِي وَيُخْلِفُ اللَّهُ تَعَالَى',
    translationFr: "Puisses-tu l'user, et qu'Allah — exalté soit-Il — te le remplace.",
    source: 'Rapporté par Abou Dawoud',
    tags: ['maison', 'autrui'],
  ),
  Dua(
    id: 'miroir',
    titleFr: 'En se regardant dans le miroir',
    titleAr: 'دعاء النظر في المرآة',
    textAr: 'اللَّهُمَّ كَمَا حَسَّنْتَ خَلْقِي فَحَسِّنْ خُلُقِي',
    translationFr:
        "Ô Allah, de même que Tu as embelli ma constitution, embellis mon caractère.",
    source: 'Rapporté par Ahmad et Ibn Ḥibbān',
    tags: ['maison', 'colere'],
  ),

  // ── Dehors ─────────────────────────────────────────────────────────────
  Dua(
    id: 'marche',
    titleFr: 'En entrant au marché',
    titleAr: 'دعاء دخول السوق',
    textAr:
        'لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ، يُحْيِي وَيُمِيتُ، وَهُوَ حَيٌّ لَا يَمُوتُ، بِيَدِهِ الْخَيْرُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ',
    translationFr:
        "Il n'y a de divinité qu'Allah, Seul, sans associé. À Lui la royauté, à Lui la louange. Il fait vivre et fait mourir, Il est Vivant et ne meurt pas. Le bien est en Sa main et Il est capable de toute chose.",
    source: 'Rapporté par At-Tirmidhi et Ibn Majah',
    virtue:
        "« Allah lui inscrit un million de bonnes actions, efface un million de mauvaises et lui élève un million de degrés. » Dite là où les gens sont le plus distraits d'Allah.",
    tags: ['sortie'],
  ),
  Dua(
    id: 'vehicule',
    titleFr: 'En montant dans un véhicule',
    titleAr: 'دعاء الركوب',
    textAr:
        'سُبْحَانَ الَّذِي سَخَّرَ لَنَا هَذَا وَمَا كُنَّا لَهُ مُقْرِنِينَ ۝ وَإِنَّا إِلَى رَبِّنَا لَمُنقَلِبُونَ',
    translit: "Subḥāna lladhī sakhkhara lanā hādhā wa mā kunnā lahu muqrinīn",
    translationFr:
        "Gloire à Celui qui a mis ceci à notre service, alors que nous n'étions pas capables de le dominer. Et c'est vers notre Seigneur que nous retournerons.",
    source: 'Az-Zukhruf 43:13-14 — Rapporté par Abou Dawoud et At-Tirmidhi',
    tags: ['sortie', 'voyage'],
    surahNumber: 43,
    ayahNumber: 13,
  ),
  Dua(
    id: 'ville_entree',
    titleFr: 'En entrant dans une ville',
    titleAr: 'دعاء دخول القرية',
    textAr:
        'اللَّهُمَّ إِنِّي أَسْأَلُكَ خَيْرَهَا وَخَيْرَ أَهْلِهَا وَخَيْرَ مَا فِيهَا، وَأَعُوذُ بِكَ مِنْ شَرِّهَا وَشَرِّ أَهْلِهَا وَشَرِّ مَا فِيهَا',
    translationFr:
        "Ô Allah, je Te demande son bien, le bien de ses habitants et le bien de ce qu'elle contient. Et je cherche refuge auprès de Toi contre son mal, le mal de ses habitants et le mal de ce qu'elle contient.",
    source: 'Rapporté par An-Nasā\'ī et Al-Hakim',
    tags: ['sortie', 'voyage'],
  ),

  // ── Le voyage ──────────────────────────────────────────────────────────
  Dua(
    id: 'voyage_depart',
    titleFr: 'Au départ du voyage',
    titleAr: 'دعاء السفر',
    textAr:
        'اللَّهُ أَكْبَرُ، اللَّهُ أَكْبَرُ، اللَّهُ أَكْبَرُ، سُبْحَانَ الَّذِي سَخَّرَ لَنَا هَذَا وَمَا كُنَّا لَهُ مُقْرِنِينَ، وَإِنَّا إِلَى رَبِّنَا لَمُنْقَلِبُونَ. اللَّهُمَّ إِنَّا نَسْأَلُكَ فِي سَفَرِنَا هَذَا الْبِرَّ وَالتَّقْوَى، وَمِنَ الْعَمَلِ مَا تَرْضَى. اللَّهُمَّ هَوِّنْ عَلَيْنَا سَفَرَنَا هَذَا وَاطْوِ عَنَّا بُعْدَهُ. اللَّهُمَّ أَنْتَ الصَّاحِبُ فِي السَّفَرِ، وَالْخَلِيفَةُ فِي الْأَهْلِ',
    translationFr:
        "Allah est le plus Grand (×3). Gloire à Celui qui a mis ceci à notre service, alors que nous n'étions pas capables de le dominer. Et c'est vers notre Seigneur que nous retournerons. Ô Allah, nous Te demandons dans ce voyage la piété, la crainte de Toi, et des œuvres que Tu agrées. Ô Allah, allège pour nous ce voyage et raccourcis-en la distance. Ô Allah, Tu es le Compagnon dans le voyage et le Remplaçant auprès de la famille.",
    source: 'Rapporté par Mouslim',
    tags: ['voyage'],
  ),
  Dua(
    id: 'voyage_retour',
    titleFr: 'Au retour',
    titleAr: 'دعاء الرجوع من السفر',
    textAr: 'آيِبُونَ، تَائِبُونَ، عَابِدُونَ، لِرَبِّنَا حَامِدُونَ',
    translit: "Āyibūna, tā'ibūna, ʿābidūna, lirabbinā ḥāmidūn",
    translationFr:
        "Nous revenons, nous nous repentons, nous adorons et nous louons notre Seigneur.",
    source: 'Rapporté par Al-Boukhari et Mouslim — à répéter en approchant de chez soi',
    tags: ['voyage'],
  ),
  Dua(
    id: 'voyage_adieu',
    titleFr: "Pour celui qui part en voyage",
    titleAr: 'دعاء توديع المسافر',
    textAr: 'أَسْتَوْدِعُ اللَّهَ دِينَكَ، وَأَمَانَتَكَ، وَخَوَاتِيمَ عَمَلِكَ',
    translationFr:
        "Je confie à Allah ta religion, ce qui t'est confié et l'issue de tes actes.",
    source: 'Rapporté par At-Tirmidhi et Abou Dawoud',
    tags: ['voyage', 'autrui'],
  ),
  Dua(
    id: 'voyage_exauce',
    titleFr: "L'invocation du voyageur",
    titleAr: 'دعوة المسافر مستجابة',
    textAr:
        'ثَلَاثُ دَعَوَاتٍ مُسْتَجَابَاتٌ لَا شَكَّ فِيهِنَّ: دَعْوَةُ الْمَظْلُومِ، وَدَعْوَةُ الْمُسَافِرِ، وَدَعْوَةُ الْوَالِدِ عَلَى وَلَدِهِ',
    translationFr:
        "« Trois invocations sont exaucées sans aucun doute : celle de l'opprimé, celle du voyageur et celle du parent pour son enfant. »",
    source: 'Rapporté par Abou Dawoud et At-Tirmidhi',
    virtue: "Le trajet est un temps mort pour le corps — mais un créneau ouvert pour la demande.",
    tags: ['voyage'],
  ),

  // ── Ciel & météo ───────────────────────────────────────────────────────
  Dua(
    id: 'pluie',
    titleFr: 'Quand il pleut',
    titleAr: 'دعاء نزول المطر',
    textAr: 'اللَّهُمَّ صَيِّبًا نَافِعًا',
    translit: "Allāhumma ṣayyiban nāfiʿan",
    translationFr: "Ô Allah, fais-en une pluie abondante et bénéfique.",
    source: 'Rapporté par Al-Boukhari',
    virtue: "L'invocation n'est pas repoussée au moment de la pluie (Al-Hakim).",
    tags: ['meteo'],
  ),
  Dua(
    id: 'apres_pluie',
    titleFr: 'Après la pluie',
    titleAr: 'الذكر بعد نزول المطر',
    textAr: 'مُطِرْنَا بِفَضْلِ اللَّهِ وَرَحْمَتِهِ',
    translationFr: "Nous avons reçu la pluie par la grâce d'Allah et Sa miséricorde.",
    source: 'Rapporté par Al-Boukhari et Mouslim',
    tags: ['meteo'],
  ),
  Dua(
    id: 'vent',
    titleFr: 'Quand le vent se lève',
    titleAr: 'دعاء الريح',
    textAr:
        'اللَّهُمَّ إِنِّي أَسْأَلُكَ خَيْرَهَا وَخَيْرَ مَا فِيهَا وَخَيْرَ مَا أُرْسِلَتْ بِهِ، وَأَعُوذُ بِكَ مِنْ شَرِّهَا وَشَرِّ مَا فِيهَا وَشَرِّ مَا أُرْسِلَتْ بِهِ',
    translationFr:
        "Ô Allah, je Te demande son bien, le bien de ce qu'il contient et le bien de ce pour quoi il a été envoyé. Et je cherche refuge auprès de Toi contre son mal, le mal de ce qu'il contient et le mal de ce pour quoi il a été envoyé.",
    source: 'Rapporté par Mouslim',
    virtue: "Le Prophète ﷺ ne maudissait jamais le vent : « il est envoyé par ordre d'Allah ».",
    tags: ['meteo'],
  ),
  Dua(
    id: 'tonnerre',
    titleFr: 'En entendant le tonnerre',
    titleAr: 'دعاء سماع الرعد',
    textAr: 'سُبْحَانَ الَّذِي يُسَبِّحُ الرَّعْدُ بِحَمْدِهِ وَالْمَلَائِكَةُ مِنْ خِيفَتِهِ',
    translationFr:
        "Gloire à Celui que le tonnerre glorifie par Sa louange, ainsi que les anges, par crainte de Lui.",
    source: 'Rapporté par Mālik dans Al-Muwaṭṭaʾ (propos d\'Ibn az-Zubayr)',
    tags: ['meteo'],
  ),
  Dua(
    id: 'nouvelle_lune',
    titleFr: 'En voyant le croissant de lune',
    titleAr: 'دعاء رؤية الهلال',
    textAr:
        'اللَّهُمَّ أَهِلَّهُ عَلَيْنَا بِالْيُمْنِ وَالْإِيمَانِ، وَالسَّلَامَةِ وَالْإِسْلَامِ، رَبِّي وَرَبُّكَ اللَّهُ',
    translationFr:
        "Ô Allah, fais lever ce croissant sur nous avec la bénédiction et la foi, la sécurité et l'Islam. Mon Seigneur et le tien est Allah.",
    source: 'Rapporté par At-Tirmidhi et Ad-Dārimī',
    tags: ['meteo'],
  ),

  // ── Avec les autres ────────────────────────────────────────────────────
  Dua(
    id: 'jazaka_allah',
    titleFr: "Remercier quelqu'un",
    titleAr: 'جزاك الله خيرا',
    textAr: 'جَزَاكَ اللَّهُ خَيْرًا',
    translit: "Jazāka llāhu khayran",
    translationFr: "Qu'Allah te récompense par un bien.",
    source: 'Rapporté par At-Tirmidhi',
    virtue:
        "« Celui à qui l'on fait un bien et qui dit à son auteur « jazāka llāhu khayran » a porté la louange à son comble. »",
    tags: ['autrui'],
  ),
  Dua(
    id: 'amour_fillah',
    titleFr: "Quand on te dit : je t'aime en Allah",
    titleAr: 'إذا قيل لك أحبك في الله',
    textAr: 'أَحَبَّكَ الَّذِي أَحْبَبْتَنِي لَهُ',
    translationFr: "Que Celui pour qui tu m'aimes t'aime.",
    source: 'Rapporté par Abou Dawoud',
    tags: ['autrui'],
  ),
  Dua(
    id: 'mariage_felicitation',
    titleFr: 'Féliciter les mariés',
    titleAr: 'الدعاء للمتزوج',
    textAr: 'بَارَكَ اللَّهُ لَكَ، وَبَارَكَ عَلَيْكَ، وَجَمَعَ بَيْنَكُمَا فِي خَيْرٍ',
    translationFr:
        "Qu'Allah te bénisse, qu'Il répande Sa bénédiction sur toi et qu'Il vous unisse dans le bien.",
    source: 'Rapporté par Abou Dawoud et At-Tirmidhi',
    tags: ['autrui'],
  ),
  Dua(
    id: 'eternuement',
    titleFr: 'L\'éternuement',
    titleAr: 'تشميت العاطس',
    textAr:
        'يَقُولُ الْعَاطِسُ: الْحَمْدُ لِلَّهِ. فَيَقُولُ لَهُ صَاحِبُهُ: يَرْحَمُكَ اللَّهُ. فَيَرُدُّ: يَهْدِيكُمُ اللَّهُ وَيُصْلِحُ بَالَكُمْ',
    translationFr:
        "Celui qui éternue dit : « Louange à Allah. » Son compagnon lui répond : « Qu'Allah te fasse miséricorde. » Il réplique : « Qu'Allah vous guide et améliore votre condition. »",
    source: 'Rapporté par Al-Boukhari',
    tags: ['autrui'],
  ),
  Dua(
    id: 'parents',
    titleFr: 'Pour ses parents',
    titleAr: 'الدعاء للوالدين',
    textAr: 'رَّبِّ ارْحَمْهُمَا كَمَا رَبَّيَانِي صَغِيرًا',
    translit: "Rabbi rḥamhumā kamā rabbayānī ṣaghīrā",
    translationFr:
        "Seigneur, fais-leur miséricorde comme ils m'ont élevé tout petit.",
    source: 'Al-Isrāʾ 17:24',
    virtue:
        "Reste valable après leur mort : « ou un enfant vertueux qui invoque pour lui » est l'une des trois œuvres qui ne s'interrompent pas (Mouslim).",
    tags: ['autrui', 'deuil'],
    surahNumber: 17,
    ayahNumber: 24,
  ),
  Dua(
    id: 'baraka_oeil',
    titleFr: 'En admirant ce qui appartient à autrui',
    titleAr: 'التبريك خشية العين',
    textAr: 'مَا شَاءَ اللَّهُ، لَا قُوَّةَ إِلَّا بِاللَّهِ، اللَّهُمَّ بَارِكْ فِيهِ',
    translit: "Mā shā'a llāh, lā quwwata illā billāh",
    translationFr:
        "Ce qu'Allah a voulu ! Il n'y a de force qu'en Allah. Ô Allah, bénis-le.",
    source: 'Al-Kahf 18:39 — et hadith rapporté par Ibn Majah sur le mauvais œil',
    virtue:
        "« Si l'un de vous voit chez son frère quelque chose qui lui plaît, qu'il invoque la bénédiction pour lui. » Le mauvais œil est réel — la bénédiction le désamorce.",
    tags: ['autrui', 'peur'],
  ),
];

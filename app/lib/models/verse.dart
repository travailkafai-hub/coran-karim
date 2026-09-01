class Verse {
  final int surahNumber;
  final int ayahNumber;
  final String textUthmani;
  final String? textUthmaniTajweed; // HTML with tajweed class spans
  final String? translationFr;
  // Numéro de page du Mushaf standard (1-604) -- utilisé pour charger le
  // texte à réciter page par page plutôt que sourate entière d'un coup (cf.
  // KaraokeRecitationScreen._maybeExtendNextPage, demande utilisateur
  // 2026-07-11 : charger dix fois moins d'un coup pour un enchaînement
  // Al-Baqarah, 286 versets, chargeait tout instantanément). Null seulement
  // si l'appelant n'a pas demandé le champ `page_number` à l'API.
  final int? pageNumber;
  // Numérotation GLOBALE sur tout le Coran (hizb 1-60, rub' 1-240) --
  // présente dans assets/data/quran_verses.json, utilisée pour découper une
  // sourate longue en portions de suivi Coach (cf. SUITE portions/Hizb).
  // Null seulement si l'appelant n'a pas demandé ces champs à l'API.
  final int? hizbNumber;
  final int? rubElHizbNumber;

  /// Numéro de sajda (prosternation) porté par les données, ou `null`.
  ///
  /// ⚠️ NE PAS s'en servir SEUL pour décider d'un marquage à l'écran : il
  /// couvre 14 versets, alors que le TEXTE uthmani porte le signe ۩ sur 15
  /// (l'écart est 22:77). Ce n'est pas une incohérence des données, c'est une
  /// divergence d'écoles réelle -- Al-Hajj compte deux sajdas chez les
  /// shafiites, une seule ailleurs. Cf. [aSajda], qui suit le texte plutôt
  /// que de trancher.
  final int? sajdahNumber;

  const Verse({
    required this.surahNumber,
    required this.ayahNumber,
    required this.textUthmani,
    this.textUthmaniTajweed,
    this.translationFr,
    this.pageNumber,
    this.hizbNumber,
    this.rubElHizbNumber,
    this.sajdahNumber,
  });

  String get key => '$surahNumber:$ayahNumber';

  /// Ce verset porte-t-il une sajda ?
  ///
  /// Fondé sur le SIGNE ۩ (U+06E9) réellement présent dans le texte uthmani,
  /// pas sur [sajdahNumber] : le texte est la source, et il porte les 15
  /// signes. S'appuyer sur le champ numérique reviendrait à retenir
  /// silencieusement le comptage d'une école plutôt qu'une autre (cf. sa doc)
  /// -- ce n'est pas à l'app de trancher cela.
  ///
  /// MESURE 2026-09-01, sur les deux fichiers réellement livrés, qui confirme
  /// que lire le TEXTE est le seul choix correct (et non le champ) :
  ///
  /// | source                    | signe ۩ | champ `sajdah_number` |
  /// |---------------------------|---------|-----------------------|
  /// | `quran_verses.json` (Hafs)|   15    |          14           |
  /// | `..._warsh.json` (Warsh)  |   11    |          14           |
  ///
  /// Les deux écarts sont doctrinaux, pas des données abîmées :
  ///  - Hafs porte 22:77 en signe sans l'avoir en champ (2ᵉ sajda d'Al-Hajj,
  ///    retenue par les shafiites) ;
  ///  - Warsh n'a que 11 signes : l'école malikite, qui va avec cette riwaya,
  ///    ne retient PAS les trois sajdas d'al-Mufassal (53:62, 84:21, 96:19),
  ///    et place celle de Fussilat à 41:37 là où Hafs la met à 41:38.
  ///
  /// Le champ `sajdah_number` du fichier Warsh vaut pourtant 14 et cite
  /// 41:38/53:62/84:21/96:19 : il a été recopié de la source Hafs et décrit
  /// donc une école qui n'est pas celle du texte qu'il accompagne. S'y fier
  /// afficherait quatre prosternations que ce mushaf ne demande pas.
  /// ⇒ Ne JAMAIS basculer ce getter sur [sajdahNumber] : ce n'est pas une
  /// simplification, c'est une régression doctrinale sur Warsh.
  bool get aSajda => textUthmani.contains('۩');

  factory Verse.fromJson(Map<String, dynamic> json) {
    final key = json['verse_key'] as String;
    final parts = key.split(':');
    return Verse(
      surahNumber: int.parse(parts[0]),
      ayahNumber: int.parse(parts[1]),
      textUthmani: json['text_uthmani'] as String? ?? json['text'] as String,
      textUthmaniTajweed: json['text_uthmani_tajweed'] as String?,
      pageNumber: json['page_number'] as int?,
      hizbNumber: json['hizb_number'] as int?,
      rubElHizbNumber: json['rub_el_hizb_number'] as int?,
      sajdahNumber: json['sajdah_number'] as int?,
    );
  }
}

class Surah {
  final int number;
  final String nameArabic;
  final String nameSimple;
  final String nameTranslationFr;
  final int versesCount;
  final String revelationPlace;

  const Surah({
    required this.number,
    required this.nameArabic,
    required this.nameSimple,
    required this.nameTranslationFr,
    required this.versesCount,
    required this.revelationPlace,
  });

  factory Surah.fromJson(Map<String, dynamic> json) {
    return Surah(
      number: json['id'] as int,
      nameArabic: json['name_arabic'] as String,
      nameSimple: json['name_simple'] as String,
      nameTranslationFr: json['translated_name']?['name'] as String? ?? '',
      versesCount: json['verses_count'] as int,
      revelationPlace: json['revelation_place'] as String? ?? '',
    );
  }
}

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

  const Verse({
    required this.surahNumber,
    required this.ayahNumber,
    required this.textUthmani,
    this.textUthmaniTajweed,
    this.translationFr,
    this.pageNumber,
    this.hizbNumber,
    this.rubElHizbNumber,
  });

  String get key => '$surahNumber:$ayahNumber';

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

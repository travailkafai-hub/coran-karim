import 'package:dio/dio.dart';
import '../models/verse.dart';

class QuranApi {
  static const _base = 'https://api.quran.com/api/v4';
  static final _dio = Dio(BaseOptions(
    baseUrl: _base,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  static Verse? _bismillahCache;

  /// La Bismillah = texte du verset 1:1 (Al-Fatiha), VERBATIM identique à ce
  /// qui doit apparaître au début de toute autre sourate (sauf At-Tawbah).
  /// Récupérée depuis l'API comme n'importe quel autre verset -- JAMAIS
  /// tapée à la main (texte sacré : un caractère tapé à la main peut se
  /// tromper de variante Unicode sans que ça se voie -- bug réel du
  /// 2026-07-09, un "ي" persan au lieu du "ي" arabe standard a cassé la
  /// reconnaissance de "الرحيم" dans une constante tapée directement dans le
  /// code). Mise en cache après le premier appel (contenu immuable).
  static Future<Verse> fetchBismillah() async {
    if (_bismillahCache != null) return _bismillahCache!;
    final verses = await fetchVerses(1);
    _bismillahCache = verses.first;
    return _bismillahCache!;
  }

  static Future<List<Surah>> fetchSurahs() async {
    final r = await _dio.get('/chapters', queryParameters: {'language': 'fr'});
    final list = r.data['chapters'] as List;
    return list.map((e) => Surah.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<Verse>> fetchVerses(int surahNumber) async {
    final r = await _dio.get(
      '/verses/by_chapter/$surahNumber',
      queryParameters: {
        'translations': '136',  // fr-montada
        'fields': 'text_uthmani,text_uthmani_tajweed',
        'per_page': '286',
      },
    );
    final list = r.data['verses'] as List;
    return list.map((v) {
      final map = v as Map<String, dynamic>;
      final verse = Verse.fromJson(map);
      final translations = map['translations'] as List?;
      return Verse(
        surahNumber: verse.surahNumber,
        ayahNumber: verse.ayahNumber,
        textUthmani: verse.textUthmani,
        textUthmaniTajweed: map['text_uthmani_tajweed'] as String?,
        translationFr: translations?.isNotEmpty == true
            ? translations!.first['text'] as String?
            : null,
      );
    }).toList();
  }

  /// Returns all audio file URLs for a surah, keyed by verse_key.
  /// CDN base: https://verses.quran.com/
  static Future<Map<String, String>> fetchSurahAudioUrls(
      int recitationId, int surahNumber) async {
    final r = await _dio.get(
      '/recitations/$recitationId/by_chapter/$surahNumber',
      queryParameters: {'per_page': '286'},
    );
    final files = r.data['audio_files'] as List;
    return {
      for (final f in files)
        f['verse_key'] as String:
            'https://verses.quran.com/${f['url']}',
    };
  }

  static Future<Map<String, dynamic>> fetchSurahInfo(int surahNumber) async {
    final r = await _dio.get('/chapters/$surahNumber');
    return r.data['chapter'] as Map<String, dynamic>;
  }

  /// Timing mot-par-mot de l'audio d'un verset — endpoint officiel Quran
  /// Foundation/quran.com (même API que le reste de l'app), vérifié en appel
  /// réel le 2026-07-05 : `fields=segments` sur `/recitations/{id}/by_ayah/{verse_key}`
  /// renvoie `audio_files[0].segments`, une liste de
  /// `[word_index_0based, word_position_1based, start_ms, end_ms]`.
  /// Utilisé pour ne rejouer QUE le(s) mot(s) fautif(s) lors de la correction
  /// automatique plutôt que tout le verset — pas d'estimation inventée, un
  /// découpage réel fourni par la même source que le texte/l'audio.
  static Future<List<List<int>>> fetchAyahSegments(
      int recitationId, String verseKey) async {
    final r = await _dio.get(
      '/recitations/$recitationId/by_ayah/$verseKey',
      queryParameters: {'fields': 'segments'},
    );
    final files = r.data['audio_files'] as List;
    if (files.isEmpty) return [];
    final segments = (files.first as Map<String, dynamic>)['segments'] as List?;
    if (segments == null) return [];
    return segments
        .map<List<int>>(
            (s) => (s as List).map((e) => (e as num).toInt()).toList())
        .toList();
  }
}

import 'dart:convert' show json;
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/verse.dart';

/// Texte du Coran (chapitres, versets, tajweed, traduction fr) -- 100%
/// LOCAL depuis le 2026-07-19 (`assets/data/quran_{chapters,verses}.json`,
/// générés une fois par `benchmark/fetch_quran_full_local.py`, 8 Mo au
/// total). Avant cette date, `fetchSurahs`/`fetchVerses`/`fetchVersesByPage`
/// appelaient `api.quran.com` en direct à CHAQUE lancement de l'app -- sans
/// aucun cache, contrairement au reste du pipeline (ASR/ML) qui est
/// entièrement on-device. Découvert via un écran "Connexion requise" sur un
/// téléphone dont le WiFi était en réalité connecté mais dont la résolution
/// DNS échouait (`api.quran.com` injoignable) -- a révélé que la lecture du
/// Coran elle-même, pas seulement la vérification, dépendait du réseau.
/// Nécessaire aussi pour le futur stockage local d'erreurs/mémorisation
/// (coach) : impossible de bâtir des fonctionnalités locales sur un texte
/// qui doit être re-téléchargé à chaque session.
///
/// Reste volontairement EN LIGNE (streaming, pas raisonnable à embarquer,
/// des centaines de Mo par récitateur) : `fetchSurahAudioUrls`,
/// `fetchAyahSegments`, `fetchSurahInfo`.
class QuranApi {
  static const _base = 'https://api.quran.com/api/v4';
  static final _dio = Dio(BaseOptions(
    baseUrl: _base,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  static List<Surah>? _chapters;
  static Map<int, List<Verse>>? _versesBySurah;
  static Map<int, List<Verse>>? _versesByPage;
  static Future<void>? _loading;

  static Verse _parseVerse(Map<String, dynamic> map) {
    final verse = Verse.fromJson(map);
    final translations = map['translations'] as List?;
    return Verse(
      surahNumber: verse.surahNumber,
      ayahNumber: verse.ayahNumber,
      textUthmani: verse.textUthmani,
      textUthmaniTajweed: map['text_uthmani_tajweed'] as String?,
      pageNumber: verse.pageNumber,
      translationFr: translations?.isNotEmpty == true
          ? translations!.first['text'] as String?
          : null,
    );
  }

  /// Charge et indexe les deux assets une seule fois (idempotent, réutilisé
  /// par tous les appels ci-dessous -- même contenu qu'un appel réseau
  /// aurait renvoyé, juste lu depuis l'APK au lieu de `api.quran.com`).
  static Future<void> _ensureLoaded() {
    if (_chapters != null) return Future.value();
    return _loading ??= () async {
      final chaptersRaw = json.decode(
          await rootBundle.loadString('assets/data/quran_chapters.json')) as List;
      _chapters = chaptersRaw
          .map((e) => Surah.fromJson(e as Map<String, dynamic>))
          .toList();

      final versesRaw = json.decode(
          await rootBundle.loadString('assets/data/quran_verses.json')) as List;
      final bySurah = <int, List<Verse>>{};
      final byPage = <int, List<Verse>>{};
      for (final v in versesRaw) {
        final verse = _parseVerse(v as Map<String, dynamic>);
        bySurah.putIfAbsent(verse.surahNumber, () => []).add(verse);
        if (verse.pageNumber != null) {
          byPage.putIfAbsent(verse.pageNumber!, () => []).add(verse);
        }
      }
      _versesBySurah = bySurah;
      _versesByPage = byPage;
    }();
  }

  static Verse? _bismillahCache;

  /// La Bismillah = texte du verset 1:1 (Al-Fatiha), VERBATIM identique à ce
  /// qui doit apparaître au début de toute autre sourate (sauf At-Tawbah).
  /// Récupérée comme n'importe quel autre verset -- JAMAIS tapée à la main
  /// (texte sacré : un caractère tapé à la main peut se tromper de variante
  /// Unicode sans que ça se voie -- bug réel du 2026-07-09, un "ي" persan au
  /// lieu du "ي" arabe standard a cassé la reconnaissance de "الرحيم" dans
  /// une constante tapée directement dans le code). Mise en cache après le
  /// premier appel (contenu immuable).
  static Future<Verse> fetchBismillah() async {
    if (_bismillahCache != null) return _bismillahCache!;
    final verses = await fetchVerses(1);
    _bismillahCache = verses.first;
    return _bismillahCache!;
  }

  static Future<List<Surah>> fetchSurahs() async {
    await _ensureLoaded();
    return _chapters!;
  }

  static Future<List<Verse>> fetchVerses(int surahNumber) async {
    await _ensureLoaded();
    return _versesBySurah![surahNumber] ?? const [];
  }

  /// Une page du Mushaf standard (1-604) -- utilisé pour l'enchaînement
  /// dynamique entre sourates (KaraokeRecitationScreen._maybeExtendNextPage) :
  /// charger une page à la fois plutôt que la sourate suivante en entier
  /// (une sourate longue comme Al-Baqarah, 286 versets/~6100 mots, chargeait
  /// tout instantanément dès qu'on en approchait -- demande utilisateur
  /// 2026-07-11 : "il faut faire ça dynamiquement, une page avant et une page
  /// après").
  static Future<List<Verse>> fetchVersesByPage(int pageNumber) async {
    await _ensureLoaded();
    return _versesByPage![pageNumber] ?? const [];
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

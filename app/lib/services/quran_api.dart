import 'dart:convert' show json;
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/riwaya.dart';
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
  static final _dio = Dio(
    BaseOptions(
      baseUrl: _base,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  static List<Surah>? _chapters;

  /// Catalogue des sourates DEJA charge, ou `null` s'il ne l'est pas encore.
  ///
  /// Lecture seule et NON bloquante (2026-09-02) : la vue page a besoin du nom
  /// arabe pendant un `build`, ou l'on ne peut pas attendre un Future. Rendre
  /// `null` plutot que declencher un chargement laisse l'appelant afficher un
  /// repli ; le nom apparait au rendu suivant, sans jamais bloquer la peinture.
  static List<Surah>? get chapitresCharges => _chapters;
  static Map<int, List<Verse>>? _versesBySurah;
  static Map<int, List<Verse>>? _versesByPage;
  static Future<void>? _loading;

  // ── RIWAYA : QUEL TEXTE DU CORAN L'APP LIT (2026-08-12) ──────────────────
  //
  // Point de bascule UNIQUE de tout le texte de l'application. Volontairement
  // un champ statique et non un provider : `QuranApi` est appelé depuis des
  // endroits qui n'ont pas de `Ref` (services, isolats de calcul), et surtout
  // c'est ICI que vit le cache -- le réglage et le cache qu'il invalide
  // doivent être au même endroit, sinon un écran peut lire l'ancien texte
  // après le basculement.
  //
  // Le REGLAGE, lui, est dans `riwayaProvider` (app_settings_provider.dart),
  // qui pousse sa valeur ici. Ne jamais écrire ce champ ailleurs.
  static Riwaya _riwaya = Riwaya.hafs;

  /// ── DEUX BUGS CONFIRMES PAR L'AUDIT DE SECURITE (QUAL-01, 2026-09-09) ────
  ///
  /// Rapport `AUDIT_SECURITE_CHGPT_2026-09-06.md`, reproduits par execution
  /// (interception du canal d'assets, deux jeux de donnees factices) :
  ///
  ///     AUDIT concurrent fetch: Null check operator used on a null value
  ///     AUDIT active=warsh, cached=HAFS_FIXTURE
  ///
  /// BUG 1 -- `_ensureLoaded()` prenait `_chapters != null` comme preuve de
  /// chargement COMPLET, alors que `_chapters` etait affecte avant l'attente
  /// de lecture des versets. Un second appel pendant cette attente retournait
  /// donc trop tot, et `fetchVerses()` dereferencait `_versesBySurah!` encore
  /// nul -- le crash `Null check operator`.
  ///
  /// BUG 2 -- changer `riwaya` remettait les caches a null mais n'invalidait
  /// pas le chargement asynchrone deja en vol : un vieux chargement Hafs
  /// pouvait terminer APRES la bascule vers Warsh et ecraser ses resultats
  /// avec ceux de l'ancienne riwaya. Silencieux : aucune erreur, juste le
  /// mauvais texte affiche et fourni a l'ASR sous l'etiquette Warsh.
  ///
  /// CORRECTIF, exactement celui que le rapport recommandait : « generations
  /// de chargement verifiees avant publication ; publier atomiquement un
  /// ensemble complet de donnees ». `_generation` est incremente a chaque
  /// bascule de riwaya ; un chargement ne publie ses resultats QUE si la
  /// generation n'a pas change pendant son attente reseau/disque -- sinon il
  /// est jete en silence, la generation suivante le refera.
  static int _generation = 0;

  static Riwaya get riwaya => _riwaya;

  static set riwaya(Riwaya value) {
    if (value == _riwaya) return;
    _riwaya = value;
    // Tout le texte déjà chargé appartient à l'autre riwaya : le garder ferait
    // cohabiter les deux à l'écran. Les chapitres (noms de sourates) sont
    // communs aux deux, mais on repart de zéro par simplicité -- le
    // rechargement est local et quasi instantané.
    _chapters = null;
    _versesBySurah = null;
    _versesByPage = null;
    _bismillahCache = null;
    _loading = null;
    // Toute charge en vol visait l'ANCIENNE riwaya : elle ne doit plus rien
    // publier a son retour. Cf. le commentaire de `_generation` ci-dessus.
    _generation++;
  }

  /// Asset de texte correspondant à la riwaya courante. Les deux fichiers ont
  /// exactement la même forme et les mêmes clés de verset (cf.
  /// `benchmark/build_warsh_verses_asset.py`), donc rien en aval ne change.
  static String get _versesAsset => switch (_riwaya) {
    Riwaya.hafs => 'assets/data/quran_verses.json',
    Riwaya.warsh => 'assets/data/quran_verses_warsh.json',
  };

  static Verse _parseVerse(Map<String, dynamic> map) {
    final verse = Verse.fromJson(map);
    final translations = map['translations'] as List?;
    return Verse(
      surahNumber: verse.surahNumber,
      ayahNumber: verse.ayahNumber,
      textUthmani: verse.textUthmani,
      textUthmaniTajweed: map['text_uthmani_tajweed'] as String?,
      pageNumber: verse.pageNumber,
      hizbNumber: verse.hizbNumber,
      rubElHizbNumber: verse.rubElHizbNumber,
      juzNumber: verse.juzNumber,
      sajdahNumber: verse.sajdahNumber,
      translationFr: translations?.isNotEmpty == true
          ? translations!.first['text'] as String?
          : null,
    );
  }

  /// Charge et indexe les deux assets une seule fois (idempotent, réutilisé
  /// par tous les appels ci-dessous -- même contenu qu'un appel réseau
  /// aurait renvoyé, juste lu depuis l'APK au lieu de `api.quran.com`).
  static Future<void> _ensureLoaded() {
    // BUG 1 corrige : les DEUX caches doivent etre prets, pas seulement
    // `_chapters`. Tant que l'un des deux manque, on rejoint le chargement en
    // cours via `_loading ??=` plus bas -- jamais un retour premature.
    if (_chapters != null && _versesBySurah != null) return Future.value();
    // Capture au moment de l'APPEL, pas a la publication : c'est CETTE
    // tentative de chargement qu'on veut pouvoir invalider si la riwaya
    // bascule pendant qu'elle est en vol.
    final generationDemandee = _generation;
    // Meme raison : figer QUELLE riwaya ce chargement sert, plutot que relire
    // `_versesAsset` (donc `_riwaya`, mutable) une fois l'attente reseau/
    // disque passee -- sans quoi une bascule pendant le chargement ferait lire
    // le mauvais fichier pour la generation qu'on croit servir.
    final versesAssetCible = _versesAsset;
    return _loading ??= () async {
      final chaptersRaw =
          json.decode(
                await rootBundle.loadString('assets/data/quran_chapters.json'),
              )
              as List;
      final chapters = chaptersRaw
          .map((e) => Surah.fromJson(e as Map<String, dynamic>))
          .toList();

      final versesRaw =
          json.decode(await rootBundle.loadString(versesAssetCible)) as List;
      final bySurah = <int, List<Verse>>{};
      final byPage = <int, List<Verse>>{};
      for (final v in versesRaw) {
        final verse = _parseVerse(v as Map<String, dynamic>);
        bySurah.putIfAbsent(verse.surahNumber, () => []).add(verse);
        if (verse.pageNumber != null) {
          byPage.putIfAbsent(verse.pageNumber!, () => []).add(verse);
        }
      }
      // BUG 2 corrige : publication ATOMIQUE, et seulement si rien n'a
      // change pendant l'attente. Une riwaya basculee entre-temps a deja
      // incremente `_generation` (cf. le setter) -- ce resultat, obtenu pour
      // l'ancienne generation, est alors jete plutot que publie a tort.
      if (generationDemandee != _generation) return;
      _chapters = chapters;
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

  // ── UNE TROISIEME COURSE, TROUVEE EN VERIFIANT LE CORRECTIF (2026-09-09)
  //
  // Le correctif ci-dessus (generation + publication atomique) supprime les
  // deux bugs du rapport, MAIS un test qui le rejoue exactement plantait
  // encore -- verifie par execution, pas suppose corrige sur relecture du
  // code. Sa trace montrait le vrai coupable : entre le moment ou
  // `_ensureLoaded()` rend un `Future.value()` (chemin rapide, cache deja
  // rempli) et le moment ou l'appelant reprend la main pour LIRE ce cache,
  // une bascule de riwaya SYNCHRONE peut s'intercaler et le nuller. Le
  // `await` ne protege que contre la course sur le CHARGEMENT ; il ne protege
  // pas la LECTURE qui le suit.
  //
  // `_versesCharges()`/`_chapitresCharges()` ferment cette fenetre en ne
  // retournant JAMAIS une reference qui pourrait avoir ete nullee entre-temps
  // -- elles relisent la variable locale immediatement apres l'attente, et
  // rechargent si une bascule s'est glissee dans l'intervalle. Ce n'est pas
  // une boucle sans fin : une bascule est un evenement synchrone rare
  // (geste utilisateur), pas quelque chose qui se reproduit a chaque tour.
  static Future<Map<int, List<Verse>>> _versesCharges() async {
    while (true) {
      await _ensureLoaded();
      final v = _versesBySurah;
      if (v != null) return v;
    }
  }

  static Future<List<Surah>> _chapitresCharges() async {
    while (true) {
      await _ensureLoaded();
      final c = _chapters;
      if (c != null) return c;
    }
  }

  static Future<List<Surah>> fetchSurahs() => _chapitresCharges();

  static Future<List<Verse>> fetchVerses(int surahNumber) async {
    final bySurah = await _versesCharges();
    return bySurah[surahNumber] ?? const [];
  }

  /// Concatène plusieurs plages de versets (potentiellement de sourates
  /// différentes, ex. les trois muʿawwidhāt) en UNE playlist ordonnée, pour
  /// `Dua.verseRanges` (cf. son commentaire). Une plage introuvable/vide est
  /// simplement omise plutôt que de faire échouer toute la playlist.
  static Future<List<Verse>> fetchVerseRanges(
    List<(int surah, int ayahStart, int ayahEnd)> ranges,
  ) async {
    final bySurah = await _versesCharges();
    final result = <Verse>[];
    for (final (surah, start, end) in ranges) {
      final verses = bySurah[surah] ?? const [];
      result.addAll(
        verses.where((v) => v.ayahNumber >= start && v.ayahNumber <= end),
      );
    }
    return result;
  }

  /// Une page du Mushaf standard (1-604) -- utilisé pour l'enchaînement
  /// dynamique entre sourates (KaraokeRecitationScreen._maybeExtendNextPage) :
  /// charger une page à la fois plutôt que la sourate suivante en entier
  /// (une sourate longue comme Al-Baqarah, 286 versets/~6100 mots, chargeait
  /// tout instantanément dès qu'on en approchait -- demande utilisateur
  /// 2026-07-11 : "il faut faire ça dynamiquement, une page avant et une page
  /// après").
  static Future<List<Verse>> fetchVersesByPage(int pageNumber) async {
    while (true) {
      await _ensureLoaded();
      final byPage = _versesByPage;
      if (byPage != null) return byPage[pageNumber] ?? const [];
    }
  }

  static Map<int, List<Verse>>? _warshMushafByPage;
  static Map<int, int>? _warshMushafVerseCounts;

  static int? warshMushafVerseCount(int surahNumber) =>
      _warshMushafVerseCounts?[surahNumber];

  /// Pagination native du Mushaf papier Warsh. Cet index est volontairement
  /// distinct de l'asset de recitation Warsh, dont les cles Hafs restent
  /// necessaires pour faire correspondre les fichiers audio verset par verset.
  static Future<List<Verse>> fetchWarshMushafVersesByPage(
    int pageNumber,
  ) async {
    // Le catalogue alimente les bandeaux. Il est deja charge dans le parcours
    // normal, mais pas lors d'un lancement direct du banc de capture.
    await _ensureLoaded();
    if (_warshMushafByPage == null) {
      final raw =
          json.decode(
                await rootBundle.loadString(
                  'assets/data/quran_mushaf_warsh.json',
                ),
              )
              as List;
      final byPage = <int, List<Verse>>{};
      final counts = <int, int>{};
      for (final item in raw) {
        final verse = _parseVerse(item as Map<String, dynamic>);
        byPage.putIfAbsent(verse.pageNumber!, () => []).add(verse);
        if (verse.ayahNumber > 0) {
          final previous = counts[verse.surahNumber] ?? 0;
          if (verse.ayahNumber > previous) {
            counts[verse.surahNumber] = verse.ayahNumber;
          }
        }
      }
      _warshMushafByPage = byPage;
      _warshMushafVerseCounts = counts;
    }
    return _warshMushafByPage![pageNumber] ?? const [];
  }

  /// Returns all audio file URLs for a surah, keyed by verse_key.
  /// CDN base: https://verses.quran.com/
  static Future<Map<String, String>> fetchSurahAudioUrls(
    int recitationId,
    int surahNumber,
  ) async {
    final r = await _dio.get(
      '/recitations/$recitationId/by_chapter/$surahNumber',
      queryParameters: {'per_page': '286'},
    );
    final files = r.data['audio_files'] as List;
    return {
      for (final f in files)
        f['verse_key'] as String: 'https://verses.quran.com/${f['url']}',
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
    int recitationId,
    String verseKey,
  ) async {
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
          (s) => (s as List).map((e) => (e as num).toInt()).toList(),
        )
        .toList();
  }
}

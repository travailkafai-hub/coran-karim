import 'dart:convert' show json, utf8;
import 'dart:typed_data' show Uint8List;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import '../models/riwaya.dart';
import '../models/verse.dart';
import 'diagnostic_log.dart';

/// Décode l'asset des versets et construit les deux index — exécuté sur un
/// ISOLATE DE FOND via `compute`, jamais sur l'isolate qui dessine.
///
/// Fonction de premier niveau, et pas une méthode d'instance : `compute` exige
/// une cible top-level ou statique (elle doit pouvoir être envoyée à l'isolate
/// par son adresse). Elle ne touche AUCUN état statique de [QuranApi] — un
/// isolate a son propre tas, écrire dans `_versesBySurah` d'ici ne modifierait
/// qu'une copie invisible depuis l'isolate principal. Tout revient par la
/// valeur de retour, et c'est l'appelant qui publie.
(Map<int, List<Verse>>, Map<int, List<Verse>>) _decoderEtIndexer(
    Uint8List octets) {
  final versesRaw = json.decode(utf8.decode(octets)) as List;
  final bySurah = <int, List<Verse>>{};
  final byPage = <int, List<Verse>>{};
  for (final v in versesRaw) {
    final verse = QuranApi.parseVersePourIsolate(v as Map<String, dynamic>);
    bySurah.putIfAbsent(verse.surahNumber, () => []).add(verse);
    if (verse.pageNumber != null) {
      byPage.putIfAbsent(verse.pageNumber!, () => []).add(verse);
    }
  }
  return (bySurah, byPage);
}

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

  /// Même chose que [_parseVerse], exposée pour `_decoderEtIndexer` qui vit
  /// hors de cette classe (contrainte de `compute`, cf. sa doc). Simple
  /// délégation : aucune logique dupliquée — dupliquer le parsing d'un texte
  /// sacré serait le meilleur moyen de laisser diverger deux variantes Unicode
  /// sans que ça se voie (piège déjà payé le 2026-07-09).
  static Verse parseVersePourIsolate(Map<String, dynamic> map) =>
      _parseVerse(map);

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
      // ── INSTRUMENTATION (2026-09-13, audit de performance) ───────────────
      //
      // Cette fonction charge L'INTEGRALITE du Coran -- `quran_verses.json`
      // fait 8,0 Mo (4,4 Mo en Warsh) -- puis le decode et le reindexe, le
      // tout sur l'ISOLATE PRINCIPAL, celui qui dessine. `json.decode` est
      // synchrone et non interruptible : tant qu'il tourne, aucune frame n'est
      // produite et aucun geste n'est traite.
      //
      // Symptome rapporte par l'utilisateur, et qui a mis sur la piste :
      // « la deja suis mushaf papier je n'utilise meme pas ASR ! juste un page
      // de mushaf » -- puis, en regardant les assets : « est ce que c tt le
      // curan qui est charge !! ». Oui. Mesure a l'appui ci-dessous.
      //
      // Les trois etapes sont chronometrees separement parce qu'elles
      // appellent des correctifs differents : la LECTURE de l'asset se
      // deplace en arriere-plan, le DECODAGE aussi, mais l'INDEXATION porte
      // sur des objets Dart et coute surtout des allocations. Un chiffre
      // global ne dirait pas laquelle traiter.
      final tLecture = Stopwatch()..start();
      final chaptersRaw =
          json.decode(
                await rootBundle.loadString('assets/data/quran_chapters.json'),
              )
              as List;
      final chapters = chaptersRaw
          .map((e) => Surah.fromJson(e as Map<String, dynamic>))
          .toList();

      // ── LE GROS DU TRAVAIL PART SUR UN ISOLATE DE FOND (2026-09-13) ──────
      //
      // Mesure qui l'a motive (Redmi Note 9 Pro, build debug) :
      //     lecture=276..623ms decodage=140..172ms indexation=26..34ms
      // soit ~470 ms en regime etabli et ~800 ms a froid, INTEGRALEMENT sur
      // l'isolate principal. `json.decode` est synchrone et non interruptible :
      // pendant ce temps aucune frame n'est produite et aucun geste n'est
      // traite. L'instrument de fluidite voyait la meme chose par l'autre
      // bout -- une frame unique a `PIRE=880,5ms`, `construction p99=878ms`.
      // Effet visible pour l'utilisateur : 12 gestes de tourne de page n'en
      // faisaient avancer que 7, cinq gestes perdus dans le gel.
      //
      // `rootBundle.load` (et non `loadString`) rend des OCTETS sans les
      // decoder : la conversion UTF-8 de 8 Mo, qui etait synchrone sur le
      // thread UI et represente l'essentiel des « 276..623 ms de lecture »,
      // part elle aussi en arriere-plan.
      //
      // `compute` termine par `Isolate.exit`, qui TRANSFERE le resultat au
      // lieu de le copier -- sans quoi on aurait remplace un gel de decodage
      // par un gel de copie de 7 Mo, et rien n'aurait ete gagne.
      //
      // ⚠️ CE QUE CECI NE CORRIGE PAS, et il ne faut pas le presenter
      // autrement : on charge TOUJOURS les 6,67 Mo du Coran entier pour
      // afficher une seule page. L'interface ne gele plus, mais la page met
      // toujours ~470 ms a apparaitre. La correction de fond est le
      // fenetrage par page (N-1/N/N+1 = ~31,5 Ko, facteur 210) demande par
      // l'utilisateur -- cf. `PERFORMANCE.md` §7. Ceci est l'etape A, pas la
      // reponse complete.
      final tLectureOctets = Stopwatch()..start();
      final octets = await rootBundle.load(versesAssetCible);
      tLectureOctets.stop();
      tLecture.stop();
      final tFond = Stopwatch()..start();
      final (chargesBySurah, chargesByPage) = await compute(
          _decoderEtIndexer, octets.buffer.asUint8List());
      tFond.stop();
      final bySurah = chargesBySurah;
      final byPage = chargesByPage;
      DiagnosticLog.log(
          'Perf',
          'QuranApi chargement TOTAL du Coran ($versesAssetCible) : '
              'octets=${tLectureOctets.elapsedMilliseconds}ms '
              'decodage+indexation HORS thread UI=${tFond.elapsedMilliseconds}ms '
              '-> ${bySurah.length} sourates, ${byPage.length} pages '
              '(interface VIVANTE pendant ce temps -- mais le Coran entier est '
              'toujours charge pour une seule page, cf. PERFORMANCE.md §7)');
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
      // Instrumentation jumelle de celle de `_ensureLoaded` (2026-09-13).
      // ⚠️ CE CHEMIN PAIE LES DEUX : le `_ensureLoaded()` juste au-dessus a
      // deja decode l'integralite du Coran Hafs (6,67 Mo), et on enchaine ici
      // sur les 2,0 Mo du Mushaf Warsh. Sans ces deux chronometres cote a
      // cote, impossible de savoir lequel des deux domine -- et la branche
      // `chantier-warsh` est precisement celle ou l'utilisateur constate le
      // ralentissement sur une simple page de Mushaf papier.
      final tWarsh = Stopwatch()..start();
      final brutWarsh =
          await rootBundle.loadString('assets/data/quran_mushaf_warsh.json');
      final tLectureWarsh = tWarsh.elapsedMilliseconds;
      final raw = json.decode(brutWarsh) as List;
      final tDecodageWarsh = tWarsh.elapsedMilliseconds - tLectureWarsh;
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
      tWarsh.stop();
      DiagnosticLog.log(
          'Perf',
          'QuranApi Mushaf WARSH (quran_mushaf_warsh.json) : '
              'lecture=${tLectureWarsh}ms decodage=${tDecodageWarsh}ms '
              'indexation=${tWarsh.elapsedMilliseconds - tLectureWarsh - tDecodageWarsh}ms '
              '-> ${raw.length} versets, ${byPage.length} pages '
              '(S\'AJOUTE au chargement Hafs ci-dessus, meme isolate principal)');
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

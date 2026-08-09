import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/reciter.dart';
import '../models/verse.dart';
import 'diagnostic_log.dart';
import 'quran_api.dart';
import 'reciter_download_service.dart';

/// Lecteur audio DÉDIÉ à la correction automatique (demande utilisateur
/// 2026-07-05) — volontairement séparé du lecteur principal (`AudioPlayerService`,
/// singleton partagé par `PlayerNotifier`/Mushaf) : réutiliser ce singleton
/// déclencherait aussi la logique d'avance de playlist du lecteur principal
/// (`_onComplete` -> `_advance()`) sur un état (`playerState.playlist`) qui n'a
/// rien à voir avec la session de récitation en cours. Instance isolée, un
/// seul rôle : jouer UN verset et signaler la fin.
///
/// Réutilisée depuis 2026-07-24 par le moteur de répétition incrémentale du
/// Coach (`coach_incremental_repeat.dart`) pour jouer l'audio réel du
/// récitateur sur la fenêtre de mots en cours d'apprentissage -- malgré son
/// nom, [playWordRange] n'a rien de spécifique à la correction d'erreur,
/// c'est un lecteur générique "plage de mots" ; ne pas dupliquer ce
/// mécanisme ailleurs.
class WordCorrectionAudio {
  static final _player = AudioPlayer();
  static final _urlCache = <int, Map<String, String>>{};
  static final _segmentsCache = <String, List<List<int>>>{};
  // Fichier MP3 local déjà téléchargé pour segKey ('${reciter.id}:${verse.key}')
  // -- le format (MP3, servi tel quel par verses.quran.com) n'est PAS le
  // problème : le convertir n'aurait réduit ni la taille (déjà compressé) ni
  // le principal coût mesuré (les DEUX appels réseau JSON de métadonnées
  // dans playWordRange, cf. `prefetch`). Le vrai levier est QUAND le
  // téléchargement a lieu : ici, l'audio lui-même est aussi précaché en local
  // pendant la récitation (avant toute erreur), pour que la lecture démarre
  // depuis le disque -- zéro dépendance réseau au moment de la correction --
  // plutôt que de streamer depuis `verses.quran.com` au moment précis où le
  // réseau peut être dégradé.
  static final _fileCache = <String, String>{};
  // Ordre d'insertion (LRU approximatif) -- borne le nombre de clips MP3
  // conservés sur disque pendant une longue session continue (chaque clip
  // fait quelques dizaines à ~200 Ko, pas de quoi remplir le stockage, mais
  // pas de raison d'accumuler indéfiniment sur une récitation de plusieurs
  // heures/sourates).
  static final _fileCacheOrder = <String>[];
  static const _kMaxCachedFiles = 12;
  static final _dio = Dio();

  /// Joue le mot fautif de [verse], entouré d'[wordsBefore] mots avant et
  /// [wordsAfter] mots après (par défaut 1 avant / 0 après = comportement de
  /// la correction automatique) — PAS tout le verset (demande utilisateur
  /// 2026-07-05 : "rester sur le mot en lui-même... ne pas continuer, c'est
  /// au réciteur de se souvenir de la suite"). [wordsBefore]/[wordsAfter]
  /// réglables (demande utilisateur 2026-07-06 : "choisir" combien de mots
  /// entourent le mot tapé, pour l'écoute manuelle). [errorWordIndex] est la
  /// position 0-based du mot fautif DANS ce verset. Découpe l'audio réel du
  /// récitateur au bon endroit grâce aux segments de timing officiels
  /// (`QuranApi.fetchAyahSegments`) plutôt que d'estimer une découpe
  /// approximative. Ne jette pas si l'audio ou le timing sont introuvables
  /// (retourne simplement immédiatement).
  /// Joue un fichier local ENTIER et attend la fin — sert à rejouer la VOIX DU
  /// RÉCITATEUR extraite du flux brut (2026-08-06, cf.
  /// `FastConformerCtcVerifier.v2ExtraitVoix`).
  ///
  /// Passe par le MÊME lecteur statique que [playWordRange] : les deux ne
  /// doivent jamais jouer en parallèle (un seul haut-parleur, et surtout un
  /// seul jeu d'abonnements — piège déjà payé le 2026-07-16 entre correction
  /// automatique et souffleur).
  static Future<void> playFile(String path) async {
    DiagnosticLog.log('Voix', 'lecture extrait : $path');
    await _player.stop();
    final completer = Completer<void>();
    late final StreamSubscription doneSub;
    doneSub = _player.onPlayerComplete.listen((_) {
      doneSub.cancel();
      if (!completer.isCompleted) completer.complete();
    });
    await _player.play(DeviceFileSource(path));
    // Garde-fou : un extrait fait au plus quelques secondes. Sans borne, une
    // fin de lecture jamais notifiée laisserait le bouton bloqué.
    await completer.future.timeout(const Duration(seconds: 15), onTimeout: () {
      doneSub.cancel();
    });
  }

  static Future<void> playWordRange(
    Verse verse,
    Reciter reciter, {
    required int errorWordIndex,
    /// Fraction de la duree jouee (1.0 = tout). Demande utilisateur
    /// 2026-08-07 : « l'audio de repetition est un peu long, reduis de 20 % ».
    /// On rogne la FIN, jamais le debut : c'est le depart du passage qui
    /// permet de le reconnaitre. Plancher a 800 ms pour ne pas rendre un
    /// souffle inaudible sur une plage deja courte.
    double facteurDuree = 1.0,
    int wordsBefore = 1,
    int wordsAfter = 0,
  }) async {
    final segKey = '${reciter.id}:${verse.key}';
    // ── AUDIO TÉLÉCHARGÉ D'ABORD (2026-08-01) ─────────────────────────────
    // AVANT : ce service appelait `fetchSurahAudioUrls` (RÉSEAU) en tout
    // premier et abandonnait en silence sur `url == null` -- même quand le
    // récitateur avait DÉJÀ téléchargé la sourate. Symptôme rapporté par
    // l'utilisateur : « les deux corrections sont activées, je fais des
    // erreurs, je n'entends aucun audio » -- aucune erreur affichée, aucune
    // trace, d'où l'impression que « les audios ne sont plus là ».
    // Le lecteur du Mushaf (`audio_player_service.dart`) consultait pourtant
    // déjà `ReciterDownloadService.localPathIfPresent` ; ce service, lui, ne
    // connaissait que son propre cache MÉMOIRE de session (`_fileCache`,
    // rempli par `prefetch`), perdu à chaque redémarrage.
    // Demande explicite : « favoriser les audios qui sont en local au lieu de
    // chercher par API ».
    final telecharge = ReciterDownloadService().localPathIfPresent(reciter.id, verse);
    String? url;
    if (telecharge == null) {
      _urlCache[verse.surahNumber] ??=
          await QuranApi.fetchSurahAudioUrls(reciter.id, verse.surahNumber);
      url = _urlCache[verse.surahNumber]?[verse.key];
      if (url == null) {
        // Journalisé : cet abandon était MUET, ce qui rendait la panne
        // indiagnosticable côté utilisateur comme côté log.
        DiagnosticLog.log('Correction-Audio',
            'ABANDON verset=${verse.key} : aucun fichier local ET aucune URL '
            '(réseau indisponible ou récitateur ${reciter.id} sans audio) '
            '-> pas de correction audible');
        return;
      }
    }

    final segments = _segmentsCache[segKey] ??=
        await QuranApi.fetchAyahSegments(reciter.id, verse.key);
    // Pas de timing dispo pour ce récitateur/verset -> on abandonne plutôt
    // que de rejouer tout le verset par défaut (contredirait la demande).
    // Journalisé depuis le 2026-08-01 : SECOND point d'abandon muet, et
    // second appel réseau -- avoir le MP3 en local ne suffit donc pas encore,
    // il faut aussi ces timings (mis en cache mémoire seulement). Si cette
    // ligne apparaît souvent dans les logs, c'est ici qu'il faudra
    // persister/embarquer les segments.
    if (segments.isEmpty) {
      DiagnosticLog.log('Correction-Audio',
          'ABANDON verset=${verse.key} : timings mot-à-mot indisponibles '
          '(récitateur ${reciter.id}) -> pas de correction audible');
      return;
    }

    final fromIdx =
        (errorWordIndex - wordsBefore).clamp(0, errorWordIndex);
    final toIdx = errorWordIndex + wordsAfter;
    final startSeg = segments.firstWhere((s) => s[0] == fromIdx,
        orElse: () => segments.first);
    final endSeg = segments.firstWhere((s) => s[0] == toIdx,
        orElse: () => segments.last);
    final startMs = startSeg[2];
    var endMs = endSeg[3];
    if (facteurDuree < 1.0 && endMs > startMs) {
      final pleine = endMs - startMs;
      final reduite = (pleine * facteurDuree).round();
      endMs = startMs + (reduite < 800 ? (pleine < 800 ? pleine : 800) : reduite);
    }
    // Priorité : (1) sourate TÉLÉCHARGÉE par l'utilisateur, (2) précache
    // mémoire de la session (cf. `prefetch`), (3) streaming direct.
    // (1) est nouveau (2026-08-01) -- cf. commentaire en tête de fonction.
    // Ne JAMAIS attendre un téléchargement ici, ce serait aussi lent que
    // l'ancien chemin.
    final localPath = telecharge ?? _fileCache[segKey];
    final source =
        localPath != null ? DeviceFileSource(localPath) : UrlSource(url!);
    DiagnosticLog.log('Correction-Audio', 'verset=${verse.key} '
        'errorWordIndex=$errorWordIndex (mot attendu local) '
        'fromIdx=$fromIdx toIdx=$toIdx '
        'startSeg=$startSeg endSeg=$endSeg '
        'startMs=$startMs endMs=$endMs '
        'source=${telecharge != null ? "telecharge($telecharge)" : localPath != null ? "precache($localPath)" : "url($url)"}');

    final completer = Completer<void>();
    late final StreamSubscription posSub;
    late final StreamSubscription doneSub;
    void finish() {
      posSub.cancel();
      doneSub.cancel();
      if (!completer.isCompleted) completer.complete();
    }

    posSub = _player.onPositionChanged.listen((pos) {
      if (pos.inMilliseconds >= endMs) {
        _player.pause();
        finish();
      }
    });
    doneSub = _player.onPlayerComplete.listen((_) => finish());

    await _player.play(source, position: Duration(milliseconds: startMs));
    // Garde-fou : si ni la position ni la fin de lecture ne se déclenchent
    // (URL corrompue, lecteur bloqué), ne pas bloquer la reprise indéfiniment.
    return completer.future.timeout(const Duration(seconds: 15), onTimeout: () {
      posSub.cancel();
      doneSub.cancel();
      _player.pause();
    });
  }

  /// Joue exactement les mots [startWordIdx]..[endWordIdx] (inclus) --
  /// wrapper de lisibilité au-dessus de [playWordRange] pour le moteur de
  /// répétition incrémentale (fenêtre de mots à apprendre), qui n'a pas de
  /// notion de "mot fautif" mais veut une plage explicite.
  static Future<void> playWordWindow(
    Verse verse,
    Reciter reciter, {
    required int startWordIdx,
    required int endWordIdx,
  }) =>
      playWordRange(
        verse,
        reciter,
        errorWordIndex: endWordIdx,
        wordsBefore: endWordIdx - startWordIdx,
        wordsAfter: 0,
      );

  /// Préchauffe les caches réseau (URLs audio du récitateur + segments de
  /// timing du verset) AVANT qu'une erreur ne survienne (demande utilisateur
  /// 2026-07-11 : "en cas d'erreur ça prend beaucoup de temps pour réagir").
  /// Log natif corrélé au moment de l'écriture de ce fix : le fetch À LA
  /// DEMANDE dans [playWordRange] (`fetchSurahAudioUrls`/`fetchAyahSegments`,
  /// jamais préchargés) coûtait 4,5 à 9,2 s sur un réseau dégradé -- capture
  /// déjà en pause tout ce temps, sans le moindre retour utilisateur. Appelé
  /// dès qu'un nouveau verset devient "courant" pendant la récitation (avant
  /// toute erreur), pour que le cache soit déjà chaud le temps qu'une
  /// correction soit éventuellement nécessaire sur CE verset. Best-effort :
  /// une erreur ici (réseau) est silencieusement ignorée -- [playWordRange]
  /// retente son propre fetch si le cache n'a pas eu le temps de se remplir.
  static Future<void> prefetch(Verse verse, Reciter reciter) async {
    final segKey = '${reciter.id}:${verse.key}';
    try {
      _urlCache[verse.surahNumber] ??=
          await QuranApi.fetchSurahAudioUrls(reciter.id, verse.surahNumber);
      final url = _urlCache[verse.surahNumber]?[verse.key];
      _segmentsCache[segKey] ??=
          await QuranApi.fetchAyahSegments(reciter.id, verse.key);
      if (url != null && !_fileCache.containsKey(segKey)) {
        await _downloadToCache(segKey, url);
      }
    } catch (_) {
      // best-effort -- playWordRange retentera son propre fetch/streaming si
      // le cache n'a pas eu le temps de se remplir.
    }
  }

  /// Télécharge [url] vers un fichier local et l'enregistre sous [segKey]
  /// dans `_fileCache`, en évinçant le plus ancien au-delà de
  /// `_kMaxCachedFiles` (borne le disque sur une longue session continue).
  static Future<void> _downloadToCache(String segKey, String url) async {
    final dir = await getTemporaryDirectory();
    final safeName = segKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '${dir.path}/word_correction_cache/$safeName.mp3';
    await Directory('${dir.path}/word_correction_cache').create(recursive: true);
    await _dio.download(url, path);
    _fileCache[segKey] = path;
    _fileCacheOrder.remove(segKey);
    _fileCacheOrder.add(segKey);
    while (_fileCacheOrder.length > _kMaxCachedFiles) {
      final evicted = _fileCacheOrder.removeAt(0);
      final evictedPath = _fileCache.remove(evicted);
      if (evictedPath != null) {
        try {
          await File(evictedPath).delete();
        } catch (_) {}
      }
    }
  }

  static Future<void> stop() => _player.stop();
}

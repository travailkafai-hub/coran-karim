import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import '../models/reciter.dart';
import '../models/verse.dart';
import 'quran_api.dart';

/// Lecteur audio DÉDIÉ à la correction automatique (demande utilisateur
/// 2026-07-05) — volontairement séparé du lecteur principal (`AudioPlayerService`,
/// singleton partagé par `PlayerNotifier`/Mushaf) : réutiliser ce singleton
/// déclencherait aussi la logique d'avance de playlist du lecteur principal
/// (`_onComplete` -> `_advance()`) sur un état (`playerState.playlist`) qui n'a
/// rien à voir avec la session de récitation en cours. Instance isolée, un
/// seul rôle : jouer UN verset et signaler la fin.
class WordCorrectionAudio {
  static final _player = AudioPlayer();
  static final _urlCache = <int, Map<String, String>>{};
  static final _segmentsCache = <String, List<List<int>>>{};

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
  static Future<void> playWordRange(
    Verse verse,
    Reciter reciter, {
    required int errorWordIndex,
    int wordsBefore = 1,
    int wordsAfter = 0,
  }) async {
    _urlCache[verse.surahNumber] ??=
        await QuranApi.fetchSurahAudioUrls(reciter.id, verse.surahNumber);
    final url = _urlCache[verse.surahNumber]?[verse.key];
    if (url == null) return;

    final segKey = '${reciter.id}:${verse.key}';
    final segments = _segmentsCache[segKey] ??=
        await QuranApi.fetchAyahSegments(reciter.id, verse.key);
    // Pas de timing dispo pour ce récitateur/verset -> on abandonne plutôt
    // que de rejouer tout le verset par défaut (contredirait la demande).
    if (segments.isEmpty) return;

    final fromIdx =
        (errorWordIndex - wordsBefore).clamp(0, errorWordIndex);
    final toIdx = errorWordIndex + wordsAfter;
    final startSeg = segments.firstWhere((s) => s[0] == fromIdx,
        orElse: () => segments.first);
    final endSeg = segments.firstWhere((s) => s[0] == toIdx,
        orElse: () => segments.last);
    final startMs = startSeg[2];
    final endMs = endSeg[3];

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

    await _player.play(UrlSource(url), position: Duration(milliseconds: startMs));
    // Garde-fou : si ni la position ni la fin de lecture ne se déclenchent
    // (URL corrompue, lecteur bloqué), ne pas bloquer la reprise indéfiniment.
    return completer.future.timeout(const Duration(seconds: 15), onTimeout: () {
      posSub.cancel();
      doneSub.cancel();
      _player.pause();
    });
  }

  static Future<void> stop() => _player.stop();
}

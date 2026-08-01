import 'package:audioplayers/audioplayers.dart';
import '../models/verse.dart';
import '../models/reciter.dart';
import '../models/player_state_model.dart';
import 'quran_api.dart';
import 'reciter_download_service.dart';

/// Singleton audio service wrapping audioplayers.
/// Manages one AudioPlayer instance for the whole app lifetime.
class AudioPlayerService {
  static final AudioPlayerService _i = AudioPlayerService._();
  factory AudioPlayerService() => _i;
  AudioPlayerService._();

  final _player = AudioPlayer();

  // Cached audio URLs: surahNumber → { verse_key → url }
  final _urlCache = <int, Map<String, String>>{};

  Stream<Duration> get positionStream => _player.onPositionChanged;
  Stream<Duration> get durationStream =>
      _player.onDurationChanged.map((d) => d ?? Duration.zero);
  Stream<void> get onComplete => _player.onPlayerComplete;
  Stream<PlayerState> get stateStream => _player.onPlayerStateChanged;

  Future<void> preloadSurah(int recitationId, int surahNumber) async {
    if (_urlCache.containsKey(surahNumber)) return;
    _urlCache[surahNumber] =
        await QuranApi.fetchSurahAudioUrls(recitationId, surahNumber);
  }

  Future<bool> playVerse(Verse verse, Reciter reciter) async {
    // Sourate téléchargée : on ne touche AUCUNEMENT au réseau -- ni pour
    // l'audio, ni pour la liste d'URLs (`preloadSurah` est lui aussi un appel
    // HTTP). C'est ce qui supprime la fenêtre pendant laquelle un appui sur
    // pause restait sans effet : diagnostic du 2026-07-28, la lecture était
    // 100 % en streaming (`UrlSource`), donc chaque `play()` traversait deux
    // aller-retours réseau pendant lesquels `togglePlayPause` ne faisait rien
    // (statut `loading`) et une lecture en vol pouvait démarrer APRÈS le pause.
    // En local la lecture démarre immédiatement, la fenêtre disparaît.
    final local =
        ReciterDownloadService().localPathIfPresent(reciter.id, verse);
    if (local != null) {
      await _player.play(DeviceFileSource(local));
      return true;
    }
    await preloadSurah(reciter.id, verse.surahNumber);
    final url = _urlCache[verse.surahNumber]?[verse.key];
    if (url == null) return false;
    await _player.play(UrlSource(url));
    return true;
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.resume();
  Future<void> stop() => _player.stop();

  Future<void> setSpeed(double rate) => _player.setPlaybackRate(rate);
  Future<void> seek(Duration pos) => _player.seek(pos);

  void dispose() => _player.dispose();
}

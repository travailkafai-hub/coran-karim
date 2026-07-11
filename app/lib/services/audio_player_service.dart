import 'package:audioplayers/audioplayers.dart';
import '../models/verse.dart';
import '../models/reciter.dart';
import '../models/player_state_model.dart';
import 'quran_api.dart';

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

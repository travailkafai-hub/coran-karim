import 'package:audioplayers/audioplayers.dart';

/// Lecteur dédié à l'audio des invocations hadith (URL externe
/// hisnmuslim.com), séparé du lecteur partagé `playerProvider`.
///
/// VOLONTAIREMENT SÉPARÉ (2026-08-07) : `playerProvider`/`PlayerNotifier` est
/// bâti entièrement autour du modèle `Verse` (sourate, réciteur, playlist,
/// boucles imbriquées groupe/global — cf. les commentaires de
/// `player_provider.dart` sur les bugs déjà corrigés à la dure dans cette
/// machine à états). Une invocation hadith n'a ni sourate ni réciteur ;
/// détourner ce lecteur pour y faire transiter une simple URL MP3 externe
/// aurait obligé à toucher un code fragile pour un besoin qui n'a rien à voir.
/// Même schéma de singleton que `ExplanationTtsService` (callbacks assignés
/// par l'appelant courant, pas de flux Riverpod dédié).
class DuaAudioService {
  static DuaAudioService? _instance;
  static DuaAudioService get instance => _instance ??= DuaAudioService._();
  DuaAudioService._() {
    _player.onPlayerComplete.listen((_) => _onComplete());
  }

  final AudioPlayer _player = AudioPlayer();
  int _repeatTarget = 1;
  int _repeatDone = 0;
  Source? _currentSource;
  // Identité stable de la lecture en cours pour les callbacks -- une `Source`
  // (UrlSource/AssetSource) n'a pas d'égalité pratique à comparer, donc
  // l'appelant fournit une CLÉ (ex. `dua.audioAsset ?? dua.audioUrl`) que ce
  // service se contente de faire transiter telle quelle.
  String? _currentKey;

  /// Appelé à chaque répétition franchie, avec la clé concernée -- l'appelant
  /// vérifie que c'est bien SA clé avant d'agir (le service est un singleton
  /// partagé par tous les écrans d'invocations à la fois).
  void Function(String key, int done, int target)? onProgress;
  void Function(String key)? onFinished;
  void Function(String key, Object error)? onError;

  String? get currentKey => _currentKey;
  int get repeatDone => _repeatDone;
  int get repeatTarget => _repeatTarget;

  Future<void> play(Source source, {required String key, int repeat = 1}) async {
    await _player.stop();
    _currentSource = source;
    _currentKey = key;
    _repeatTarget = repeat < 1 ? 1 : repeat;
    _repeatDone = 0;
    try {
      await _player.play(source);
    } catch (e) {
      _currentSource = null;
      _currentKey = null;
      onError?.call(key, e);
    }
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.resume();

  Future<void> stop() async {
    await _player.stop();
    _currentSource = null;
    _currentKey = null;
    _repeatDone = 0;
  }

  void _onComplete() {
    final key = _currentKey;
    final source = _currentSource;
    if (key == null || source == null) return; // stop() venait de tourner la page
    final done = _repeatDone + 1;
    if (done < _repeatTarget) {
      _repeatDone = done;
      onProgress?.call(key, _repeatDone, _repeatTarget);
      _player.play(source);
    } else {
      _repeatDone = done;
      _currentSource = null;
      _currentKey = null;
      onProgress?.call(key, done, _repeatTarget);
      onFinished?.call(key);
    }
  }

  Stream<PlayerState> get stateStream => _player.onPlayerStateChanged;
}

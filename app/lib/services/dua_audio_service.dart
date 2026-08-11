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
    _player.onPlayerComplete.listen((_) => _occurrenceTerminee());
    // Coupe pilotée par la POSITION DE LECTURE et non par une minuterie : la
    // source est une URL distante, donc la lecture peut se mettre en tampon.
    // Une minuterie murale dériverait ou se déclencherait pendant un blocage ;
    // la position, elle, ne bouge que quand du son sort.
    _player.onPositionChanged.listen((p) {
      final coupe = _cutMs;
      if (coupe == null || _coupeDeclenchee) return;
      if (p.inMilliseconds >= coupe) {
        _coupeDeclenchee = true;
        _occurrenceTerminee();
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();
  int _repeatTarget = 1;
  int _repeatDone = 0;
  Source? _currentSource;

  /// Position d'arrêt d'une écoute, cf. [play]. `null` = lire jusqu'au bout.
  int? _cutMs;

  /// Empêche la coupe de se déclencher plusieurs fois sur la même occurrence :
  /// `onPositionChanged` émet en continu, et toutes les positions au-delà du
  /// seuil satisfont la condition.
  var _coupeDeclenchee = false;
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

  /// [cutMs] : arrêter chaque écoute à cette position, au lieu d'aller au bout
  /// du fichier.
  ///
  /// ── POURQUOI CE PARAMÈTRE EXISTE (2026-08-10) ────────────────────────────
  /// Onze fichiers de hisnmuslim.com enchaînent la MÊME invocation quatre ou
  /// cinq fois de suite (le tahlīl : 32 s pour cinq occurrences). Le bouton
  /// « Écouter » n'en a besoin que d'une -- et l'app gère elle-même la
  /// répétition, via [repeat].
  ///
  /// La version du 2026-08-09 réglait ça en embarquant des copies DÉCOUPÉES de
  /// leurs fichiers dans l'APK (`assets/audio/duas/*_cut.mp3`). Retiré le
  /// 2026-08-10 : redistribuer une œuvre dérivée d'un enregistrement dont on
  /// n'a aucune licence était le risque juridique le plus net de l'app, et un
  /// test fermé sur Play reste une distribution.
  ///
  /// Ici on ne copie plus rien : on lit LEUR fichier depuis LEUR serveur, et on
  /// s'arrête au bout d'une occurrence. Seule une DURÉE est conservée dans le
  /// code -- une mesure, pas une œuvre.
  Future<void> play(Source source,
      {required String key, int repeat = 1, int? cutMs}) async {
    await _player.stop();
    _currentSource = source;
    _currentKey = key;
    _repeatTarget = repeat < 1 ? 1 : repeat;
    _repeatDone = 0;
    _cutMs = (cutMs != null && cutMs > 0) ? cutMs : null;
    _coupeDeclenchee = false;
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

  /// Une occurrence vient de se terminer — soit parce que le fichier est fini,
  /// soit parce qu'on a atteint [_cutMs].
  void _occurrenceTerminee() {
    final key = _currentKey;
    final source = _currentSource;
    if (key == null || source == null) return; // stop() venait de tourner la page
    final done = _repeatDone + 1;
    if (done < _repeatTarget) {
      _repeatDone = done;
      onProgress?.call(key, _repeatDone, _repeatTarget);
      if (_cutMs != null) {
        // Revenir au début plutôt que relancer la source : `play()` sur une URL
        // relance le téléchargement, alors qu'un `seek(0)` réutilise ce qui est
        // déjà en tampon. Sur une invocation répétée cent fois, la différence
        // n'est pas cosmétique.
        _coupeDeclenchee = false;
        _player.seek(Duration.zero);
        _player.resume();
      } else {
        _player.play(source);
      }
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

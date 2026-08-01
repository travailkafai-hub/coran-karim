import 'verse.dart';
import 'reciter.dart';

enum RepeatMode { off, verse, surah }
enum PlayerStatus { idle, loading, playing, paused, error }

class PlayerStateModel {
  final Verse? currentVerse;
  final List<Verse> playlist;
  final int currentIndex;
  final PlayerStatus status;
  final RepeatMode repeatMode;
  final int repeatCount;    // 0 = infinite, 1-10 = N times
  final int repeatDone;     // how many repetitions completed
  final double speed;
  final Reciter reciter;
  final Duration position;
  final Duration duration;
  final String? error;

  const PlayerStateModel({
    this.currentVerse,
    this.playlist = const [],
    this.currentIndex = 0,
    this.status = PlayerStatus.idle,
    this.repeatMode = RepeatMode.off,
    this.repeatCount = 1,
    this.repeatDone = 0,
    this.speed = 1.0,
    this.reciter = kDefaultReciter,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.error,
  });

  bool get isPlaying => status == PlayerStatus.playing;
  bool get isPaused => status == PlayerStatus.paused;
  bool get isActive => status == PlayerStatus.playing || status == PlayerStatus.paused;
  bool get hasVerse => currentVerse != null;

  Verse? get nextVerse {
    if (currentIndex + 1 < playlist.length) return playlist[currentIndex + 1];
    return null;
  }
  Verse? get prevVerse {
    if (currentIndex > 0) return playlist[currentIndex - 1];
    return null;
  }

  /// Sentinelle « argument non fourni », pour les champs NULLABLES.
  ///
  /// Sans elle, `error: error ?? this.error` rendait `error` et `currentVerse`
  /// **impossibles à effacer** : le `error: null` de `PlayerNotifier.play()`
  /// ne remettait rien à zéro, donc un « Audio introuvable » survenu une fois
  /// collait pour toute la vie de l'app et faussait ensuite tout diagnostic de
  /// l'état du lecteur (constaté 2026-07-28). Les champs non-nullables gardent
  /// le `??`, qui est correct pour eux.
  static const _unset = Object();

  PlayerStateModel copyWith({
    Object? currentVerse = _unset,
    List<Verse>? playlist,
    int? currentIndex,
    PlayerStatus? status,
    RepeatMode? repeatMode,
    int? repeatCount,
    int? repeatDone,
    double? speed,
    Reciter? reciter,
    Duration? position,
    Duration? duration,
    Object? error = _unset,
  }) => PlayerStateModel(
    currentVerse: identical(currentVerse, _unset)
        ? this.currentVerse
        : currentVerse as Verse?,
    playlist: playlist ?? this.playlist,
    currentIndex: currentIndex ?? this.currentIndex,
    status: status ?? this.status,
    repeatMode: repeatMode ?? this.repeatMode,
    repeatCount: repeatCount ?? this.repeatCount,
    repeatDone: repeatDone ?? this.repeatDone,
    speed: speed ?? this.speed,
    reciter: reciter ?? this.reciter,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    error: identical(error, _unset) ? this.error : error as String?,
  );
}

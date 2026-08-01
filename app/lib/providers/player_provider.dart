import 'dart:async';
import 'package:audioplayers/audioplayers.dart' show PlayerState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/verse.dart';
import '../models/reciter.dart';
import '../models/player_state_model.dart';
import '../services/audio_player_service.dart';

const _kPrefReciterId = 'preferred_reciter_id';

final playerProvider =
    StateNotifierProvider<PlayerNotifier, PlayerStateModel>((ref) {
  return PlayerNotifier(AudioPlayerService());
});

class PlayerNotifier extends StateNotifier<PlayerStateModel> {
  final AudioPlayerService _svc;
  late final List<StreamSubscription> _subs;

  PlayerNotifier(this._svc) : super(const PlayerStateModel()) {
    _restoreReciter();
    _subs = [
      _svc.positionStream.listen((p) => state = state.copyWith(position: p)),
      _svc.durationStream.listen((d) => state = state.copyWith(duration: d)),
      _svc.onComplete.listen((_) => _onComplete()),
      _svc.stateStream.listen((ps) {
        if (ps == PlayerState.playing) {
          state = state.copyWith(status: PlayerStatus.playing);
        } else if (ps == PlayerState.paused) {
          state = state.copyWith(status: PlayerStatus.paused);
        }
      }),
    ];
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    super.dispose();
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  // `auto: true` = enchaînement automatique interne (verset suivant en
  // lecture continue/répétition, cf. _advance) -- PAS un tap utilisateur. Sans
  // ce paramètre, chaque changement de verset repassait par
  // `PlayerStatus.loading` un court instant, ce qui faisait clignoter l'icône
  // play/pause (isPlaying devient faux le temps du "loading") à chaque
  // verset -- symptôme utilisateur "flash de changement d'état" 2026-08-01.
  // On garde `playing` pendant la transition auto ; un tap manuel garde le
  // passage par `loading` (légitime, la lecture vient tout juste de démarrer).
  Future<void> play(Verse verse, List<Verse> playlist,
      {Reciter? reciter, bool auto = false}) async {
    final rc = reciter ?? state.reciter;
    final idx = playlist.indexWhere((v) => v.key == verse.key);
    state = state.copyWith(
      currentVerse: verse,
      playlist: playlist,
      currentIndex: idx < 0 ? 0 : idx,
      status: auto ? PlayerStatus.playing : PlayerStatus.loading,
      reciter: rc,
      position: Duration.zero,
      duration: Duration.zero,
      repeatDone: 0,
      error: null,
    );
    final ok = await _svc.playVerse(verse, rc);
    if (!ok) {
      state = state.copyWith(
          status: PlayerStatus.error, error: 'Audio introuvable');
    }
  }

  Future<void> pause() async {
    await _svc.pause();
    state = state.copyWith(status: PlayerStatus.paused);
  }

  Future<void> resume() async {
    await _svc.resume();
    state = state.copyWith(status: PlayerStatus.playing);
  }

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await pause();
    } else if (state.isPaused) {
      await resume();
    }
  }

  Future<void> stop() async {
    await _svc.stop();
    state = state.copyWith(status: PlayerStatus.idle);
  }

  Future<void> next() async {
    final next = state.nextVerse;
    if (next != null) await play(next, state.playlist);
  }

  Future<void> prev() async {
    // If well into the verse, restart it; else go to previous
    if (state.position.inSeconds > 3) {
      await _svc.seek(Duration.zero);
    } else {
      final prev = state.prevVerse;
      if (prev != null) await play(prev, state.playlist);
    }
  }

  Future<void> seek(Duration pos) => _svc.seek(pos);

  // ── Settings ──────────────────────────────────────────────────────────────

  void setRepeatMode(RepeatMode mode) =>
      state = state.copyWith(repeatMode: mode, repeatDone: 0);

  void setRepeatCount(int count) =>
      state = state.copyWith(repeatCount: count, repeatDone: 0);

  Future<void> setSpeed(double speed) async {
    await _svc.setSpeed(speed);
    state = state.copyWith(speed: speed);
  }

  /// Le réciteur choisi est persisté : c'est le "réciteur préféré" utilisé
  /// partout (lecture Mushaf, fiche tajwid du Contrôle…) et il survit au
  /// redémarrage de l'app.
  void setReciter(Reciter reciter) {
    state = state.copyWith(reciter: reciter);
    SharedPreferences.getInstance()
        .then((p) => p.setInt(_kPrefReciterId, reciter.id));
  }

  Future<void> _restoreReciter() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_kPrefReciterId);
    if (id == null) return;
    final saved = kReciters.where((r) => r.id == id);
    if (saved.isNotEmpty && mounted) {
      state = state.copyWith(reciter: saved.first);
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _onComplete() {
    // `onPlayerComplete` arrive AUSSI quand l'utilisateur vient de mettre en
    // pause ou d'arrêter dans les derniers instants du verset : sans ce
    // garde-fou, la pause était immédiatement suivie d'une relance automatique
    // -- l'audio repartait tout seul (bug constaté 2026-07-28). On ne
    // poursuit que si la lecture était réellement en cours ; le plugin laisse
    // le statut à `playing` en fin de piste (l'événement `completed` n'est pas
    // écouté), donc l'enchaînement normal passe bien ce test.
    if (state.status != PlayerStatus.playing) return;
    final current = state.currentVerse;
    if (current == null) return; // `state.currentVerse!` levait ici
    switch (state.repeatMode) {
      case RepeatMode.verse:
        final done = state.repeatDone + 1;
        final limit = state.repeatCount; // 0 = infinite
        if (limit == 0 || done < limit) {
          state = state.copyWith(repeatDone: done, position: Duration.zero);
          _svc.playVerse(current, state.reciter);
        } else {
          // Repeat done → advance to next
          state = state.copyWith(repeatDone: 0);
          _advance();
        }
      case RepeatMode.surah:
        _advance(loop: true);
      case RepeatMode.off:
        _advance();
    }
  }

  void _advance({bool loop = false}) {
    final next = state.currentIndex + 1;
    if (next < state.playlist.length) {
      play(state.playlist[next], state.playlist, auto: true);
    } else if (loop) {
      play(state.playlist[0], state.playlist, auto: true);
    } else {
      state = state.copyWith(status: PlayerStatus.idle);
    }
  }
}

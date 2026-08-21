import 'dart:async';
import 'package:audioplayers/audioplayers.dart' show PlayerState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/verse.dart';
import '../models/reciter.dart';
import '../models/player_state_model.dart';
import '../services/audio_player_service.dart';
import '../services/word_correction_audio.dart';
import '../services/diagnostic_log.dart';

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
    // Coupe aussi un eventuel clip de correction en cours (WordCorrectionAudio
    // est un lecteur partage, cf. coach_incremental_repeat.dart) -- un seul
    // son a la fois dans l'app.
    await WordCorrectionAudio.stop();
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
    // ── DEUX BOUCLES IMBRIQUEES : LE GROUPE, PUIS LE PASSAGE ──────────────
    //
    // Demande utilisateur (2026-08-06) : « répéter la sourate 3 fois, mais pour
    // chaque sourate tu vas répéter 3 versets 3 fois ». Cf. les champs
    // `groupeVersets` / `repetitionsGroupe` / `repetitionsGlobales` de
    // PlayerStateModel.
    //
    // L'ancien modele ne savait pas l'exprimer : `RepeatMode.verse` repetait UN
    // verset N fois, `RepeatMode.surah` bouclait a l'infini, et les deux
    // s'excluaient. Le code d'origine est conserve ci-dessous pour les modes
    // historiques -- le nouveau chemin ne prend la main que si un reglage de
    // groupe est actif, donc rien ne change tant qu'on n'y touche pas.
    final groupe = state.groupeVersets;
    final repGroupe = state.repetitionsGroupe;
    final repGlobal = state.repetitionsGlobales;
    final boucleAvancee =
        groupe > 1 || repGroupe != 1 || repGlobal != 1;
    if (boucleAvancee) {
      // ── LA BOUCLE GLOBALE PORTE SUR LA SOURATE, PAS SUR LA PLAYLIST ─────
      //
      // Correction (2026-08-06) : « c'est mal fait, il n'y a pas sourate ».
      // La premiere version bouclait sur toute la playlist chargee -- or dans
      // le Mushaf celle-ci suit l'enchainement des PAGES et peut couvrir
      // plusieurs sourates. L'exemple donne etait pourtant explicite :
      // « répéter la SOURATE 3 fois, mais pour chaque sourate répéter 3
      // versets 3 fois ». Le tour complet, c'est donc la sourate du verset en
      // cours -- ni la page, ni tout ce qui est charge.
      final sourate = current.surahNumber;
      var borneBas = state.currentIndex;
      while (borneBas > 0 &&
          state.playlist[borneBas - 1].surahNumber == sourate) {
        borneBas--;
      }
      var borneHaut = state.currentIndex;
      while (borneHaut + 1 < state.playlist.length &&
          state.playlist[borneHaut + 1].surahNumber == sourate) {
        borneHaut++;
      }
      final n = borneHaut + 1;
      final debut = state.debutGroupe < borneBas ? borneBas : state.debutGroupe;
      final finGroupe = (debut + groupe - 1).clamp(borneBas, borneHaut);
      if (state.currentIndex < finGroupe) {
        // Encore des versets dans le groupe : on avance simplement.
        _advance();
        return;
      }
      // Fin du groupe : le redit-on ?
      final fait = state.groupeFait + 1;
      if (repGroupe == 0 || fait < repGroupe) {
        state = state.copyWith(groupeFait: fait, position: Duration.zero);
        play(state.playlist[debut], state.playlist, auto: true);
        return;
      }
      // Groupe termine : au suivant.
      final prochain = debut + groupe;
      if (prochain < n) {
        state = state.copyWith(groupeFait: 0, debutGroupe: prochain);
        play(state.playlist[prochain], state.playlist, auto: true);
        return;
      }
      // SOURATE terminee : la reprend-on depuis son premier verset ?
      final tours = state.globalFait + 1;
      if (repGlobal == 0 || tours < repGlobal) {
        state = state.copyWith(
            groupeFait: 0, debutGroupe: borneBas, globalFait: tours);
        play(state.playlist[borneBas], state.playlist, auto: true);
      } else {
        // Tours epuises : on laisse l'enchainement normal reprendre la main,
        // donc on passe a la sourate suivante au lieu de s'arreter net.
        state = state.copyWith(
            groupeFait: 0, debutGroupe: borneHaut + 1, globalFait: 0);
        _advance();
      }
      return;
    }

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

  /// Reglages de boucle imbriquee (cf. `_onCompleted`). Repartir du debut a
  /// chaque changement : sinon on garderait un `debutGroupe` calcule pour une
  /// taille de groupe qui n'existe plus.
  void setBoucle({int? groupe, int? repGroupe, int? repGlobal}) {
    state = state.copyWith(
      groupeVersets: groupe,
      repetitionsGroupe: repGroupe,
      repetitionsGlobales: repGlobal,
      debutGroupe: 0,
      groupeFait: 0,
      globalFait: 0,
    );
  }

  void _advance({bool loop = false}) {
    final next = state.currentIndex + 1;
    if (next < state.playlist.length) {
      play(state.playlist[next], state.playlist, auto: true);
    } else if (loop) {
      play(state.playlist[0], state.playlist, auto: true);
    } else {
      // ── FIN DE PLAYLIST : IL FAUT VRAIMENT ARRETER LE SON (2026-08-18) ──
      //
      // Passer le statut a `idle` ne suffit pas, et c'est ce qui manquait.
      // Avec MP3Quran la source est le fichier de la SOURATE ENTIERE : le
      // minuteur de frontiere (`_jouerViaMp3Quran`) ne fait qu'EMETTRE un
      // signal de fin, il ne touche pas au lecteur. Sans pause explicite, le
      // son continuait donc sur le verset suivant pendant que l'app se
      // croyait a l'arret.
      //
      // Invisible dans le Mushaf, ou la playlist a toujours un verset apres.
      // Visible des que la playlist n'en contient QU'UN -- l'etape « Lecture »
      // du Coach (`verses: [currentVerse]`), ou l'utilisateur l'a constate :
      // « la premiere etape ou le reciteur recite tout le verset, il ne
      // s'arrete pas au verset en question ».
      //
      // `pause()` et non `stop()` : `stop()` ferme le flux et remet
      // `_sourateEnCoursMp3Quran` a null, ce qui obligerait a rouvrir le gros
      // fichier au prochain verset de la meme sourate. En pause, un
      // `playVerse` suivant se contente d'un seek+resume.
      DiagnosticLog.log('Lecture',
          'fin de playlist (${state.playlist.length} verset(s)) -> pause du '
          'lecteur + statut idle');
      _svc.pause();
      state = state.copyWith(status: PlayerStatus.idle);
    }
  }
}

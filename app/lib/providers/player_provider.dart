import 'dart:async';
import 'package:audioplayers/audioplayers.dart' show PlayerState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/verse.dart';
import '../models/reciter.dart';
import '../models/player_state_model.dart';
import '../services/audio_player_service.dart';
import '../services/quran_api.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import '../services/word_correction_audio.dart';

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
      // Un NOUVEAU depart repart du premier mot du verset. Sans cette remise a
      // zero, taper un autre verset en mode mot reprenait au `debutMot` du
      // precedent (`_boucleMots` le relit pour pouvoir reprendre apres pause)
      // -- on serait tombe en plein milieu, sans rien qui l'explique.
      debutMot: 0,
    );
    if (state.uniteMot) {
      // Autre moteur de lecture (cf. `_boucleMots`) : plages temporelles dans
      // un fichier, pas enchainement de fichiers.
      await _boucleMots();
      return;
    }
    final ok = await _svc.playVerse(verse, rc);
    if (!ok) {
      state = state.copyWith(
          status: PlayerStatus.error, error: 'Audio introuvable');
    }
  }

  Future<void> pause() async {
    if (state.uniteMot) {
      // La boucle au mot ne tient pas son etat dans le plugin audio mais dans
      // une boucle Dart : la mettre en "pause" reviendrait a suspendre un
      // `await` au milieu d'une plage, sans point de reprise propre. On
      // l'ARRETE, et `resume` la relance au groupe de mots courant
      // (`debutMot`) -- ce qui est aussi le comportement attendu en
      // memorisation : on reprend au debut de l'unite, pas au milieu d'un mot.
      _generationMots++;
      await WordCorrectionAudio.stop();
      state = state.copyWith(status: PlayerStatus.paused);
      return;
    }
    await _svc.pause();
    state = state.copyWith(status: PlayerStatus.paused);
  }

  Future<void> resume() async {
    if (state.uniteMot) {
      state = state.copyWith(status: PlayerStatus.playing);
      await _boucleMots();
      return;
    }
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
    _generationMots++; // coupe la boucle au mot si elle tourne
    await WordCorrectionAudio.stop();
    await _svc.stop();
    state = state.copyWith(status: PlayerStatus.idle, debutMot: 0);
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
    // En mode MOT, la sequence est portee par `_boucleMots`, pas par les
    // evenements du plugin : un `completed` residuel du moteur par versets
    // (celui d'avant la bascule, arrive apres coup) relancerait `play()` et
    // demarrerait une SECONDE boucle. Le compteur de generation la ferait
    // converger, mais autant ne pas la creer.
    if (state.uniteMot) return;
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

  // ── BOUCLE AU MOT ────────────────────────────────────────────────────────
  //
  // Demande utilisateur 2026-08-06, juste apres la validation des trois
  // curseurs : « on peut descendre au mot ? ». L'unite repetee devient le MOT
  // et non plus le verset ; `groupeVersets` se lit alors en nombre de mots.
  //
  // ⚠️ CE N'EST PAS UN CURSEUR DE PLUS, C'EST UN SECOND MOTEUR DE LECTURE.
  // Le chemin normal enchaine des FICHIERS de verset et se pilote aux
  // evenements du plugin (`_svc.onComplete` -> `_onComplete`). Ici il n'y a
  // qu'un fichier et des PLAGES TEMPORELLES dedans : la sequence est portee
  // par cette boucle Dart, et `WordCorrectionAudio.playWordWindow` rend la
  // main a la fin de chaque plage. Les deux moteurs ne doivent jamais jouer
  // en meme temps -- d'ou le `_svc.stop()` en entree.
  //
  // Les timings mot-a-mot viennent de quran.com (`fetchAyahSegments`) et ne
  // sont PAS garantis pour tous les recitateurs : quand ils manquent,
  // `playWordRange` abandonne en journalisant (`Correction-Audio ABANDON`) et
  // la plage est silencieuse. On ne fait pas semblant de jouer : on repasse
  // alors le verset entier par le moteur normal (repli explicite ci-dessous),
  // plutot que de boucler dans le vide.
  //
  // `_generationMots` est le seul moyen d'arreter une boucle deja engagee
  // dans un `await` : chaque pause/stop/nouveau depart l'incremente, et toute
  // iteration qui constate un ecart se retire sans toucher a l'etat.
  int _generationMots = 0;

  Future<void> _boucleMots() async {
    final gen = ++_generationMots;
    await _svc.stop();

    final playlist = state.playlist;
    if (playlist.isEmpty) return;
    var index = state.currentIndex.clamp(0, playlist.length - 1);
    final sourate = playlist[index].surahNumber;
    // Bornes de la SOURATE (et non de la playlist : dans le Mushaf elle suit
    // les pages et peut couvrir plusieurs sourates -- meme raison qu'en
    // lecture par versets, cf. `_onComplete`).
    var borneBas = index;
    while (borneBas > 0 && playlist[borneBas - 1].surahNumber == sourate) {
      borneBas--;
    }
    var borneHaut = index;
    while (borneHaut + 1 < playlist.length &&
        playlist[borneHaut + 1].surahNumber == sourate) {
      borneHaut++;
    }

    // Preflight : ce recitateur publie-t-il des timings mot-a-mot ?
    // Sans ce controle, l'absence de timings ne se voit pas -- la boucle
    // tournerait a vide en silence, ce qui se lit comme « l'app est cassee ».
    // Un seul appel, deja mis en cache par `playWordRange` ensuite.
    final segments = await QuranApi.fetchAyahSegments(
        state.reciter.id, playlist[index].key);
    if (!mounted || gen != _generationMots) return;
    if (segments.isEmpty) {
      state = state.copyWith(
        uniteMot: false,
        error: 'Ce récitateur ne fournit pas de repères mot à mot — '
            'répétition au verset',
      );
      final ok = await _svc.playVerse(playlist[index], state.reciter);
      if (!ok && mounted) {
        state = state.copyWith(
            status: PlayerStatus.error, error: 'Audio introuvable');
      }
      return;
    }

    final taille = state.groupeVersets.clamp(1, 50); // en MOTS ici
    final repGroupe = state.repetitionsGroupe;
    final repGlobal = state.repetitionsGlobales;
    var toursSourate = state.globalFait;

    state = state.copyWith(status: PlayerStatus.playing);

    while (mounted && gen == _generationMots) {
      final verse = playlist[index];
      final nbMots =
          ArabicNormalizer.splitExpectedWords(verse.textUthmani).length;
      if (nbMots == 0) {
        if (index < borneHaut) { index++; continue; }
        break;
      }
      // Reprise apres pause : on repart du groupe courant, pas du debut du
      // verset (cf. commentaire de `pause`).
      var debut = index == state.currentIndex ? state.debutMot : 0;
      if (debut >= nbMots) debut = 0;

      while (debut < nbMots) {
        final fin = (debut + taille - 1).clamp(0, nbMots - 1);
        state = state.copyWith(
            currentVerse: verse, currentIndex: index, debutMot: debut);
        var fois = 0;
        while (repGroupe == 0 || fois < repGroupe) {
          if (!mounted || gen != _generationMots) return;
          await WordCorrectionAudio.playWordWindow(verse, state.reciter,
              startWordIdx: debut, endWordIdx: fin);
          fois++;
        }
        if (!mounted || gen != _generationMots) return;
        debut = fin + 1;
      }

      if (index < borneHaut) {
        index++;
        state = state.copyWith(debutMot: 0);
        continue;
      }
      // Sourate terminee : la reprend-on ?
      toursSourate++;
      if (repGlobal == 0 || toursSourate < repGlobal) {
        index = borneBas;
        state = state.copyWith(globalFait: toursSourate, debutMot: 0);
        continue;
      }
      break;
    }

    if (mounted && gen == _generationMots) {
      state = state.copyWith(
          status: PlayerStatus.idle, debutMot: 0, globalFait: 0);
    }
  }

  /// Bascule l'unite de repetition entre le verset et le mot.
  void setUniteMot(bool mot) {
    _generationMots++;
    WordCorrectionAudio.stop();
    state = state.copyWith(
      uniteMot: mot,
      debutMot: 0,
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
      state = state.copyWith(status: PlayerStatus.idle);
    }
  }
}

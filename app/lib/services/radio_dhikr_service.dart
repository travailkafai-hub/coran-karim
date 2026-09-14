// La radio de dhikr continue de jouer quand on quitte l'écran, et se pilote
// depuis la notification (2026-09-14).
//
// ── POURQUOI CE SERVICE EXISTE ──────────────────────────────────────────────
//
// Demande utilisateur : « invocation radio, quand c'est play, garder le
// contrôle sur la notification ».
//
// Avant, le lecteur était un `AudioPlayer` créé DANS le widget `_RadiosDhikr`
// et détruit par son `dispose()` : quitter l'onglet coupait le flux. Une
// notification n'aurait donc rien eu à piloter — elle serait apparue puis aurait
// commandé un lecteur déjà mort. Sortir le lecteur du widget est la condition
// de la demande, pas un raffinement.
//
// ── CE QUI EST RÉUTILISÉ, ET POURQUOI ON NE CRÉE PAS UNE SECONDE SESSION ────
//
// `audio_service` est déjà initialisé pour le lecteur du Coran
// (`session_media.dart`, `AudioService.init` avant `runApp`). Android n'accepte
// qu'UNE session média par application : en ouvrir une seconde ferait
// disparaître la première. La radio emprunte donc le MÊME handler.
//
// ⚠️ CONSÉQUENCE À NE PAS OUBLIER : les rappels du handler (`auPlay`,
// `auPause`, `auStop`) sont branchés par `PlayerNotifier` au démarrage, UNE
// SEULE FOIS. Si la radio les écrasait sans les rendre, les boutons de la
// notification continueraient ensuite à piloter la radio pendant une lecture du
// Coran — un bouton qui commande autre chose que ce qu'il affiche. Ce service
// SAUVEGARDE donc les rappels avant de prendre la main et les REMET à l'arrêt.
//
// ── LE FLUX ICY N'A PAS DE FIN, LE LECTEUR CROIT QUE SI ─────────────────────
//
// La logique de reconnexion vient telle quelle de `_RadiosDhikrState` : ce sont
// des flux Shoutcast (`Transfer-Encoding: chunked`, `icy-br: 128`), que le
// lecteur Android traite comme des fichiers — au premier creux de tampon il
// annonce la fin et s'arrête. On se reconnecte tant que l'utilisateur n'a pas
// demandé l'arrêt, avec le même garde-fou : trois échecs immédiats (moins de
// 5 s d'écoute utile) et on abandonne en le disant, plutôt que de marteler le
// serveur en silence.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/radio_dhikr.dart';
import 'session_media.dart';

/// État observable de la radio, pour que l'écran s'y abonne sans posséder le
/// lecteur. `null` = rien en cours.
class EtatRadioDhikr {
  final int? idEnCours;
  final bool chargement;
  const EtatRadioDhikr({this.idEnCours, this.chargement = false});
}

class RadioDhikrService {
  RadioDhikrService._();
  static final RadioDhikrService instance = RadioDhikrService._();

  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<EtatRadioDhikr> etat =
      ValueNotifier(const EtatRadioDhikr());

  /// Signalé à l'écran quand le flux abandonne, pour qu'il affiche le message.
  /// Un service ne connaît ni `BuildContext` ni traductions : il dit QUE ça a
  /// échoué, l'écran dit COMMENT le formuler.
  final ValueNotifier<int> echecs = ValueNotifier(0);

  StreamSubscription<void>? _finSub;
  RadioDhikr? _radio;
  String _titre = '';
  int _reconnexions = 0;
  DateTime? _debutEcoute;

  /// Rappels du handler média appartenant au lecteur du Coran, mis de côté le
  /// temps que la radio joue (cf. l'avertissement en tête de fichier).
  Future<void> Function()? _playPrecedent;
  Future<void> Function()? _pausePrecedent;
  Future<void> Function()? _stopPrecedent;
  bool _aPrisLaMain = false;

  bool get enLecture => _radio != null;

  void _init() {
    _finSub ??= _player.onPlayerComplete.listen((_) => _surCompletion());
  }

  Future<void> basculer(RadioDhikr r, String titre) async {
    _init();
    if (_radio?.id == r.id) {
      await arreter();
      return;
    }
    _radio = r;
    _titre = titre;
    etat.value = EtatRadioDhikr(idEnCours: r.id, chargement: true);
    try {
      await _player.stop();
      _reconnexions = 0;
      _debutEcoute = DateTime.now();
      await _player.play(UrlSource(r.url));
      etat.value = EtatRadioDhikr(idEnCours: r.id);
      _prendreLaMain();
      _publier(enLecture: true);
    } catch (_) {
      _radio = null;
      etat.value = const EtatRadioDhikr();
      echecs.value++;
      _rendreLaMain();
    }
  }

  Future<void> arreter() async {
    // `_radio` à null AVANT le stop : `onPlayerComplete` peut se déclencher
    // pendant l'arrêt, et `_surCompletion` doit alors voir que plus rien n'est
    // demandé — sinon un appui sur stop relancerait le flux.
    _radio = null;
    etat.value = const EtatRadioDhikr();
    await _player.stop();
    sessionMedia?.publierArret();
    _rendreLaMain();
  }

  Future<void> _pause() async {
    await _player.pause();
    _publier(enLecture: false);
  }

  Future<void> _reprendre() async {
    // Un flux continu ne se « reprend » pas là où il s'était arrêté : le
    // serveur diffuse en direct. On rouvre donc la source plutôt que de
    // `resume()` sur un tampon périmé.
    final r = _radio;
    if (r == null) return;
    _debutEcoute = DateTime.now();
    await _player.play(UrlSource(r.url));
    _publier(enLecture: true);
  }

  Future<void> _surCompletion() async {
    final r = _radio;
    if (r == null) return;
    final ecouteUtile = _debutEcoute != null &&
        DateTime.now().difference(_debutEcoute!).inSeconds >= 5;
    _reconnexions = ecouteUtile ? 0 : _reconnexions + 1;
    if (_reconnexions >= 3) {
      _radio = null;
      etat.value = const EtatRadioDhikr();
      echecs.value++;
      sessionMedia?.publierArret();
      _rendreLaMain();
      return;
    }
    try {
      _debutEcoute = DateTime.now();
      await _player.play(UrlSource(r.url));
    } catch (_) {
      // Silencieux : la prochaine complétion repassera ici, et le compteur
      // ci-dessus finira par trancher.
    }
  }

  void _prendreLaMain() {
    final s = sessionMedia;
    if (s == null || _aPrisLaMain) return;
    _playPrecedent = s.auPlay;
    _pausePrecedent = s.auPause;
    _stopPrecedent = s.auStop;
    s.auPlay = _reprendre;
    s.auPause = _pause;
    s.auStop = arreter;
    _aPrisLaMain = true;
  }

  void _rendreLaMain() {
    final s = sessionMedia;
    if (s == null || !_aPrisLaMain) return;
    s.auPlay = _playPrecedent;
    s.auPause = _pausePrecedent;
    s.auStop = _stopPrecedent;
    _aPrisLaMain = false;
  }

  void _publier({required bool enLecture}) {
    final s = sessionMedia;
    if (s == null || _radio == null) return;
    s.publierPiste(titre: _titre, sousTitre: 'Coran Karim');
    // Pas de position ni de durée : un flux continu n'en a pas, et en publier
    // une ferait apparaître une barre de progression qui n'avancerait jamais.
    s.publierEtat(enLecture: enLecture, charge: false);
  }
}

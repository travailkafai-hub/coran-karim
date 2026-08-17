import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/verse.dart';
import '../models/reciter.dart';
import '../models/player_state_model.dart';
import 'mp3quran_api.dart';
import 'quran_api.dart';
import 'reciter_download_service.dart';

/// Singleton audio service wrapping audioplayers.
/// Manages one AudioPlayer instance for the whole app lifetime.
class AudioPlayerService {
  static final AudioPlayerService _i = AudioPlayerService._();
  factory AudioPlayerService() => _i;
  AudioPlayerService._() {
    _relaisCompletionReelle = _player.onPlayerComplete.listen((_) {
      if (!_completionCtrl.isClosed) _completionCtrl.add(null);
    });
  }

  final _player = AudioPlayer();

  // Cached audio URLs: surahNumber → { verse_key → url }
  final _urlCache = <int, Map<String, String>>{};

  // ── Frontière de verset dans un flux MP3Quran (2026-08-13) ────────────────
  //
  // MP3Quran sert UN FICHIER PAR SOURATE ENTIÈRE (cf. mp3quran_api.dart) --
  // lire "un verset" veut dire ouvrir ce flux, sauter à son `startMs`, puis
  // s'arrêter à son `endMs`. `audioplayers` n'a pas de "lecture jusqu'à un
  // instant" natif : un `Timer` armé sur la durée exacte du verset simule
  // cette frontière (cf. `_jouerViaMp3Quran` pour le détail et l'historique
  // du correctif du 2026-08-16 -- un sondage de position causait un retard
  // ET une coupure audible).
  //
  // `_minuteurFrontiere` n'est JAMAIS armé pour les récitateurs quran.com
  // (chemin existant, inchangé) -- seul le chemin MP3Quran l'utilise.
  final _completionCtrl = StreamController<void>.broadcast();
  StreamSubscription<void>? _relaisCompletionReelle;

  Stream<Duration> get positionStream => _player.onPositionChanged;
  Stream<Duration> get durationStream =>
      _player.onDurationChanged.map((d) => d ?? Duration.zero);
  // Fusionne la fin de fichier réelle (quran.com, un fichier par verset) et
  // la fin SIMULÉE en franchissant `endMs` (MP3Quran, un fichier par
  // sourate) -- `PlayerNotifier._onComplete` (avance/répétition) n'a pas à
  // savoir laquelle des deux s'est produite. Relais construit une seule fois
  // (pas de StreamGroup pour éviter une dépendance directe supplémentaire) :
  // chaque complétion réelle du lecteur natif est simplement republiée sur
  // le même contrôleur que les complétions simulées.
  Stream<void> get onComplete => _completionCtrl.stream;
  Stream<PlayerState> get stateStream => _player.onPlayerStateChanged;

  Future<void> preloadSurah(int recitationId, int surahNumber) async {
    if (_urlCache.containsKey(surahNumber)) return;
    _urlCache[surahNumber] =
        await QuranApi.fetchSurahAudioUrls(recitationId, surahNumber);
  }

  Future<bool> playVerse(Verse verse, Reciter reciter) async {
    // Toute nouvelle lecture désarme le minuteur de frontière précédent --
    // sinon celui du verset N-1 (calé sur SA durée à lui) sonnerait au
    // mauvais instant pour le verset N tout juste démarré.
    _minuteurFrontiere?.cancel();
    _minuteurFrontiere = null;

    if (Mp3QuranApi.sertCeReciter(reciter.id)) {
      return _jouerViaMp3Quran(verse, reciter);
    }

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

  // Sourate en cours de diffusion via MP3Quran, pour éviter de rouvrir le
  // MÊME flux (et donc de le faire rebuffériser depuis zéro) quand on saute
  // simplement d'un verset au suivant DANS la même sourate.
  int? _sourateEnCoursMp3Quran;

  /// Lit UN verset depuis le flux MP3Quran de la sourate entière : ouvre (ou
  /// réutilise) le flux, saute au début du verset, arme une veille qui coupe
  /// la lecture à sa fin. Cf. le commentaire de tête de fichier de
  /// `mp3quran_api.dart` pour le pourquoi de cette architecture.
  ///
  /// ── DEUX DÉFAUTS CORRIGÉS ICI (2026-08-16, constat utilisateur sur
  /// device : « le suivi du verset est en retard, et ça coupe l'audio une
  /// microseconde pendant le défilement ») ─────────────────────────────────
  ///
  /// 1. RETARD -- la première version détectait la frontière en écoutant
  ///    `onPositionChanged`, qui n'émet pas en continu (audioplayers publie
  ///    la position par intervalles, pas à chaque milliseconde). Le passage
  ///    au verset suivant attendait donc jusqu'au prochain sondage après la
  ///    frontière réelle. Remplacé par un `Timer` armé sur la durée EXACTE du
  ///    verset (`endMs - startMs`) dès le `seek()` -- précision de l'ordre de
  ///    la milliseconde côté Dart, plus de dépendance à la cadence de
  ///    sondage du plugin.
  ///    Compromis assumé : si le flux réseau cale en plein verset (rare, un
  ///    seul flux continu par sourate plutôt qu'une requête par verset comme
  ///    l'ancien système), le minuteur peut sonner avant que l'audio ait
  ///    réellement atteint `endMs`. Pas de filet de sécurité ajouté pour ce
  ///    cas -- à revoir seulement s'il se manifeste réellement sur device.
  ///
  /// 2. COUPURE AUDIBLE -- la version précédente appelait `_player.pause()`
  ///    À LA FRONTIÈRE, puis reprenait plus tard par `resume()+seek()` pour
  ///    le verset suivant : un vrai arrêt du flux natif, entendu comme un
  ///    clic. Entre deux versets de la MÊME sourate le flux ne doit jamais
  ///    s'arrêter -- seul un `seek()` (un saut dans un flux qui continue de
  ///    jouer) est nécessaire, ce qui ne produit pas la coupure d'un
  ///    pause()/resume(). Le `pause()` a été retiré de la veille de
  ///    frontière ; elle se contente de signaler la fin du verset.
  Timer? _minuteurFrontiere;

  Future<bool> _jouerViaMp3Quran(Verse verse, Reciter reciter) async {
    debugPrint('[Mp3Quran] _jouerViaMp3Quran verset=${verse.key}');
    final List<AyahTiming> timing;
    try {
      timing = await Mp3QuranApi.ayatTiming(verse.surahNumber);
    } catch (e) {
      debugPrint('[Mp3Quran] abandon (minutage) : $e');
      return false;
    }
    AyahTiming? t;
    for (final e in timing) {
      if (e.ayah == verse.ayahNumber) {
        t = e;
        break;
      }
    }
    if (t == null) return false;

    _minuteurFrontiere?.cancel();

    // ── MARGE DE SÉCURITÉ AU DÉBUT DU VERSET (2026-08-16, constat
    // utilisateur : « الم est coupé au début ») ──────────────────────────────
    //
    // Les frontières de MP3Quran sont PARFAITEMENT CONTIGUËS -- la fin du
    // verset N est EXACTEMENT le début du verset N+1, sans le moindre
    // intervalle codé (vérifié sur la sourate 1 : ayah1 end_time=13189,
    // ayah2 start_time=13189, identiques au ms près). Un `seek()` posé pile
    // sur ce point risque de mordre sur la toute première syllabe si le
    // lecteur natif n'a pas fini de se préparer -- particulièrement juste
    // après l'ouverture d'un gros fichier local (cas neuf ci-dessous).
    //
    // Reculer le point de départ d'une petite marge protège contre ça : la
    // fin du verset PRÉCÉDENT porte presque toujours un reste de silence
    // avant que le suivant ne commence réellement à être prononcé, donc
    // reculer de quelques dizaines de ms tombe dans ce silence plutôt que sur
    // de la parole. La durée du minuteur est augmentée d'autant pour que la
    // fin du verset reste au bon endroit (`t.endMs`), sans grignoter sur le
    // verset suivant.
    const margeDebutMs = 120;
    final debutMs = (t.startMs - margeDebutMs).clamp(0, t.startMs);
    final margeReelle = t.startMs - debutMs;

    if (_sourateEnCoursMp3Quran != verse.surahNumber) {
      // Fichier LOCAL, pas un flux réseau (2026-08-16) : sauter dans un
      // `UrlSource` peut re-tamponner sur le réseau au moment du `seek`,
      // même avec un minutage exact -- un fichier déjà sur le disque n'a
      // besoin d'aucune requête pour sauter d'un point à un autre. Le prix
      // est ici, à l'ouverture d'une sourate neuve : on attend la fin du
      // téléchargement du fichier ENTIER avant de démarrer (cf. le
      // commentaire de `Mp3QuranApi.fichierLocalSourate`).
      final String path;
      try {
        path = await Mp3QuranApi.fichierLocalSourate(
            reciter.id, verse.surahNumber);
      } catch (e) {
        // Téléchargement échoué (réseau coupé, sourate trop grosse pour le
        // délai imparti...) -- même contrat que l'échec de minutage
        // ci-dessus : on renvoie false, jamais d'exception qui remonterait
        // jusqu'à l'appelant.
        debugPrint('[Mp3Quran] abandon (telechargement) : $e');
        return false;
      }
      debugPrint('[Mp3Quran] fichier local pret, lance _player.play : $path');
      await _player.play(DeviceFileSource(path));
      _sourateEnCoursMp3Quran = verse.surahNumber;
      await _player.seek(Duration(milliseconds: debutMs));
      debugPrint('[Mp3Quran] play()+seek() termines');
    } else {
      // Déjà en train de jouer cette sourate : JAMAIS de pause()/resume()
      // ici, seulement un saut dans le flux en cours -- c'est ce qui
      // supprime le clic entre deux versets contigus. `resume()` reste
      // nécessaire si l'utilisateur avait explicitement mis en pause avant
      // de taper un autre verset (no-op audioplayers si déjà en lecture,
      // donc sans risque de provoquer lui-même une coupure).
      await _player.seek(Duration(milliseconds: debutMs));
      await _player.resume();
    }

    // La marge est ajoutée à la durée du minuteur : le point de départ réel
    // recule de `margeReelle`, donc la durée à attendre pour atteindre
    // `t.endMs` augmente d'autant -- sinon le verset finirait trop tôt et
    // grignoterait sur le suivant, déplaçant le défaut au lieu de le retirer.
    final dureeMs = t.endMs - t.startMs + margeReelle;
    _minuteurFrontiere = Timer(Duration(milliseconds: dureeMs), () {
      _minuteurFrontiere = null;
      if (!_completionCtrl.isClosed) _completionCtrl.add(null);
    });
    return true;
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.resume();
  Future<void> stop() async {
    // Le flux MP3Quran réellement ouvert dans le lecteur natif est fermé par
    // `_player.stop()` -- sans remettre `_sourateEnCoursMp3Quran` à null, un
    // `playVerse` ultérieur sur la même sourate croirait le flux encore
    // actif et se contenterait d'un `resume()` sur un lecteur arrêté.
    _minuteurFrontiere?.cancel();
    _minuteurFrontiere = null;
    _sourateEnCoursMp3Quran = null;
    await _player.stop();
  }

  Future<void> setSpeed(double rate) => _player.setPlaybackRate(rate);
  Future<void> seek(Duration pos) => _player.seek(pos);

  void dispose() {
    _minuteurFrontiere?.cancel();
    _relaisCompletionReelle?.cancel();
    _completionCtrl.close();
    _player.dispose();
  }
}

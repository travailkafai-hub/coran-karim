// Session média Android : contrôler la lecture depuis la notification, l'écran
// verrouillé et les boutons d'un casque — app réduite.
//
// ── POURQUOI (demande utilisateur 2026-09-03) ────────────────────────────────
//
// « Je veux que la gestion pause/play soit avec la notification, si on réduit
// l'app [...] pour libérer, économiser la batterie [...] je sens le tél devenir
// chaud. » Et, plus juste encore : « si on réduit l'app et que l'audio continue
// de tourner, OK, mais garder toute l'app en arrière-plan, c'est pas une bonne
// idée. »
//
// C'est exactement ce que fait une session média : l'interface Flutter est
// suspendue par le système, et seul un service natif léger continue à jouer.
// Rien ne « garde l'app vivante ».
//
// ── CE QUE LA MESURE A DIT, ET CE QU'ELLE N'A PAS DIT ────────────────────────
//
// Trois régimes de trois minutes, charge CPU du processus relevée par `top` :
//
//     repos                        0 %
//     écoute (lecture audio)      40 %
//     récitation (micro + ASR)   226 %, pointes à 333 %
//
// 226 %, ce sont deux à trois cœurs saturés en continu : la chaleur vient de
// l'ASR, pas de l'écran ni du décodage audio. Cette session média règle donc le
// confort d'usage (contrôler sans rouvrir l'app) et la consommation pendant
// l'ÉCOUTE — elle ne change rien à la chauffe de la récitation, qui est un
// autre chantier.
//
// ⚠️ La colonne « température » de cette mesure était inexploitable : le script
// prenait le maximum parmi toutes les zones thermiques, donc pas la même zone
// d'un relevé à l'autre. Et une première tentative, qui coupait la charge par
// `dumpsys battery set ac 0`, ne mesurait rien du tout : cette commande fige le
// rapport batterie au lieu de couper la charge, température comprise. Ne pas
// refaire ces deux erreurs.
//
// ── POURQUOI ENVELOPPER PLUTÔT QUE MIGRER ───────────────────────────────────
//
// `AudioPlayerService` porte toute la logique MP3Quran — lecture d'un fichier
// de sourate entière avec un minuteur de frontière de verset, cf.
// `_jouerViaMp3Quran`. Migrer vers `just_audio` l'aurait fait réécrire.
// `audio_service` s'interpose au-dessus sans y toucher : ce fichier ne fait que
// relayer des ordres.
//
// Le handler ne connaît NI Riverpod NI le lecteur : il expose des rappels que
// `PlayerNotifier` branche à sa création. Sans ce découplage il faudrait un
// provider avant `runApp`, alors que `AudioService.init` doit être appelé
// avant — l'ordre d'initialisation deviendrait un piège.

import 'package:audio_service/audio_service.dart';

/// Relais entre la notification média du système et le lecteur de l'app.
///
/// Les rappels sont assignés par `PlayerNotifier`. Tant qu'ils sont nuls, un
/// appui sur la notification ne fait rien — c'est voulu : mieux vaut un bouton
/// inerte pendant les quelques millisecondes du démarrage qu'un plantage.
class SessionMediaHandler extends BaseAudioHandler with SeekHandler {
  Future<void> Function()? auPlay;
  Future<void> Function()? auPause;
  Future<void> Function()? auStop;
  Future<void> Function()? auSuivant;
  Future<void> Function()? auPrecedent;
  Future<void> Function(Duration)? auSeek;

  @override
  Future<void> play() async => auPlay?.call();

  @override
  Future<void> pause() async => auPause?.call();

  @override
  Future<void> stop() async => auStop?.call();

  @override
  Future<void> skipToNext() async => auSuivant?.call();

  @override
  Future<void> skipToPrevious() async => auPrecedent?.call();

  @override
  Future<void> seek(Duration position) async => auSeek?.call(position);

  /// Publie l'état vers la notification.
  ///
  /// `playing` commande l'icône du bouton ; `processingState` dit au système si
  /// la session est vivante — `idle` la fait disparaître de la notification,
  /// ce qui est le comportement attendu à l'arrêt.
  void publierEtat({
    required bool enLecture,
    required bool charge,
    Duration position = Duration.zero,
    double vitesse = 1.0,
  }) {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (enLecture) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.seek},
        // Les trois indices sont ceux des `controls` ci-dessus à afficher en
        // mode compact (notification repliée) : précédent, play/pause, suivant.
        androidCompactActionIndices: const [0, 1, 2],
        processingState: charge
            ? AudioProcessingState.loading
            : AudioProcessingState.ready,
        playing: enLecture,
        updatePosition: position,
        speed: vitesse,
      ),
    );
  }

  /// La session n'a plus rien à jouer : la notification doit disparaître.
  void publierArret() {
    playbackState.add(
      PlaybackState(
        controls: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  /// Ce que la notification affiche : sourate, récitateur, numéro de verset.
  void publierPiste({
    required String titre,
    required String sousTitre,
    Duration? duree,
  }) {
    mediaItem.add(
      MediaItem(
        // L'id doit être stable pour une même piste : le système s'en sert
        // pour reconnaître un changement de morceau.
        id: '$titre|$sousTitre',
        title: titre,
        artist: sousTitre,
        duration: duree,
      ),
    );
  }
}

/// Le handler de l'application, ou null tant que `initSessionMedia` n'a pas
/// abouti (plateforme non gérée, ou échec d'initialisation du service).
SessionMediaHandler? sessionMedia;

/// Démarre la session média. À appeler AVANT `runApp`.
///
/// Un échec n'est pas fatal : l'application doit continuer à fonctionner sans
/// notification média plutôt que de ne pas démarrer. C'est pourquoi le résultat
/// est stocké dans une variable nullable et non dans une dépendance obligatoire.
Future<void> initSessionMedia() async {
  sessionMedia = await AudioService.init(
    builder: SessionMediaHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.corankarim.coran_karim.lecture',
      androidNotificationChannelName: 'Lecture du Coran',
      // La notification suit la lecture : elle s'efface quand on arrête, et
      // le service cesse d'être au premier plan — c'est ce qui libère
      // réellement le téléphone au lieu de le garder éveillé.
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: true,
    ),
  );
}

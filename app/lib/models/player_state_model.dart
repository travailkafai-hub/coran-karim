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

  // ── TROIS NIVEAUX DE BOUCLE (demande utilisateur 2026-08-06) ─────────────
  //
  // « on doit avoir deux curseurs : un curseur pour ce qu'on va répéter, et
  // l'autre concerne la boucle globale. Exemple : répéter la sourate 3 fois,
  // mais pour chaque sourate tu vas répéter 3 versets 3 fois. »
  //
  // Le modele n'avait qu'UN compteur (`repeatCount`, sur le verset) et la
  // sourate bouclait a l'infini : impossible d'exprimer « ce groupe-la, tant
  // de fois, et le tout tant de fois ». Trois reglages independants :
  //
  //   groupeVersets      taille de l'unite repetee (1 = un verset)
  //   repetitionsGroupe  combien de fois cette unite, 0 = illimite
  //   repetitionsGlobales combien de fois le passage entier, 0 = illimite
  //
  // Exemple de l'utilisateur : groupe=3, repetitionsGroupe=3,
  // repetitionsGlobales=3 -- chaque tranche de 3 versets est dite 3 fois, et
  // toute la sourate est reprise 3 fois.
  final int groupeVersets;
  final int repetitionsGroupe;
  final int repetitionsGlobales;

  /// Premier verset du groupe en cours (index dans la playlist).
  final int debutGroupe;
  /// Repetitions du GROUPE deja faites.
  final int groupeFait;
  /// Repetitions GLOBALES deja faites.
  final int globalFait;

  /// L'unite repetee est-elle le MOT plutot que le verset ?
  /// (demande utilisateur 2026-08-06 : « on peut descendre au mot ? »)
  /// `groupeVersets` se lit alors en NOMBRE DE MOTS a l'interieur du verset
  /// courant. Ce mode change de moteur de lecture : au lieu d'enchainer des
  /// FICHIERS de verset (`AudioPlayerService`), il joue des PLAGES
  /// TEMPORELLES dans un meme fichier via `WordCorrectionAudio.playWordRange`
  /// et les timings mot-a-mot officiels du recitateur. Consequence assumee :
  /// si le recitateur choisi ne publie pas ces timings, ce mode est
  /// indisponible (l'ecran de reglages le dit).
  final bool uniteMot;

  /// Premier mot du groupe en cours, dans le verset courant (0-based).
  final int debutMot;
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
    this.groupeVersets = 1,
    this.repetitionsGroupe = 1,
    this.repetitionsGlobales = 1,
    this.debutGroupe = 0,
    this.groupeFait = 0,
    this.globalFait = 0,
    this.uniteMot = false,
    this.debutMot = 0,
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
    int? groupeVersets,
    int? repetitionsGroupe,
    int? repetitionsGlobales,
    int? debutGroupe,
    int? groupeFait,
    int? globalFait,
    bool? uniteMot,
    int? debutMot,
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
    groupeVersets: groupeVersets ?? this.groupeVersets,
    repetitionsGroupe: repetitionsGroupe ?? this.repetitionsGroupe,
    repetitionsGlobales: repetitionsGlobales ?? this.repetitionsGlobales,
    debutGroupe: debutGroupe ?? this.debutGroupe,
    groupeFait: groupeFait ?? this.groupeFait,
    globalFait: globalFait ?? this.globalFait,
    uniteMot: uniteMot ?? this.uniteMot,
    debutMot: debutMot ?? this.debutMot,
    repeatCount: repeatCount ?? this.repeatCount,
    repeatDone: repeatDone ?? this.repeatDone,
    speed: speed ?? this.speed,
    reciter: reciter ?? this.reciter,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    error: identical(error, _unset) ? this.error : error as String?,
  );
}

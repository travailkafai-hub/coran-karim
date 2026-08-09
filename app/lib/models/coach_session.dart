import 'verse.dart';

enum CoachMode { lecture, apprentissage, controle }

class CoachSessionState {
  final List<Verse> verses;

  /// Position dans [verses] du verset actuellement travaillé (demande
  /// utilisateur 2026-07-24 : garder le flux "ayah par ayah" même quand on
  /// mémorise une sourate entière -- avant cette date, les 3 modes
  /// concaténaient TOUS les versets de [verses] en un seul bloc de texte.
  /// Naviguer entre versets ne doit PAS demander de retour arrière (quitter
  /// l'écran) -- cf. [CoachNotifier.nextVerse]/[previousVerse].
  final int currentVerseIndex;

  final CoachMode mode;
  final int appStep; // 0=écoute, 1=imite, 2=répète
  final double? baselineAccuracy; // null until Mode 1 completed
  final List<String> difficultWords; // words with errors in Mode 1
  final double? controlAccuracy; // null until Mode 3 completed

  const CoachSessionState({
    this.verses = const [],
    this.currentVerseIndex = 0,
    // ── ON DEMARRE SUR L'ENTRAINEMENT (demande utilisateur 2026-08-06) ────
    //
    // « dans mémorisation par verset, on démarre directement par entraîner ;
    // il y a écoute puis imite puis répète puis contrôle -- la première
    // lecture ne sert à rien ».
    //
    // Elle servait de REFERENCE : c'est elle qui alimentait `baselineAccuracy`
    // et le message « 1ère lecture : X % → De mémoire : Y % ». Choix de
    // l'utilisateur, question posee explicitement : SCORE ABSOLU. La
    // comparaison disparait donc, et `baselineAccuracy` reste simplement null.
    //
    // Le mode `lecture` n'est PAS supprime : il reste accessible par la barre
    // d'etapes pour qui veut lire avant de travailler. Seul le point de DEPART
    // change.
    this.mode = CoachMode.apprentissage,
    this.appStep = 0,
    this.baselineAccuracy,
    this.difficultWords = const [],
    this.controlAccuracy,
  });

  Verse get currentVerse => verses[currentVerseIndex];
  bool get hasNextVerse => currentVerseIndex < verses.length - 1;
  bool get hasPreviousVerse => currentVerseIndex > 0;
  bool get isLastVerse => !hasNextVerse;

  bool get mode1Done => baselineAccuracy != null;
  bool get mode3Done => controlAccuracy != null;

  // Positive = user recites better than they read → memorized
  double? get memorizationGap {
    if (baselineAccuracy == null || controlAccuracy == null) return null;
    return controlAccuracy! - baselineAccuracy!;
  }

  bool get isMemorized => (memorizationGap ?? -1) >= 5;

  CoachSessionState copyWith({
    List<Verse>? verses,
    int? currentVerseIndex,
    CoachMode? mode,
    int? appStep,
    List<String>? difficultWords,
  }) =>
      CoachSessionState(
        verses: verses ?? this.verses,
        currentVerseIndex: currentVerseIndex ?? this.currentVerseIndex,
        mode: mode ?? this.mode,
        appStep: appStep ?? this.appStep,
        baselineAccuracy: baselineAccuracy,
        difficultWords: difficultWords ?? this.difficultWords,
        controlAccuracy: controlAccuracy,
      );

  CoachSessionState withBaseline(double accuracy, List<String> difficult) =>
      CoachSessionState(
        verses: verses,
        currentVerseIndex: currentVerseIndex,
        mode: mode,
        appStep: appStep,
        baselineAccuracy: accuracy,
        difficultWords: difficult,
        controlAccuracy: controlAccuracy,
      );

  CoachSessionState withControlScore(double accuracy) => CoachSessionState(
        verses: verses,
        currentVerseIndex: currentVerseIndex,
        mode: mode,
        appStep: appStep,
        baselineAccuracy: baselineAccuracy,
        difficultWords: difficultWords,
        controlAccuracy: accuracy,
      );

  CoachSessionState withResetControl() => CoachSessionState(
        verses: verses,
        currentVerseIndex: currentVerseIndex,
        mode: mode,
        appStep: appStep,
        baselineAccuracy: baselineAccuracy,
        difficultWords: difficultWords,
      );

  /// Nouveau verset = nouvelle passe Lecture->Entraîne->Contrôle : le score,
  /// les mots difficiles et l'étape en cours ne doivent pas fuiter d'un
  /// verset à l'autre (chaque ayah se travaille indépendamment).
  CoachSessionState withVerseIndex(int index) => CoachSessionState(
        verses: verses,
        currentVerseIndex: index,
      );
}

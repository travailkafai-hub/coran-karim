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
    this.mode = CoachMode.lecture,
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

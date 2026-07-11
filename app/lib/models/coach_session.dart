import 'verse.dart';

enum CoachMode { lecture, apprentissage, controle }

class CoachSessionState {
  final List<Verse> verses;
  final CoachMode mode;
  final int appStep; // 0=écoute, 1=imite, 2=répète
  final double? baselineAccuracy; // null until Mode 1 completed
  final List<String> difficultWords; // words with errors in Mode 1
  final double? controlAccuracy; // null until Mode 3 completed
  final int repeatDoneCount; // répétitions complétées à l'étape "Répète"

  const CoachSessionState({
    this.verses = const [],
    this.mode = CoachMode.lecture,
    this.appStep = 0,
    this.baselineAccuracy,
    this.difficultWords = const [],
    this.controlAccuracy,
    this.repeatDoneCount = 0,
  });

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
    CoachMode? mode,
    int? appStep,
    List<String>? difficultWords,
  }) =>
      CoachSessionState(
        verses: verses ?? this.verses,
        mode: mode ?? this.mode,
        appStep: appStep ?? this.appStep,
        baselineAccuracy: baselineAccuracy,
        difficultWords: difficultWords ?? this.difficultWords,
        controlAccuracy: controlAccuracy,
        repeatDoneCount: repeatDoneCount,
      );

  CoachSessionState withBaseline(double accuracy, List<String> difficult) =>
      CoachSessionState(
        verses: verses,
        mode: mode,
        appStep: appStep,
        baselineAccuracy: accuracy,
        difficultWords: difficult,
        controlAccuracy: controlAccuracy,
        repeatDoneCount: repeatDoneCount,
      );

  CoachSessionState withControlScore(double accuracy) => CoachSessionState(
        verses: verses,
        mode: mode,
        appStep: appStep,
        baselineAccuracy: baselineAccuracy,
        difficultWords: difficultWords,
        controlAccuracy: accuracy,
        repeatDoneCount: repeatDoneCount,
      );

  CoachSessionState withResetControl() => CoachSessionState(
        verses: verses,
        mode: mode,
        appStep: appStep,
        baselineAccuracy: baselineAccuracy,
        difficultWords: difficultWords,
        repeatDoneCount: repeatDoneCount,
      );

  CoachSessionState withRepeatIncrement() => CoachSessionState(
        verses: verses,
        mode: mode,
        appStep: appStep,
        baselineAccuracy: baselineAccuracy,
        difficultWords: difficultWords,
        controlAccuracy: controlAccuracy,
        repeatDoneCount: repeatDoneCount + 1,
      );
}

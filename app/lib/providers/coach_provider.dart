import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/coach_session.dart';
import '../models/verse.dart';

final coachProvider =
    StateNotifierProvider.autoDispose<CoachNotifier, CoachSessionState>((ref) {
  return CoachNotifier();
});

class CoachNotifier extends StateNotifier<CoachSessionState> {
  CoachNotifier() : super(const CoachSessionState());

  void setup(List<Verse> verses) {
    state = CoachSessionState(verses: verses);
  }

  void setMode(CoachMode mode) => state = state.copyWith(mode: mode);

  /// Passe au verset suivant/précédent SANS quitter l'écran (demande
  /// utilisateur 2026-07-24) -- réinitialise la progression (mode, étape,
  /// scores) puisqu'un nouveau verset démarre sa propre passe.
  void nextVerse() {
    if (state.hasNextVerse) {
      state = state.withVerseIndex(state.currentVerseIndex + 1);
    }
  }

  void previousVerse() {
    if (state.hasPreviousVerse) {
      state = state.withVerseIndex(state.currentVerseIndex - 1);
    }
  }

  /// Enchaîne SEUL sur le verset suivant, en sautant directement à
  /// l'Entraîne -- PAS à `nextVerse()`, qui repart en Lecture (juste, pour
  /// une navigation manuelle délibérée avec les flèches/le glissement).
  ///
  /// Demande utilisateur (2026-08-09) : « une fois le contrôle d'un verset
  /// validé, on passe au verset suivant, du coup on passe la première étape
  /// [Lecture] [...] je veux limiter les clics ». Appelé uniquement quand le
  /// Contrôle vient d'être réussi à 100 % (cf.
  /// `coach_screen._ControleModeState`) -- l'audio de référence du nouveau
  /// palier se déclenche alors tout seul, `IncrementalRepeatStep.initState`
  /// s'en charge déjà sans intervention supplémentaire ici.
  void advanceAfterPerfectControl() {
    if (!state.hasNextVerse) return;
    state = state
        .withVerseIndex(state.currentVerseIndex + 1)
        .copyWith(mode: CoachMode.apprentissage);
  }

  void nextAppStep() {
    if (state.appStep < 2) state = state.copyWith(appStep: state.appStep + 1);
  }

  void setAppStep(int step) => state = state.copyWith(appStep: step);

  void saveBaseline(double accuracy, List<String> difficultWords) {
    state = state.withBaseline(accuracy, difficultWords);
  }

  void saveControlScore(double accuracy) {
    state = state.withControlScore(accuracy);
  }

  void resetControl() {
    state = state.withResetControl();
  }
}

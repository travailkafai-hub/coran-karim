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

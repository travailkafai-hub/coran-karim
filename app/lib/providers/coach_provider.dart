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

  void incrementRepeatDone() {
    state = state.withRepeatIncrement();
  }
}

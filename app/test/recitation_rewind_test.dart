import 'package:coran_karim/models/recitation_state.dart';
import 'package:coran_karim/providers/recitation_provider.dart';
import 'package:coran_karim/services/recitation_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestRecitationNotifier extends RecitationNotifier {
  _TestRecitationNotifier() : super(MockRecitationVerifier());

  void replaceState(RecitationSessionState value) {
    state = value;
  }
}

void main() {
  test('rewindAndUnlock resynchronizes the visible pointer with the native anchor',
      () {
    final notifier = _TestRecitationNotifier();
    addTearDown(notifier.dispose);
    notifier.setup(
      'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ '
      'الٓمٓ ذَٰلِكَ ٱلْكِتَـٰبُ لَا رَيْبَ فِيهِ',
    );

    notifier.markWordCorrected(8);
    final judgedWords = [
      for (var i = 0; i < notifier.state.words.length; i++)
        notifier.state.words[i].copyWith(
          status: switch (i) {
            3 => WordStatus.error,
            4 => WordStatus.skipped,
            5 => WordStatus.unclear,
            < 9 => WordStatus.correct,
            _ => WordStatus.current,
          },
          locked: i < 9,
        ),
    ];
    notifier.replaceState(notifier.state.copyWith(
      words: judgedWords,
      pointer: 9,
      correctCount: 6,
      unclearCount: 1,
      errorCount: 2,
      status: RecitationStatus.listening,
    ));

    notifier.rewindAndUnlock(3);

    expect(notifier.state.pointer, 3);
    expect(notifier.state.words[3].status, WordStatus.current);
    expect(notifier.state.words[3].locked, isFalse);
    expect(notifier.state.correctCount, 3);
    expect(notifier.state.unclearCount, 0);
    expect(notifier.state.errorCount, 0);
    expect(
      notifier.state.words.where((word) => word.status == WordStatus.current),
      hasLength(1),
    );
    for (var i = 4; i < 9; i++) {
      expect(notifier.state.words[i].status, WordStatus.pending);
      expect(notifier.state.words[i].locked, isFalse);
    }
  });
}

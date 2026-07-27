import 'dart:async';

import 'package:coran_karim/models/recitation_state.dart';
import 'package:coran_karim/providers/recitation_provider.dart';
import 'package:coran_karim/services/fastconformer_verifier.dart';
import 'package:coran_karim/services/recitation_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

class _AlignmentVerifier extends MockRecitationVerifier {
  final _alignments = StreamController<AlignPayload>.broadcast();
  var _generation = 0;

  @override
  Stream<AlignPayload> get alignedWords => _alignments.stream;

  @override
  int get sessionGeneration => _generation;

  @override
  Future<void> start(
    List<String> expectedWords, {
    bool continuous = false,
    List<int?>? refMinFrames,
  }) async {
    _generation++;
  }

  void emit(AlignPayload payload) => _alignments.add(payload);

  @override
  void dispose() {
    _alignments.close();
    super.dispose();
  }
}

class _TestRecitationNotifier extends RecitationNotifier {
  _TestRecitationNotifier(super.verifier);

  void replaceState(RecitationSessionState value) {
    state = value;
  }
}

RecitedWord _word(String text, {bool isBasmala = false}) => RecitedWord(
      display: text,
      normalized: ArabicNormalizer.normalize(text),
      strict: ArabicNormalizer.normalizeStrict(text),
      training: ArabicNormalizer.normalizeTraining(text),
      isBasmala: isBasmala,
    );

AlignedWord _aligned(int index, String actual) => AlignedWord(
      index: index,
      gop: actual.isEmpty ? -4 : 0,
      forced: actual.isEmpty ? -4.05 : -0.05,
      covered: true,
      actual: actual,
    );

void main() {
  // Ce que ce test verrouille (2026-07-26) : une Bismillah dont aucun son n'a
  // été capté ne doit NI bloquer la progression (bug mesuré : 4 rouges ->
  // correction -> ancre 6 vers 0, le curseur n'avançait jamais) NI être
  // validée en vert, ce qui reviendrait à valider du silence -- interdit
  // depuis le 2026-07-25 (cf. le garde-fou `!hasSpeech` et son
  // « Ne pas le redescendre » dans recitation_provider.dart).
  test(
      'une Bismillah sans son capté n\'est ni jugée ni bloquante, et ne valide rien',
      () async {
    final verifier = _AlignmentVerifier();
    final notifier = _TestRecitationNotifier(verifier);
    addTearDown(notifier.dispose);
    addTearDown(verifier.dispose);

    notifier.replaceState(RecitationSessionState(words: [
      _word('بِسْمِ', isBasmala: true),
      _word('ٱللَّهِ', isBasmala: true),
      _word('ٱلرَّحْمَـٰنِ', isBasmala: true),
      _word('ٱلرَّحِيمِ', isBasmala: true),
      _word('ٱلْحَمْدُ'),
      _word('لِلَّهِ'),
    ]));
    await notifier.startContinuous();

    verifier.emit(AlignPayload(
      seq: 9,
      anchor: 0,
      frontier: 6,
      isFinal: true,
      words: [
        _aligned(0, ''),
        _aligned(1, ''),
        _aligned(2, ''),
        _aligned(3, ''),
        _aligned(4, 'ٱلْحَمْدُ'),
        _aligned(5, 'لِلَّهِ'),
      ],
    ));
    await pumpEventQueue();

    // La progression n'est plus bloquée...
    expect(notifier.state.pointer, 6);
    expect(notifier.state.errorCount, 0);
    // ...mais seuls les DEUX mots réellement entendus sont validés.
    expect(notifier.state.correctCount, 2);
    for (var i = 0; i < 4; i++) {
      expect(notifier.state.words[i].status, isNot(WordStatus.correct),
          reason: 'un mot sans son capté ne doit jamais passer au vert');
      expect(notifier.state.words[i].status, isNot(WordStatus.error),
          reason: 'la Bismillah est exclue de la vérification');
      expect(notifier.state.words[i].locked, isFalse);
    }
    for (var i = 4; i < 6; i++) {
      expect(notifier.state.words[i].status, WordStatus.correct);
    }
  });
}

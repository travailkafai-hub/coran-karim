import 'dart:async';

import 'package:coran_karim/services/recitation_start_sequence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('announces Go only after the causal model and microphone are ready',
      () async {
    final modelReady = Completer<bool>();
    final microphoneReady = Completer<void>();
    final stages = <RecitationStartStage>[];
    var microphoneStarted = false;

    final sequence = RecitationStartSequence(
      wait: (_) async {},
    );
    final result = sequence.run(
      prepareModel: () => modelReady.future,
      startCapture: () {
        microphoneStarted = true;
        return microphoneReady.future;
      },
      onStage: stages.add,
    );

    await Future<void>.delayed(Duration.zero);
    expect(stages, [RecitationStartStage.loadingModel]);
    expect(microphoneStarted, isFalse);

    modelReady.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(stages, [
      RecitationStartStage.loadingModel,
      RecitationStartStage.countdown3,
      RecitationStartStage.countdown2,
      RecitationStartStage.countdown1,
      RecitationStartStage.startingCapture,
    ]);
    expect(microphoneStarted, isTrue);
    expect(stages, isNot(contains(RecitationStartStage.go)));

    microphoneReady.complete();
    expect(await result, isTrue);
    expect(stages.last, RecitationStartStage.go);
  });

  test('does not count down or open the microphone when the model is missing',
      () async {
    final stages = <RecitationStartStage>[];
    var microphoneStarted = false;

    final result = await RecitationStartSequence(wait: (_) async {}).run(
      prepareModel: () async => false,
      startCapture: () async => microphoneStarted = true,
      onStage: stages.add,
    );

    expect(result, isFalse);
    expect(microphoneStarted, isFalse);
    expect(stages, [
      RecitationStartStage.loadingModel,
      RecitationStartStage.modelUnavailable,
    ]);
  });

  test('does not open the microphone after the caller is disposed', () async {
    final stages = <RecitationStartStage>[];
    var active = true;
    var microphoneStarted = false;

    final result = await RecitationStartSequence(
      wait: (_) async => active = false,
    ).run(
      prepareModel: () async => true,
      startCapture: () async => microphoneStarted = true,
      onStage: stages.add,
      canContinue: () => active,
    );

    expect(result, isFalse);
    expect(microphoneStarted, isFalse);
    expect(stages, [
      RecitationStartStage.loadingModel,
      RecitationStartStage.countdown3,
    ]);
  });
}

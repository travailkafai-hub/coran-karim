typedef RecitationStartWait = Future<void> Function(Duration duration);

enum RecitationStartStage {
  loadingModel,
  countdown3,
  countdown2,
  countdown1,
  startingCapture,
  go,
  modelUnavailable,
}

class RecitationStartSequence {
  final RecitationStartWait wait;
  final Duration countdownStep;
  final Duration goDuration;

  RecitationStartSequence({
    RecitationStartWait? wait,
    this.countdownStep = const Duration(seconds: 1),
    this.goDuration = const Duration(milliseconds: 900),
  }) : wait = wait ?? Future<void>.delayed;

  Future<bool> run({
    required Future<bool> Function() prepareModel,
    required Future<void> Function() startCapture,
    required void Function(RecitationStartStage stage) onStage,
    bool Function()? canContinue,
  }) async {
    final isActive = canContinue ?? () => true;

    onStage(RecitationStartStage.loadingModel);
    final modelReady = await prepareModel();
    if (!isActive()) return false;
    if (!modelReady) {
      onStage(RecitationStartStage.modelUnavailable);
      return false;
    }

    for (final stage in const [
      RecitationStartStage.countdown3,
      RecitationStartStage.countdown2,
      RecitationStartStage.countdown1,
    ]) {
      onStage(stage);
      await wait(countdownStep);
      if (!isActive()) return false;
    }

    onStage(RecitationStartStage.startingCapture);
    await startCapture();
    if (!isActive()) return false;

    onStage(RecitationStartStage.go);
    await wait(goDuration);
    return isActive();
  }
}

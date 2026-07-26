import 'dart:async';
import 'dart:typed_data';

import 'package:coran_karim/services/fastconformer_verifier.dart';
import 'package:coran_karim/services/recitation_verifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

class _FakeRecorder implements AudioRecorder {
  int startStreamCalls = 0;
  int stopCalls = 0;
  int pauseCalls = 0;
  StreamController<Uint8List>? _stream;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    startStreamCalls++;
    _stream = StreamController<Uint8List>();
    return _stream!.stream;
  }

  @override
  Future<String?> stop() async {
    stopCalls++;
    await _stream?.close();
    _stream = null;
    return null;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> resume() async {}

  @override
  Future<bool> isPaused() async => pauseCalls > 0;

  @override
  Future<bool> isRecording() async => _stream != null;

  @override
  Future<void> dispose() async {
    await _stream?.close();
    _stream = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFastConformer extends FastConformerVerifier {
  @override
  Future<bool> ensureStreamingLoaded() async => true;

  @override
  Future<bool> setAlignmentTarget(
          List<String> strictWords, int anchor) async =>
      true;

  @override
  Future<void> resetStreaming() async {}

  @override
  Future<void> disposeStreaming() async {}
}

void main() {
  test('un nouveau start ferme le flux micro précédent resté en pause',
      () async {
    final recorder = _FakeRecorder();
    final verifier = WhisperOnnxVerifier(
      recorder: recorder,
      fastConformer: _FakeFastConformer(),
    );
    addTearDown(verifier.dispose);

    await verifier.start(const ['بِسْمِ'], continuous: true);
    await verifier.pauseCapture();
    await verifier.start(const ['بِسْمِ'], continuous: true);

    expect(recorder.startStreamCalls, 2);
    expect(recorder.stopCalls, 1);
  });
}

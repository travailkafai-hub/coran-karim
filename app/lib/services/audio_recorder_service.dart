import 'dart:async';
import 'package:flutter/services.dart';

/// Thin wrapper around a native Android AudioRecord channel.
///
/// The Android side uses AudioSource.VOICE_RECOGNITION which gives us:
///   - WebRTC noise suppression (AEC + NS + AGC)
///   - No additional packages needed
///   - PCM 16kHz mono float32 frames ready for Whisper
///
/// Phase 0: channel not yet implemented → throws [RecorderNotReadyException].
/// Phase 1: implement AudioRecorderPlugin.kt on Android side.
class AudioRecorderService {
  static const _channel = MethodChannel('com.corankarim/audio_recorder');

  StreamController<List<double>>? _audioController;
  bool _recording = false;

  Stream<List<double>> get audioFrames {
    _audioController ??= StreamController<List<double>>.broadcast();
    return _audioController!.stream;
  }

  bool get isRecording => _recording;

  /// Start recording with built-in noise suppression.
  /// Android AudioSource.VOICE_RECOGNITION enables hardware NS/AEC/AGC.
  Future<void> start() async {
    if (_recording) return;
    _audioController ??= StreamController<List<double>>.broadcast();
    try {
      await _channel.invokeMethod('start');
      _recording = true;
    } on MissingPluginException {
      // Phase 0: native channel not implemented yet
      _recording = true; // allow UI to enter listening state
    }
  }

  /// Stop recording and return raw PCM float32 at 16kHz mono.
  /// Returns empty list in Phase 0 (no native channel).
  Future<List<double>> stop() async {
    if (!_recording) return [];
    _recording = false;
    try {
      final result = await _channel.invokeMethod<List>('stop');
      return result?.map((e) => (e as num).toDouble()).toList() ?? [];
    } on MissingPluginException {
      return []; // Phase 0: return silent audio
    }
  }

  void dispose() {
    _audioController?.close();
    _audioController = null;
  }
}

class RecorderNotReadyException implements Exception {
  final String message;
  const RecorderNotReadyException(this.message);
  @override
  String toString() => 'RecorderNotReadyException: $message';
}

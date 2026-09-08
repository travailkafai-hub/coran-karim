import 'dart:async';
import 'dart:typed_data';

/// ChGPT: bounded, overlapping PCM snapshots, without stopping the microphone.
/// This is identification only: no tokens or correctness verdicts are emitted.
class PrayerIdentificationAudio {
  PrayerIdentificationAudio({
    required this.transcribe,
    required this.onText,
    required this.onError,
    this.windowBytes = 7 * 32000,
    this.stepBytes = 3 * 32000,
  }) : _buffer = Uint8List(windowBytes) {
    if (windowBytes <= 0 ||
        stepBytes <= 0 ||
        windowBytes.isOdd ||
        stepBytes.isOdd ||
        stepBytes > windowBytes) {
      throw ArgumentError('Invalid PCM16 window');
    }
  }

  final Future<String?> Function(Uint8List pcm) transcribe;
  final Future<void> Function(String text) onText;
  final void Function(Object error) onError;
  final int windowBytes;
  final int stepBytes;
  final Uint8List _buffer;
  int _total = 0;
  int _lastSubmitted = 0;
  bool _busy = false;
  bool _closed = false;
  Future<void> _pending = Future.value();

  Future<void> get settled => _pending;

  void add(Uint8List pcm) {
    if (_closed || pcm.isEmpty) return;
    if (pcm.length.isOdd) throw ArgumentError('Incomplete PCM16 sample');
    // Keep only the tail, but retain the absolute write position.
    final skip = pcm.length > windowBytes ? pcm.length - windowBytes : 0;
    var source = skip;
    var destination = (_total + skip) % windowBytes;
    while (source < pcm.length) {
      final count = (pcm.length - source).clamp(0, windowBytes - destination);
      _buffer.setRange(destination, destination + count, pcm, source);
      source += count;
      destination = 0;
    }
    _total += pcm.length;
    _pump();
  }

  void _pump() {
    if (_closed || _busy || _total - _lastSubmitted < stepBytes) return;
    _busy = true;
    _lastSubmitted = _total;
    final length = _total.clamp(0, windowBytes);
    final start = (_total - length) % windowBytes;
    final pcm = Uint8List(length);
    final first = length.clamp(0, windowBytes - start);
    pcm.setRange(0, first, _buffer, start);
    pcm.setRange(first, length, _buffer);
    _pending = _run(pcm);
  }

  Future<void> _run(Uint8List pcm) async {
    try {
      final text = await transcribe(pcm);
      if (!_closed && text != null && text.trim().isNotEmpty) {
        await onText(text);
      }
    } catch (error) {
      if (!_closed) onError(error);
    } finally {
      _busy = false;
      _pump();
    }
  }

  void close() {
    _closed = true;
    _buffer.fillRange(0, _buffer.length, 0);
  }
}

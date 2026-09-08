import 'dart:async';
import 'dart:typed_data';
import 'package:coran_karim/services/prayer_identification_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('growing PCM retains context and bounds the rolling window', () async {
    final windows = <List<int>>[];
    final texts = <String>[];
    final audio = PrayerIdentificationAudio(
      windowBytes: 8,
      stepBytes: 4,
      transcribe: (pcm) async {
        windows.add(pcm.toList());
        return 'text';
      },
      onText: (text) async => texts.add(text),
      onError: (error) => fail('$error'),
    );
    addTearDown(audio.close);
    audio.add(Uint8List.fromList([0, 1]));
    expect(windows, isEmpty);
    audio.add(Uint8List.fromList([2, 3]));
    await audio.settled;
    audio.add(Uint8List.fromList([4, 5, 6, 7]));
    await audio.settled;
    audio.add(Uint8List.fromList([8, 9, 10, 11]));
    await audio.settled;
    expect(windows, [
      [0, 1, 2, 3],
      [0, 1, 2, 3, 4, 5, 6, 7],
      [4, 5, 6, 7, 8, 9, 10, 11],
    ]);
    expect(texts.length, 3);
  });

  test(
    'one inference in flight, audio received during it is retained',
    () async {
      final first = Completer<String?>();
      final windows = <List<int>>[];
      final audio = PrayerIdentificationAudio(
        windowBytes: 8,
        stepBytes: 4,
        transcribe: (pcm) {
          windows.add(pcm.toList());
          return windows.length == 1 ? first.future : Future.value('next');
        },
        onText: (_) async {},
        onError: (e) => fail('$e'),
      );
      addTearDown(audio.close);
      final reused = Uint8List.fromList([0, 1, 2, 3]);
      audio.add(reused);
      reused.fillRange(0, 4, 99);
      audio.add(Uint8List.fromList([4, 5, 6, 7, 8, 9, 10, 11]));
      expect(windows, [
        [0, 1, 2, 3],
      ]);
      first.complete('first');
      await audio.settled;
      await audio.settled;
      expect(windows.last, [4, 5, 6, 7, 8, 9, 10, 11]);
      expect(windows.length, 2);
    },
  );

  test(
    'closing ignores a late result and never starts another inference',
    () async {
      final result = Completer<String?>();
      var calls = 0;
      final texts = <String>[];
      final audio = PrayerIdentificationAudio(
        windowBytes: 8,
        stepBytes: 4,
        transcribe: (_) {
          calls++;
          return result.future;
        },
        onText: (t) async => texts.add(t),
        onError: (e) => fail('$e'),
      );
      audio.add(Uint8List(4));
      audio.add(Uint8List(8));
      audio.close();
      result.complete('obsolete');
      await audio.settled;
      audio.add(Uint8List(8));
      expect(texts, isEmpty);
      expect(calls, 1);
    },
  );

  test(
    'transcription failure does not permanently lock the next probe',
    () async {
      var calls = 0;
      var errors = 0;
      final texts = <String>[];
      final audio = PrayerIdentificationAudio(
        windowBytes: 8,
        stepBytes: 4,
        transcribe: (_) async {
          if (++calls == 1) throw StateError('unavailable');
          return 'recovered';
        },
        onText: (t) async => texts.add(t),
        onError: (_) => errors++,
      );
      addTearDown(audio.close);
      audio.add(Uint8List(4));
      await audio.settled;
      audio.add(Uint8List(4));
      await audio.settled;
      expect(errors, 1);
      expect(texts, ['recovered']);
    },
  );
}

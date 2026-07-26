import 'dart:io';
import 'dart:typed_data';

import 'package:coran_karim/services/streaming_wav_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('écrit un WAV PCM16 mono 16 kHz lisible avec la taille finale', () async {
    final temp = await Directory.systemTemp.createTemp('causal_wav_test_');
    addTearDown(() => temp.delete(recursive: true));
    final path = '${temp.path}/recitation.wav';
    final capture = await StreamingWavCapture.open(path);
    final pcm = Uint8List.fromList([0, 0, 1, 0, 255, 127, 0, 128]);

    capture.add(pcm.sublist(0, 4));
    capture.add(pcm.sublist(4));
    await capture.close();

    final bytes = await File(path).readAsBytes();
    final header = ByteData.sublistView(bytes);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(header.getUint32(4, Endian.little), 36 + pcm.length);
    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint16(34, Endian.little), 16);
    expect(header.getUint32(40, Endian.little), pcm.length);
    expect(bytes.sublist(44), pcm);
  });

  // Verrouille le correctif du 2026-07-26 : sans lui, un fichier jamais
  // fermé proprement (mise en veille, appli tuée) restait avec un en-tête
  // tout à zéro -- définitivement illisible malgré un PCM intact.
  test('reste un WAV valide et lisible AVANT close() (session non terminée)',
      () async {
    final temp = await Directory.systemTemp.createTemp('causal_wav_test_');
    addTearDown(() => temp.delete(recursive: true));
    final path = '${temp.path}/recitation.wav';
    final capture = await StreamingWavCapture.open(path);
    final pcm = Uint8List.fromList([1, 0, 2, 0, 3, 0]);

    capture.add(pcm);
    // Laisse la chaîne d'écriture asynchrone (_writeTail) se dérouler, mais
    // NE FERME PAS la capture -- simule un process tué en plein milieu.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final bytes = await File(path).readAsBytes();
    final header = ByteData.sublistView(bytes);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(header.getUint32(40, Endian.little), pcm.length,
        reason: 'la taille de data doit refléter ce qui est déjà écrit, '
            'sans attendre close()');
    expect(bytes.sublist(44), pcm);
  });
}

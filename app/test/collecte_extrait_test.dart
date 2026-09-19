// L'extrait doit être un WAV VALIDE, pas seulement des octets au bon endroit.
//
// Le piège de ce genre de découpe : on copie la bonne plage de PCM mais on
// oublie de réécrire les deux tailles de l'en-tête. Le fichier s'ouvre quand
// même dans certains lecteurs — et annonce la durée du segment entier. Un
// chargeur d'entraînement, lui, lit au-delà des données ou rejette le fichier,
// et on ne le découvre qu'au moment d'entraîner, sur un corpus déjà collecté.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:coran_karim/services/collecte_extrait.dart';

/// Un WAV 16 kHz mono 16 bits de [echantillons] échantillons, dont la valeur
/// vaut l'index : on peut donc vérifier QUELLE plage a été extraite.
File _wavTemoin(Directory dir, int echantillons) {
  final pcm = Uint8List(echantillons * 2);
  final vue = ByteData.sublistView(pcm);
  for (var i = 0; i < echantillons; i++) {
    vue.setInt16(i * 2, i % 32000, Endian.little);
  }
  final entete = Uint8List(44);
  final e = ByteData.sublistView(entete);
  entete.setRange(0, 4, 'RIFF'.codeUnits);
  e.setUint32(4, 36 + pcm.length, Endian.little);
  entete.setRange(8, 12, 'WAVE'.codeUnits);
  entete.setRange(12, 16, 'fmt '.codeUnits);
  e.setUint32(16, 16, Endian.little);
  e.setUint16(20, 1, Endian.little); // PCM
  e.setUint16(22, 1, Endian.little); // mono
  e.setUint32(24, 16000, Endian.little);
  e.setUint32(28, 32000, Endian.little);
  e.setUint16(32, 2, Endian.little);
  e.setUint16(34, 16, Endian.little);
  entete.setRange(36, 40, 'data'.codeUnits);
  e.setUint32(40, pcm.length, Endian.little);

  final f = File('${dir.path}/temoin.wav')
    ..writeAsBytesSync([...entete, ...pcm]);
  return f;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('extrait'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('extraction du mot signalé et de ses voisins', () {
    test('les tailles de l\'en-tête sont RÉÉCRITES, pas recopiées', () {
      final source = _wavTemoin(dir, 16000 * 10); // 10 s
      final extrait = CollecteExtrait.decouper(
        clipPath: source.path,
        debutFrame: 10,
        finFrame: 19, // 10 frames
        samplesParFrame: 1280,
      );
      expect(extrait, isNotNull);
      final vue = ByteData.sublistView(extrait!);
      expect(vue.getUint32(4, Endian.little), extrait.length - 8,
          reason: 'taille du fichier');
      expect(vue.getUint32(40, Endian.little), extrait.length - 44,
          reason: 'taille du bloc de données');
      // 10 frames x 1280 échantillons x 2 octets
      expect(extrait.length, 44 + 10 * 1280 * 2);
    });

    test('c\'est bien la plage demandée qui sort', () {
      final source = _wavTemoin(dir, 16000 * 5);
      final extrait = CollecteExtrait.decouper(
        clipPath: source.path,
        debutFrame: 2,
        finFrame: 2,
        samplesParFrame: 1280,
      )!;
      // Le témoin vaut son propre index : le premier échantillon extrait doit
      // valoir 2 * 1280.
      expect(ByteData.sublistView(extrait).getInt16(44, Endian.little),
          2 * 1280);
    });

    test('une borne qui déborde est ramenée dans le clip, pas refusée', () {
      final source = _wavTemoin(dir, 1280 * 10); // 10 frames exactement
      final extrait = CollecteExtrait.decouper(
        clipPath: source.path,
        debutFrame: 8,
        finFrame: 40, // très au-delà de la fin
        samplesParFrame: 1280,
      );
      expect(extrait, isNotNull,
          reason: 'un mot en fin de segment peut déborder de quelques frames');
      expect(extrait!.length, 44 + 2 * 1280 * 2);
    });

    test('refuse ce qui ne veut rien dire', () {
      final source = _wavTemoin(dir, 16000);
      // -1 = la DP n'a rien placé pour ce mot.
      expect(
          CollecteExtrait.decouper(
              clipPath: source.path,
              debutFrame: -1,
              finFrame: 5,
              samplesParFrame: 1280),
          isNull);
      // Conversion inconnue : extraire au hasard serait pire que ne rien
      // envoyer.
      expect(
          CollecteExtrait.decouper(
              clipPath: source.path,
              debutFrame: 0,
              finFrame: 5,
              samplesParFrame: 0),
          isNull);
      expect(
          CollecteExtrait.decouper(
              clipPath: '${dir.path}/absent.wav',
              debutFrame: 0,
              finFrame: 5,
              samplesParFrame: 1280),
          isNull);
    });

    test('la durée annoncée correspond aux octets réellement présents', () {
      final source = _wavTemoin(dir, 16000 * 10);
      final extrait = CollecteExtrait.decouper(
        clipPath: source.path,
        debutFrame: 0,
        finFrame: 24, // 25 frames = 32 000 échantillons = 2 s
        samplesParFrame: 1280,
      )!;
      expect(CollecteExtrait.dureeSecondes(extrait), closeTo(2.0, 0.001));
    });
  });
}

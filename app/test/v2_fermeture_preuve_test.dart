import 'package:coran_karim/services/fastconformer_verifier.dart';
import 'package:coran_karim/services/recitation_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

class _FinNative extends FastConformerVerifier {
  @override
  Future<List<V2FermetureNative>> v2Terminer() async => [
    decoderFermetureV2({
      'i': 4, 'statut': 'Definitif(couleur=ROUGE)',
      'entendu': 'ٱلْمُرْسَلُونَ', 'preuveFenetre': 5,
      'preuveDebutAbs': 100, 'preuveFinAbs': 200,
      'gop': -.01, 'forced': -.2, 'free': -.19,
      'frames': 9, 'interieur': true, 'margeL': 1.25,
      'rules': [], 'tajwidObserve': true,
    }, []),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la fermeture conserve la lecture gagnante et sa preuve jusqu au verifier', () async {
    final verifier = WhisperOnnxVerifier(fastConformer: _FinNative());
    final mot = (await verifier.v2Terminer()).single;
    expect(mot.statut, 'Definitif(couleur=ROUGE)');
    expect(mot.heard, 'ٱلْمُرْسَلُونَ');
    expect(mot.trace, contains('f=5 abs=[100,200]'));
    expect(mot.trace, contains('frames=9'));
    expect(mot.tajwidObserve, isTrue);
    expect(mot.margeLettres, 1.25);
  });

  test('une absence de preuve ne fabrique aucun mot entendu', () {
    final mot = decoderFermetureV2({'i': 3, 'statut': 'Omis'}, []);
    expect(mot.heard, isEmpty);
    expect(mot.tajwidObserve, isFalse);
  });
}

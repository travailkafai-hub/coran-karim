// « je veux tout le temps avoir 4 propositions » (utilisateur, 2026-09-19).
//
// Ce test verrouille exactement cela, y compris dans les deux cas où la
// sourate seule ne peut pas y suffire :
//   - fin de parcours, où il ne reste plus de verset FUTUR à emprunter ;
//   - sourate trop courte (Al-Kawthar, Al-Falaq), où les leurres doivent venir
//     des voisines sans jamais devenir des questions.
//
// Le jeu est passé par deux régressions du même genre avant d'arriver ici (le
// QCM tombait à trois puis deux cases), et le bouton Lire/Pause du Mushaf a
// oscillé quatre fois faute de test. D'où celui-ci.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:coran_karim/models/verse.dart';
import 'package:coran_karim/providers/debut_verset_game_provider.dart';

Verse _v(int sourate, int ayah, String texte) =>
    Verse(surahNumber: sourate, ayahNumber: ayah, textUthmani: texte);

/// Une sourate fictive de [n] versets, tous de début DIFFÉRENT.
List<Verse> _sourate(int numero, int n) => [
      for (var i = 1; i <= n; i++) _v(numero, i, 'بدايه$i كلمه$i ثم ذلك'),
    ];

void main() {
  group('début de verset — toujours 4 propositions', () {
    test('sourate longue : 4 propositions à CHAQUE question, du premier '
        'verset au dernier', () {
      final pool = PoolDebutVerset(sourate: 2, versets: _sourate(2, 12));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(debutVersetGameProvider(pool).notifier);

      // On parcourt toute la sourate : c'est en FIN de parcours que l'ancienne
      // version tombait à trois cases, faute de verset futur à emprunter.
      for (var i = 0; i < 12; i++) {
        final q = c.read(debutVersetGameProvider(pool)).question;
        expect(q, isNotNull, reason: 'question $i absente');
        expect(q!.propositions.length, 4,
            reason: 'question $i : ${q.propositions.length} propositions');
        expect(q.propositions.toSet().length, 4,
            reason: 'question $i : doublons dans les propositions');
        expect(q.propositions, contains(q.reponseCorrecte));
        n.repondre(q.reponseCorrecte);
      }
    });

    test('sourate de 3 versets : les voisines complètent, et on ne les '
        'interroge JAMAIS', () {
      // Al-Kawthar et consorts : trois débuts seulement dans la sourate.
      final pool = PoolDebutVerset(
        sourate: 108,
        versets: _sourate(108, 3),
        leurresEnPlus: const ['غريب اول', 'غريب ثاني', 'غريب ثالث'],
      );
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(debutVersetGameProvider(pool).notifier);

      final interroges = <String>{};
      for (var i = 0; i < 3; i++) {
        final q = c.read(debutVersetGameProvider(pool)).question!;
        expect(q.propositions.length, 4, reason: 'question $i');
        expect(q.propositions.toSet().length, 4, reason: 'doublons, question $i');
        interroges.add(q.reponseCorrecte);
        n.repondre(q.reponseCorrecte);
      }
      // Le point qui compte : un verset étranger peut être proposé, jamais
      // demandé. Réviser Al-Kawthar en se voyant interroger sur une autre
      // sourate n'aurait aucun sens.
      for (final texte in interroges) {
        expect(texte.startsWith('غريب'), isFalse,
            reason: 'un leurre externe est devenu une question : $texte');
      }
    });

    test('sourate d\'un seul verset : aucune question plutôt qu\'un QCM '
        'insoluble', () {
      final pool = PoolDebutVerset(sourate: 112, versets: _sourate(112, 1));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(debutVersetGameProvider(pool)).question, isNull);
    });

    test('une mauvaise réponse repose la MÊME question, toujours à 4 cases',
        () {
      final pool = PoolDebutVerset(sourate: 2, versets: _sourate(2, 8));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(debutVersetGameProvider(pool).notifier);
      final avant = c.read(debutVersetGameProvider(pool)).question!;
      final faux = avant.propositions.firstWhere((p) => p != avant.reponseCorrecte);
      n.repondre(faux);
      final apres = c.read(debutVersetGameProvider(pool));
      expect(apres.revele, avant.reponseCorrecte,
          reason: 'la bonne réponse doit être montrée après une erreur');
      expect(apres.streak, 0);
      expect(apres.question!.propositions.length, 4);
    });

    test('le pool s\'identifie par sa SOURATE : deux listes équivalentes ne '
        'redémarrent pas la partie', () {
      // Sans `==` sur le numéro de sourate, chaque reconstruction de l'écran
      // fabriquerait un provider neuf et remettrait le score à zéro.
      final a = PoolDebutVerset(sourate: 5, versets: _sourate(5, 6));
      final b = PoolDebutVerset(sourate: 5, versets: _sourate(5, 6));
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}

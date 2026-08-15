// Verrou sur la GRADATION des presets de jugement.
//
// Écrit le 2026-08-14 après avoir découvert que les trois presets jugeaient à
// l'identique sur la chaîne qui peint l'écran : `_relaxJudged` (qui porte LES
// DEUX indulgences) vivait dans la v1 et ne s'exécutait plus depuis que la v2
// pilote l'affichage. Le défaut était invisible parce que les VALEURS des
// presets, elles, restaient correctes -- lire `judgement_options.dart` donnait
// l'impression que tout allait bien.
//
// Ces tests ne peuvent donc pas prouver que le relâchement s'applique (il
// dépend de la chaîne native). Ils verrouillent l'autre moitié : que la
// gradation reste celle décidée, et surtout que l'ADULTE ne redevienne pas
// souple par inadvertance -- décision utilisateur 2026-08-14, « garde adulte
// forcément strict ».
import 'package:flutter_test/flutter_test.dart';
import 'package:coran_karim/models/judgement_options.dart';

void main() {
  group('Gradation des presets de jugement', () {
    test('adulte est STRICT sur les harakat (décision 2026-08-14)', () {
      // Contrepartie indispensable du rebranchement de `_relaxJudged` sur la
      // v2 : sans elle, réanimer le relâchement rendait l'adulte souple, ce
      // qui n'a jamais été demandé.
      expect(JudgementOptions.adulteDefault.strictHarakat, isTrue);
      expect(JudgementOptions.adulteDefault.tolerateConfusables, isFalse);
    });

    test('enfant porte LES DEUX indulgences', () {
      expect(JudgementOptions.enfantDefault.strictHarakat, isFalse);
      expect(JudgementOptions.enfantDefault.tolerateConfusables, isTrue);
    });

    test('tajwid est le plus exigeant', () {
      expect(JudgementOptions.tajwidDefault.strictHarakat, isTrue);
      expect(JudgementOptions.tajwidDefault.tolerateConfusables, isFalse);
    });

    test('enfant est strictement plus permissif qu adulte, adulte que tajwid',
        () {
      // La gradation doit rester ORDONNÉE : si deux presets finissent avec les
      // mêmes valeurs d'indulgence, ils ne se distinguent plus que par les
      // règles de tajwid actives -- ce qui est le cas voulu pour adulte/tajwid
      // (l'adulte n'active aucune règle), mais jamais pour enfant.
      const enfant = JudgementOptions.enfantDefault;
      const adulte = JudgementOptions.adulteDefault;
      expect(enfant.strictHarakat, isNot(adulte.strictHarakat),
          reason: 'enfant doit pardonner une voyelle, pas adulte');
      expect(enfant.tolerateConfusables, isNot(adulte.tolerateConfusables),
          reason: 'enfant doit pardonner س/ص, pas adulte');
      expect(adulte.activeRules, isEmpty,
          reason: 'aucune règle de tajwid en adulte : c est ce qui le sépare '
              'du preset tajwid maintenant que les deux sont stricts');
    });
  });
}

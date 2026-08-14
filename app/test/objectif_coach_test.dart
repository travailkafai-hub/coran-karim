// Le rythme dérivé de l'objectif « tout le Coran en N années » (refonte
// 2026-08-14, cf. PLAN_COACH.md).
//
// Pourquoi CE test alors que le Coach n'en avait aucun : la formule est la
// seule chose que l'utilisateur voit de son engagement, et elle est
// entièrement dérivée -- une erreur d'un facteur 7 ou 30 y passerait
// inaperçue à l'écran (un chiffre plausible reste plausible). Le tableau du
// plan sert de référence : s'il ne tombe plus, c'est le code qui a bougé.

import 'package:flutter_test/flutter_test.dart';

import 'package:coran_karim/models/objectif_coach.dart';

void main() {
  group('ObjectifCoach — rythme dérivé', () {
    test('aucun objectif fixé : rythme nul, jamais de division par zéro', () {
      const o = ObjectifCoach();
      expect(o.actif, isFalse);
      final r = o.rythmePour(0);
      expect(r.parJour, 0);
      expect(r.parSemaine, 0);
      expect(r.parMois, 0);
    });

    test('le tableau de PLAN_COACH.md, sur 240 quarts restants', () {
      // Durée -> (par jour, par semaine, cible mensuelle affichée).
      // Valeurs EXACTES du calcul ; le tableau du plan les arrondit (il donne
      // 1,5 par semaine à 3 ans, le calcul rend 1,534). C'est le tableau qui
      // simplifie, pas le code qui dérive : la cible mensuelle, elle, tombe
      // sur les mêmes entiers de part et d'autre.
      const attendu = {
        1: (0.6575, 4.6027, 20),
        2: (0.3288, 2.3014, 10),
        3: (0.2192, 1.5342, 7),
        6: (0.1096, 0.7671, 3),
      };
      for (final e in attendu.entries) {
        final r = ObjectifCoach(annees: e.key).rythmePour(0);
        expect(r.parJour, closeTo(e.value.$1, 0.01),
            reason: '${e.key} an(s), par jour');
        expect(r.parSemaine, closeTo(e.value.$2, 0.01),
            reason: '${e.key} an(s), par semaine');
        expect(r.cibleDuMois, e.value.$3,
            reason: '${e.key} an(s), cible mensuelle');
      }
    });

    test("l'échéance porte sur le RESTE, pas sur les 240 quarts", () {
      const o = ObjectifCoach(annees: 3);
      final depart = o.rythmePour(0);
      final avance = o.rythmePour(18); // 18 quarts déjà acquis
      expect(avance.quartsRestants, 222);
      // Le rythme se DÉTEND quand on avance -- c'est tout l'objet de la
      // décision du 2026-08-14.
      expect(avance.parJour, lessThan(depart.parJour));
      expect(avance.parJour, closeTo(222 / (3 * 365), 0.0001));
    });

    test('Coran entièrement acquis : plus rien à répartir', () {
      final r = const ObjectifCoach(annees: 2).rythmePour(240);
      expect(r.quartsRestants, 0);
      expect(r.parJour, 0);
      // La cible mensuelle ne descend jamais sous 1 : une barre de
      // progression sur une cible nulle n'aurait aucun sens.
      expect(r.cibleDuMois, 1);
    });

    test('un dépassement des 240 quarts ne rend jamais le reste négatif', () {
      final r = const ObjectifCoach(annees: 2).rythmePour(999);
      expect(r.quartsRestants, 0);
      expect(r.parJour, 0);
    });
  });

  group('EtatRythme — le sens des couleurs', () {
    test('au moins ce qui était attendu : dans le rythme', () {
      expect(EtatRythme.depuis(fait: 5, attendu: 5), EtatRythme.tenu);
      expect(EtatRythme.depuis(fait: 9, attendu: 5), EtatRythme.tenu);
    });

    test('entre 70 % et 100 % : léger retard', () {
      expect(EtatRythme.depuis(fait: 3.5, attendu: 5), EtatRythme.derape);
      expect(EtatRythme.depuis(fait: 4.9, attendu: 5), EtatRythme.derape);
    });

    test('sous 70 % : à rattraper', () {
      expect(EtatRythme.depuis(fait: 3.4, attendu: 5), EtatRythme.aRattraper);
      expect(EtatRythme.depuis(fait: 0, attendu: 5), EtatRythme.aRattraper);
    });

    test('un débutant régulier est VERT, pas rouge', () {
      // 3 jours d'usage sur une fenêtre de 30 : l'attendu vaut un dixième de
      // la cible. Sans cette pondération, tout nouvel utilisateur ouvrirait
      // l'app sur du rouge -- la culpabilisation que PLAN_COACH.md §2 refuse.
      const cible = 5.0;
      final attendu = cible * (3 / 30);
      expect(EtatRythme.depuis(fait: 0.84, attendu: attendu), EtatRythme.tenu);
    });

    test('aucun jour suivi : jamais en retard sur une période non commencée',
        () {
      expect(EtatRythme.depuis(fait: 0, attendu: 0), EtatRythme.tenu);
    });
  });

  group('RythmeCoach — cible annuelle', () {
    test('une année vaut douze fois le mois, aux arrondis près', () {
      for (final annees in [1, 2, 3, 6]) {
        final r = ObjectifCoach(annees: annees).rythmePour(0);
        expect(r.cibleDeLAnnee, closeTo(r.parJour * 365, 1),
            reason: '$annees an(s)');
      }
    });

    test('la cible annuelle ne descend jamais sous 1', () {
      expect(const ObjectifCoach(annees: 6).rythmePour(239.9).cibleDeLAnnee,
          greaterThanOrEqualTo(1));
    });
  });

  group('RythmeCoach — seuil quotidien de la série', () {
    test('une échéance courte demande un vrai volume quotidien', () {
      final r = const ObjectifCoach(annees: 1).rythmePour(0);
      // 240 quarts / 365 jours x ~322,6 mots ≈ 212 mots.
      expect(r.seuilMotsParJour, closeTo(212, 2));
    });

    test('le plancher empêche une série automatique sur les longues durées',
        () {
      final r = const ObjectifCoach(annees: 6).rythmePour(0);
      // Seuil brut ≈ 35 mots, soit An-Nasr (23 mots) et une ligne : sans
      // plancher, la série ne pourrait plus se rompre.
      expect(r.seuilMotsParJour, RythmeCoach.plancherMotsParJour);
    });

    test('le seuil ne tombe jamais à zéro, même Coran acquis', () {
      final r = const ObjectifCoach(annees: 3).rythmePour(240);
      expect(r.seuilMotsParJour, RythmeCoach.plancherMotsParJour);
    });
  });
}

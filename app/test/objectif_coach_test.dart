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

  // ── L'ÉCHÉANCE EST DATÉE ET SE CONSOMME ────────────────────────────────
  //
  // Question utilisateur du 2026-08-14 : « est-ce qu'il est daté ? 4 ans, puis
  // après 4 mois je modifie en 5 ans, est-ce que ça redémarre ? ». Elle a
  // révélé que l'échéance GLISSAIT (recalculée chaque jour à partir de
  // maintenant), donc qu'aucun retard n'était visible. Ces tests verrouillent
  // la règle qu'il a posée en réponse.
  group('ObjectifCoach — échéance datée', () {
    final pose = DateTime(2026, 1, 1);
    ObjectifCoach quatreAns() =>
        ObjectifCoach(annees: 4, debut: pose);

    test('au départ 4 ans, six mois plus tard il reste 3 ans et 6 mois', () {
      final o = quatreAns();
      final dansSixMois = pose.add(const Duration(days: 182));
      final restants = o.joursRestants(dansSixMois);
      // 4 x 365 - 182 = 1278 jours, soit 3 ans (1095) + ~6 mois.
      expect(restants, 1278);
      expect(restants ~/ 365, 3);
      expect((restants % 365) ~/ 30, 6);
    });

    test('sans progrès, le rythme MONTE à mesure que le temps passe', () {
      // C'est tout l'objet du changement : le retard doit se voir dans le
      // chiffre, sans détecteur de retard ni alerte.
      final o = quatreAns();
      final auDebut = o.rythmePour(0, pose).parJour;
      final dansUnAn = o.rythmePour(0, pose.add(const Duration(days: 365)));
      expect(dansUnAn.parJour, greaterThan(auDebut));
      // 240 quarts sur les 1095 jours qui restent.
      expect(dansUnAn.parJour, closeTo(240 / 1095, 0.0001));
    });

    test('le progrès détend le rythme, même échéance inchangée', () {
      final o = quatreAns();
      final sansRien = o.rythmePour(0, pose).parJour;
      final avecCent = o.rythmePour(100, pose).parJour;
      expect(avecCent, lessThan(sansRien));
    });

    test('échéance dépassée : signalée, et le rythme ne diverge pas', () {
      final o = quatreAns();
      final apres = pose.add(const Duration(days: 4 * 365 + 10));
      expect(o.depassee(apres), isTrue);
      // Plancher à 1 jour : sans lui, division par zéro puis rythme infini
      // affiché le jour où l'utilisateur a le plus besoin d'être encouragé.
      expect(o.joursRestants(apres), 1);
      // 50 quarts ACQUIS, donc 190 restants, répartis sur le dernier jour.
      // Le chiffre est gros, mais il est FINI et exact — c'est tout ce qu'on
      // demande ici : ni infini, ni NaN.
      final r = o.rythmePour(50, apres).parJour;
      expect(r, 190);
      expect(r.isFinite, isTrue);
    });

    test('le repère vise la FIN du premier jour, jamais 0', () {
      // Correction utilisateur 2026-08-14 : « ça devrait pas être 0 au début,
      // ça devrait être l'objectif de fin de journée, donc 1 jour ». Un repère
      // à zéro ne demande rien le jour même où l'on commence.
      final o = quatreAns();
      final part = o.partDueALaFinDuJour(pose);
      expect(part, greaterThan(0));
      expect(part, closeTo(1 / (4 * 365), 0.00001));
    });

    test('le repère avance d un jour par jour', () {
      final o = quatreAns();
      final j1 = o.partDueALaFinDuJour(pose);
      final j2 = o.partDueALaFinDuJour(pose.add(const Duration(days: 1)));
      expect(j2 - j1, closeTo(1 / (4 * 365), 0.00001));
    });

    test('à mi-échéance le repère est à la moitié', () {
      final o = quatreAns();
      final moitie = o.partDueALaFinDuJour(pose.add(const Duration(days: 730)));
      expect(moitie, closeTo(0.5, 0.002));
    });

    test('le repère ne dépasse jamais 100 %', () {
      final o = quatreAns();
      expect(o.partDueALaFinDuJour(pose.add(const Duration(days: 3000))), 1.0);
    });

    test('un objectif sans date se comporte comme avant (pas de régression)',
        () {
      const o = ObjectifCoach(annees: 4); // hérité d'avant la datation
      expect(o.echeance, isNull);
      expect(o.depassee(), isFalse);
      expect(o.joursRestants(), 4 * 365);
    });
  });
}

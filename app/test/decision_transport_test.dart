// UN TEST PAR PLAINTE UTILISATEUR, NOMMÉ PAR SA DATE.
//
// Le bouton Lire/Pause du Mushaf a oscillé sur quatre correctifs (cf. l'en-tête
// de `decision_transport.dart`) : chacun réparait la plainte du jour et cassait
// celle d'avant, sans qu'aucun test ne le dise. Le symptôme du 2026-08-13 est
// revenu chez l'utilisateur le 2026-09-18, six semaines plus tard.
//
// Ces tests sont la garde : un cinquième correctif qui reprendrait un ancien
// scénario échouera ICI, au lieu de revenir par le téléphone.

import 'package:flutter_test/flutter_test.dart';

import 'package:coran_karim/services/decision_transport.dart';

void main() {
  group('bouton Lire/Pause du Mushaf', () {
    test('08-01 — « je fais pause, il recommence » : un 2e tap pendant la '
        'lecture met en PAUSE, il ne relance pas', () {
      expect(
        decisionTransport(
          afficheCeQuiJoue: true,
          selectionEstLeVersetCharge: true,
          enLecture: true,
          enPause: false,
        ),
        ActionTransport.pause,
      );
    });

    test('08-01 — « je change de sourate, je fais play, ça reste sur la '
        'première » : ce qui joue est AILLEURS, donc on lance ici', () {
      // Le lecteur est global : la sourate A joue encore pendant qu'on regarde
      // la sourate B. Sans `afficheCeQuiJoue`, le tap mettrait A en pause.
      expect(
        decisionTransport(
          afficheCeQuiJoue: false,
          selectionEstLeVersetCharge: false,
          enLecture: true,
          enPause: false,
        ),
        ActionTransport.lectureNeuve,
      );
    });

    test('08-13 / 09-18 — la lecture a ENCHAÎNÉ toute seule sur un autre '
        'verset : le tap met quand même en PAUSE', () {
      // LE test de non-régression du bug revenu. La lecture est passée au
      // verset suivant, `_activeVerse` est resté en arrière : les deux
      // divergent, et l'ancienne condition relançait depuis la sélection.
      expect(
        decisionTransport(
          afficheCeQuiJoue: true,
          selectionEstLeVersetCharge: false,
          enLecture: true,
          enPause: false,
        ),
        ActionTransport.pause,
      );
    });

    test('08-16 — en pause, je sélectionne un AUTRE verset : le play prend la '
        'nouvelle sélection, il ne reprend pas l\'ancienne', () {
      expect(
        decisionTransport(
          afficheCeQuiJoue: true,
          selectionEstLeVersetCharge: false,
          enLecture: false,
          enPause: true,
        ),
        ActionTransport.lectureNeuve,
      );
    });

    test('reprise normale : en pause sur le verset sélectionné, le tap '
        'REPREND', () {
      expect(
        decisionTransport(
          afficheCeQuiJoue: true,
          selectionEstLeVersetCharge: true,
          enLecture: false,
          enPause: true,
        ),
        ActionTransport.reprise,
      );
    });

    test('rien de chargé : le tap lance', () {
      expect(
        decisionTransport(
          afficheCeQuiJoue: false,
          selectionEstLeVersetCharge: false,
          enLecture: false,
          enPause: false,
        ),
        ActionTransport.lectureNeuve,
      );
    });

    test('le lecteur joue mais l\'écran n\'affiche pas ce passage, et la '
        'sélection coïncide par hasard : on lance ici', () {
      // Garde-fou : `selectionEstLeVersetCharge` ne doit JAMAIS suffire à
      // déclencher un transport quand le passage n'est pas celui affiché.
      expect(
        decisionTransport(
          afficheCeQuiJoue: false,
          selectionEstLeVersetCharge: true,
          enLecture: true,
          enPause: false,
        ),
        ActionTransport.lectureNeuve,
      );
    });
  });
}

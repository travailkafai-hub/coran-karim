// Le test qui compte : le paquet produit ici doit être déchiffrable PAR L'AUTRE
// CÔTÉ.
//
// Un test Dart qui chiffrerait puis déchiffrerait lui-même ne prouverait rien
// d'utile : deux implémentations d'un même format peuvent être cohérentes avec
// elles-mêmes et incompatibles entre elles — un ordre d'octets dans `info`, un
// `aad` oublié, et rien ne le signale. Le seul défaut qui compte ici est celui
// qu'on découvrirait après avoir collecté des milliers de sessions devenues
// illisibles.
//
// Ce test écrit donc un paquet sur disque, et `benchmark/collecte_chiffrement_interop.py`
// vérifie que le Python le rouvre. Les deux se lancent ensemble :
//
//     flutter test test/collecte_chiffrement_test.dart
//     python benchmark/collecte_chiffrement_interop.py

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:coran_karim/services/collecte_chiffrement.dart';

/// Clé PUBLIQUE de test, sans valeur : sa privée est dans le dépôt, juste à
/// côté, et ne sert qu'à ce test. La clé de production ne figure nulle part
/// ici — elle se génère sur la machine d'entraînement.
const _clePubliqueTest =
    'daf2a39e78586bf7ac0e9c43ad8185d23c6283124d6de2a4fc7866c84d33e015';

void main() {
  group('chiffrement de la collecte', () {
    test('sans clé configurée, rien ne peut être chiffré', () async {
      // Le comportement voulu est de rendre `null`, jamais du clair : tant
      // qu'aucune clé n'est posée, la collecte doit être inerte.
      expect(CollecteChiffrement.pretAEnvoyer, isFalse,
          reason: 'la constante de production ne doit PAS porter de clé '
              'tant que la paire n\'est pas générée');
      expect(await CollecteChiffrement.chiffrer([1, 2, 3]), isNull);
    });

    test('le paquet a la forme annoncée par le format', () async {
      final clair = utf8.encode('بسم الله — session de test');
      final paquet = await CollecteChiffrement.chiffrer(clair,
          clePubliqueHex: _clePubliqueTest);
      expect(paquet, isNotNull);
      expect(paquet!.sublist(0, 4), kCollecteMagique, reason: 'magique "CKR1"');
      // 4 magique + 32 éphémère + 12 nonce + clair + 16 tag
      expect(paquet.length, clair.length + 64);
    });

    test('deux chiffrements du MÊME message diffèrent (paire éphémère par envoi)',
        () async {
      final clair = utf8.encode('même contenu');
      final a = await CollecteChiffrement.chiffrer(clair,
          clePubliqueHex: _clePubliqueTest);
      final b = await CollecteChiffrement.chiffrer(clair,
          clePubliqueHex: _clePubliqueTest);
      expect(a, isNotNull);
      expect(a, isNot(equals(b)),
          reason: 'sans paire éphémère renouvelée, deux sessions du même '
              'appareil partageraient une clé');
    });

    test('écrit un paquet que le Python doit pouvoir rouvrir', () async {
      // Contenu volontairement non trivial : de l'arabe, des octets nuls et
      // une taille qui dépasse un bloc AES.
      final clair = <int>[
        ...utf8.encode('ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ'),
        0, 0, 0, 255,
        ...List<int>.generate(5000, (i) => i % 256),
      ];
      final paquet = await CollecteChiffrement.chiffrer(clair,
          clePubliqueHex: _clePubliqueTest);
      expect(paquet, isNotNull);

      final dossier = Directory('build/collecte_interop')
        ..createSync(recursive: true);
      File('${dossier.path}/paquet_dart.bin').writeAsBytesSync(paquet!);
      File('${dossier.path}/clair_attendu.bin').writeAsBytesSync(clair);
      // Le test Dart s'arrête ici : c'est le script Python qui tranche.
      expect(File('${dossier.path}/paquet_dart.bin').lengthSync(),
          clair.length + 64);
    });
  });
}

// QUAL-01 (audit securite 2026-09-06) : `QuranApi` peut planter ou melanger
// Hafs/Warsh sous concurrence. Rejoue le scenario de l'audit -- canal
// d'assets intercepte avec deux jeux de donnees factices -- pour verifier le
// correctif de `_ensureLoaded()`, plutot que de se fier a la lecture du code.
//
// Trois bugs, tous confirmes par execution avant d'etre corriges :
//   1. plantage : `_chapters != null` pris pour preuve de chargement COMPLET
//      alors que `_versesBySurah` pouvait rester nul (rapport, reproduit).
//   2. melange : un chargement Hafs en vol pouvait publier ses resultats
//      APRES une bascule vers Warsh, ecrasant le texte actif (rapport,
//      reproduit).
//   3. plantage residuel, trouve en VERIFIANT le correctif des deux premiers
//      par execution : entre `await _ensureLoaded()` (chemin rapide, cache
//      deja rempli) et la relecture du cache par l'appelant, une bascule
//      SYNCHRONE peut s'intercaler et nuller ce cache dans l'intervalle.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:coran_karim/models/riwaya.dart';
import 'package:coran_karim/services/quran_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const chaptersJson = '''
  [{"id": 1, "name_arabic": "الفاتحة", "name_simple": "Al-Fatiha",
    "translated_name": {"name": "L'ouverture"}, "verses_count": 7,
    "revelation_place": "makkah"}]
  ''';

  String versesJson(String marqueur) => jsonEncode([
        {
          'verse_key': '1:1',
          'text_uthmani': marqueur,
          'page_number': 1,
        },
      ]);

  void installerCanalAssets({
    required Duration delaiHafs,
    required Duration delaiWarsh,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final cle = utf8.decode(message!.buffer.asUint8List());
      String corps;
      Duration delai = Duration.zero;
      if (cle == 'assets/data/quran_chapters.json') {
        corps = chaptersJson;
      } else if (cle == 'assets/data/quran_verses.json') {
        corps = versesJson('HAFS_FIXTURE');
        delai = delaiHafs;
      } else if (cle == 'assets/data/quran_verses_warsh.json') {
        corps = versesJson('WARSH_FIXTURE');
        delai = delaiWarsh;
      } else {
        return null;
      }
      if (delai > Duration.zero) await Future<void>.delayed(delai);
      final octets = utf8.encode(corps);
      return ByteData.view(Uint8List.fromList(octets).buffer);
    });
  }

  /// Remet `QuranApi` dans un etat totalement neuf entre chaque test : basculer
  /// deux fois de riwaya, quel que soit l'etat de depart, GARANTIT que le
  /// setter s'execute reellement (son garde `if (value == _riwaya) return;`
  /// ne ferait sinon rien si le test precedent avait laisse la riwaya sur la
  /// meme valeur -- defaut de methode qui a fait echouer une premiere version
  /// de ce fichier en laissant un cache d'un test contaminer le suivant).
  void reinitialiser() {
    QuranApi.riwaya = Riwaya.warsh;
    QuranApi.riwaya = Riwaya.hafs;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  }

  setUp(reinitialiser);
  tearDown(reinitialiser);

  test('deux appels concurrents pendant le chargement ne plantent plus '
      '(bug 1)', () async {
    installerCanalAssets(
      delaiHafs: const Duration(milliseconds: 30),
      delaiWarsh: Duration.zero,
    );

    final premier = QuranApi.fetchVerses(1);
    final second = QuranApi.fetchVerses(1);

    final resultats = await Future.wait([premier, second]);
    expect(resultats[0].single.textUthmani, 'HAFS_FIXTURE');
    expect(resultats[1].single.textUthmani, 'HAFS_FIXTURE');
  });

  test('une bascule Warsh pendant un chargement Hafs en vol ne se fait pas '
      'ecraser (bug 2)', () async {
    installerCanalAssets(
      delaiHafs: const Duration(milliseconds: 60),
      delaiWarsh: Duration.zero,
    );

    final chargementHafs = QuranApi.fetchVerses(1);
    QuranApi.riwaya = Riwaya.warsh;
    final versetsWarsh = await QuranApi.fetchVerses(1);
    expect(versetsWarsh.single.textUthmani, 'WARSH_FIXTURE');

    await chargementHafs;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final apresCoup = await QuranApi.fetchVerses(1);
    expect(apresCoup.single.textUthmani, 'WARSH_FIXTURE',
        reason: 'le chargement Hafs perime ne doit plus rien publier');
  });

  test('une bascule pile entre chargement termine et lecture ne plante '
      'plus (bug 3, chemin rapide)', () async {
    // Hafs se charge et publie d'abord (delai nul des deux cotes) : le
    // PREMIER appel emprunte le chemin RAPIDE de `_ensureLoaded` (cache deja
    // rempli). C'est precisement ce chemin, pas le chargement lui-meme, qui
    // portait la troisieme course.
    installerCanalAssets(delaiHafs: Duration.zero, delaiWarsh: Duration.zero);
    await QuranApi.fetchVerses(1);

    // Chemin rapide + bascule synchrone juste apres : avant le correctif,
    // ceci levait `Null check operator used on a null value`.
    final lecture = QuranApi.fetchVerses(1);
    QuranApi.riwaya = Riwaya.warsh;
    final resultat = await lecture;

    // La lecture avait deja commence en Hafs : elle peut legitimement rendre
    // l'un ou l'autre texte selon l'instant exact de la bascule -- ce que ce
    // test exige, c'est qu'elle NE PLANTE PAS.
    expect(resultat, isNotEmpty);
  });
}

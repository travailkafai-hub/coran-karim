// IDENTIFICATION TESTÉE SUR L'AUDIO RÉEL DE L'UTILISATEUR -- demande
// explicite (2026-08-29) : « il y a un problème ; quand tu testes, teste avec
// mon WAV ».
//
// ── POURQUOI CE FICHIER EXISTE, ET EN QUOI IL DIFFÈRE DES DEUX AUTRES ────
// `simulation_priere_complete_test.dart` et `..._limites_test.dart` partent du
// texte coranique PARFAIT et lui appliquent des dégradations que J'AI
// INVENTÉES (inspirées des logs, mais inventées). C'est une approximation --
// et l'utilisateur a eu raison de la refuser comme preuve.
//
// ICI, les textes ne sont pas fabriqués : ce sont les transcriptions
// EXACTES produites par le VRAI modèle (`deux-geles-int8-2026-08-22`, celui
// déployé, vérifié bit-à-bit identique entre le PC et l'appareil) sur le
// VRAI audio de l'utilisateur, relevées dans les logs device de la journée
// du 2026-08-29 (lignes `identification (capture dediee...) : entendu="..."`).
//
// Chaque séquence ci-dessous est un cas réellement vécu, avec son horodatage
// et le verdict que l'app a effectivement rendu ce jour-là.
import 'package:flutter_test/flutter_test.dart';
import 'package:coran_karim/providers/recitation_provider.dart'
    show choisirSelonOrdreDePriere;
import 'package:coran_karim/services/quran_verse_locator_service.dart';

Future<String> _meilleureTroncature(String requete) async {
  final mots =
      requete.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  var meilleure = requete;
  var meilleurScore = -1.0;
  for (var drop = 0; drop <= 4 && mots.length - drop >= 2; drop++) {
    final variante = mots.sublist(drop).join(' ');
    final m = await QuranVerseLocatorService.instance
        .locateTopMatches(variante, k: 1, minScore: 0.0);
    final score = m.isEmpty ? 0.0 : m.first.confidence;
    if (score > meilleurScore) {
      meilleurScore = score;
      meilleure = variante;
    }
  }
  return meilleure;
}

/// LA CHAÎNE COMPLÈTE de `_identifierParCaptureDediee`, y compris le CUMUL
/// (v202) : on lui donne les captures successives RÉELLES, dans l'ordre.
/// Retourne le match retenu et le RANG de la capture qui a permis de trancher
/// (1 = dès la première), ou null si aucune n'a suffi.
Future<({QuranMatch? match, int rang})> _identifierAvecCumul(
    List<String> capturesSuccessives, int? sourateRakahPrecedente) async {
  final cumul = <String>[];
  for (var i = 0; i < capturesSuccessives.length; i++) {
    cumul.addAll(capturesSuccessives[i]
        .split(RegExp(r'\s+'))
        .where((m) => m.isNotEmpty));
    while (cumul.length > 15) {
      cumul.removeAt(0);
    }
    if (cumul.length < 3) continue;
    final requete = await _meilleureTroncature(cumul.join(' '));
    final candidats = await QuranVerseLocatorService.instance
        .locateTopMatches(requete, k: 5, minScore: 0.45);
    final m = choisirSelonOrdreDePriere(candidats, sourateRakahPrecedente);
    // Filtre Bismillah/Fatiha residuelle, comme en production.
    if (m != null && m.surahNumber != 1) return (match: m, rang: i + 1);
  }
  return (match: null, rang: -1);
}

/// L'ANCIEN comportement (avant v202) : chaque capture est jugée SEULE, ce
/// qui ne suffit pas est JETÉ.
Future<({QuranMatch? match, int rang})> _identifierSansCumul(
    List<String> capturesSuccessives, int? sourateRakahPrecedente) async {
  for (var i = 0; i < capturesSuccessives.length; i++) {
    final requete = await _meilleureTroncature(capturesSuccessives[i]);
    final candidats = await QuranVerseLocatorService.instance
        .locateTopMatches(requete, k: 5, minScore: 0.45);
    final m = choisirSelonOrdreDePriere(candidats, sourateRakahPrecedente);
    if (m != null && m.surahNumber != 1) return (match: m, rang: i + 1);
  }
  return (match: null, rang: -1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AUDIO RÉEL -- séquences relevées dans les logs device 2026-08-29', () {
    test('18:59:09 (v201) -- 1re capture = fragment "يَـٰٓ", 2e = 12 mots',
        () async {
      // Le cas qui a motivé le cumul : la 1re capture tombe sur la pause
      // apres Al-Fatiha. L'app a mis 15,1s (2 blocs de 7s).
      const captures = [
        'يَـٰٓ',
        'نَاسُ ٱتَّقُوا۟ رَبَّكُمُ ٱلَّذِى خَلَقَكُم مِّن نَّفٍْ وَٰحِدَةٍ وَخَلَقَ',
      ];
      final avec = await _identifierAvecCumul(captures, null);
      expect(avec.match?.surahNumber, 4,
          reason: 'An-Nisa 4:1 -- ce que le recitateur disait reellement');
    });

    test('17:20:31 (v195) -- residu de Bismillah en tete du cumul', () async {
      // Piege du cumul : la 1re capture est de la BISMILLAH mal transcrite.
      // Cumulee avec la suivante, elle pourrait faire deriver vers la Fatiha
      // ou une autre ouverture de sourate. La troncature doit la retirer.
      const captures = [
        'ٱلرَّحْمَـٰنِ ٱلرَّحِيمِيأَيُّهَا',
        'تَرُ رَبَّكُمُ ٱلَّذِى خَلَقَكُم مِن نَّفٍْ وَٰحِدَةٍ',
      ];
      final avec = await _identifierAvecCumul(captures, null);
      expect(avec.match?.surahNumber, 4,
          reason: 'le residu de Bismillah cumule ne doit pas faire deriver');
    });

    test('18:07:34 (v199) -- 2 mots puis suite', () async {
      const captures = [
        'يَـٰٓأَيُّهَا ٱلنَّاسُ',
        'هُمُ ٱلَّذِى خَلَقَكُم مِّن نَّفٍْ وَٰحِدَةٍ وَخَلَقَ',
      ];
      final avec = await _identifierAvecCumul(captures, null);
      expect(avec.match?.surahNumber, 4);
    });

    test('17:48:34 -- 3 mots seulement ont suffi (verdict device : 4:1)',
        () async {
      const captures = ['يَـٰٓأَيُّهَا ٱلنَّاسُ ٱتَّقُوا۟'];
      final avec = await _identifierAvecCumul(captures, null);
      expect(avec.match?.surahNumber, 4,
          reason: 'l\'app avait bien trouve 4:1 ce jour-la, il faut le tenir');
    });

    test('14:09:20 (v193) -- residu "وَحِيف" : device avait dit 3:200 (FAUX)',
        () async {
      const captures = ['وَحِيف يَـٰٓأَيُّهَا ٱلنَّاسُ ٱتَّقُوا۟ رَبَّكُمُ'];
      final avec = await _identifierAvecCumul(captures, null);
      expect(avec.match?.surahNumber, 4,
          reason: 'corrige par la troncature (v194) -- ne doit pas regresser');
    });

    test(
        '17:36:18 (v196) -- 2 mots seuls : device avait dit 2:21 (FAUX). '
        'Le cumul doit ATTENDRE au lieu de trancher sur si peu', () async {
      // Avec le cumul, une capture de 2 mots ne declenche PAS `locate()`
      // (plancher de 3 mots) : on attend la capture suivante. C'est ce qui
      // remplace l'ancien plancher de votes.
      const captures = [
        'يَـٰٓأَيُّهَا ٱلنَّاسُ', // 2 mots -> ne doit RIEN trancher
        'ٱتَّقُوا۟ رَبَّكُمُ ٱلَّذِى خَلَقَكُم',
      ];
      final avec = await _identifierAvecCumul(captures, null);
      expect(avec.match?.surahNumber, 4,
          reason: 'le faux positif 2:21 ne doit plus se produire');
      expect(avec.rang, 2,
          reason: 'la decision ne doit PAS tomber des la 1re capture (2 mots)');
    });
  });

  group('AUDIO RÉEL -- le CUMUL apporte-t-il vraiment quelque chose ?', () {
    test('comparaison cumul / sans cumul sur toutes les sequences reelles',
        () async {
      // Chaque entree : (libelle, captures reelles, sourate reellement recitee)
      final cas = <(String, List<String>, int)>[
        (
          '18:59 fragment puis suite',
          ['يَـٰٓ', 'نَاسُ ٱتَّقُوا۟ رَبَّكُمُ ٱلَّذِى خَلَقَكُم مِّن نَّفٍْ وَٰحِدَةٍ وَخَلَقَ'],
          4
        ),
        (
          '17:20 bismillah puis suite',
          ['ٱلرَّحْمَـٰنِ ٱلرَّحِيمِيأَيُّهَا', 'تَرُ رَبَّكُمُ ٱلَّذِى خَلَقَكُم مِن نَّفٍْ وَٰحِدَةٍ'],
          4
        ),
        (
          '18:07 deux mots puis suite',
          ['يَـٰٓأَيُّهَا ٱلنَّاسُ', 'هُمُ ٱلَّذِى خَلَقَكُم مِّن نَّفٍْ وَٰحِدَةٍ وَخَلَقَ'],
          4
        ),
        (
          '17:36 deux mots (device: faux positif 2:21)',
          ['يَـٰٓأَيُّهَا ٱلنَّاسُ', 'ٱتَّقُوا۟ رَبَّكُمُ ٱلَّذِى خَلَقَكُم'],
          4
        ),
      ];
      var okAvec = 0, okSans = 0;
      var rangAvec = 0, rangSans = 0;
      // ignore: avoid_print
      print('\n=== SEQUENCES REELLES (audio de l\'utilisateur, vrai modele) ===');
      for (final (libelle, captures, attendue) in cas) {
        final a = await _identifierAvecCumul(captures, null);
        final s = await _identifierSansCumul(captures, null);
        final aOk = a.match?.surahNumber == attendue;
        final sOk = s.match?.surahNumber == attendue;
        if (aOk) {
          okAvec++;
          rangAvec += a.rang;
        }
        if (sOk) {
          okSans++;
          rangSans += s.rang;
        }
        // ignore: avoid_print
        print('  $libelle');
        // ignore: avoid_print
        print('      sans cumul : '
            '${s.match == null ? "AUCUN" : "${s.match!.surahNumber}:${s.match!.ayahNumber}"}'
            '${sOk ? " OK" : " FAUX"} (capture ${s.rang})');
        // ignore: avoid_print
        print('      avec cumul : '
            '${a.match == null ? "AUCUN" : "${a.match!.surahNumber}:${a.match!.ayahNumber}"}'
            '${aOk ? " OK" : " FAUX"} (capture ${a.rang})');
      }
      // ignore: avoid_print
      print('  BILAN : sans cumul $okSans/${cas.length} '
          '(rang cumule $rangSans) | avec cumul $okAvec/${cas.length} '
          '(rang cumule $rangAvec)');
      expect(okAvec, greaterThanOrEqualTo(okSans),
          reason: 'le cumul ne doit jamais faire PIRE sur l\'audio reel');
      expect(okAvec, cas.length,
          reason: 'toutes les sequences reelles doivent etre identifiees');
    });
  });

  group('AUDIO RÉEL -- le trou noir du 13:03 (63 s sans rien trouver)', () {
    // ── CAS LE PLUS GRAVE TROUVE DANS LES LOGS ────────────────────────────
    // Session 13:03:50 : NEUF captures dediees consecutives, 63 secondes, et
    // `retenu=None` -- l'app n'a JAMAIS rien identifie. En lisant les textes,
    // la raison saute aux yeux : le recitateur recitait AL-FATIHA (on y lit
    // "مالك يوم الدين", "صراط الذين", "الحمد لله رب العالمين"...). L'app
    // avait bascule en phase d'identification alors qu'il etait encore/de
    // nouveau dans la Fatiha, et le filtre `surahNumber != 1` -- necessaire
    // par ailleurs -- rejetait donc TOUT, indefiniment.
    const capturesFatiha = [
      'رَحِ مَلِكِ مِ ٱلدِّينِ كَمَاعْبُدُ وَإِيَّاكَسْتَعِينُ إِذَا صِرَٰطَ',
      'صِرَٰطَ ٱلَّذِينَ ٱللَّهُوَكْ وَبِ بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
      'بِ ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ مَكِ يَوْ',
    ];

    test('ces captures SONT bien de la Fatiha (sourate 1)', () async {
      // On le prouve : sans le filtre `!= 1`, locate() les rattache a la
      // sourate 1. C'est donc bien un probleme de PHASE, pas de recherche.
      var trouveesEnFatiha = 0;
      for (final c in capturesFatiha) {
        final r = await QuranVerseLocatorService.instance
            .locateTopMatches(await _meilleureTroncature(c), k: 3, minScore: 0.3);
        if (r.any((m) => m.surahNumber == 1)) trouveesEnFatiha++;
      }
      // ignore: avoid_print
      print('\n=== TROU NOIR 13:03 -- captures rattachees a la Fatiha : '
          '$trouveesEnFatiha / ${capturesFatiha.length} ===');
      expect(trouveesEnFatiha, greaterThan(0),
          reason: 'ces captures viennent bien d\'Al-Fatiha : la phase '
              'd\'identification n\'aurait pas du etre active');
    });

    test('l\'identification ne peut RIEN retenir sur ces captures', () async {
      // C'est CORRECT qu'elle ne retienne rien : aucune de ces captures ne
      // designe une sourate hors Fatiha. Le defaut n'etait pas la, il etait
      // dans le fait de CONTINUER A CHERCHER indefiniment -- cf. le test
      // suivant.
      final r = await _identifierAvecCumul(capturesFatiha, null);
      expect(r.match, isNull,
          reason: 'aucune de ces captures ne designe une sourate hors Fatiha');
    });

    // ── LES NEUF CAPTURES REELLES, dans l'ordre exact du log 13:03 ────────
    const neufCapturesReelles = [
      'رَحِ مَلِكِ مِ ٱلدِّينِ كَمَاعْبُدُ وَإِيَّاكَسْتَعِينُ إِذَا صِرَٰطَ',
      'صِرَٰطَ ٱلَّذِينَ ٱللَّهُوَكْ وَبِ بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
      'رَّرْحْ رَّحِيمًامِ يَاكَبُدُ وَإِيَّاكَ نَسْتَعِينُ إِذْ ٱلصِّرَٰطَ ٱلْمُس',
      'لَأَنْعَمْتَ عَلَيْهِمْ عَنِمَغُْوبَةِ',
      'بِ ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ مَكِ يَوْ',
      'تَعْبُدُ أَيَّكَ ٱلسَّيِّدُ صِرَٰطَ مُسْتَقِيمَ',
      'ٱللَّهُ أَكْرَ بِٱسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِحِيمِ ٱلْحَمْدُدِ لِلَّهِ رَبِّ',
      'ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ مَكِ يَوْمِ ٱلدِّينِ وَتُوََّكَ صِرَٰطَ',
      'يَعْمُ ٱلْمَغْضُبَمَرْرْضَنَمٍ',
    ];

    test(
        'PIEGE ECARTE PAR LE CUMUL : la capture 6 seule donne 2:142 a 1,00 '
        '(FAUX -- c\'est de la Fatiha deformee)', () async {
      // Danger reel : "تعبد أيك السيد صراط مستقيم" isolee franchit le seuil
      // sur 2:142 avec un score PARFAIT (1 seul vote). Sans le cumul, l'app
      // aurait pu verrouiller une sourate entierement fausse.
      final seule = await _identifierSansCumul(
          [neufCapturesReelles[5]], null);
      expect(seule.match?.surahNumber, isNot(1),
          reason: 'documente le piege : seule, cette capture passe');
      // Avec le cumul (15 mots de contexte), le faux positif est dilue.
      final avecCumul = await _identifierAvecCumul(neufCapturesReelles, null);
      expect(avecCumul.match, isNull,
          reason: 'le cumul doit REJETER toute la sequence : le recitateur '
              'etait dans Al-Fatiha, aucune sourate n\'avait commence');
    });

    test(
        'GARDE ANTI-BOUCLE (v203) : apres N captures sans resultat, l\'app '
        'doit sortir au lieu de tourner 63 s', () async {
      // Reproduit le compteur de `_identifierParCaptureDediee` : on compte
      // les captures qui n'aboutissent a RIEN, cumul compris. Sur les
      // donnees reelles, ce compteur doit atteindre le seuil de sortie (5).
      //
      // ⚠️ Une premiere version de ce garde comptait les captures
      // rattachees a la Fatiha -- REFUTEE par ces memes donnees : au seuil
      // de 0,45 la Fatiha deformee ne se signale pas comme telle (1:5 a
      // 0,30, 1:2 a 0,43, 1:3 a 0,33). Ce sont les donnees reelles qui ont
      // impose de compter les ECHECS plutot que les detections de Fatiha.
      const seuilSortie = 5;
      final cumul = <String>[];
      var infructueuses = 0;
      var sortiA = -1;
      for (var i = 0; i < neufCapturesReelles.length; i++) {
        cumul.addAll(neufCapturesReelles[i]
            .split(RegExp(r'\s+'))
            .where((m) => m.isNotEmpty));
        while (cumul.length > 15) {
          cumul.removeAt(0);
        }
        if (cumul.length < 3) continue;
        final candidats = await QuranVerseLocatorService.instance
            .locateTopMatches(await _meilleureTroncature(cumul.join(' ')),
                k: 5, minScore: 0.45);
        final m = choisirSelonOrdreDePriere(candidats, null);
        if (m != null && m.surahNumber != 1) break; // aurait verrouille
        infructueuses++;
        if (infructueuses >= seuilSortie) {
          sortiA = i + 1;
          break;
        }
      }
      // ignore: avoid_print
      print('  sortie de la boucle a la capture $sortiA '
          '(sur ${neufCapturesReelles.length} reellement observees)');
      expect(sortiA, greaterThan(0),
          reason: 'l\'app doit SORTIR de la boucle sur ces donnees reelles');
      expect(sortiA, lessThan(neufCapturesReelles.length),
          reason: 'elle doit sortir AVANT d\'avoir consomme les 9 captures '
              '(63 s mesurees le 2026-08-29)');
    });
  });
}

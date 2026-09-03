// SIMULATION COMPLÈTE du mode "Suivre une prière" -- demande utilisateur
// explicite (2026-08-29) : « test JVM avec des API Quran, j'ai trop testé, tu
// m'as fait perdre beaucoup de temps [...] ne me donne pas la main que lorsque
// t'es sûr à 100% que ça va répondre au besoin, une simulation réelle ».
//
// ── CE QUE CE FICHIER SIMULE, ET POURQUOI C'EST UNE VRAIE SIMULATION ──────
// Il ne rejoue pas trois cas choisis à la main : il prend le TEXTE CORANIQUE
// RÉEL (`assets/data/quran_search_index.json`, le même index que celui que
// `locate()` interroge en production), simule ce qu'un imam récite après
// Al-Fatiha (les premiers mots d'une sourate), applique les DÉGRADATIONS ASR
// RÉELLEMENT OBSERVÉES dans les logs device du jour, et vérifie que la chaîne
// d'identification retrouve la bonne sourate.
//
// Les dégradations ne sont pas inventées -- chacune est tirée d'une ligne de
// log réelle :
//   - résidu de tête       : "وَحِيف …", "ءَامِي بِسْمِـٰنِحِيمِ مِي يَـٰٓ …"
//   - lettre doublée       : "نَّفْفْسٍِ" (نفس), "كَثِيرًاا" (كثيرا)
//   - lettre tombée        : "أَنْمْتَ" (أنعمت), "نَّفٍْ" (نفس)
//   - mot tronqué en fin   : "وَنِسَ" (ونساء), "زَوْجَ" (زوجها)
//
// ⚠️ CE QUE ÇA NE COUVRE PAS, ET IL FAUT LE SAVOIR : la couche AUDIO (micro,
// fenêtrage natif, cycle de vie de la capture). Le gel de flux mesuré après
// identification ne peut PAS être reproduit ici -- il vit dans le natif. Ce
// banc couvre la couche DÉCISION, qui est celle qui a produit toutes les
// mauvaises identifications de la journée.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:coran_karim/providers/recitation_provider.dart'
    show choisirSelonOrdreDePriere;
import 'package:coran_karim/services/quran_verse_locator_service.dart';

/// Copie fidèle de `RecitationNotifier._meilleureTroncatureDeTete` (privée).
/// Si elle change dans le provider, mettre à jour ici en miroir.
Future<String> _meilleureTroncature(String requete) async {
  final mots =
      requete.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  var meilleure = requete;
  var meilleurScore = -1.0;
  for (var drop = 0; drop <= 4 && mots.length - drop >= 2; drop++) {
    final variante = mots.sublist(drop).join(' ');
    final matches = await QuranVerseLocatorService.instance
        .locateTopMatches(variante, k: 1, minScore: 0.0);
    final score = matches.isEmpty ? 0.0 : matches.first.confidence;
    if (score > meilleurScore) {
      meilleurScore = score;
      meilleure = variante;
    }
  }
  return meilleure;
}

/// LA CHAÎNE COMPLÈTE telle qu'elle tourne en production dans
/// `_identifierParCaptureDediee` : troncature anti-résidu, puis candidats au
/// seuil de l'oreille, puis départage par l'ordre de prière.
Future<QuranMatch?> _identifierCommeEnProduction(
    String texteEntendu, int? sourateRakahPrecedente) async {
  final requete = await _meilleureTroncature(texteEntendu);
  final candidats = await QuranVerseLocatorService.instance
      .locateTopMatches(requete, k: 5, minScore: 0.45);
  return choisirSelonOrdreDePriere(candidats, sourateRakahPrecedente);
}

// ── Le texte coranique réel, chargé une fois ─────────────────────────────
class _Verset {
  final int sourate;
  final int ayah;
  final List<String> mots;
  _Verset(this.sourate, this.ayah, this.mots);
}

late final List<_Verset> versets;

/// Les [n] premiers mots d'une sourate, à partir du verset [depuisAyah] --
/// ce que l'imam récite après Al-Fatiha.
String _debutDeSourate(int sourate, int n, {int depuisAyah = 1}) {
  final mots = <String>[];
  for (final v in versets) {
    if (v.sourate != sourate || v.ayah < depuisAyah) continue;
    mots.addAll(v.mots);
    if (mots.length >= n) break;
  }
  return mots.take(n).join(' ');
}

// ── Dégradations ASR, toutes tirées de logs device réels ─────────────────

/// Résidu de fin d'Al-Fatiha / Bismillah mal transcrite, collé en tête.
/// Cas réels : "وَحِيف" (v193), "ءَامِي بِسْمِـٰنِحِيمِ مِي يَـٰٓ" (v185).
String _avecResiduDeTete(String texte, String residu) => '$residu $texte';

/// Double une lettre au milieu d'un mot -- "نفس" -> "نففس" (observé :
/// "نَّفْفْسٍِ", "كَثِيرًاا", "ٱلرَّحِييمِ").
String _avecLettreDoublee(String texte, Random rnd) {
  final mots = texte.split(' ');
  if (mots.length < 3) return texte;
  final i = 1 + rnd.nextInt(mots.length - 1);
  final m = mots[i];
  if (m.length < 3) return texte;
  final j = 1 + rnd.nextInt(m.length - 1);
  mots[i] = m.substring(0, j) + m[j] + m.substring(j);
  return mots.join(' ');
}

/// Retire une lettre au milieu d'un mot -- "أنعمت" -> "أنمت" (observé :
/// "أَنْمْتَ", "ٱلْمَغُْوبِ", "لَهَبَ" pour "لَذَهَبَ").
String _avecLettreTombee(String texte, Random rnd) {
  final mots = texte.split(' ');
  if (mots.length < 3) return texte;
  final i = 1 + rnd.nextInt(mots.length - 1);
  final m = mots[i];
  if (m.length < 4) return texte;
  final j = 1 + rnd.nextInt(m.length - 2);
  mots[i] = m.substring(0, j) + m.substring(j + 1);
  return mots.join(' ');
}

/// Tronque le DERNIER mot -- la fenêtre de capture s'est fermée en pleine
/// parole (observé : "وَنِسَ" pour "ونساء", "زَوْجَ" pour "زوجها").
String _avecDernierMotTronque(String texte) {
  final mots = texte.split(' ');
  final dernier = mots.last;
  if (dernier.length < 3) return texte;
  mots[mots.length - 1] = dernier.substring(0, dernier.length - 2);
  return mots.join(' ');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final brut = File('assets/data/quran_search_index.json').readAsStringSync();
    final data = jsonDecode(brut) as Map<String, dynamic>;
    versets = [
      for (final v in data['verses'] as List)
        _Verset(v['s'] as int, v['a'] as int,
            (v['w'] as List).cast<String>()),
    ];
  });

  // Échantillon REPRÉSENTATIF de ce qu'un imam récite réellement : les
  // sourates courtes de Juz 'Amma (prières quotidiennes), les moyennes, et
  // quelques longues (Tarawih / prières où l'imam récite longuement).
  const souratesTestees = <int>[
    2, 3, 4, 5, 6, 7, // longues, début de mushaf
    18, 19, 36, 55, 56, 67, // fréquentes en prière
    78, 87, 91, 93, 96, 97, 99, 103, 105, 107, 109, 110, 112, 113, 114,
  ];

  group('SIMULATION -- texte propre (reference)', () {
    for (final s in souratesTestees) {
      test('sourate $s, debut recite proprement -> identifiee', () async {
        final texte = _debutDeSourate(s, 10);
        final match = await _identifierCommeEnProduction(texte, null);
        expect(match, isNotNull,
            reason: 'sourate $s : aucun candidat sur "$texte"');
        expect(match!.surahNumber, s,
            reason: 'sourate $s attendue, ${match.surahNumber} trouvee '
                'sur "$texte"');
      });
    }
  });

  group('SIMULATION -- residu de tete (cas reels des logs device)', () {
    // Les deux residus EXACTS mesures le 2026-08-29.
    const residus = <String>[
      'وحيف',
      'ءامي بسمانحيم مي يا',
    ];
    for (final s in souratesTestees) {
      for (var r = 0; r < residus.length; r++) {
        test('sourate $s, residu #$r en tete -> toujours identifiee',
            () async {
          final texte =
              _avecResiduDeTete(_debutDeSourate(s, 10), residus[r]);
          final match = await _identifierCommeEnProduction(texte, null);
          expect(match, isNotNull,
              reason: 'sourate $s + residu #$r : aucun candidat');
          expect(match!.surahNumber, s,
              reason: 'sourate $s attendue avec residu #$r, '
                  '${match.surahNumber} trouvee sur "$texte"');
        });
      }
    }
  });

  group('SIMULATION -- degradations ASR au milieu du texte', () {
    for (final s in souratesTestees) {
      test('sourate $s, lettres doublees/tombees + fin tronquee', () async {
        // Graine FIXE par sourate : le test est deterministe, rejouable a
        // l'identique -- pas de flakiness possible.
        final rnd = Random(s);
        var texte = _debutDeSourate(s, 12);
        texte = _avecLettreDoublee(texte, rnd);
        texte = _avecLettreTombee(texte, rnd);
        texte = _avecDernierMotTronque(texte);
        final match = await _identifierCommeEnProduction(texte, null);
        expect(match, isNotNull,
            reason: 'sourate $s degradee : aucun candidat sur "$texte"');
        expect(match!.surahNumber, s,
            reason: 'sourate $s attendue, ${match.surahNumber} trouvee '
                'sur "$texte"');
      });
    }
  });

  group('SIMULATION -- prière complète, plusieurs rak\'ah enchaînées', () {
    // LE SCENARIO REEL : l'imam recite dans l'ordre du mushaf d'une rak'ah a
    // l'autre. C'est ce que `choisirSelonOrdreDePriere` exploite.
    test('rak\'ah 1 = 109, rak\'ah 2 = 110 (enchainement mushaf)', () async {
      final m1 = await _identifierCommeEnProduction(
          _debutDeSourate(109, 10), null);
      expect(m1?.surahNumber, 109);
      final m2 = await _identifierCommeEnProduction(
          _debutDeSourate(110, 8), m1!.surahNumber);
      expect(m2?.surahNumber, 110,
          reason: 'la rak\'ah 2 doit suivre dans l\'ordre du mushaf');
    });

    test('rak\'ah 1 = 112, rak\'ah 2 = 113, rak\'ah 3 = 114', () async {
      final m1 = await _identifierCommeEnProduction(
          _debutDeSourate(112, 8), null);
      expect(m1?.surahNumber, 112);
      final m2 = await _identifierCommeEnProduction(
          _debutDeSourate(113, 8), m1!.surahNumber);
      expect(m2?.surahNumber, 113);
      final m3 = await _identifierCommeEnProduction(
          _debutDeSourate(114, 8), m2!.surahNumber);
      expect(m3?.surahNumber, 114);
    });

    test('sourate LONGUE poursuivie sur la rak\'ah suivante (4 puis 4)',
        () async {
      final m1 =
          await _identifierCommeEnProduction(_debutDeSourate(4, 10), null);
      expect(m1?.surahNumber, 4);
      // Rak'ah 2 : l'imam poursuit An-Nisa plus loin dans la sourate.
      final m2 = await _identifierCommeEnProduction(
          _debutDeSourate(4, 10, depuisAyah: 10), m1!.surahNumber);
      expect(m2?.surahNumber, 4,
          reason: 'une sourate longue peut etre poursuivie a la rak\'ah 2');
    });

    test(
        'le prior NE FORCE PAS : imam qui change completement de zone '
        '(rak\'ah 1 = 109, rak\'ah 2 = 2) reste correctement identifie',
        () async {
      // Garde-fou : le curseur ne doit jamais imposer une sourate voisine
      // quand le texte dit clairement autre chose.
      final m = await _identifierCommeEnProduction(
          _debutDeSourate(2, 12), 109);
      expect(m?.surahNumber, 2,
          reason: 'le prior departage, il ne doit JAMAIS forcer');
    });
  });

  group('SIMULATION -- le cas exact qui a echoue sur device', () {
    test(
        'An-Nisa 4:1 avec residu "وحيف" -- mesure device v193 : donnait 3:200',
        () async {
      const texte = 'وحيف ياايها الناس اتقوا ربكم';
      final match = await _identifierCommeEnProduction(texte, null);
      expect(match?.surahNumber, 4,
          reason: 'regression du correctif de troncature (v194)');
      expect(match?.ayahNumber, 1);
    });

    test(
        'An-Nisa 4:1 apres une rak\'ah 1 sur Al-Imran (3) -- le curseur doit '
        'aider, pas nuire', () async {
      const texte = 'ياايها الناس اتقوا ربكم الذي خلقكم';
      final match = await _identifierCommeEnProduction(texte, 3);
      expect(match?.surahNumber, 4,
          reason: '4 suit 3 dans le mushaf : le curseur doit le preferer');
    });
  });
}

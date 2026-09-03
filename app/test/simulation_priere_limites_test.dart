// OÙ EST-CE QUE ÇA CASSE ? -- complément indispensable à
// `simulation_priere_complete_test.dart`.
//
// Ce banc-ci ne cherche PAS à passer au vert : il MESURE le taux de réussite
// de l'identification en fonction de deux variables qui décident tout en
// conditions réelles :
//   1. le NOMBRE DE MOTS captés (donc la durée d'écoute) ;
//   2. l'INTENSITÉ de la dégradation ASR.
//
// Pourquoi c'est indispensable (demande utilisateur 2026-08-29 : « ne me
// donne pas la main que lorsque t'es sûr à 100% ») : un banc qui ne teste que
// des cas confortables passe au vert et ne prouve rien. Toute la journée du
// 2026-08-29 s'est passée à régler une durée d'écoute (7s -> 5s -> 3s -> 4s
// -> 7s) SANS JAMAIS SAVOIR combien de mots il fallait réellement. Ce banc
// répond à cette question, chiffres à l'appui, hors device.
//
// Il n'échoue que sur un seuil DÉLIBÉRÉMENT BAS (une régression franche) :
// son rôle est d'imprimer le tableau, pas de barrer la route.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

Future<QuranMatch?> _identifier(String texte, int? precedente) async {
  final requete = await _meilleureTroncature(texte);
  final candidats = await QuranVerseLocatorService.instance
      .locateTopMatches(requete, k: 5, minScore: 0.45);
  return choisirSelonOrdreDePriere(candidats, precedente);
}

class _Verset {
  final int sourate;
  final int ayah;
  final List<String> mots;
  _Verset(this.sourate, this.ayah, this.mots);
}

late final List<_Verset> versets;

String _debutDeSourate(int sourate, int n, {int depuisAyah = 1}) {
  final mots = <String>[];
  for (final v in versets) {
    if (v.sourate != sourate || v.ayah < depuisAyah) continue;
    mots.addAll(v.mots);
    if (mots.length >= n) break;
  }
  return mots.take(n).join(' ');
}

/// Dégradation d'intensité réglable : [taux] = fraction de mots touchés.
/// Chaque mot touché subit au hasard une lettre doublée, une lettre tombée,
/// ou une troncature -- les trois familles observées dans les logs device.
String _degrader(String texte, double taux, Random rnd) {
  final mots = texte.split(' ');
  for (var i = 0; i < mots.length; i++) {
    if (rnd.nextDouble() >= taux) continue;
    final m = mots[i];
    if (m.length < 4) continue;
    switch (rnd.nextInt(3)) {
      case 0: // lettre doublee
        final j = 1 + rnd.nextInt(m.length - 1);
        mots[i] = m.substring(0, j) + m[j] + m.substring(j);
      case 1: // lettre tombee
        final j = 1 + rnd.nextInt(m.length - 2);
        mots[i] = m.substring(0, j) + m.substring(j + 1);
      default: // mot tronque
        mots[i] = m.substring(0, m.length - 2);
    }
  }
  return mots.join(' ');
}

/// Les sourates du corpus, ÉCHANTILLON LARGE (une sur quatre, tout le
/// mushaf) -- pas seulement celles que j'aurais choisies pour réussir.
const _souratesBalayage = <int>[
  2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38,
  40, 42, 44, 46, 48, 50, 52, 54, 56, 58, 60, 62, 64, 66, 68, 70, 72, 74,
  76, 78, 80, 82, 84, 86, 88, 90, 92, 94, 96, 98, 100, 102, 104, 106, 108,
  110, 112, 114,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final brut = File('assets/data/quran_search_index.json').readAsStringSync();
    final data = jsonDecode(brut) as Map<String, dynamic>;
    versets = [
      for (final v in data['verses'] as List)
        _Verset(v['s'] as int, v['a'] as int, (v['w'] as List).cast<String>()),
    ];
  });

  test('COMBIEN DE MOTS FAUT-IL ? -- balayage 2..14 mots, texte propre',
      () async {
    final resultats = <int, double>{};
    for (final n in [2, 3, 4, 5, 6, 7, 8, 10, 12, 14]) {
      var ok = 0;
      for (final s in _souratesBalayage) {
        final m = await _identifier(_debutDeSourate(s, n), null);
        if (m?.surahNumber == s) ok++;
      }
      resultats[n] = ok / _souratesBalayage.length;
    }
    // ignore: avoid_print
    print('\n=== TAUX D\'IDENTIFICATION CORRECTE / NOMBRE DE MOTS '
        '(texte propre, ${_souratesBalayage.length} sourates) ===');
    resultats.forEach((n, taux) {
      // ignore: avoid_print
      print('  $n mots\t-> ${(taux * 100).toStringAsFixed(1)} %');
    });
    // Plancher DELIBEREMENT BAS : ce test imprime, il ne barre la route que
    // sur une regression franche.
    expect(resultats[10]!, greaterThan(0.75),
        reason: 'a 10 mots propres, l\'identification doit etre tres fiable');
  });

  test('RESISTANCE A LA DEGRADATION -- 10 mots, taux 0 a 60 %', () async {
    final resultats = <int, double>{};
    for (final pct in [0, 10, 20, 30, 40, 50, 60]) {
      var ok = 0;
      for (final s in _souratesBalayage) {
        final rnd = Random(s * 100 + pct); // deterministe
        final texte = _degrader(_debutDeSourate(s, 10), pct / 100, rnd);
        final m = await _identifier(texte, null);
        if (m?.surahNumber == s) ok++;
      }
      resultats[pct] = ok / _souratesBalayage.length;
    }
    // ignore: avoid_print
    print('\n=== TAUX D\'IDENTIFICATION / INTENSITE DE DEGRADATION '
        '(10 mots, ${_souratesBalayage.length} sourates) ===');
    resultats.forEach((pct, taux) {
      // ignore: avoid_print
      print('  $pct % de mots abimes\t-> ${(taux * 100).toStringAsFixed(1)} %');
    });
    expect(resultats[20]!, greaterThan(0.60),
        reason: 'a 20 % de mots abimes (regime courant sur device), '
            'l\'identification doit rester majoritairement correcte');
  });

  test('LE CURSEUR AIDE-T-IL VRAIMENT ? -- avec vs sans, cas difficiles',
      () async {
    // Enchainements de mushaf reels (rak'ah N -> rak'ah N+1), sur un texte
    // COURT et ABIME : le regime ou le score seul se trompe le plus.
    const enchainements = <List<int>>[
      [105, 106], [106, 107], [107, 108], [108, 109], [109, 110],
      [110, 111], [111, 112], [112, 113], [113, 114], [93, 94],
      [94, 95], [95, 96], [99, 100], [101, 102], [102, 103],
    ];
    // BALAYAGE sur le REGIME AMBIGU : peu de mots (3 a 6) et forte
    // degradation -- c'est la seule zone ou le curseur peut apporter quelque
    // chose, puisqu'au-dela le score tranche deja seul (cf. le balayage plus
    // haut : 100 % a 10 mots propres). Un test qui ne mesurerait le curseur
    // qu'en zone confortable conclurait "inutile" a tort... ou "utile" a
    // tort. On mesure donc la ou ca se joue.
    // ignore: avoid_print
    print('\n=== APPORT DU CURSEUR (ordre de priere), par regime ===');
    var gainTotal = 0;
    for (final nbMots in [3, 4, 5, 6]) {
      for (final pctAbime in [0.0, 0.3]) {
        var okSans = 0, okAvec = 0;
        for (var i = 0; i < enchainements.length; i++) {
          final precedente = enchainements[i][0];
          final attendue = enchainements[i][1];
          final rnd = Random(i * 1000 + nbMots);
          final texte = pctAbime == 0.0
              ? _debutDeSourate(attendue, nbMots)
              : _degrader(_debutDeSourate(attendue, nbMots), pctAbime, rnd);
          final sans = await _identifier(texte, null);
          final avec = await _identifier(texte, precedente);
          if (sans?.surahNumber == attendue) okSans++;
          if (avec?.surahNumber == attendue) okAvec++;
        }
        gainTotal += okAvec - okSans;
        // ignore: avoid_print
        print('  $nbMots mots, ${(pctAbime * 100).toInt()} % abimes\t'
            '-> sans: $okSans/${enchainements.length}   '
            'avec: $okAvec/${enchainements.length}   '
            '(${okAvec - okSans >= 0 ? "+" : ""}${okAvec - okSans})');
      }
    }
    // ignore: avoid_print
    print('  GAIN TOTAL du curseur : '
        '${gainTotal >= 0 ? "+" : ""}$gainTotal identification(s)');
    expect(gainTotal, greaterThanOrEqualTo(0),
        reason: 'le curseur ne doit JAMAIS degrader le resultat global');
  });

  test(
      'CUMUL vs BLOC JETE -- combien de temps pour identifier ? (le correctif '
      'du 2026-08-29 soir)', () async {
    // ── CE QUE CE TEST REPRODUIT ────────────────────────────────────────
    // Mesure device (log v201, 18:59:09 -> 18:59:24) : la 1re capture tombe
    // sur la PAUSE entre Al-Fatiha et la sourate et ne capte qu'un fragment
    // ("يَـٰٓ"). ANCIEN comportement : ce fragment est JETE, on attend un bloc
    // entier de plus. NOUVEAU : il est CUMULE avec la capture suivante.
    //
    // On simule le flux mot a mot tel qu'il arrive reellement (~1,3 mot/s,
    // mesure sur les logs), avec la pause initiale, et on compte au bout de
    // combien de SECONDES chaque strategie identifie la sourate.
    const pauseInitialeS = 5.0; // "آمين" + reprise de souffle
    const motsParSeconde = 1.3; // mesure device
    const blocAncien = 7.0; // ancienne capture, jetee si insuffisante
    const blocNouveau = 3.0; // nouvelle capture, cumulee

    Future<double?> tempsPourIdentifier(int sourate,
        {required double dureeBloc, required bool cumule}) async {
      final cumul = <String>[];
      for (var bloc = 1; bloc <= 12; bloc++) {
        final finBlocS = bloc * dureeBloc;
        // Mots effectivement prononces depuis le debut de la sourate a la fin
        // de ce bloc (rien avant la fin de la pause).
        final motsDits =
            ((finBlocS - pauseInitialeS) * motsParSeconde).floor();
        if (motsDits <= 0) continue;
        final debutBlocS = (bloc - 1) * dureeBloc;
        final motsAvant =
            ((debutBlocS - pauseInitialeS) * motsParSeconde).floor();
        final captes = _debutDeSourate(sourate, motsDits)
            .split(' ')
            .skip(motsAvant > 0 ? motsAvant : 0)
            .toList();
        if (captes.isEmpty) continue;
        if (cumule) {
          cumul.addAll(captes);
          while (cumul.length > 15) {
            cumul.removeAt(0);
          }
        } else {
          cumul
            ..clear()
            ..addAll(captes); // ANCIEN : on ne garde que le bloc courant
        }
        if (cumul.length < 3) continue;
        final m = await _identifier(cumul.join(' '), null);
        if (m?.surahNumber == sourate) return finBlocS;
      }
      return null;
    }

    var totalAncien = 0.0, totalNouveau = 0.0;
    var echecsAncien = 0, echecsNouveau = 0;
    final echantillon = _souratesBalayage.take(25).toList();
    for (final s in echantillon) {
      final a = await tempsPourIdentifier(s, dureeBloc: blocAncien, cumule: false);
      final n =
          await tempsPourIdentifier(s, dureeBloc: blocNouveau, cumule: true);
      if (a == null) {
        echecsAncien++;
      } else {
        totalAncien += a;
      }
      if (n == null) {
        echecsNouveau++;
      } else {
        totalNouveau += n;
      }
    }
    final moyAncien = totalAncien / (echantillon.length - echecsAncien);
    final moyNouveau = totalNouveau / (echantillon.length - echecsNouveau);
    // ignore: avoid_print
    print('\n=== DELAI D\'IDENTIFICATION apres la fin d\'Al-Fatiha '
        '(${echantillon.length} sourates, pause initiale ${pauseInitialeS}s, '
        '${motsParSeconde} mot/s) ===');
    // ignore: avoid_print
    print('  ANCIEN (blocs de ${blocAncien}s, jetes si insuffisants) : '
        '${moyAncien.toStringAsFixed(1)}s en moyenne, '
        '$echecsAncien echec(s)');
    // ignore: avoid_print
    print('  NOUVEAU (blocs de ${blocNouveau}s, CUMULES)            : '
        '${moyNouveau.toStringAsFixed(1)}s en moyenne, '
        '$echecsNouveau echec(s)');
    // ignore: avoid_print
    print('  GAIN : ${(moyAncien - moyNouveau).toStringAsFixed(1)}s');
    expect(moyNouveau, lessThan(moyAncien),
        reason: 'le cumul doit identifier PLUS VITE que les blocs jetes');
    expect(echecsNouveau, lessThanOrEqualTo(echecsAncien),
        reason: 'le cumul ne doit pas identifier MOINS souvent');
  });

  test('LE CURSEUR NE FORCE JAMAIS -- imam qui saute ailleurs', () async {
    // Garde-fou dur : pour CHAQUE sourate du balayage, on ment a l'algorithme
    // en lui donnant une rak'ah precedente sans rapport. Il ne doit jamais
    // preferer la voisine de ce mensonge a ce que le texte dit clairement.
    var faussesInfluences = 0;
    for (final s in _souratesBalayage) {
      // Mensonge : on pretend que la rak'ah precedente etait s-50 (donc les
      // "voisines" s-49..s-47 seraient favorisees si le prior forcait).
      final mensonge = s > 55 ? s - 50 : s + 50;
      final m = await _identifier(_debutDeSourate(s, 10), mensonge);
      if (m != null && m.surahNumber != s) faussesInfluences++;
    }
    // ignore: avoid_print
    print('\n=== ROBUSTESSE DU CURSEUR (rak\'ah precedente MENSONGERE) ===');
    // ignore: avoid_print
    print('  identifications devoyees : $faussesInfluences / '
        '${_souratesBalayage.length}');
    expect(faussesInfluences, lessThanOrEqualTo(2),
        reason: 'le curseur ne doit pas devoyer l\'identification quand le '
            'texte est clair');
  });
}

// Calibration GOP par mot -- REFONTE_IHM.md / PLAN_ENTRAINEMENT_HYBRIDE.md
// §5quinquies (2026-07-20 nuit). Un seuil global (-0.45/-1.60) condamne
// injustement les mots structurellement durs (chadda/gémination : "مِّن",
// Bismillah...) qui ont un gop bas MÊME bien récités -- mesuré sur 42 927
// clips coraniques réels (benchmark/build_gop_word_baseline.py), certains
// mots (ex. "مِّنَ") tombent en moyenne à -7.58 sur des récitations
// professionnelles vérifiées. Ce fichier charge la ligne de base (moyenne
// par mot, calculée depuis ces vraies récitations) pour RECENTRER le gop
// avant de le comparer aux seuils habituels -- un mot "normalement" à -5.5
// ne doit plus être jugé sur son gop brut, mais sur son ÉCART à sa propre
// moyenne.
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [n] : nombre d'occurrences observées dans le corpus de calibration --
/// sert de garde-fou (cf. RuleReliability) : une moyenne calculée sur trop
/// peu d'exemples ne doit pas recentrer le gop avec confiance.
class GopWordBaseline {
  final double mean;
  final double std;
  final int n;
  const GopWordBaseline({required this.mean, required this.std, required this.n});

  /// Sous ce seuil, la moyenne est trop peu fiable pour recentrer (cf. le
  /// même seuil de prudence que RuleReliability.capsToUnclear, arbitraire
  /// mais cohérent : quelques occurrences ne prouvent rien).
  bool get reliable => n >= 5;
}

final gopWordBaselineProvider =
    FutureProvider<Map<String, GopWordBaseline>>((ref) async {
  final raw = await rootBundle.loadString('assets/data/gop_word_baseline.json');
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final result = <String, GopWordBaseline>{};
  for (final entry in json.entries) {
    final data = entry.value as Map<String, dynamic>;
    result[entry.key] = GopWordBaseline(
      mean: (data['mean'] as num).toDouble(),
      std: (data['std'] as num).toDouble(),
      n: data['n'] as int,
    );
  }
  return result;
});

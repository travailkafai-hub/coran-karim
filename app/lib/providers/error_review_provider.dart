import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/verse.dart';
import '../services/quran_api.dart';
import '../services/recitation_error_log_service.dart';

/// Erreurs d'une sourate, agrégées (REFONTE_IHM.md §11.3).
///
/// POURQUOI CET AGRÉGAT (demande utilisateur 2026-07-20) : le volet erreurs
/// précédent (`coach_ai_screen.dart`) affichait une liste PLATE, toutes
/// sourates mélangées, triée par nombre d'erreurs -- on voyait « An-Nisa v1 :
/// 9 » à côté de « Al-Qalam v20 : 6 » sans jamais savoir QUELLE sourate est
/// fragile ni pouvoir travailler par bloc cohérent. Ici on remonte d'un cran :
/// la sourate devient l'unité de travail, le verset le détail.
class SurahErrorSummary {
  final Surah surah;
  final int totalErrors;

  /// Versets fautifs de cette sourate, triés par nombre d'erreurs décroissant.
  final List<AyahErrorCount> ayahs;

  const SurahErrorSummary({
    required this.surah,
    required this.totalErrors,
    required this.ayahs,
  });

  int get versesTouched => ayahs.length;

  /// Part des versets de la sourate qui ont au moins une erreur. Donne le
  /// CONTEXTE que le total brut ne donne pas : 5 versets fragiles sur 7
  /// (Al-Fatiha) n'a pas le même sens que 5 sur 286 (Al-Baqarah).
  double get touchedRatio =>
      surah.versesCount == 0 ? 0 : versesTouched / surah.versesCount;
}

/// Journal d'erreurs regroupé par sourate, trié par nombre d'erreurs
/// décroissant (= le plus actionnable en premier : « où dois-je travailler ? »).
///
/// Regroupement CÔTÉ CLIENT à partir de `errorCountsByAyah()` (déjà existant)
/// plutôt qu'une nouvelle requête SQL : volumes réels de l'ordre de quelques
/// centaines de lignes, coût négligeable, et zéro risque de régression sur le
/// schéma sqlite. À réévaluer seulement si le journal grossit beaucoup.
final surahErrorSummariesProvider =
    FutureProvider.autoDispose<List<SurahErrorSummary>>((ref) async {
  final results = await Future.wait([
    RecitationErrorLogService.instance.errorCountsByAyah(),
    QuranApi.fetchSurahs(),
  ]);
  final counts = results[0] as List<AyahErrorCount>;
  final surahs = results[1] as List<Surah>;
  final byNumber = {for (final s in surahs) s.number: s};

  final grouped = <int, List<AyahErrorCount>>{};
  for (final c in counts) {
    grouped.putIfAbsent(c.surahNumber, () => []).add(c);
  }

  final out = <SurahErrorSummary>[];
  for (final entry in grouped.entries) {
    final surah = byNumber[entry.key];
    if (surah == null) continue; // sourate inconnue -> on ignore, jamais planter
    final ayahs = [...entry.value]..sort((a, b) => b.count.compareTo(a.count));
    out.add(SurahErrorSummary(
      surah: surah,
      totalErrors: ayahs.fold(0, (sum, a) => sum + a.count),
      ayahs: ayahs,
    ));
  }
  out.sort((a, b) => b.totalErrors.compareTo(a.totalErrors));
  return out;
});

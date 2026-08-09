import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/judgement_options.dart' show TajwidRule;
import '../models/recitation_state.dart' show RecitationErrorKind;
import '../models/verse.dart';
import '../services/quran_api.dart';
import '../services/recitation_error_log_service.dart';
import '../services/session_archive_service.dart';

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

/// Répartition GLOBALE des erreurs par type (demande utilisateur 2026-07-20 :
/// « catégoriser par type : tajwid ou prononciation »). Affichée en tête du
/// volet erreurs : elle répond à « sur quoi je bute le plus ? » avant même de
/// regarder quelle sourate.
final errorKindBreakdownProvider =
    FutureProvider.autoDispose<Map<RecitationErrorKind, int>>((ref) async {
  return RecitationErrorLogService.instance.errorCountsByKind();
});

/// Répartition GLOBALE des erreurs de type tajwid PAR RÈGLE PRÉCISE (demande
/// utilisateur 2026-07-22) — répond à « quelle règle je rate le plus ? »,
/// un cran plus fin que le compteur "Tajwid" unique de [errorKindBreakdownProvider].
final tajwidRuleBreakdownProvider =
    FutureProvider.autoDispose<Map<TajwidRule, int>>((ref) async {
  return RecitationErrorLogService.instance.errorCountsByRule();
});

/// Même chose, restreinte à UNE sourate (utilisé dans le détail par sourate
/// du volet erreurs) -- `family` car chaque tuile de sourate a besoin de sa
/// propre requête, indépendamment des autres.
final surahTajwidRuleBreakdownProvider = FutureProvider.autoDispose
    .family<Map<TajwidRule, int>, int>((ref, surahNumber) async {
  return RecitationErrorLogService.instance
      .errorCountsByRule(surahNumber: surahNumber);
});

/// Détail mot par mot des erreurs d'UN verset (demande utilisateur
/// 2026-07-22 : « je veux en détaille le mot ou il ya erreur et type
/// d'erreur ») -- chaque entrée porte son mot, son type, et ses règles de
/// tajwid précises le cas échéant (cf. RecitationErrorEntry.rules/pairWord).
final ayahErrorDetailsProvider = FutureProvider.autoDispose
    .family<List<RecitationErrorEntry>, ({int surahNumber, int ayahNumber})>(
        (ref, key) async {
  return RecitationErrorLogService.instance
      .errorsForAyah(key.surahNumber, key.ayahNumber);
});

/// La voix la plus récente disponible pour UN mot précis, fusion Coach hub
/// (2026-08-09) : « une seule liste fusionnée, groupée par sourate » -- cf.
/// `SessionArchiveService.dernierMotAvecAudio` pour le pourquoi. `null` si
/// aucun enregistrement n'existe (jamais archivé, ou archive expirée après
/// 7 jours) -- pas une erreur, juste rien à écouter.
final derniereVoixPourMotProvider = FutureProvider.autoDispose
    .family<MotArchive?, ({int surahNumber, int ayahNumber, int wordInAyah})>(
        (ref, key) async {
  return SessionArchiveService.instance
      .dernierMotAvecAudio(key.surahNumber, key.ayahNumber, key.wordInAyah);
});

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

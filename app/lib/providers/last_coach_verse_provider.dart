import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dernier verset travaillé en mémorisation (REFONTE_IHM.md §11.2, zone A).
///
/// POURQUOI : l'action n°1 de quelqu'un qui mémorise au quotidien est
/// « je continue là où j'en étais ». Sans cette mémoire, il faut re-choisir
/// la sourate puis le verset à chaque ouverture -- friction inutile sur
/// l'usage le plus fréquent.
///
/// Volontairement MINIMAL (sourate + verset + nom affichable) : pas de
/// progression fine ni de score, qui vivent déjà dans le journal d'erreurs et
/// dans FSRS. Ici on ne stocke que de quoi rouvrir le bon écran.
class LastCoachVerse {
  final int surahNumber;
  final int ayahNumber;
  final String surahName;

  const LastCoachVerse({
    required this.surahNumber,
    required this.ayahNumber,
    required this.surahName,
  });
}

const _kPrefSurah = 'coach.last.surah';
const _kPrefAyah = 'coach.last.ayah';
const _kPrefName = 'coach.last.name';

/// Enregistre le verset en cours de travail. Appelé par `CoachScreen` à
/// l'ouverture d'une session -- silencieux, ne doit jamais faire échouer la
/// session si l'écriture échoue.
Future<void> recordLastCoachVerse({
  required int surahNumber,
  required int ayahNumber,
  required String surahName,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrefSurah, surahNumber);
    await prefs.setInt(_kPrefAyah, ayahNumber);
    await prefs.setString(_kPrefName, surahName);
  } catch (_) {
    // Reprendre est un confort, jamais un bloquant.
  }
}

/// `autoDispose` : relu à chaque affichage du hub, donc à jour après une
/// session de mémorisation sans avoir à invalider manuellement.
final lastCoachVerseProvider =
    FutureProvider.autoDispose<LastCoachVerse?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final surah = prefs.getInt(_kPrefSurah);
  final ayah = prefs.getInt(_kPrefAyah);
  if (surah == null || ayah == null) return null;
  return LastCoachVerse(
    surahNumber: surah,
    ayahNumber: ayah,
    surahName: prefs.getString(_kPrefName) ?? 'Sourate $surah',
  );
});

import 'quran_verse_locator_service.dart';

/// ChGPT: a short, growing audio window needs evidence, not just a high ratio
/// on one common pair. Ambiguous surahs remain candidates, never a forced pick.
QuranMatch? confirmedPrayerTarget(List<QuranMatch> candidates) {
  if (candidates.isEmpty) return null;
  final ranked = [...candidates]
    ..sort((a, b) => b.confidence.compareTo(a.confidence));
  final best = ranked.first;
  if (best.surahNumber == 1 || best.confidence < 0.45 || best.votes < 5) {
    return null;
  }
  for (final other in ranked.skip(1)) {
    if (other.surahNumber != best.surahNumber &&
        best.confidence < other.confidence * 1.3) {
      return null;
    }
  }
  return best;
}

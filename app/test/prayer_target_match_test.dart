import 'package:coran_karim/services/prayer_target_match.dart';
import 'package:coran_karim/services/quran_verse_locator_service.dart';
import 'package:flutter_test/flutter_test.dart';

QuranMatch candidate(int surah, double score, int votes, {int ayah = 1}) =>
    QuranMatch(
      surahNumber: surah,
      ayahNumber: ayah,
      confidence: score,
      votes: votes,
    );

void main() {
  test('distinctive confirmed surah needs no extra waiting cycle', () {
    final best = candidate(4, 0.9, 8);
    expect(confirmedPrayerTarget([best, candidate(2, 0.5, 5)]), same(best));
  });
  test('one common pair is not confirmation, even with a perfect score', () {
    expect(confirmedPrayerTarget([candidate(2, 1, 1)]), isNull);
  });
  test(
    'ambiguous surahs wait for more audio, not the previous rakah order',
    () {
      expect(
        confirmedPrayerTarget([candidate(4, .9, 8), candidate(2, .85, 7)]),
        isNull,
      );
    },
  );
  test('neighboring verses in the same surah do not block confirmation', () {
    expect(
      confirmedPrayerTarget([
        candidate(4, .9, 8),
        candidate(4, .85, 7, ayah: 2),
      ])?.surahNumber,
      4,
    );
  });
  test('Fatiha and weak candidates are not a confirmed second surah', () {
    expect(
      confirmedPrayerTarget([candidate(1, 1, 9), candidate(4, .5, 5)]),
      isNull,
    );
    expect(confirmedPrayerTarget([candidate(4, .2, 9)]), isNull);
    expect(confirmedPrayerTarget([]), isNull);
  });
}

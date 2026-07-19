/// Mots coraniques verifies (api.quran.com, text_uthmani) contenant une
/// lettre "confusable" (makharij proches, tajweed classique) -- utilise
/// pour la calibration voix personnelle (FONCTIONNALITES_FUTURES.md
/// section 8ter, 2026-07-14). [correct] = graphie authentique du Coran,
/// [wrong] = meme mot avec la lettre cible substituee par sa confusable --
/// PAS un mot coranique reel, sert uniquement a demander a l'utilisateur
/// de le prononcer expres avec cette substitution pour calibrer sa
/// sensibilite au modele.
class CalibrationPair {
  final String correct;
  final String wrong;
  final String targetLetter;
  final String confusedLetter;
  final String reference;
  const CalibrationPair({
    required this.correct, required this.wrong,
    required this.targetLetter, required this.confusedLetter,
    required this.reference,
  });
}

const List<CalibrationPair> kVoiceCalibrationPairs = [
  CalibrationPair(
    correct: "ٱلصِّرَٰطَ",
    wrong: "ٱلسِّرَٰطَ",
    targetLetter: "ص",
    confusedLetter: "س",
    reference: "Al-Fatiha 1:6",
  ),
  CalibrationPair(
    correct: "صِرَٰطَ",
    wrong: "صِرَٰتَ",
    targetLetter: "ط",
    confusedLetter: "ت",
    reference: "Al-Fatiha 1:7",
  ),
  CalibrationPair(
    correct: "نَسْتَعِينُ",
    wrong: "نَصْتَعِينُ",
    targetLetter: "س",
    confusedLetter: "ص",
    reference: "Al-Fatiha 1:5",
  ),
  CalibrationPair(
    correct: "ٱلرَّحِيمِ",
    wrong: "ٱلرَّهِيمِ",
    targetLetter: "ح",
    confusedLetter: "ه",
    reference: "Al-Fatiha 1:1",
  ),
  CalibrationPair(
    correct: "ٱلرَّحْمَـٰنِ",
    wrong: "ٱلرَّهْمَـٰنِ",
    targetLetter: "ح",
    confusedLetter: "ه",
    reference: "Al-Fatiha 1:1",
  ),
  CalibrationPair(
    correct: "ٱلضَّآلِّينَ",
    wrong: "ٱلدَّآلِّينَ",
    targetLetter: "ض",
    confusedLetter: "د",
    reference: "Al-Fatiha 1:7",
  ),
  CalibrationPair(
    correct: "ٱلَّذِينَ",
    wrong: "ٱلَّزِينَ",
    targetLetter: "ذ",
    confusedLetter: "ز",
    reference: "Al-Fatiha 1:7",
  ),
  CalibrationPair(
    correct: "ٱلَّذِى",
    wrong: "ٱلَّزِى",
    targetLetter: "ذ",
    confusedLetter: "ز",
    reference: "An-Nas 114:5",
  ),
  CalibrationPair(
    correct: "عَلَيْهِمْ",
    wrong: "ءَلَيْهِمْ",
    targetLetter: "ع",
    confusedLetter: "ء",
    reference: "Al-Fatiha 1:7",
  ),
  CalibrationPair(
    correct: "مَلِكِ",
    wrong: "مَلِقِ",
    targetLetter: "ك",
    confusedLetter: "ق",
    reference: "An-Nas 114:2",
  ),
  CalibrationPair(
    correct: "ٱلْخَنَّاسِ",
    wrong: "ٱلْحَنَّاسِ",
    targetLetter: "خ",
    confusedLetter: "ح",
    reference: "An-Nas 114:4",
  ),
  CalibrationPair(
    correct: "ٱلنَّاسِ",
    wrong: "ٱلنَّاصِ",
    targetLetter: "س",
    confusedLetter: "ص",
    reference: "An-Nas 114:1",
  ),
  CalibrationPair(
    correct: "أَعُوذُ",
    wrong: "أَءُوذُ",
    targetLetter: "ع",
    confusedLetter: "ء",
    reference: "An-Nas 114:1",
  ),
  CalibrationPair(
    correct: "ٱلْوَسْوَاسِ",
    wrong: "ٱلْوَصْوَاصِ",
    targetLetter: "س",
    confusedLetter: "ص",
    reference: "An-Nas 114:4",
  ),
];

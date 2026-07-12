import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/cascade_explanation.dart';
import 'recitation_verifier.dart' show ArabicNormalizer;

/// Lookup DIRECT (paliers 1/2/3, texte déjà écrit/sourcé) dans les fichiers
/// générés par `benchmark/build_explanation_cascade.py` -- AUCUNE génération
/// LLM ici (cf. WORD_AYAH_EXPLANATION_PLAN.md : "l'algorithme sert la
/// vérité, il ne la génère pas", même philosophie que le pilier Récitation).
///
/// `ayah_explanations.jsonl` (128 Mo) et `word_explanations.jsonl` (177 Mo)
/// sont trop volumineux pour un chargement complet en RAM (contrainte 6 Go
/// RAM, cf. `.claude/skills/model-training/references/asr.md`) -- accès
/// direct par offset (`RandomAccessFile`, index `*.offsets.json` généré côté
/// PC par `build_explanation_offset_index.py`), un seul verset lu à la fois.
///
/// Déployé dans `ApplicationSupportDirectory/quran_sciences/` (même
/// convention que les modèles ASR) : `word_root_index.jsonl`,
/// `ayah_explanations.jsonl` + `.offsets.json`,
/// `word_explanations.jsonl` + `.offsets.json`. Absent tant que non déployé
/// -- `ensureLoaded()` retourne alors false, jamais une exception (l'appelant
/// doit se rabattre sur le tuteur Gemma).
class QuranSciencesService {
  static const _kSubdir = 'quran_sciences';

  static QuranSciencesService? _instance;
  static QuranSciencesService get instance =>
      _instance ??= QuranSciencesService._();
  QuranSciencesService._();

  RandomAccessFile? _ayahFile;
  RandomAccessFile? _wordFile;
  Map<String, dynamic>? _ayahOffsets;
  Map<String, dynamic>? _wordOffsets;
  bool _ready = false;
  bool _loadAttempted = false;

  /// Idempotent, best-effort. Ne relance pas les vérifications de fichiers à
  /// chaque appel une fois tentée (évite de re-frapper le disque en boucle
  /// si les données ne sont simplement pas encore déployées).
  Future<bool> ensureLoaded() async {
    if (_ready) return true;
    if (_loadAttempted) return false;
    _loadAttempted = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final base = '${dir.path}/$_kSubdir';
      final ayahOffsetsFile = File('$base/ayah_explanations.offsets.json');
      final wordOffsetsFile = File('$base/word_explanations.offsets.json');
      final ayahDataFile = File('$base/ayah_explanations.jsonl');
      final wordDataFile = File('$base/word_explanations.jsonl');
      if (!await ayahOffsetsFile.exists() ||
          !await wordOffsetsFile.exists() ||
          !await ayahDataFile.exists() ||
          !await wordDataFile.exists()) {
        return false; // pas encore déployé -- pas une erreur
      }
      _ayahOffsets =
          jsonDecode(await ayahOffsetsFile.readAsString()) as Map<String, dynamic>;
      _wordOffsets =
          jsonDecode(await wordOffsetsFile.readAsString()) as Map<String, dynamic>;
      _ayahFile = await ayahDataFile.open();
      _wordFile = await wordDataFile.open();
      _ready = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _readAt(
      RandomAccessFile f, List<dynamic> offsetLen) async {
    final offset = offsetLen[0] as int;
    final length = offsetLen[1] as int;
    await f.setPosition(offset);
    final bytes = await f.read(length);
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  /// Explication d'un verset ENTIER, pour [lang] ('ar'/'fr'/'en'). Null si
  /// les données ne sont pas déployées, ou si ce verset/cette langue n'a
  /// aucune source (l'appelant doit alors se rabattre sur le tuteur Gemma).
  Future<CascadeExplanation?> explainAyah(
      int surahNumber, int ayahNumber, String lang) async {
    if (!await ensureLoaded()) return null;
    final offsetLen = _ayahOffsets?['$surahNumber:$ayahNumber'] as List?;
    if (offsetLen == null) return null;
    final obj = await _readAt(_ayahFile!, offsetLen);
    if (obj == null) return null;
    return CascadeExplanation.fromLangJson(obj[lang] as Map<String, dynamic>?);
  }

  /// Explication ciblée sur UN mot précis. [wordIndex] = position 0-based
  /// dans le découpage de l'app (`ArabicNormalizer.splitExpectedWords`),
  /// [expectedSurface] = la forme exacte de ce mot telle qu'affichée --
  /// utilisée pour VÉRIFIER que l'entrée trouvée à [wordIndex] correspond
  /// bien à ce mot (le fichier source est construit à partir d'un
  /// découpage grammatical indépendant, `ar-tahlil-kalimat` -- généralement
  /// aligné avec le découpage par espaces de l'app, mais jamais garanti à
  /// 100% ; on ne veut jamais afficher l'explication d'un AUTRE mot avec
  /// confiance, cf. les bugs de désynchronisation déjà rencontrés sur ce
  /// projet pour cette même classe de problème). Repli : recherche la même
  /// forme de surface ailleurs dans le verset, la plus proche en position.
  /// Retourne null si aucune entrée ne correspond, ou si ce mot n'a pas
  /// d'explication dans [lang] (fréquent en FR/EN -- pas de vrai
  /// dictionnaire mot-à-mot dans ces langues, cf. le plan).
  Future<CascadeExplanation?> explainWord(
    int surahNumber,
    int ayahNumber,
    int wordIndex,
    String expectedSurface,
    String lang,
  ) async {
    if (!await ensureLoaded()) return null;
    final offsetLen = _wordOffsets?['$surahNumber:$ayahNumber'] as List?;
    if (offsetLen == null) return null;
    final obj = await _readAt(_wordFile!, offsetLen);
    if (obj == null) return null;
    final words = obj['words'] as List?;
    if (words == null || words.isEmpty) return null;
    final entry = _findWordEntry(words, wordIndex, expectedSurface);
    if (entry == null) return null;
    return CascadeExplanation.fromLangJson(
      entry[lang] as Map<String, dynamic>?,
      root: entry['root'] as String?,
    );
  }

  Map<String, dynamic>? _findWordEntry(
      List words, int wordIndex, String expectedSurface) {
    final target = ArabicNormalizer.normalize(expectedSurface);
    if (wordIndex >= 0 && wordIndex < words.length) {
      final w = words[wordIndex] as Map<String, dynamic>;
      if (ArabicNormalizer.normalize(w['surface'] as String) == target) return w;
    }
    Map<String, dynamic>? best;
    var bestDist = 1 << 30;
    for (var i = 0; i < words.length; i++) {
      final w = words[i] as Map<String, dynamic>;
      if (ArabicNormalizer.normalize(w['surface'] as String) == target) {
        final dist = (i - wordIndex).abs();
        if (dist < bestDist) {
          bestDist = dist;
          best = w;
        }
      }
    }
    return best;
  }

  Future<void> dispose() async {
    await _ayahFile?.close();
    await _wordFile?.close();
    _ayahFile = null;
    _wordFile = null;
    _ready = false;
    _loadAttempted = false;
  }
}

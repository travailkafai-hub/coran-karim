import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import '../models/judgement_options.dart';

/// Symboles de règles tajwid (zone privée Unicode U+E000..U+E010) émis par le
/// modèle stage1b-260h. L'ordre est celui de
/// benchmark/data/quran_tajweed_rules/rules_map.json, qui est AUSSI l'ordre de
/// l'enum [TajwidRule] (judgement_options.dart) : U+E000+i correspond à
/// TajwidRule.values[i]. Ne jamais réordonner l'un sans l'autre (vérifié à la
/// main 2026-07-19). La correspondance est reconstruite ici par index plutôt
/// que recopiée en dur, pour qu'un ajout de règle reste cohérent des deux
/// côtés tant que l'ordre est préservé.
class RuleSymbols {
  RuleSymbols._();

  static const int _base = 0xE000;
  static const int _lastRule = 0xE010; // 17 règles : E000..E010 inclus

  static bool isSymbol(int codeUnit) =>
      codeUnit >= _base && codeUnit <= 0xF8FF;

  /// Règle associée à un caractère de symbole, ou null si hors plage règles.
  static TajwidRule? ruleOf(int codeUnit) {
    if (codeUnit < _base || codeUnit > _lastRule) return null;
    final idx = codeUnit - _base;
    if (idx >= TajwidRule.values.length) return null;
    return TajwidRule.values[idx];
  }

  /// Retire tous les symboles de règles d'une chaîne (pour comparer/afficher
  /// le texte "nu"). La normalisation arabe standard les retire déjà via son
  /// filtre `[^؀-ۿ]`, mais ce helper explicite sert aux endroits qui
  /// manipulent la sortie brute du modèle avant toute normalisation.
  static String strip(String s) {
    if (!s.codeUnits.any(isSymbol)) return s;
    final sb = StringBuffer();
    for (final cu in s.runes) {
      if (!isSymbol(cu)) sb.writeCharCode(cu);
    }
    return sb.toString();
  }

  /// Règles détectées dans une chaîne annotée, dans l'ordre d'apparition
  /// (doublons possibles si la même règle apparaît plusieurs fois).
  static List<TajwidRule> rulesIn(String s) {
    final out = <TajwidRule>[];
    for (final cu in s.runes) {
      final r = ruleOf(cu);
      if (r != null) out.add(r);
    }
    return out;
  }
}

/// Fournit, pour un verset donné, ses mots ANNOTÉS de règles tajwid (forme
/// que le modèle stage1b-260h a apprise : lettres + harakat + symboles PUA).
///
/// POURQUOI par verset et pas par mot : l'application d'une règle dépend du
/// CONTEXTE (lettre suivante, position dans le verset). Mesuré le 2026-07-19 :
/// 39,4 % des occurrences de mots portent une annotation qui varie selon le
/// contexte -- un dictionnaire mot->annotation serait faux 4 fois sur 10. La
/// clé est donc "surah:ayah" et le mapping est positionnel (le nombre de mots
/// annotés == nombre de mots canoniques, garanti à la génération de l'asset,
/// cf. build_app_rules_assets.py).
///
/// Asset : assets/data/quran_rules_annotated.json  {"s:a": ["mot1", ...]}
/// (mots au format Uthmani avec harakat ET symboles ; ~1,8 Mo, chargé une
/// fois puis gardé en mémoire).
class RuleAnnotationService {
  RuleAnnotationService._();
  static final instance = RuleAnnotationService._();

  Map<String, List<String>>? _byVerse;
  bool _loading = false;

  Future<void> ensureLoaded() async {
    if (_byVerse != null || _loading) return;
    _loading = true;
    try {
      final raw = await rootBundle
          .loadString('assets/data/quran_rules_annotated.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _byVerse = data.map(
          (k, v) => MapEntry(k, (v as List).cast<String>()));
      debugPrint('[Rules] annotations chargées : ${_byVerse!.length} versets');
    } catch (e) {
      debugPrint('[Rules] échec chargement annotations : $e');
      _byVerse = const {}; // asset absent -> repli silencieux (aligne sur canonique)
    } finally {
      _loading = false;
    }
  }

  bool get isReady => _byVerse != null;

  /// Mots annotés du verset (surah, ayah), ou null si l'asset n'est pas chargé
  /// ou si le verset est absent (ex. texte hors-Coran) -- l'appelant retombe
  /// alors sur la forme canonique (comportement de l'ancien modèle, sûr).
  List<String>? annotatedWords(int surah, int ayah) =>
      _byVerse?['$surah:$ayah'];
}

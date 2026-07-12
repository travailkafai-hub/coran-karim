/// Une source pour un palier donné (ex. "Tafsir al-Muyassar", "Al-Mufradat
/// fi Gharib al-Qur'an") -- texte déjà écrit/sourcé, jamais généré (cf.
/// WORD_AYAH_EXPLANATION_PLAN.md : "l'algorithme sert la vérité, il ne la
/// génère pas").
class ExplanationSource {
  final String source;
  final String text;
  const ExplanationSource({required this.source, required this.text});

  factory ExplanationSource.fromJson(Map<String, dynamic> j) =>
      ExplanationSource(
        source: j['source'] as String,
        text: j['text'] as String,
      );
}

/// Explication en cascade (paliers 1 synthétique -> 3 érudit) pour UNE
/// langue déjà résolue -- cf. `QuranSciencesService`. [root] : racine
/// arabe du mot (uniquement pour une explication de MOT, null pour un
/// verset entier).
class CascadeExplanation {
  final Map<int, List<ExplanationSource>> tiers;
  final String? root;
  const CascadeExplanation(this.tiers, {this.root});

  bool get isEmpty => tiers.isEmpty;

  int get maxTier =>
      tiers.keys.isEmpty ? 0 : tiers.keys.reduce((a, b) => a > b ? a : b);

  List<ExplanationSource>? tier(int n) => tiers[n];

  static CascadeExplanation? fromLangJson(Map<String, dynamic>? langJson,
      {String? root}) {
    if (langJson == null || langJson.isEmpty) return null;
    final tiers = <int, List<ExplanationSource>>{};
    for (final entry in langJson.entries) {
      final tierNum = int.tryParse(entry.key);
      if (tierNum == null) continue;
      final list = (entry.value as List)
          .map((e) => ExplanationSource.fromJson(e as Map<String, dynamic>))
          .toList();
      if (list.isNotEmpty) tiers[tierNum] = list;
    }
    if (tiers.isEmpty) return null;
    return CascadeExplanation(tiers, root: root);
  }
}

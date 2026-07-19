// Modèle de données pour la carte mentale des sourates (REFONTE_IHM.md §7).
// Schéma JSON exact spécifié dans le plan, un fichier par sourate par langue :
// assets/mindmaps/{lang}/{NNN}.json.

class MindMapLeaf {
  final String v; // "1" ou "1-2"
  final String t;

  const MindMapLeaf({required this.v, required this.t});

  factory MindMapLeaf.fromJson(Map<String, dynamic> json) => MindMapLeaf(
        v: json['v'] as String,
        t: json['t'] as String,
      );

  /// Premier numéro de verset couvert par ce nœud (pour "Aller au verset").
  int get firstAyah => int.parse(v.split('-').first);
}

enum MindMapCategory { croyance, recit, loi, promesse, avertissement, louange }

MindMapCategory _categoryFromString(String s) => MindMapCategory.values
    .firstWhere((c) => c.name == s, orElse: () => MindMapCategory.recit);

class MindMapBranch {
  final String side; // "left" | "right"
  final String range; // "1-8"
  final MindMapCategory cat;
  final String title;
  final String resume;
  final List<MindMapLeaf> children;

  const MindMapBranch({
    required this.side,
    required this.range,
    required this.cat,
    required this.title,
    required this.resume,
    required this.children,
  });

  factory MindMapBranch.fromJson(Map<String, dynamic> json) => MindMapBranch(
        side: json['side'] as String,
        range: json['range'] as String,
        cat: _categoryFromString(json['cat'] as String),
        title: json['title'] as String,
        resume: json['resume'] as String,
        children: (json['children'] as List<dynamic>? ?? [])
            .map((c) => MindMapLeaf.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  int get firstAyah => int.parse(range.split('-').first);
}

class MindMapData {
  final String themeCentral;
  final List<MindMapBranch> branches;

  const MindMapData({required this.themeCentral, required this.branches});

  factory MindMapData.fromJson(Map<String, dynamic> json) => MindMapData(
        themeCentral: json['theme_central'] as String,
        branches: (json['branches'] as List<dynamic>)
            .map((b) => MindMapBranch.fromJson(b as Map<String, dynamic>))
            .toList(),
      );
}

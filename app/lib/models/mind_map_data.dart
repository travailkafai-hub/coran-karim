import 'package:flutter/widgets.dart' show BuildContext;
import '../l10n/app_localizations.dart';

// Modèle de données pour la carte mentale des sourates (REFONTE_IHM.md §7).
//
// SCHÉMA RÉEL (assets/mindmaps/{locale}/{NNN}.json, 114 sourates par langue).
// Il diffère de la maquette que j'avais écrite
// au départ dans `fr/` (12 sourates, supprimées) sur trois points, ne pas les
// re-inverser :
//   - `cat` est porté par l'ENFANT (le passage), pas par la branche ;
//   - il n'y a PAS de champ `side` (la répartition gauche/droite est calculée
//     par l'algorithme de rendu, pas dictée par les données) ;
//   - en-tête riche : `name_ar`, `name_latin`, `ayat_count`, `theme_central`
//     (une phrase, pas un titre court) et `sources_note`.
//
// `sources_note` documente d'où vient la structure (analyses structurelles
// citées) et signale parfois qu'une partie reste à vérifier — c'est une
// information d'HONNÊTETÉ sur le contenu, affichée à l'utilisateur, pas un
// commentaire interne à masquer.

/// Catégories réelles présentes dans les données (relevé exhaustif sur les
/// 114 fichiers, 921 passages) : recits, croyance, eschatologie,
/// argumentation, ethique, legislation, signes, adoration.
enum MindMapCategory {
  recits,
  croyance,
  eschatologie,
  argumentation,
  ethique,
  legislation,
  signes,
  adoration,
  autre,
}

MindMapCategory categoryFromString(String? s) => switch (s) {
      'recits' => MindMapCategory.recits,
      'croyance' => MindMapCategory.croyance,
      'eschatologie' => MindMapCategory.eschatologie,
      'argumentation' => MindMapCategory.argumentation,
      'ethique' => MindMapCategory.ethique,
      'legislation' => MindMapCategory.legislation,
      'signes' => MindMapCategory.signes,
      'adoration' => MindMapCategory.adoration,
      // Catégorie inconnue -> `autre` plutôt qu'une exception : un fichier
      // enrichi plus tard ne doit jamais faire planter l'écran.
      _ => MindMapCategory.autre,
    };

/// Libellé localisé (fr/en/ar, cf. lib/l10n/app_*.arb) -- indépendant de la
/// langue du CONTENU (`assets/mindmaps/{locale}/...`) : les deux suivent la
/// langue de l'app, mais par des mécanismes différents (l10n générée ici,
/// fichiers JSON par dossier là-bas), donc pas de lien de code entre eux.
String categoryLabel(BuildContext context, MindMapCategory c) {
  final l10n = AppLocalizations.of(context)!;
  return switch (c) {
    MindMapCategory.recits => l10n.mindMapCatRecits,
    MindMapCategory.croyance => l10n.mindMapCatCroyance,
    MindMapCategory.eschatologie => l10n.mindMapCatEschatologie,
    MindMapCategory.argumentation => l10n.mindMapCatArgumentation,
    MindMapCategory.ethique => l10n.mindMapCatEthique,
    MindMapCategory.legislation => l10n.mindMapCatLegislation,
    MindMapCategory.signes => l10n.mindMapCatSignes,
    MindMapCategory.adoration => l10n.mindMapCatAdoration,
    MindMapCategory.autre => l10n.mindMapCatAutre,
  };
}

/// Un passage : plage de versets + catégorie + description.
class MindMapLeaf {
  final String v; // "1" ou "1-7"
  final MindMapCategory cat;
  final String t;

  const MindMapLeaf({required this.v, required this.cat, required this.t});

  factory MindMapLeaf.fromJson(Map<String, dynamic> json) => MindMapLeaf(
        v: '${json['v']}',
        cat: categoryFromString(json['cat'] as String?),
        t: json['t'] as String? ?? '',
      );

  /// Premier verset couvert (pour « Aller au verset »).
  int get firstAyah => int.tryParse(v.split('-').first.trim()) ?? 1;
}

/// Une section de la sourate.
class MindMapBranch {
  final String range; // "1-20"
  final String title;
  final String resume;
  final List<MindMapLeaf> children;

  const MindMapBranch({
    required this.range,
    required this.title,
    required this.resume,
    required this.children,
  });

  factory MindMapBranch.fromJson(Map<String, dynamic> json) => MindMapBranch(
        range: '${json['range'] ?? ''}',
        title: json['title'] as String? ?? '',
        resume: json['resume'] as String? ?? '',
        children: (json['children'] as List<dynamic>? ?? [])
            .map((c) => MindMapLeaf.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  int get firstAyah => int.tryParse(range.split('-').first.trim()) ?? 1;

  /// Catégorie dominante de la section, dérivée de ses passages : sert à
  /// colorer la branche alors que les données ne portent la catégorie que sur
  /// les enfants. En cas d'égalité, la première rencontrée gagne (ordre de
  /// lecture = ordre du texte, choix stable et non arbitraire).
  MindMapCategory get dominantCategory {
    if (children.isEmpty) return MindMapCategory.autre;
    final counts = <MindMapCategory, int>{};
    for (final c in children) {
      counts[c.cat] = (counts[c.cat] ?? 0) + 1;
    }
    var best = children.first.cat;
    var bestN = 0;
    for (final c in children) {
      final n = counts[c.cat]!;
      if (n > bestN) {
        best = c.cat;
        bestN = n;
      }
    }
    return best;
  }
}

class MindMapData {
  final int surahNumber;
  final String nameAr;
  final String nameLatin;
  final int ayatCount;

  /// Phrase (pas un titre court) résumant le fil directeur de la sourate.
  final String themeCentral;

  /// Provenance de la structure + réserves éventuelles. Peut être vide.
  final String sourcesNote;

  final List<MindMapBranch> branches;

  const MindMapData({
    required this.surahNumber,
    required this.nameAr,
    required this.nameLatin,
    required this.ayatCount,
    required this.themeCentral,
    required this.sourcesNote,
    required this.branches,
  });

  factory MindMapData.fromJson(Map<String, dynamic> json) => MindMapData(
        surahNumber: (json['surah'] as num?)?.toInt() ?? 0,
        nameAr: json['name_ar'] as String? ?? '',
        nameLatin: json['name_latin'] as String? ?? '',
        ayatCount: (json['ayat_count'] as num?)?.toInt() ?? 0,
        themeCentral: json['theme_central'] as String? ?? '',
        sourcesNote: json['sources_note'] as String? ?? '',
        branches: (json['branches'] as List<dynamic>? ?? [])
            .map((b) => MindMapBranch.fromJson(b as Map<String, dynamic>))
            .toList(),
      );
}

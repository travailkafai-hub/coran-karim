import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Le DÉCOUPAGE EN LIGNES du mushaf imprimé : où commence et où finit CHAQUE
/// ligne de chaque page.
///
/// ── POURQUOI CE SERVICE EXISTE (2026-09-04) ──────────────────────────────
///
/// Constat utilisateur, après une longue série de correctifs qui ne traitaient
/// que des symptômes (réserve sous la dernière ligne, tolérance du clip,
/// interligne, marges du cadre) :
///
///   « tu ne respectes pas le Coran papier. Ce n'est pas juste un nombre de
///     pages : chaque page a un nombre précis de lignes, chaque ligne commence
///     et finit avec les mêmes mots, quel que soit le type d'écriture. »
///
/// ⚠️ CE QUI FAIT FOI, CE SONT LES BORNES DE CHAQUE LIGNE -- pas un nombre de
/// lignes. L'utilisateur a dû le rappeler : « j'ai pas dit 15 lignes fixes,
/// c'est toi qui l'as dit ; respecte à la lettre le début et la fin de chaque
/// ligne du mushaf ». La distinction est réelle : le nombre varie selon les
/// pages (8, 12 ou 15), et une mise en page bâtie sur « 15 » serait fausse sur
/// quatre pages. Le rendu lit donc la LISTE des lignes de la page et s'y
/// conforme, quelle que soit sa longueur.
///
/// C'était exact, et c'était un défaut d'ARCHITECTURE. L'app ne connaissait que
/// le `page_number` de chaque verset : elle versait le texte d'une page dans un
/// paragraphe justifié et laissait Flutter choisir où couper. Le découpage
/// dépendait donc de la police, de la largeur et de la taille calculée -- d'où
/// les demi-lignes rognées qu'on rattrapait sans fin. Aucun réglage ne produit
/// un mushaf : il fallait la donnée.
///
/// CE QUE CET ASSET CONTIENT, ET CE QU'IL NE CONTIENT PAS. Uniquement des
/// FRONTIÈRES : pour chaque ligne, son type et ses mots de début et de fin. Le
/// TEXTE reste celui du projet (`quran_verses.json`, vérifié caractère par
/// caractère le 2026-09-03 — « faut pas inventer et modifier le texte sacré »).
/// Aucun texte coranique n'est repris d'une source tierce.
///
/// CONTRÔLE FAIT AVANT D'Y TOUCHER : les 17 640 bornes de l'asset ont été
/// confrontées à notre texte (le mot n° i du verset s:a doit exister). Zéro
/// écart -- les deux découpent les mots à l'identique, sans quoi toutes les
/// lignes seraient décalées.
///
/// Généré par `benchmark/build_mushaf_lignes_asset.py` depuis le layout KFGQPC
/// (1441H). La plupart des pages portent 15 lignes ; quatre font exception, et
/// c'est conforme à l'imprimé : 1 et 2 sont encadrées (8 lignes), 586 et 590 en
/// ont 12. Ces exceptions sont la raison pour laquelle rien ici ne suppose un
/// nombre de lignes.
class MushafLignesService {
  MushafLignesService._();
  static final instance = MushafLignesService._();

  Map<int, List<LigneMushaf>>? _pages;

  bool get charge => _pages != null;

  Future<void> ensureLoaded() async {
    if (_pages != null) return;
    final brut = await rootBundle.loadString('assets/data/mushaf_lignes.json');
    final data = jsonDecode(brut) as Map<String, dynamic>;
    _pages = {
      for (final e in data.entries)
        int.parse(e.key): [
          for (final l in (e.value as List))
            LigneMushaf._depuisJson(l as Map<String, dynamic>),
        ],
    };
  }

  /// Les lignes de [page], ou une liste vide si l'asset n'est pas chargé.
  List<LigneMushaf> lignes(int page) => _pages?[page] ?? const [];
}

/// Une ligne de la page : un titre de sourate, une basmala, ou du texte.
class LigneMushaf {
  /// Numéro de sourate, pour un titre (`type == LigneType.titreSourate`).
  final int? sourate;

  /// Premier et dernier mot de la ligne, en `sourate:verset:mot` (mot 1-based),
  /// pour une ligne de texte. Les mots d'une ligne sont contigus : deux bornes
  /// suffisent à la reconstruire.
  final MotRef? debut;
  final MotRef? fin;

  final LigneType type;

  const LigneMushaf._({
    required this.type,
    this.sourate,
    this.debut,
    this.fin,
  });

  factory LigneMushaf._depuisJson(Map<String, dynamic> j) =>
      switch (j['t'] as String) {
        's' => LigneMushaf._(
            type: LigneType.titreSourate,
            sourate: (j['s'] as num).toInt(),
          ),
        'b' => const LigneMushaf._(type: LigneType.basmala),
        _ => LigneMushaf._(
            type: LigneType.texte,
            debut: MotRef.depuis(j['d'] as String),
            fin: MotRef.depuis(j['f'] as String),
          ),
      };
}

enum LigneType { titreSourate, basmala, texte }

/// Référence d'un mot : sourate, verset, et rang du mot DANS le verset
/// (1-based, comme le layout QPC).
class MotRef {
  final int sourate;
  final int verset;
  final int mot;

  const MotRef(this.sourate, this.verset, this.mot);

  factory MotRef.depuis(String s) {
    final p = s.split(':');
    return MotRef(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  String get cleVerset => '$sourate:$verset';

  @override
  String toString() => '$sourate:$verset:$mot';
}

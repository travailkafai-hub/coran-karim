import 'dart:convert';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/recitation_verifier.dart' show ArabicNormalizer;
import '../theme/app_theme.dart';

const _kPrefEchecsParMot = 'memorization_game.echecs_par_mot';

/// Combien de fois CHAQUE mot a été raté dans le jeu de mémorisation, à
/// travers toutes les parties (2026-08-26, demande utilisateur : « garde
/// toujours la même couleur pour le même mot [...] une règle pour que ça
/// s'applique »).
///
/// ── LA COULEUR VIENT DE LA DIFFICULTÉ, PAS DU MOT LUI-MÊME ─────────────────
///
/// Deux lectures possibles de la demande, arbitrées avec l'utilisateur : une
/// couleur arbitraire fixée par mot (table mot→couleur pour tout le corpus),
/// ou une couleur qui DIT quelque chose. C'est la seconde qui est retenue --
/// elle sert la mémorisation au lieu de seulement décorer : un mot souvent
/// raté se teinte, et sa couleur devient une carte de ses propres points
/// faibles, stable d'une partie à l'autre.
///
/// La règle est déterministe (`couleurPourEchecs`) : même nombre d'échecs =
/// même couleur, partout, toujours. La couleur d'un mot ne change QUE quand
/// sa difficulté réelle change.
///
/// ── LA CLÉ EST LE MOT NORMALISÉ ───────────────────────────────────────────
/// `ArabicNormalizer.normalize` -- le même que partout ailleurs dans l'app.
/// Sans ça, deux occurrences du même mot avec une vocalisation de fin
/// différente (contexte de pause) compteraient comme deux mots distincts, et
/// la couleur sauterait d'une occurrence à l'autre alors que c'est le même
/// mot à mémoriser.
class MemorizationWordDifficulty extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefEchecsParMot);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      state = decoded.map((k, v) => MapEntry(k, v as int));
    } catch (_) {
      // Confort d'apprentissage : jamais un motif d'échec au démarrage.
    }
  }

  static String cle(String mot) => ArabicNormalizer.normalize(mot);

  int echecsPour(String mot) => state[cle(mot)] ?? 0;

  /// Un mot vient d'être raté : sa difficulté monte d'un cran, donc sa
  /// couleur aussi (jusqu'au palier maximum, cf. `couleurPourEchecs`).
  void signalerEchec(String mot) {
    final k = cle(mot);
    if (k.isEmpty) return;
    state = {...state, k: (state[k] ?? 0) + 1};
    _persister();
  }

  /// Un mot raté vient d'être réussi : sa difficulté REDESCEND d'un cran.
  ///
  /// Sans ce dégradé inverse, la couleur ne dirait que « déjà raté un jour »
  /// et ne redescendrait jamais -- au bout de quelques parties tout serait
  /// rouge, donc plus rien ne se distinguerait. Un cran à la fois : un mot
  /// raté cinq fois ne devient pas facile parce qu'il est réussi une fois.
  void signalerReussiteApresEchec(String mot) {
    final k = cle(mot);
    final actuel = state[k] ?? 0;
    if (actuel <= 0) return;
    state = {...state, k: actuel - 1};
    _persister();
  }

  void _persister() {
    SharedPreferences.getInstance()
        .then((p) => p.setString(_kPrefEchecsParMot, jsonEncode(state)))
        .catchError((_) => false);
  }
}

final memorizationWordDifficultyProvider =
    NotifierProvider<MemorizationWordDifficulty, Map<String, int>>(
        MemorizationWordDifficulty.new);

/// LA RÈGLE D'AFFECTATION DE COULEUR — un mot, une couleur, pour toujours
/// (2026-08-26, demande utilisateur : « garde toujours la même couleur pour
/// le même mot [...] une règle pour que ça s'applique »).
///
/// ── POURQUOI UNE FONCTION DU MOT, ET RIEN D'AUTRE ──────────────────────────
///
/// PREMIER JET, FAUX, corrigé le jour même : la couleur de fond venait de la
/// POSITION de la puce dans la grille (`gameChipColors[i % n]`) et la grille
/// est remélangée à chaque tour -- le même mot changeait donc de couleur d'un
/// essai à l'autre. Constat utilisateur : « j'ai effectué deux fois le jeu sur
/// le même verset, le mot change de couleur entre le premier essai et le
/// deuxième ». Une couleur qui bouge n'est pas un repère mnémotechnique, c'est
/// du bruit.
///
/// La couleur est donc dérivée du MOT NORMALISÉ, par une somme de ses unités
/// de code. Conséquences voulues :
///   - déterministe : même mot = même couleur, à chaque partie, sur chaque
///     appareil, sans rien avoir à persister ;
///   - stable dans le temps : elle ne dépend ni de la difficulté, ni de la
///     progression, ni du hasard du tirage ;
///   - le même mot qui réapparaît dans un autre verset garde sa couleur, ce
///     qui est exactement ce qui permet de l'ancrer en mémoire.
///
/// ⚠️ Deux mots DIFFÉRENTS peuvent partager une couleur (la palette est plus
/// petite que le vocabulaire) -- c'est sans conséquence : la couleur est un
/// repère, jamais une réponse. Elle n'a pas à être unique, elle a à être
/// CONSTANTE.
Color couleurDuMot(String mot) {
  final k = MemorizationWordDifficulty.cle(mot);
  if (k.isEmpty) return AppColors.gameChipColors.first;
  var somme = 0;
  for (final unite in k.codeUnits) {
    somme = (somme + unite) % 100000;
  }
  return AppColors.gameChipColors[somme % AppColors.gameChipColors.length];
}

/// LA DIFFICULTÉ SE LIT SUR UN AUTRE CANAL QUE LA COULEUR (2026-08-26).
///
/// La couleur de fond appartient au MOT et ne doit jamais bouger (cf.
/// `couleurDuMot`). La difficulté, elle, change par nature -- la mettre dans
/// la même couleur casserait la règle de constance que l'utilisateur a
/// demandée. Elle passe donc par un ANNEAU autour de la puce, un canal
/// visuel distinct qui peut évoluer sans que la couleur du mot bouge :
///
///   0 échec       -> null (aucun anneau : ce mot n'a jamais posé problème)
///   1 échec       -> anneau doré   (à surveiller)
///   2 échecs      -> anneau corail (fragile)
///   3 et au-delà  -> anneau rouge  (point faible installé)
///
/// Plafonné à 3 volontairement : au-delà, distinguer "raté 4 fois" de "raté
/// 9 fois" n'apprend rien de plus au joueur.
Color? anneauDifficulte(int echecs) {
  if (echecs <= 0) return null;
  if (echecs == 1) return AppColors.gameStar;
  if (echecs == 2) return AppColors.gameWrong.withAlpha(170);
  return AppColors.gameWrong;
}

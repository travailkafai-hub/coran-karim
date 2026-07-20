import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/mind_map_data.dart';

/// Charge la carte mentale d'une sourate depuis assets/mindmaps/{NNN}.json.
///
/// CHEMIN CORRIGÉ le 2026-07-20 : lisait auparavant `mindmaps/fr/{NNN}.json`
/// (12 sourates que j'avais rédigées en maquette). L'utilisateur a fourni le
/// jeu COMPLET — 114 sourates — à la racine `assets/mindmaps/`. Les fichiers
/// de `fr/` ont été supprimés : ils étaient une ébauche au schéma différent
/// (cf. mind_map_data.dart), et les garder aurait fait cohabiter deux formats.
/// Pas de sous-dossier de langue pour l'instant : le contenu fourni est en
/// français ; si l'anglais/arabe arrive un jour, réintroduire un préfixe de
/// langue ICI (et pas en dupliquant le provider).
///
/// Retourne null si le fichier est absent ou illisible -> l'écran affiche son
/// état « bientôt disponible » plutôt que de planter.
final mindMapProvider =
    FutureProvider.family<MindMapData?, int>((ref, surahNumber) async {
  final path =
      'assets/mindmaps/${surahNumber.toString().padLeft(3, '0')}.json';
  try {
    final raw = await rootBundle.loadString(path);
    return MindMapData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});
